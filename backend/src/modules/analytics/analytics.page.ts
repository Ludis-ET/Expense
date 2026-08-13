/**
 * Everything the analytics page shows, in one round trip.
 *
 * The page answers three questions - am I living within my means, where did the
 * money actually go, and how much of my cash is genuinely free - so the figures
 * here are deliberately few and each one is meant to change a decision.
 *
 * Two traps are handled centrally rather than left to callers:
 *
 *  - **Reservations.** `locked` is never re-derived here. There is exactly one
 *    derivation of what a wallet holds and what plans have reserved of it, in
 *    `core/money`, and `accounts.list()` already carries its answer.
 *  - **Currency.** Nothing is converted. One currency is in scope at a time and
 *    the response says which other currencies were left out, so an incomplete
 *    total announces itself instead of quietly under-reporting.
 */
import {
  Frequency,
  LedgerKind,
  LedgerStatus,
  Prisma,
  TxKind,
  WishlistStatus,
} from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import type { AuthUser } from '../../core/context.js';
import { monthRange } from '../budgets/budgets.periods.js';
import * as accountsService from '../accounts/accounts.service.js';
import * as budgetsService from '../budgets/budgets.service.js';

const zero = new Prisma.Decimal(0);
const DAY = 86_400_000;

/** Average days in a month/week, so a cadence can be stated per month. */
const DAYS_PER_MONTH = 30.436_875;
const WEEKS_PER_MONTH = DAYS_PER_MONTH / 7;

/**
 * What one recurring rule costs per month.
 *
 * `interval` is the multiplier that turns a frequency into a real cadence -
 * WEEKLY with interval 2 is fortnightly, and treating it as weekly would double
 * the fixed-cost floor. Dividing by it is the whole point of this function.
 */
export function monthlyEquivalent(
  amount: Prisma.Decimal,
  frequency: Frequency,
  interval: number,
): Prisma.Decimal {
  const every = Math.max(1, interval);
  switch (frequency) {
    case Frequency.DAILY:
      return amount.mul(DAYS_PER_MONTH).div(every);
    case Frequency.WEEKLY:
      return amount.mul(WEEKS_PER_MONTH).div(every);
    case Frequency.MONTHLY:
      return amount.div(every);
    case Frequency.YEARLY:
      return amount.div(12 * every);
  }
}

function pct(part: Prisma.Decimal, whole: Prisma.Decimal): number {
  if (whole.lte(0)) return 0;
  return Number(part.div(whole).mul(100).toFixed(1));
}

/** Percentage change, or null when there is no previous figure to compare to. */
function delta(now: Prisma.Decimal, before: Prisma.Decimal): number | null {
  if (before.isZero()) return null;
  return Number(now.sub(before).div(before.abs()).mul(100).toFixed(1));
}

function avgDays(spans: number[]): number | null {
  if (spans.length === 0) return null;
  return Math.round(spans.reduce((s, n) => s + n, 0) / spans.length);
}

async function sumExpenses(
  userId: string,
  currency: string,
  start: Date,
  end: Date,
  extra: Prisma.TransactionWhereInput = {},
): Promise<Prisma.Decimal> {
  const agg = await prisma.transaction.aggregate({
    where: { userId, currency, kind: TxKind.EXPENSE, date: { gte: start, lt: end }, ...extra },
    _sum: { amount: true },
  });
  return agg._sum.amount ?? zero;
}

