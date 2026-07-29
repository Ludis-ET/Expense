/**
 * Weekly snapshots and daily-spend series.
 *
 * Weeks run Sunday 00:00 UTC to the next Sunday. The current week is kept up to
 * date on every read; the moment a week ends it is sealed and never recomputed,
 * so the comparison you see is genuinely what that week looked like. Only two
 * rows per user survive - anything older is derivable from the transactions.
 */
import { Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import type { AuthUser } from '../../core/context.js';
import { resolveCurrency } from '../../core/currency.service.js';

const DAY = 86_400_000;
const zero = new Prisma.Decimal(0);

/** Midnight UTC on the Sunday on or before `d`. */
export function weekStartOf(d: Date): Date {
  const utc = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  utc.setUTCDate(utc.getUTCDate() - utc.getUTCDay()); // getUTCDay: 0 = Sunday
  return utc;
}

interface WeekTotals {
  income: Prisma.Decimal;
  expense: Prisma.Decimal;
  txCount: number;
  topCategory: string | null;
  topCategoryAmount: Prisma.Decimal | null;
}

async function totalsForWeek(
  userId: string,
  currency: string,
  start: Date,
  end: Date,
): Promise<WeekTotals> {
  const where: Prisma.TransactionWhereInput = {
    userId,
    currency,
    date: { gte: start, lt: end },
    kind: { in: [TxKind.INCOME, TxKind.EXPENSE] },
  };

  const [byKind, byCategory] = await Promise.all([
    prisma.transaction.groupBy({
      by: ['kind'],
      where,
      _sum: { amount: true },
      _count: { _all: true },
    }),
    prisma.transaction.groupBy({
      by: ['categoryId'],
      where: { ...where, kind: TxKind.EXPENSE },
      _sum: { amount: true },
      orderBy: { _sum: { amount: 'desc' } },
      take: 1,
    }),
  ]);

  const income = byKind.find((r) => r.kind === TxKind.INCOME)?._sum.amount ?? zero;
  const expense = byKind.find((r) => r.kind === TxKind.EXPENSE)?._sum.amount ?? zero;
  const txCount = byKind.reduce((s, r) => s + r._count._all, 0);

  let topCategory: string | null = null;
  const topAmount = byCategory[0]?._sum.amount ?? null;
  if (byCategory[0]?.categoryId) {
    const cat = await prisma.category.findUnique({
      where: { id: byCategory[0].categoryId },
      select: { name: true },
    });
    topCategory = cat?.name ?? null;
  }

  return { income, expense, txCount, topCategory, topCategoryAmount: topAmount };
}

/**
 * Bring the stored snapshots in line with the clock: refresh the running week,
 * seal and backfill the one before it, and drop anything older.
 */
export async function rollWeekSnapshots(userId: string, currency: string) {
  const now = new Date();
  const currentStart = weekStartOf(now);
  const currentEnd = new Date(currentStart.getTime() + 7 * DAY);
  const prevStart = new Date(currentStart.getTime() - 7 * DAY);

  // Elapsed days decide the running week's average; a sealed week always uses 7.
  const elapsedDays = Math.min(
    7,
    Math.max(1, Math.ceil((now.getTime() - currentStart.getTime()) / DAY)),
  );

  const [current, previous] = await Promise.all([
    totalsForWeek(userId, currency, currentStart, currentEnd),
    totalsForWeek(userId, currency, prevStart, currentStart),
  ]);

  const write = async (
    start: Date,
    end: Date,
    t: WeekTotals,
    days: number,
    sealed: boolean,
  ) => {
    const data = {
      weekEnd: end,
      income: t.income,
      expense: t.expense,
      net: t.income.sub(t.expense),
      avgDailySpend: t.expense.div(days),
      txCount: t.txCount,
      topCategory: t.topCategory,
      topCategoryAmount: t.topCategoryAmount,
      sealed,
    };
    return prisma.weekSnapshot.upsert({
      where: { userId_currency_weekStart: { userId, currency, weekStart: start } },
      // A sealed week is history: refresh only while it is still running.
      update: sealed ? { sealed: true } : data,
      create: { userId, currency, weekStart: start, ...data },
    });
  };

  const [currentRow, previousRow] = await Promise.all([
    write(currentStart, currentEnd, current, elapsedDays, false),
    write(prevStart, currentStart, previous, 7, true),
  ]);

  // Keep two weeks, no more.
  await prisma.weekSnapshot.deleteMany({
    where: { userId, currency, weekStart: { lt: prevStart } },
  });

  return { currentRow, previousRow };
}

function pctDelta(now: Prisma.Decimal, before: Prisma.Decimal): number | null {
  if (before.lte(0)) return now.gt(0) ? 100 : null;
  return Number(now.sub(before).div(before).mul(100).toFixed(1));
}

const serializeWeek = (r: {
  weekStart: Date;
  weekEnd: Date;
  income: Prisma.Decimal;
  expense: Prisma.Decimal;
  net: Prisma.Decimal;
  avgDailySpend: Prisma.Decimal;
  txCount: number;
  topCategory: string | null;
  topCategoryAmount: Prisma.Decimal | null;
  sealed: boolean;
}) => ({
  weekStart: r.weekStart.toISOString(),
  weekEnd: r.weekEnd.toISOString(),
  income: r.income.toFixed(2),
  expense: r.expense.toFixed(2),
  net: r.net.toFixed(2),
  avgDailySpend: r.avgDailySpend.toFixed(2),
  txCount: r.txCount,
  topCategory: r.topCategory,
  topCategoryAmount: r.topCategoryAmount ? r.topCategoryAmount.toFixed(2) : null,
  sealed: r.sealed,
});

/** This week against last week, straight from the stored snapshots. */
export async function weeklySnapshot(user: AuthUser, currency?: string) {
  const cur = await resolveCurrency(user.id, currency);
  const { currentRow, previousRow } = await rollWeekSnapshots(user.id, cur);

  return {
    currency: cur,
    current: serializeWeek(currentRow),
    previous: serializeWeek(previousRow),
    delta: {
      income: pctDelta(currentRow.income, previousRow.income),
      expense: pctDelta(currentRow.expense, previousRow.expense),
      net: pctDelta(currentRow.net, previousRow.net),
      /** Absolute change, which reads better than a percentage for net. */
      netAmount: currentRow.net.sub(previousRow.net).toFixed(2),
      expenseAmount: currentRow.expense.sub(previousRow.expense).toFixed(2),
    },
  };
}

export interface DailySpendQuery {
  /** YYYY-MM. Omitted means the last 30 days ending today. */
  month?: string;
  currency?: string;
}

/**
 * Per-day spending for a window, with the streak maths already done.
 *
 * "Pace" is the average daily spend *of the window being shown*, so the colours
 * always mean the same thing: below your own average for that period.
 */
export async function dailySpending(user: AuthUser, query: DailySpendQuery = {}) {
  const cur = await resolveCurrency(user.id, query.currency);
  const now = new Date();
  const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));

  let start: Date;
  let end: Date; // exclusive
  let label: string;
  let isMonth = false;

  if (query.month) {
    const [y, m] = query.month.split('-').map(Number);
    start = new Date(Date.UTC(y!, (m ?? 1) - 1, 1));
    end = new Date(Date.UTC(y!, m ?? 1, 1));
    isMonth = true;
    label = new Intl.DateTimeFormat('en-GB', {
      month: 'long',
      year: 'numeric',
      timeZone: 'UTC',
    }).format(start);
  } else {
    end = new Date(today.getTime() + DAY);
    start = new Date(end.getTime() - 30 * DAY);
    label = 'Last 30 days';
  }

  // Never chart the future: a month still running stops at today.
  const cappedEnd = end.getTime() > today.getTime() + DAY ? new Date(today.getTime() + DAY) : end;
  const inFuture = start.getTime() > today.getTime();

  const rows = inFuture
    ? []
    : await prisma.transaction.findMany({
        where: {
          userId: user.id,
          currency: cur,
          kind: TxKind.EXPENSE,
          date: { gte: start, lt: cappedEnd },
        },
        select: { amount: true, date: true },
      });

  const byDay = new Map<string, number>();
  for (const r of rows) {
    const key = r.date.toISOString().slice(0, 10);
    byDay.set(key, (byDay.get(key) ?? 0) + Number(r.amount));
  }

  const days: { date: string; amount: string; spent: boolean }[] = [];
  for (let t = start.getTime(); t < cappedEnd.getTime(); t += DAY) {
    const key = new Date(t).toISOString().slice(0, 10);
    const amount = byDay.get(key) ?? 0;
    days.push({ date: key, amount: amount.toFixed(2), spent: amount > 0 });
  }

  const total = days.reduce((s, d) => s + Number(d.amount), 0);
  const pace = days.length > 0 ? total / days.length : 0;

  // Every day is classified, including the ones that break the run - the strip
  // shows the whole window rather than stopping at the first overspend.
  const classified = days.map((d) => ({ ...d, under: Number(d.amount) <= pace }));

  let bestStreak = 0;
  let run = 0;
  for (const d of classified) {
    run = d.under ? run + 1 : 0;
    if (run > bestStreak) bestStreak = run;
  }

  let currentStreak = 0;
  for (let i = classified.length - 1; i >= 0; i -= 1) {
    if (!classified[i]!.under) break;
    currentStreak += 1;
  }

  const daysUnder = classified.filter((d) => d.under).length;
  const noSpendDays = classified.filter((d) => !d.spent).length;
  const biggest = classified.reduce(
    (max, d) => (Number(d.amount) > Number(max.amount) ? d : max),
    classified[0] ?? { date: '', amount: '0', spent: false, under: true },
  );

  return {
    currency: cur,
    label,
    isMonth,
    month: query.month ?? null,
    start: start.toISOString().slice(0, 10),
    end: new Date(cappedEnd.getTime() - DAY).toISOString().slice(0, 10),
    days: classified,
    stats: {
      total: total.toFixed(2),
      pace: pace.toFixed(2),
      dayCount: classified.length,
      daysUnder,
      daysOver: classified.length - daysUnder,
      noSpendDays,
      currentStreak,
      bestStreak,
      biggestDay: biggest.date ? { date: biggest.date, amount: biggest.amount } : null,
    },
  };
}

/** The compact form the dashboard card needs: last 30 days. */
export async function spendingStreak(user: AuthUser, currency?: string) {
  const d = await dailySpending(user, { currency });
  return {
    currency: d.currency,
    label:
      d.stats.currentStreak >= 7
        ? 'On fire'
        : d.stats.currentStreak >= 3
          ? 'Building momentum'
          : d.stats.currentStreak > 0
            ? 'Keep going'
            : 'Start today',
    avgDailySpend: d.stats.pace,
    currentDays: d.stats.currentStreak,
    bestStreak: d.stats.bestStreak,
    daysUnder: d.stats.daysUnder,
    dayCount: d.stats.dayCount,
    total: d.stats.total,
    /** The 30-day strip, so the card can show the whole run at a glance. */
    days: d.days,
  };
}
