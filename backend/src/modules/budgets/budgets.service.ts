import { BudgetPeriod, CategoryKind, Prisma, TxKind, type Budget } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type { UpsertBudgetInput } from './budgets.schema.js';

const DAY = 86_400_000;
const zero = new Prisma.Decimal(0);

/** Calendar-month bounds for a YYYY-MM (or the current month). Used across analytics/dashboard. */
export function monthRange(month?: string): { start: Date; end: Date } {
  const now = new Date();
  let y = now.getUTCFullYear();
  let m = now.getUTCMonth() + 1;
  if (month) {
    const parts = month.split('-');
    y = Number(parts[0]);
    m = Number(parts[1]);
  }
  return {
    start: new Date(Date.UTC(y, m - 1, 1)),
    end: new Date(Date.UTC(y, m, 1)),
  };
}

/** Reference date for "current period": the 1st of a YYYY-MM, or today. */
export function refDate(month?: string): Date {
  if (month) {
    const [y, m] = month.split('-').map(Number);
    return new Date(Date.UTC(y!, (m ?? 1) - 1, 1));
  }
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

function startOfDayUTC(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
}

/** Aligned start of the period that contains `d` (the anchor for a budget). */
function anchorStart(period: BudgetPeriod, d: Date): Date {
  switch (period) {
    case BudgetPeriod.WEEKLY:
      return startOfDayUTC(d); // weekly periods run from the budget's start day
    case BudgetPeriod.MONTHLY:
      return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1));
    case BudgetPeriod.QUARTERLY:
      return new Date(Date.UTC(d.getUTCFullYear(), Math.floor(d.getUTCMonth() / 3) * 3, 1));
    case BudgetPeriod.YEARLY:
      return new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  }
}

/** The start of the period `n` steps after an anchor-aligned `start`. */
function addPeriods(period: BudgetPeriod, start: Date, n: number): Date {
  switch (period) {
    case BudgetPeriod.WEEKLY: {
      const d = new Date(start);
      d.setUTCDate(d.getUTCDate() + 7 * n);
      return d;
    }
    case BudgetPeriod.MONTHLY:
      return new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + n, 1));
    case BudgetPeriod.QUARTERLY:
      return new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + 3 * n, 1));
    case BudgetPeriod.YEARLY:
      return new Date(Date.UTC(start.getUTCFullYear() + n, start.getUTCMonth(), 1));
  }
}

/** How many whole periods `ref` sits after `anchor` (can be negative). */
function periodIndex(period: BudgetPeriod, anchor: Date, ref: Date): number {
  switch (period) {
    case BudgetPeriod.WEEKLY:
      return Math.floor((startOfDayUTC(ref).getTime() - anchor.getTime()) / (7 * DAY));
    case BudgetPeriod.MONTHLY:
      return (ref.getUTCFullYear() - anchor.getUTCFullYear()) * 12 + (ref.getUTCMonth() - anchor.getUTCMonth());
    case BudgetPeriod.QUARTERLY: {
      const months =
        (ref.getUTCFullYear() - anchor.getUTCFullYear()) * 12 + (ref.getUTCMonth() - anchor.getUTCMonth());
      return Math.floor(months / 3);
    }
    case BudgetPeriod.YEARLY:
      return ref.getUTCFullYear() - anchor.getUTCFullYear();
  }
}