export async function page(user: AuthUser, month?: string, currencyInput?: string) {
  const currency = (currencyInput ?? 'ETB').toUpperCase();
  const { start, end } = monthRange(month);
  const prev = monthRange(new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() - 1, 1)).toISOString().slice(0, 7));
  const now = new Date();
  const inProgress = now >= start && now < end;

  const [
    income,
    expense,
    prevIncome,
    prevExpense,
    unplannedSpend,
    firstTx,
    accountRows,
    budgetList,
    rules,
    wishes,
    ledgerEntries,
    rates,
  ] = await Promise.all([
    prisma.transaction
      .aggregate({
        where: { userId: user.id, currency, kind: TxKind.INCOME, date: { gte: start, lt: end } },
        _sum: { amount: true },
      })
      .then((a) => a._sum.amount ?? zero),
    sumExpenses(user.id, currency, start, end),
    prisma.transaction
      .aggregate({
        where: { userId: user.id, currency, kind: TxKind.INCOME, date: { gte: prev.start, lt: prev.end } },
        _sum: { amount: true },
      })
      .then((a) => a._sum.amount ?? zero),
    sumExpenses(user.id, currency, prev.start, prev.end),
    // Spending no money was set aside for. One definition, shared with the
    // budgets page and the outlook - these three used to disagree, and quoted
    // three different numbers for the same month.
    sumExpenses(user.id, currency, start, end, budgetsService.UNPLANNED_WHERE),
    prisma.transaction.findFirst({
      where: { userId: user.id, currency },
      orderBy: { date: 'asc' },
      select: { date: true },
    }),
    accountsService.list(user).then((r) => r.items.filter((a) => a.currency === currency && !a.archived)),
    budgetsService.list(user, { currency }),
    prisma.recurringRule.findMany({
      where: {
        userId: user.id,
        currency,
        active: true,
        OR: [{ endDate: null }, { endDate: { gte: now } }],
      },
      include: { category: { select: { id: true, name: true, icon: true, color: true } } },
    }),
    prisma.wishlistItem.findMany({
      where: { userId: user.id },
      include: { budget: { select: { plannedAmount: true, currency: true } } },
    }),
    prisma.ledgerEntry.findMany({
      where: { userId: user.id, currency, status: LedgerStatus.OPEN },
      include: { payments: { select: { amount: true } } },
    }),
    prisma.exchangeRate.findMany({ where: { userId: user.id }, select: { fromCurrency: true, toCurrency: true } }),
  ]);

  // --- Cash flow ----------------------------------------------------------
  const net = income.sub(expense);
  const prevNet = prevIncome.sub(prevExpense);
  const hasPrevious = !prevIncome.isZero() || !prevExpense.isZero();

  // --- Where the money is -------------------------------------------------
  // Straight from the accounts view, which already nets reservations correctly.
  let real = zero;
  let locked = zero;
  let available = zero;
  for (const a of accountRows) {
    real = real.add(a.realBalance);
    locked = locked.add(a.lockedAmount);
    available = available.add(a.balance);
  }

  // --- Currencies left out ------------------------------------------------
  const otherCurrencies = [
    ...new Set(
      (await prisma.account.findMany({
        where: { userId: user.id, archived: false },
        select: { currency: true },
      })).map((a) => a.currency),
    ),
  ].filter((c) => c !== currency);
  const rateKeys = new Set(rates.map((r) => `${r.fromCurrency}->${r.toCurrency}`));
  const missingRates = otherCurrencies.filter((c) => !rateKeys.has(`${c}->${currency}`));

  // --- Plan discipline ----------------------------------------------------
  // Measured against the amount each cycle *opened* with, not the amount it
  // ended up at. A plan raised mid-cycle to cover an overspend still reads as
  // an overspend, which is the point: drift and discipline are different
  // failures and a single "% of budget" number hides both.
  const plans = budgetList.items
    .filter((b) => !b.isUnplanned && b.state === 'ACTIVE' && b.started)
    .map((b) => {
      const opening = new Prisma.Decimal(b.openingPlanned);
      const spent = new Prisma.Decimal(b.spentAmount);
      return {
        id: b.id,
        name: b.name,
        icon: b.icon,
        color: b.color,
        kind: b.kind,
        cycleLabel: b.cycleLabel,
        periodNoun: b.periodNoun,
        openingPlanned: b.openingPlanned,
        adjusted: b.adjustedThisCycle,
        planned: b.plannedAmount,
        funded: b.fundedAmount,
        spent: b.spentAmount,
        remaining: b.balance,
        /** Spend as a share of what the cycle opened with. Can exceed 100. */
        pctOfOpening: pct(spent, opening),
      };
    })
    .sort((a, b) => b.pctOfOpening - a.pctOfOpening);

  const planTotals = plans.reduce(
    (acc, p) => ({
      opening: acc.opening.add(p.openingPlanned),
      adjusted: acc.adjusted.add(p.adjusted),
      spent: acc.spent.add(p.spent),
    }),
    { opening: zero, adjusted: zero, spent: zero },
  );

  // --- The floor under everything else ------------------------------------
  let committedOut = zero;
  let committedIn = zero;
  const commitments = rules
    .map((r) => {
      const per = monthlyEquivalent(r.amount, r.frequency, r.interval);
      if (r.kind === TxKind.EXPENSE) committedOut = committedOut.add(per);
      else committedIn = committedIn.add(per);
      return {
        id: r.id,
        name: r.name,
        kind: r.kind,
        amount: r.amount.toFixed(2),
        frequency: r.frequency,
        interval: r.interval,
        nextRun: r.nextRun.toISOString(),
        autoPost: r.autoPost,
        category: r.category,
        monthlyEquivalent: per.toFixed(2),
      };
    })
    .sort((a, b) => Number(b.monthlyEquivalent) - Number(a.monthlyEquivalent));

  // --- Wants, and how long they sit ---------------------------------------
  const byStatus = (s: WishlistStatus) => wishes.filter((w) => w.status === s);
  const planned = byStatus(WishlistStatus.PLANNED);
  const toPlan: number[] = [];
  const toBuy: number[] = [];
  for (const w of wishes) {
    if (w.plannedAt) toPlan.push((w.plannedAt.getTime() - w.createdAt.getTime()) / DAY);
    if (w.boughtAt) toBuy.push((w.boughtAt.getTime() - (w.plannedAt ?? w.createdAt).getTime()) / DAY);
  }
  // A want carries no price of its own; the money lives on the plan behind it,
  // so only planned wants have a value at all.
  const plannedValue = planned.reduce(
    (s, w) => (w.budget && w.budget.currency === currency ? s.add(w.budget.plannedAmount) : s),
    zero,
  );

  // --- Who owes whom ------------------------------------------------------
  // Outstanding, not face value: a 5,000 loan repaid down to 1,000 is exposure
  // of 1,000.
  const ledgerByKind = new Map<LedgerKind, { total: Prisma.Decimal; count: number }>();
  const counterparties: { name: string; kind: LedgerKind; outstanding: string; dueDate: string | null; overdue: boolean }[] = [];
  for (const e of ledgerEntries) {
    const paid = e.payments.reduce((s, p) => s.add(p.amount), zero);
    const outstanding = Prisma.Decimal.max(zero, e.totalAmount.sub(paid));
    if (outstanding.lte(0)) continue;
    const row = ledgerByKind.get(e.kind) ?? { total: zero, count: 0 };
    ledgerByKind.set(e.kind, { total: row.total.add(outstanding), count: row.count + 1 });
    counterparties.push({
      name: e.counterparty,
      kind: e.kind,
      outstanding: outstanding.toFixed(2),
      dueDate: e.dueDate ? e.dueDate.toISOString() : null,
      overdue: !!e.dueDate && e.dueDate < now,
    });
  }
  counterparties.sort((a, b) => Number(b.outstanding) - Number(a.outstanding));
  const kindTotal = (k: LedgerKind) => (ledgerByKind.get(k)?.total ?? zero).toFixed(2);
  const kindCount = (k: LedgerKind) => ledgerByKind.get(k)?.count ?? 0;

  const daysInMonth = Math.round((end.getTime() - start.getTime()) / DAY);
  const daysElapsed = inProgress
    ? Math.max(1, Math.ceil((now.getTime() - start.getTime()) / DAY))
    : daysInMonth;

  return {
    period: {
      month: start.toISOString().slice(0, 7),
      start: start.toISOString(),
      end: end.toISOString(),
      inProgress,
      daysElapsed,
      daysInMonth,
    },
    scope: {
      currency,
      /** Other currencies held with no rate into the scoped one. */
      missingRates,
      complete: missingRates.length === 0,
    },
    history: {
      hasPrevious,
      firstTransactionAt: firstTx?.date.toISOString() ?? null,
    },
    cashFlow: {
      income: income.toFixed(2),
      expense: expense.toFixed(2),
      net: net.toFixed(2),
      previous: {
        income: prevIncome.toFixed(2),
        expense: prevExpense.toFixed(2),
        net: prevNet.toFixed(2),
      },
      deltaNetPct: hasPrevious ? delta(net, prevNet) : null,
      deltaExpensePct: hasPrevious ? delta(expense, prevExpense) : null,
      /** Share of income kept. Null when nothing came in. */
      savingsRate: income.gt(0) ? pct(net, income) : null,
    },
    unplanned: {
      amount: unplannedSpend.toFixed(2),
      totalExpense: expense.toFixed(2),
      pct: pct(unplannedSpend, expense),
    },
    cash: {
      real: real.toFixed(2),
      locked: locked.toFixed(2),
      available: available.toFixed(2),
      lockedPct: pct(locked, real),
      accountCount: accountRows.length,
    },
    plans: {
      items: plans,
      totals: {
        opening: planTotals.opening.toFixed(2),
        adjusted: planTotals.adjusted.toFixed(2),
        spent: planTotals.spent.toFixed(2),
        pctOfOpening: pct(planTotals.spent, planTotals.opening),
      },
      overspentCount: plans.filter((p) => p.pctOfOpening > 100).length,
      adjustedCount: plans.filter((p) => Number(p.adjusted) !== 0).length,
    },
    commitments: {
      monthlyOut: committedOut.toFixed(2),
      monthlyIn: committedIn.toFixed(2),
      items: commitments,
      /** What the fixed floor eats out of this month's income. */
      shareOfIncome: income.gt(0) ? pct(committedOut, income) : null,
    },
    wishlist: {
      wanting: byStatus(WishlistStatus.WANTING).length,
      planned: planned.length,
      bought: byStatus(WishlistStatus.BOUGHT).length,
      dropped: byStatus(WishlistStatus.DROPPED).length,
      plannedValue: plannedValue.toFixed(2),
      avgDaysToPlan: avgDays(toPlan),
      avgDaysToBuy: avgDays(toBuy),
    },
    ledger: {
      lent: kindTotal(LedgerKind.LENT),
      lentCount: kindCount(LedgerKind.LENT),
      borrowed: kindTotal(LedgerKind.BORROWED),
      borrowedCount: kindCount(LedgerKind.BORROWED),
      expectedIn: kindTotal(LedgerKind.EXPECTED_IN),
      expectedOut: kindTotal(LedgerKind.EXPECTED_OUT),
      counterparties: counterparties.slice(0, 5),
      overdueCount: counterparties.filter((c) => c.overdue).length,
    },
  };
}

export type AnalyticsPageData = Awaited<ReturnType<typeof page>>;
