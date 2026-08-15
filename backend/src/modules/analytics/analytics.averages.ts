/**
 * "Per day" - one definition, everywhere.
 *
 * There used to be three. The dashboard divided this month's spending by the
 * days elapsed; the streak card divided the last 30 days by 30; the weekly
 * snapshot divided a week by 7. All three were labelled some variant of "per
 * day", and all three showed a different number on the same screen. Nothing was
 * wrong with any single formula - the problem was having three of them.
 *
 * The canonical figure is **this month's total divided by the days elapsed so
 * far**. It is the one that answers the question people actually ask ("am I
 * on track for the month?"), it lines up with every other month-scoped number
 * on the dashboard, and it is the denominator income has to share for the two
 * to be comparable.
 */
import { Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { monthRange } from '../budgets/budgets.periods.js';

const DAY = 86_400_000;
const zero = new Prisma.Decimal(0);

export interface DailyAverages {
  currency: string;
  /** YYYY-MM the figures cover. */
  month: string;
  /** Days counted so far - the whole month once it is in the past. */
  daysElapsed: number;
  daysInMonth: number;
  /** Total spent this month, over `daysElapsed`. */
  spend: string;
  /** Total earned this month, over the same days. Comparable by construction. */
  income: string;
  /** What is left per day after spending: income - spend. */
  net: string;
}

/**
 * Days to divide by.
 *
 * A month still running counts the days gone by, so early in the month the
 * average is not diluted by days that have not happened. A month in the past
 * counts all of them.
 */
export function elapsedDays(start: Date, end: Date, now = new Date()): number {
  if (now >= end) return Math.round((end.getTime() - start.getTime()) / DAY);
  return Math.max(1, Math.ceil((now.getTime() - start.getTime()) / DAY));
}

export function daysInMonth(start: Date, end: Date): number {
  return Math.round((end.getTime() - start.getTime()) / DAY);
}

/**
 * The same per-day arithmetic over an arbitrary span, for a caller that has
 * already decided which rows it means.
 *
 * The transactions page needs this: showing a *month* average above a list
 * filtered to *last week* would recreate the exact disagreement this file was
 * written to end. So the page passes the totals from its own filtered query and
 * the span it covers, and the division happens in one place as always.
 *
 * `from`/`to` are inclusive of the days they name. An open-ended filter has no
 * span to divide by, so the caller supplies the observed range instead.
 */
export function averagesOverSpan(args: {
  income: Prisma.Decimal;
  expense: Prisma.Decimal;
  from: Date;
  to: Date;
  currency: string;
}): { currency: string; days: number; spend: string; income: string; net: string } {
  const span = Math.max(
    1,
    Math.round((args.to.getTime() - args.from.getTime()) / DAY) + 1,
  );
  const spend = args.expense.div(span);
  const income = args.income.div(span);
  return {
    currency: args.currency,
    days: span,
    spend: spend.toFixed(2),
    income: income.toFixed(2),
    net: income.sub(spend).toFixed(2),
  };
}

/** The canonical per-day figures for one month and currency. */
export async function dailyAverages(
  userId: string,
  currency: string,
  month?: string,
): Promise<DailyAverages> {
  const cur = currency.toUpperCase();
  const { start, end } = monthRange(month);
  const days = elapsedDays(start, end);

  const totals = await prisma.transaction.groupBy({
    by: ['kind'],
    where: {
      userId,
      currency: cur,
      kind: { in: [TxKind.INCOME, TxKind.EXPENSE] },
      date: { gte: start, lt: end },
    },
    _sum: { amount: true },
  });

  const pick = (kind: TxKind) =>
    totals.find((t) => t.kind === kind)?._sum.amount ?? zero;

  const spend = pick(TxKind.EXPENSE).div(days);
  const income = pick(TxKind.INCOME).div(days);

  return {
    currency: cur,
    month: start.toISOString().slice(0, 7),
    daysElapsed: days,
    daysInMonth: daysInMonth(start, end),
    spend: spend.toFixed(2),
    income: income.toFixed(2),
    net: income.sub(spend).toFixed(2),
  };
}