function periodLabel(period: BudgetPeriod, start: Date, end: Date): string {
  const d = (x: Date) =>
    new Intl.DateTimeFormat('en-GB', { day: '2-digit', month: 'short', timeZone: 'UTC' }).format(x);
  switch (period) {
    case BudgetPeriod.WEEKLY: {
      const last = new Date(end.getTime() - DAY);
      return `${d(start)} – ${d(last)}`;
    }
    case BudgetPeriod.MONTHLY:
      return new Intl.DateTimeFormat('en-GB', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(start);
    case BudgetPeriod.QUARTERLY:
      return `Q${Math.floor(start.getUTCMonth() / 3) + 1} ${start.getUTCFullYear()}`;
    case BudgetPeriod.YEARLY:
      return String(start.getUTCFullYear());
  }
}

/** Sum of EXPENSE transactions for a category in [start, end). */
async function spentIn(userId: string, categoryId: string, start: Date, end: Date): Promise<Prisma.Decimal> {
  const agg = await prisma.transaction.aggregate({
    where: { userId, categoryId, kind: TxKind.EXPENSE, date: { gte: start, lt: end } },
    _sum: { amount: true },
  });
  return agg._sum.amount ?? zero;
}

interface Window {
  index: number;
  start: Date;
  end: Date;
  anchor: Date;
}

function windowFor(budget: Pick<Budget, 'period' | 'startDate' | 'createdAt'>, ref: Date): Window {
  const anchor = anchorStart(budget.period, budget.startDate ?? budget.createdAt);
  const rawIndex = periodIndex(budget.period, anchor, ref);
  const index = Math.max(0, rawIndex);
  return {
    index: rawIndex, // may be negative → budget hasn't started yet
    start: addPeriods(budget.period, anchor, index),
    end: addPeriods(budget.period, anchor, index + 1),
    anchor,
  };
}

type BudgetStatus = 'ok' | 'warning' | 'over' | 'upcoming' | 'ended';

/** Resolve a budget against a reference date: effective limit (incl. rollover), spend, status. */
async function evaluate(
  userId: string,
  budget: Budget,
  ref: Date,
): Promise<{
  win: Window;
  spent: Prisma.Decimal;
  carryIn: Prisma.Decimal;
  effectiveLimit: Prisma.Decimal;
  pct: number;
  status: BudgetStatus;
}> {
  const win = windowFor(budget, ref);
  const ended = budget.endDate ? win.start >= budget.endDate : false;
  const upcoming = win.index < 0;

  const spent = await spentIn(userId, budget.categoryId, win.start, win.end);

  // Rollover: unused (or overspent) budget from every prior period accumulates.
  // Σ(amount − spent_i) over i in [0, index) = index·amount − spentBefore.
  let carryIn = zero;
  if (budget.rollover && win.index > 0) {
    const spentBefore = await spentIn(userId, budget.categoryId, win.anchor, win.start);
    carryIn = budget.amount.mul(win.index).sub(spentBefore);
  }

  const effectiveLimit = budget.amount.add(carryIn);
  const pct = effectiveLimit.gt(0)
    ? Number(spent.div(effectiveLimit).mul(100).toFixed(1))
    : spent.gt(0)
      ? 100
      : 0;

  let status: BudgetStatus;
  if (upcoming) status = 'upcoming';
  else if (ended) status = 'ended';
  else if (pct >= 100) status = 'over';
  else if (pct >= budget.alertThreshold) status = 'warning';
  else status = 'ok';

  return { win, spent, carryIn, effectiveLimit, pct, status };
}

function serialize(budget: Budget, ev: Awaited<ReturnType<typeof evaluate>>, category: unknown) {
  const { win, spent, carryIn, effectiveLimit, pct, status } = ev;
  return {
    id: budget.id,
    categoryId: budget.categoryId,
    category,
    amount: budget.amount.toFixed(2),
    effectiveLimit: effectiveLimit.toFixed(2),
    carryIn: carryIn.toFixed(2),
    alertThreshold: budget.alertThreshold,
    period: budget.period,
    rollover: budget.rollover,
    startDate: budget.startDate ? budget.startDate.toISOString() : null,
    endDate: budget.endDate ? budget.endDate.toISOString() : null,
    spent: spent.toFixed(2),
    remaining: effectiveLimit.sub(spent).toFixed(2),
    pct,
    status,
    periodStart: win.start.toISOString(),
    periodEnd: win.end.toISOString(),
    periodLabel: periodLabel(budget.period, win.start, win.end),
  };
}

/** Budgets, each resolved for the period containing the reference month/today. */
export async function list(user: AuthUser, month?: string) {
  const ref = refDate(month);
  const budgets = await prisma.budget.findMany({
    where: { userId: user.id },
    include: { category: { select: { id: true, name: true, icon: true, color: true, archived: true } } },
    orderBy: { createdAt: 'asc' },
  });

  const items = await Promise.all(
    budgets.map(async (b) => {
      const ev = await evaluate(user.id, b, ref);
      return serialize(b, ev, b.category);
    }),
  );

  const budgeted = items.reduce((s, i) => s.add(new Prisma.Decimal(i.effectiveLimit)), zero);
  const spent = items.reduce((s, i) => s.add(new Prisma.Decimal(i.spent)), zero);

  return {
    items,
    totals: {
      budgeted: budgeted.toFixed(2),
      spent: spent.toFixed(2),
      remaining: budgeted.sub(spent).toFixed(2),
    },
  };
}

/** Per-period spend history for one category's budget, newest period first. */
export async function history(user: AuthUser, categoryId: string, periods: number) {
  const budget = await prisma.budget.findFirst({
    where: { categoryId, userId: user.id },
    include: { category: { select: { id: true, name: true, icon: true, color: true } } },
  });
  if (!budget) throw new NotFoundError('Budget not found');

  const now = new Date();
  const anchor = anchorStart(budget.period, budget.startDate ?? budget.createdAt);
  const currentIndex = Math.max(0, periodIndex(budget.period, anchor, now));
  const firstIndex = Math.max(0, currentIndex - periods + 1);

  const rangeStart = addPeriods(budget.period, anchor, firstIndex);
  const rangeEnd = addPeriods(budget.period, anchor, currentIndex + 1);

  // One query, bucketed by period in JS.
  const txns = await prisma.transaction.findMany({
    where: {
      userId: user.id,
      categoryId,
      kind: TxKind.EXPENSE,
      date: { gte: rangeStart, lt: rangeEnd },
    },
    select: { amount: true, date: true },
  });

  const spentByIndex = new Map<number, Prisma.Decimal>();
  for (const t of txns) {
    const i = periodIndex(budget.period, anchor, t.date);
    spentByIndex.set(i, (spentByIndex.get(i) ?? zero).add(t.amount));
  }

  // Rolling carry needs everything spent before the first shown period.
  let runningCarry = zero;
  if (budget.rollover && firstIndex > 0) {
    const before = await spentIn(user.id, categoryId, anchor, rangeStart);
    runningCarry = budget.amount.mul(firstIndex).sub(before);
  }

  const rows: Array<Record<string, unknown>> = [];
  for (let i = firstIndex; i <= currentIndex; i += 1) {
    const start = addPeriods(budget.period, anchor, i);
    const end = addPeriods(budget.period, anchor, i + 1);
    const spent = spentByIndex.get(i) ?? zero;
    const carryIn = budget.rollover ? runningCarry : zero;
    const effectiveLimit = budget.amount.add(carryIn);
    const remaining = effectiveLimit.sub(spent);
    const pct = effectiveLimit.gt(0)
      ? Number(spent.div(effectiveLimit).mul(100).toFixed(1))
      : spent.gt(0)
        ? 100
        : 0;
    rows.push({
      index: i,
      current: i === currentIndex,
      label: periodLabel(budget.period, start, end),
      start: start.toISOString(),
      end: end.toISOString(),
      limit: budget.amount.toFixed(2),
      carryIn: carryIn.toFixed(2),
      effectiveLimit: effectiveLimit.toFixed(2),
      spent: spent.toFixed(2),
      remaining: remaining.toFixed(2),
      pct,
      status: pct >= 100 ? 'over' : pct >= budget.alertThreshold ? 'warning' : 'ok',
    });
    if (budget.rollover) runningCarry = remaining; // this period's leftover feeds the next
  }

  return {
    category: budget.category,
    period: budget.period,
    rollover: budget.rollover,
    amount: budget.amount.toFixed(2),
    items: rows.reverse(), // newest first
  };
}

/** Create or replace the ongoing budget for a category. */
export async function upsert(user: AuthUser, categoryId: string, input: UpsertBudgetInput) {
  const category = await prisma.category.findFirst({ where: { id: categoryId, userId: user.id } });
  if (!category) throw new NotFoundError('Category not found');
  if (category.kind !== CategoryKind.EXPENSE) {
    throw new BadRequestError('Budgets only apply to expense categories');
  }

  const data = {
    amount: input.amount,
    alertThreshold: input.alertThreshold,
    period: input.period,
    rollover: input.rollover,
    startDate: input.startDate ?? null,
    endDate: input.endDate ?? null,
  };

  return prisma.budget.upsert({
    where: { categoryId },
    create: { userId: user.id, categoryId, ...data },
    update: data,
  });
}

export async function remove(user: AuthUser, categoryId: string) {
  const budget = await prisma.budget.findFirst({ where: { categoryId, userId: user.id } });
  if (!budget) throw new NotFoundError('Budget not found');
  await prisma.budget.delete({ where: { id: budget.id } });
}
