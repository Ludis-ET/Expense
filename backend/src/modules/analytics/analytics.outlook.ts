import { BudgetKind, Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import type { AuthUser } from '../../core/context.js';
import { resolveCurrency } from '../../core/currency.service.js';

const zero = new Prisma.Decimal(0);

/** Average days in a month — the same constant the mobile client converts with. */
const DAYS_PER_MONTH = 30.436875;

/** How far back repeat detection looks. */
const PATTERN_WINDOW_DAYS = 90;

/** Occurrences needed before a payee counts as a repeat rather than a coincidence. */
const MIN_OCCURRENCES = 3;

type MonthCell = {
  month: string;
  income: string;
  expense: string;
  unplanned: string;
  net: string;
  covered: boolean;
};

/**
 * The history the monthly outlook needs, in one round trip.
 *
 * The mobile outlook used to infer everything from the dashboard's eight most
 * recent transactions, which made its "likely spend" both noisy and dependent
 * on whatever the user logged last. It also sized its surprise buffer from the
 * *current* cycle's unplanned spend, so the income target climbed as the month
 * went on. Both need real history, which is what this returns:
 *
 *  - `months`: completed months only, oldest first — the coverage track record.
 *  - `unplannedMedian`: a stable buffer that does not move within a month.
 *  - `repeatCandidates`: repeating payees over a 90-day window, with a genuine
 *    monthly rate derived from the gap between occurrences.
 */
export async function outlookHistory(user: AuthUser, currency?: string, months = 6) {
  const cur = await resolveCurrency(user.id, currency);
  const now = new Date();

  // Completed months only. The current month is deliberately excluded: it is
  // partial, and including it is what made the old buffer drift upward.
  const firstOfThisMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const windowStart = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - months, 1),
  );

  const patternStart = new Date(now.getTime() - PATTERN_WINDOW_DAYS * 86_400_000);

  const [rows, unplannedRows, patternTx] = await Promise.all([
    prisma.transaction.findMany({
      where: {
        userId: user.id,
        currency: cur,
        kind: { in: [TxKind.INCOME, TxKind.EXPENSE] },
        date: { gte: windowStart, lt: firstOfThisMonth },
      },
      select: { kind: true, amount: true, date: true },
    }),
    prisma.transaction.findMany({
      where: {
        userId: user.id,
        currency: cur,
        kind: TxKind.EXPENSE,
        date: { gte: windowStart, lt: firstOfThisMonth },
        budget: { is: { kind: BudgetKind.UNPLANNED } },
      },
      select: { amount: true, date: true },
    }),
    prisma.transaction.findMany({
      where: {
        userId: user.id,
        currency: cur,
        kind: { in: [TxKind.INCOME, TxKind.EXPENSE] },
        date: { gte: patternStart },
        // Anything already driven by a rule is, by definition, not a candidate
        // for becoming one.
        recurringRuleId: null,
        payee: { not: null },
      },
      select: {
        kind: true,
        amount: true,
        date: true,
        payee: true,
        categoryId: true,
        category: { select: { name: true, icon: true, color: true } },
      },
      orderBy: { date: 'asc' },
    }),
  ]);

  // --- monthly buckets -------------------------------------------------------

  const key = (d: Date) => d.toISOString().slice(0, 7);
  const buckets = new Map<string, { income: Prisma.Decimal; expense: Prisma.Decimal; unplanned: Prisma.Decimal }>();

  for (let i = months; i >= 1; i -= 1) {
    const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - i, 1));
    buckets.set(key(d), { income: zero, expense: zero, unplanned: zero });
  }

  for (const row of rows) {
    const cell = buckets.get(key(row.date));
    if (!cell) continue;
    if (row.kind === TxKind.INCOME) cell.income = cell.income.add(row.amount);
    else cell.expense = cell.expense.add(row.amount);
  }

  for (const row of unplannedRows) {
    const cell = buckets.get(key(row.date));
    if (!cell) continue;
    cell.unplanned = cell.unplanned.add(row.amount);
  }

  const monthCells: MonthCell[] = [...buckets.entries()].map(([month, cell]) => ({
    month,
    income: cell.income.toFixed(2),
    expense: cell.expense.toFixed(2),
    unplanned: cell.unplanned.toFixed(2),
    net: cell.income.sub(cell.expense).toFixed(2),
    covered: cell.income.gte(cell.expense),
  }));

  // --- buffer ----------------------------------------------------------------

  // Only months with any activity count: a run of empty months before the user
  // started would otherwise drag the median to zero.
  const unplannedSeries = monthCells
    .filter((m) => Number(m.income) > 0 || Number(m.expense) > 0)
    .map((m) => Number(m.unplanned))
    .sort((a, b) => a - b);

  const unplannedMedian = median(unplannedSeries);

  // --- repeat candidates -----------------------------------------------------

  const groups = new Map<
    string,
    {
      payee: string;
      kind: TxKind;
      categoryId: string | null;
      categoryName: string | null;
      categoryIcon: string | null;
      categoryColor: string | null;
      total: Prisma.Decimal;
      dates: Date[];
    }
  >();

  for (const tx of patternTx) {
    const payee = tx.payee?.trim();
    if (!payee) continue;
    const groupKey = `${tx.kind}|${payee.toLowerCase()}`;
    const group = groups.get(groupKey) ?? {
      payee,
      kind: tx.kind,
      categoryId: tx.categoryId,
      categoryName: tx.category?.name ?? null,
      categoryIcon: tx.category?.icon ?? null,
      categoryColor: tx.category?.color ?? null,
      total: zero,
      dates: [] as Date[],
    };
    group.total = group.total.add(tx.amount);
    group.dates.push(tx.date);
    groups.set(groupKey, group);
  }

  const repeatCandidates = [...groups.values()]
    .filter((g) => g.dates.length >= MIN_OCCURRENCES)
    .map((g) => {
      const count = g.dates.length;
      const first = g.dates[0]!;
      const last = g.dates[count - 1]!;

      // Cadence from the average gap between occurrences, so a weekly shop and
      // a monthly bill both convert to a truthful monthly figure. The old
      // client-side version used the average *per occurrence*, which reported
      // a daily coffee as the price of one cup.
      const spanDays = (last.getTime() - first.getTime()) / 86_400_000;
      const avgGapDays = count > 1 ? Math.max(1, spanDays / (count - 1)) : DAYS_PER_MONTH;
      const perOccurrence = g.total.div(count);
      const monthlyAmount = perOccurrence.mul(DAYS_PER_MONTH / avgGapDays);

      return {
        payee: g.payee,
        kind: g.kind,
        categoryId: g.categoryId,
        category: g.categoryName
          ? { name: g.categoryName, icon: g.categoryIcon, color: g.categoryColor }
          : null,
        count,
        avgAmount: perOccurrence.toFixed(2),
        monthlyAmount: monthlyAmount.toFixed(2),
        avgGapDays: Math.round(avgGapDays),
        cadence: describeCadence(avgGapDays),
        firstSeen: first.toISOString(),
        lastSeen: last.toISOString(),
      };
    })
    .sort((a, b) => Number(b.monthlyAmount) - Number(a.monthlyAmount))
    .slice(0, 12);

  return {
    currency: cur,
    months: monthCells,
    unplannedMedian: unplannedMedian.toFixed(2),
    unplannedSampleMonths: unplannedSeries.length,
    repeatCandidates,
    patternWindowDays: PATTERN_WINDOW_DAYS,
  };
}

function median(sorted: number[]): Prisma.Decimal {
  if (sorted.length === 0) return zero;
  const mid = Math.floor(sorted.length / 2);
  const value =
    sorted.length % 2 === 1 ? sorted[mid]! : (sorted[mid - 1]! + sorted[mid]!) / 2;
  return new Prisma.Decimal(value);
}

/** Turns an average gap in days into words a person would use. */
function describeCadence(days: number): string {
  if (days <= 1.5) return 'about daily';
  if (days <= 4) return 'a few times a week';
  if (days <= 9) return 'about weekly';
  if (days <= 18) return 'about fortnightly';
  if (days <= 45) return 'about monthly';
  if (days <= 100) return 'every couple of months';
  return 'occasionally';
}
