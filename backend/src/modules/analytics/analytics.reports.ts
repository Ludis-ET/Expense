/**
 * The long view: seasons, years, weekdays, and what moved since last month.
 *
 * Everything here reads whole history rather than one window, so it is the only
 * place that can answer "is this month unusual *for me*" instead of just "what
 * did this month cost". Each figure carries the sample size it was averaged
 * from - one January is an anecdote, four is a season.
 */
import { Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import type { AuthUser } from '../../core/context.js';
import { monthRange } from '../budgets/budgets.periods.js';

const zero = new Prisma.Decimal(0);

const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/** Monday-based ISO week key, e.g. 2026-W31. */
function isoWeek(d: Date): string {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((t.getTime() - yearStart.getTime()) / 86_400_000 + 1) / 7);
  return `${t.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

function avg(total: Prisma.Decimal, n: number): string {
  return n === 0 ? '0.00' : total.div(n).toFixed(2);
}

/**
 * Seasonal shape of the user's money: which months of the year cost most, which
 * days of the week leak, how each year compares, and the last N weeks.
 *
 * Averages are per *observed* period, not per calendar slot - a month you have
 * two Januaries for divides by two, not by however many years the account has
 * existed. Slots with no history are returned with `samples: 0` so the UI can
 * say "not enough history" rather than draw a zero.
 */
export async function seasonal(user: AuthUser, currency: string, weeks = 12) {
  const cur = currency.toUpperCase();
  const rows = await prisma.transaction.findMany({
    where: { userId: user.id, currency: cur, kind: { in: [TxKind.INCOME, TxKind.EXPENSE] } },
    select: { kind: true, amount: true, date: true },
    orderBy: { date: 'asc' },
  });

  const income = (k: TxKind) => k === TxKind.INCOME;

  // --- Month of the year --------------------------------------------------
  // Keyed by YYYY-MM first so an average divides by months observed, not rows.
  const perMonth = new Map<string, { income: Prisma.Decimal; expense: Prisma.Decimal }>();
  const perYear = new Map<number, { income: Prisma.Decimal; expense: Prisma.Decimal; count: number }>();
  const perWeekday = new Map<number, { total: Prisma.Decimal; days: Set<string>; count: number }>();
  const perWeek = new Map<string, { income: Prisma.Decimal; expense: Prisma.Decimal }>();

  for (const r of rows) {
    const ym = r.date.toISOString().slice(0, 7);
    const y = r.date.getUTCFullYear();
    const wd = r.date.getUTCDay();
    const wk = isoWeek(r.date);

    const m = perMonth.get(ym) ?? { income: zero, expense: zero };
    const yr = perYear.get(y) ?? { income: zero, expense: zero, count: 0 };
    const w = perWeek.get(wk) ?? { income: zero, expense: zero };

    if (income(r.kind)) {
      m.income = m.income.add(r.amount);
      yr.income = yr.income.add(r.amount);
      w.income = w.income.add(r.amount);
    } else {
      m.expense = m.expense.add(r.amount);
      yr.expense = yr.expense.add(r.amount);
      w.expense = w.expense.add(r.amount);
      // Weekday profile is about spending only - income lands when payroll
      // says so, which tells you nothing about habit.
      const d = perWeekday.get(wd) ?? { total: zero, days: new Set<string>(), count: 0 };
      d.total = d.total.add(r.amount);
      d.days.add(r.date.toISOString().slice(0, 10));
      d.count += 1;
      perWeekday.set(wd, d);
    }
    yr.count += 1;
    perMonth.set(ym, m);
    perYear.set(y, yr);
    perWeek.set(wk, w);
  }

  // Collapse YYYY-MM into calendar months.
  const monthSlots = MONTH_NAMES.map((name, i) => ({
    month: i + 1,
    name,
    income: zero,
    expense: zero,
    samples: 0,
  }));
  for (const [ym, v] of perMonth) {
    const idx = Number(ym.slice(5, 7)) - 1;
    const slot = monthSlots[idx]!;
    slot.income = slot.income.add(v.income);
    slot.expense = slot.expense.add(v.expense);
    slot.samples += 1;
  }

  const months = monthSlots.map((s) => ({
    month: s.month,
    name: s.name,
    samples: s.samples,
    avgIncome: avg(s.income, s.samples),
    avgExpense: avg(s.expense, s.samples),
    avgNet: s.samples === 0 ? '0.00' : s.income.sub(s.expense).div(s.samples).toFixed(2),
  }));

  const observed = months.filter((m) => m.samples > 0);
  const dearest = observed.length
    ? observed.reduce((a, b) => (Number(b.avgExpense) > Number(a.avgExpense) ? b : a))
    : null;
  const cheapest = observed.length
    ? observed.reduce((a, b) => (Number(b.avgExpense) < Number(a.avgExpense) ? b : a))
    : null;

  // --- Day of the week ----------------------------------------------------
  const daysOfWeek = DAY_NAMES.map((name, i) => {
    const d = perWeekday.get(i);
    const observedDays = d?.days.size ?? 0;
    return {
      day: i,
      name,
      /** Average spend on a day of this weekday that saw any spending. */
      avgSpend: d ? avg(d.total, observedDays) : '0.00',
      total: (d?.total ?? zero).toFixed(2),
      txCount: d?.count ?? 0,
      samples: observedDays,
    };
  });
  const activeDays = daysOfWeek.filter((d) => d.samples > 0);
  const heaviestDay = activeDays.length
    ? activeDays.reduce((a, b) => (Number(b.avgSpend) > Number(a.avgSpend) ? b : a))
    : null;

  // --- Year on year -------------------------------------------------------
  const years = [...perYear.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([year, v]) => ({
      year,
      income: v.income.toFixed(2),
      expense: v.expense.toFixed(2),
      net: v.income.sub(v.expense).toFixed(2),
      txCount: v.count,
      savingsRate: v.income.gt(0)
        ? Number(v.income.sub(v.expense).div(v.income).mul(100).toFixed(1))
        : null,
    }));

  // --- Recent weeks -------------------------------------------------------
  // Gap-filled, so a quiet week reads as a zero rather than vanishing.
  const weekKeys: string[] = [];
  const cursor = new Date();
  cursor.setUTCHours(0, 0, 0, 0);
  for (let i = weeks - 1; i >= 0; i--) {
    const d = new Date(cursor.getTime() - i * 7 * 86_400_000);
    weekKeys.push(isoWeek(d));
  }
  const weekly = weekKeys.map((key) => {
    const v = perWeek.get(key) ?? { income: zero, expense: zero };
    return {
      week: key,
      label: key.slice(5),
      income: v.income.toFixed(2),
      expense: v.expense.toFixed(2),
      net: v.income.sub(v.expense).toFixed(2),
    };
  });

  return {
    currency: cur,
    monthsObserved: perMonth.size,
    months,
    dearestMonth: dearest,
    cheapestMonth: cheapest,
    daysOfWeek,
    heaviestDay,
    years,
    weekly,
  };
}

/**
 * What actually changed since last month, per category.
 *
 * Ranked by absolute movement rather than by size, because a category that
 * doubled off a small base is the interesting one - a big steady category is
 * just the cost of living.
 */
export async function movers(user: AuthUser, month: string | undefined, currency: string) {
  const cur = currency.toUpperCase();
  const { start, end } = monthRange(month);
  const prev = monthRange(
    new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() - 1, 1)).toISOString().slice(0, 7),
  );

  const [nowRows, prevRows] = await Promise.all([
    prisma.transaction.groupBy({
      by: ['categoryId'],
      where: { userId: user.id, currency: cur, kind: TxKind.EXPENSE, date: { gte: start, lt: end } },
      _sum: { amount: true },
    }),
    prisma.transaction.groupBy({
      by: ['categoryId'],
      where: {
        userId: user.id,
        currency: cur,
        kind: TxKind.EXPENSE,
        date: { gte: prev.start, lt: prev.end },
      },
      _sum: { amount: true },
    }),
  ]);

  const ids = [
    ...new Set([...nowRows, ...prevRows].map((r) => r.categoryId).filter((id): id is string => !!id)),
  ];
  const categories = await prisma.category.findMany({
    where: { id: { in: ids } },
    select: { id: true, name: true, icon: true, color: true },
  });
  const byId = new Map(categories.map((c) => [c.id, c]));
  const nowById = new Map(nowRows.map((r) => [r.categoryId ?? '', r._sum.amount ?? zero]));
  const prevById = new Map(prevRows.map((r) => [r.categoryId ?? '', r._sum.amount ?? zero]));

  const items = [...new Set([...nowById.keys(), ...prevById.keys()])]
    .map((id) => {
      const current = nowById.get(id) ?? zero;
      const before = prevById.get(id) ?? zero;
      const change = current.sub(before);
      return {
        category: byId.get(id) ?? null,
        current: current.toFixed(2),
        previous: before.toFixed(2),
        change: change.toFixed(2),
        changePct: before.gt(0)
          ? Number(change.div(before).mul(100).toFixed(1))
          : current.gt(0)
            ? null // new this month: a percentage off zero is meaningless
            : 0,
        isNew: before.isZero() && current.gt(0),
        stopped: current.isZero() && before.gt(0),
      };
    })
    .filter((i) => Number(i.change) !== 0)
    .sort((a, b) => Math.abs(Number(b.change)) - Math.abs(Number(a.change)));

  return {
    currency: cur,
    month: start.toISOString().slice(0, 7),
    hasPrevious: prevRows.length > 0,
    up: items.filter((i) => Number(i.change) > 0).slice(0, 6),
    down: items.filter((i) => Number(i.change) < 0).slice(0, 6),
  };
}
