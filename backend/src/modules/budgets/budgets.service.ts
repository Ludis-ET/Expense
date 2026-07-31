/**
 * Budget plans (envelopes).
 *
 * A plan is a named pot with a planned amount. You fill it from accounts; that
 * money stays physically in the account but is *reserved*, so it drops out of
 * every "available" figure (accounts page, dashboard, transaction guard).
 * Spending against the plan writes a normal EXPENSE transaction that carries
 * `budgetId`: the real balance goes down and the reservation is freed at the
 * same moment, so nothing is double-counted.
 *
 *   pot balance   = SUM(allocations) - SUM(plan expenses)
 *   account lock  = SUM(allocations from that account) - SUM(plan expenses on it)
 *
 * The one exception is the built-in UNPLANNED plan. It is never funded: it just
 * labels spending you did straight from an account without reserving first.
 * It must therefore be excluded from every reservation aggregate, or its
 * expenses would cancel out real reservations on the same account.
 */
import {
  BudgetAllocationKind,
  BudgetKind,
  BudgetState,
  Prisma,
  TxKind,
  type Budget,
} from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { notify } from '../notifications/notifications.service.js';
import { addRecurrence, cycleLabel, periodNoun, recurrenceLabel } from './budgets.periods.js';
import type {
  AdjustBudgetInput,
  CreateBudgetInput,
  FundBudgetInput,
  ListBudgetsQuery,
  ReleaseBudgetInput,
  UpdateBudgetInput,
} from './budgets.schema.js';

export { monthRange, refDate } from './budgets.periods.js';

const zero = new Prisma.Decimal(0);
const dec = (v: Prisma.Decimal | number | string) => new Prisma.Decimal(v);

const categorySelect = { id: true, name: true, icon: true, color: true, kind: true } as const;
const accountSelect = { id: true, name: true, type: true, currency: true, color: true, icon: true } as const;

export const UNPLANNED_NAME = 'Unplanned';

/** Deterministic id, so the primary key alone guarantees one per user. */
export const unplannedId = (userId: string) => `unplanned_${userId}`;

/**
 * The built-in catch-all plan. Created on demand so existing users, seeded
 * users and brand-new signups all converge on the same row.
 */
export async function ensureUnplanned(userId: string, currency = 'ETB') {
  const id = unplannedId(userId);
  return prisma.budget.upsert({
    where: { id },
    update: {},
    create: {
      id,
      userId,
      name: UNPLANNED_NAME,
      kind: BudgetKind.UNPLANNED,
      plannedAmount: 0,
      cycleOpeningPlanned: 0,
      currency: currency.toUpperCase(),
      icon: 'circle-ellipsis',
      color: '#64748b',
      note: 'Everything you spend without setting money aside first.',
      alertThreshold: 100,
    },
  });
}

/**
 * Reservation aggregates must never see UNPLANNED expenses - those spend real
 * account money that was never set aside, so counting them would wrongly
 * release other plans' reservations on the same account.
 */
const RESERVED_EXPENSES = {
  kind: TxKind.EXPENSE,
  budgetId: { not: null },
  budget: { is: { kind: { not: BudgetKind.UNPLANNED } } },
} satisfies Prisma.TransactionWhereInput;

// ---------------------------------------------------------------------------
// Aggregates
// ---------------------------------------------------------------------------

interface Totals {
  /** Everything ever put in, across all cycles. */
  allocated: Prisma.Decimal;
  /** Everything ever spent out of the pot, across all cycles. */
  spent: Prisma.Decimal;
  /** Put in during the current cycle only. */
  allocatedThisCycle: Prisma.Decimal;
  /** Spent during the current cycle only. */
  spentThisCycle: Prisma.Decimal;
  /** Net raises/cuts to the plan amount during the current cycle. */
  adjustedThisCycle: Prisma.Decimal;
}

async function totalsFor(budgetId: string, cycleIndex: number): Promise<Totals> {
  const [allocAll, allocCycle, spentAll, spentCycle, adjCycle] = await Promise.all([
    prisma.budgetAllocation.aggregate({ where: { budgetId }, _sum: { amount: true } }),
    prisma.budgetAllocation.aggregate({ where: { budgetId, cycleIndex }, _sum: { amount: true } }),
    prisma.transaction.aggregate({
      where: { budgetId, kind: TxKind.EXPENSE },
      _sum: { amount: true },
    }),
    prisma.transaction.aggregate({
      where: { budgetId, kind: TxKind.EXPENSE, budgetCycle: cycleIndex },
      _sum: { amount: true },
    }),
    prisma.budgetAdjustment.aggregate({ where: { budgetId, cycleIndex }, _sum: { amount: true } }),
  ]);
  return {
    allocated: allocAll._sum.amount ?? zero,
    spent: spentAll._sum.amount ?? zero,
    allocatedThisCycle: allocCycle._sum.amount ?? zero,
    spentThisCycle: spentCycle._sum.amount ?? zero,
    adjustedThisCycle: adjCycle._sum.amount ?? zero,
  };
}

/** Batched version of `totalsFor` for a whole list of plans. */
async function totalsForMany(budgets: Budget[]): Promise<Map<string, Totals>> {
  const ids = budgets.map((b) => b.id);
  const map = new Map<string, Totals>();
  for (const b of budgets) {
    map.set(b.id, {
      allocated: zero,
      spent: zero,
      allocatedThisCycle: zero,
      spentThisCycle: zero,
      adjustedThisCycle: zero,
    });
  }
  if (ids.length === 0) return map;

  const cycleOf = new Map(budgets.map((b) => [b.id, b.cycleIndex]));
  const [allocs, spends, adjustments] = await Promise.all([
    prisma.budgetAllocation.groupBy({
      by: ['budgetId', 'cycleIndex'],
      where: { budgetId: { in: ids } },
      _sum: { amount: true },
    }),
    prisma.transaction.groupBy({
      by: ['budgetId', 'budgetCycle'],
      where: { budgetId: { in: ids }, kind: TxKind.EXPENSE },
      _sum: { amount: true },
    }),
    prisma.budgetAdjustment.groupBy({
      by: ['budgetId', 'cycleIndex'],
      where: { budgetId: { in: ids } },
      _sum: { amount: true },
    }),
  ]);

  for (const row of allocs) {
    const t = map.get(row.budgetId)!;
    const amt = row._sum.amount ?? zero;
    t.allocated = t.allocated.add(amt);
    if (row.cycleIndex === cycleOf.get(row.budgetId)) t.allocatedThisCycle = t.allocatedThisCycle.add(amt);
  }
  for (const row of spends) {
    if (!row.budgetId) continue;
    const t = map.get(row.budgetId);
    if (!t) continue;
    const amt = row._sum.amount ?? zero;
    t.spent = t.spent.add(amt);
    if (row.budgetCycle === cycleOf.get(row.budgetId)) t.spentThisCycle = t.spentThisCycle.add(amt);
  }
  for (const row of adjustments) {
    const t = map.get(row.budgetId);
    if (!t) continue;
    if (row.cycleIndex === cycleOf.get(row.budgetId)) {
      t.adjustedThisCycle = t.adjustedThisCycle.add(row._sum.amount ?? zero);
    }
  }
  return map;
}

/** The numbers every view of a plan needs, derived from its totals. */
function derive(budget: Budget, t: Totals) {
  const balance = t.allocated.sub(t.spent); // money sitting in the pot right now
  const carriedIn = t.allocated.sub(t.allocatedThisCycle).sub(t.spent.sub(t.spentThisCycle));
  const funded = carriedIn.add(t.allocatedThisCycle); // the pot's ceiling this cycle
  const fillable = Prisma.Decimal.max(zero, budget.plannedAmount.sub(funded));
  const spent = t.spentThisCycle;
  const pctOfPlan = budget.plannedAmount.gt(0)
    ? Number(spent.div(budget.plannedAmount).mul(100).toFixed(1))
    : 0;
  const pctFunded = budget.plannedAmount.gt(0)
    ? Number(funded.div(budget.plannedAmount).mul(100).toFixed(1))
    : 0;
  const pctSpentOfFunded = funded.gt(0) ? Number(spent.div(funded).mul(100).toFixed(1)) : 0;
  return { balance, carriedIn, funded, fillable, spent, pctOfPlan, pctFunded, pctSpentOfFunded };
}

type Health =
  | 'unplanned'
  | 'scheduled'
  | 'empty'
  | 'partly-funded'
  | 'ready'
  | 'spending'
  | 'low'
  | 'drained'
  | 'closed';

/** A plan cannot be spent from before the start date the user chose. */
export function hasStarted(budget: Pick<Budget, 'startsAt'>, at = new Date()): boolean {
  return budget.startsAt <= at;
}

function health(budget: Budget, d: ReturnType<typeof derive>): Health {
  if (budget.kind === BudgetKind.UNPLANNED) return 'unplanned';
  if (budget.state === BudgetState.CLOSED) return 'closed';
  if (!hasStarted(budget)) return 'scheduled';
  if (d.funded.lte(0)) return 'empty';
  if (d.balance.lte(0)) return 'drained';
  if (d.spent.lte(0)) return d.fillable.gt(0) ? 'partly-funded' : 'ready';
  return d.pctSpentOfFunded >= budget.alertThreshold ? 'low' : 'spending';
}

type BudgetWithCategory = Budget & { category?: { id: string; name: string } | null };

function serialize(budget: BudgetWithCategory, t: Totals) {
  const d = derive(budget, t);
  return {
    id: budget.id,
    name: budget.name,
    categoryId: budget.categoryId,
    category: budget.category ?? null,
    kind: budget.kind,
    isUnplanned: budget.kind === BudgetKind.UNPLANNED,
    recurrenceUnit: budget.recurrenceUnit,
    recurrenceInterval: budget.recurrenceInterval,
    /** "monthly", "every 6 hours" - ready to print. */
    recurrenceLabel: budget.recurrenceUnit
      ? recurrenceLabel(budget.recurrenceUnit, budget.recurrenceInterval)
      : null,
    /** The noun one cycle is measured in: "month", "6 hours". */
    periodNoun: budget.recurrenceUnit
      ? periodNoun(budget.recurrenceUnit, budget.recurrenceInterval)
      : null,
    currency: budget.currency,
    icon: budget.icon,
    color: budget.color,
    note: budget.note,
    alertThreshold: budget.alertThreshold,
    state: budget.state,
    closedAt: budget.closedAt ? budget.closedAt.toISOString() : null,

    plannedAmount: budget.plannedAmount.toFixed(2),
    /** What the plan was set to when this cycle opened, before any raise or cut. */
    openingPlanned: budget.cycleOpeningPlanned.toFixed(2),
    /** Net raises (+) and cuts (-) made to the plan amount during this cycle. */
    adjustedThisCycle: t.adjustedThisCycle.toFixed(2),
    /** Filled into the pot this cycle, including money carried over. */
    fundedAmount: d.funded.toFixed(2),
    /** Carried over from the previous cycle. */
    carriedIn: d.carriedIn.toFixed(2),
    /** Still accepted from accounts before hitting the planned amount. */
    fillable: d.fillable.toFixed(2),
    /** Spent out of the pot this cycle. */
    spentAmount: d.spent.toFixed(2),
    /** What is left to spend right now. */
    balance: d.balance.toFixed(2),

    pctFunded: Math.min(100, d.pctFunded),
    pctOfPlan: Math.min(100, d.pctOfPlan),
    pctSpentOfFunded: Math.min(100, d.pctSpentOfFunded),
    health: health(budget, d),

    cycleIndex: budget.cycleIndex,
    startsAt: budget.startsAt.toISOString(),
    started: hasStarted(budget),
    cycleStartedAt: budget.cycleStartedAt.toISOString(),
    nextResetAt: budget.nextResetAt ? budget.nextResetAt.toISOString() : null,
    endDate: budget.endDate ? budget.endDate.toISOString() : null,
    cycleLabel: budget.recurrenceUnit
      ? cycleLabel(
          budget.recurrenceUnit,
          budget.recurrenceInterval,
          budget.cycleStartedAt,
          budget.nextResetAt ?? budget.cycleStartedAt,
        )
      : null,

    createdAt: budget.createdAt.toISOString(),
    updatedAt: budget.updatedAt.toISOString(),
  };
}

export type SerializedBudget = ReturnType<typeof serialize>;

// ---------------------------------------------------------------------------
// Reservation lookups (used by accounts / transactions / wishlist)
// ---------------------------------------------------------------------------

/**
 * How much of each account's balance is currently tied up in plans.
 * `SUM(allocations from the account) - SUM(plan expenses charged to it)`.
 *
 * UNPLANNED expenses are deliberately excluded: they were never reserved, so
 * counting them here would release other plans' money on the same account.
 */
export async function lockedByAccount(userId: string): Promise<Map<string, Prisma.Decimal>> {
  const [allocs, spends] = await Promise.all([
    prisma.budgetAllocation.groupBy({
      by: ['accountId'],
      where: { userId },
      _sum: { amount: true },
    }),
    // Grouped by the account the reservation sat on, which is not necessarily
    // the one the cash left.
    prisma.transaction.groupBy({
      by: ['budgetSourceAccountId'],
      where: { userId, ...RESERVED_EXPENSES },
      _sum: { amount: true },
    }),
  ]);

  const map = new Map<string, Prisma.Decimal>();
  for (const a of allocs) map.set(a.accountId, a._sum.amount ?? zero);
  for (const s of spends) {
    if (!s.budgetSourceAccountId) continue;
    const id = s.budgetSourceAccountId;
    map.set(id, (map.get(id) ?? zero).sub(s._sum.amount ?? zero));
  }
  for (const [k, v] of map) map.set(k, Prisma.Decimal.max(zero, v));
  return map;
}

/** Total reserved across every plan in one currency. */
export async function lockedTotal(userId: string, currency: string): Promise<Prisma.Decimal> {
  const accounts = await prisma.account.findMany({
    where: { userId, currency: currency.toUpperCase(), archived: false },
    select: { id: true },
  });
  if (accounts.length === 0) return zero;
  const byAccount = await lockedByAccount(userId);
  return accounts.reduce((s, a) => s.add(byAccount.get(a.id) ?? zero), zero);
}

/**
 * Per-account remaining share of one plan's pot, largest first.
 *
 * Meaningless for UNPLANNED, which is never filled: subtracting its spending
 * from zero allocations would report negative "held" amounts. It holds no
 * money, so it has no sources.
 */
export async function sourcesFor(budgetId: string) {
  const budget = await prisma.budget.findUnique({
    where: { id: budgetId },
    select: { kind: true },
  });
  if (!budget || budget.kind === BudgetKind.UNPLANNED) return [];

  const [allocs, spends] = await Promise.all([
    prisma.budgetAllocation.groupBy({
      by: ['accountId'],
      where: { budgetId },
      _sum: { amount: true },
    }),
    prisma.transaction.groupBy({
      by: ['budgetSourceAccountId'],
      where: { budgetId, kind: TxKind.EXPENSE },
      _sum: { amount: true },
    }),
  ]);

  const shares = new Map<string, Prisma.Decimal>();
  for (const a of allocs) shares.set(a.accountId, a._sum.amount ?? zero);
  for (const s of spends) {
    if (!s.budgetSourceAccountId) continue;
    const id = s.budgetSourceAccountId;
    shares.set(id, (shares.get(id) ?? zero).sub(s._sum.amount ?? zero));
  }

  const ids = [...shares.keys()];
  if (ids.length === 0) return [];
  const accounts = await prisma.account.findMany({ where: { id: { in: ids } }, select: accountSelect });
  const byId = new Map(accounts.map((a) => [a.id, a]));

  return ids
    .map((id) => ({ account: byId.get(id) ?? null, available: shares.get(id) ?? zero }))
    .filter((r) => r.account !== null)
    .sort((a, b) => b.available.comparedTo(a.available));
}

// ---------------------------------------------------------------------------
// Recurring cycles
// ---------------------------------------------------------------------------

/**
 * Runaway guard when catching up a long-dormant plan. Generous because an
 * hourly plan legitimately rolls 24x a day; quiet cycles are cheap (skipped).
 */
const MAX_ROLLS = 800;

/**
 * Close out every cycle of a recurring plan whose reset time has passed:
 * freeze a snapshot of what was planned/funded/spent, then open the next cycle.
 * Leftover money is not moved anywhere - the pot balance is cumulative, so it
 * simply carries in as the new cycle's starting balance.
 */
export async function rollDueCycles(userId: string): Promise<void> {
  const now = new Date();
  const due = await prisma.budget.findMany({
    where: {
      userId,
      kind: BudgetKind.RECURRING,
      state: BudgetState.ACTIVE,
      nextResetAt: { lte: now },
    },
  });

  for (const budget of due) {
    let b = budget;
    let rolls = 0;
    let carriedForward = zero;
    let skipped = 0;

    while (b.nextResetAt && b.nextResetAt <= now && rolls < MAX_ROLLS) {
      const t = await totalsFor(b.id, b.cycleIndex);
      const d = derive(b, t);
      const txCount = await prisma.transaction.count({
        where: { budgetId: b.id, budgetCycle: b.cycleIndex, kind: TxKind.EXPENSE },
      });

      const endedAt = b.nextResetAt;

      // A fast cadence (hourly, daily) left dormant would otherwise mint a
      // snapshot per empty cycle. Only cycles where something actually happened
      // are worth keeping; the rest just advance the clock. Leftovers still
      // carry, because the pot balance is cumulative and never touched here.
      const hadActivity =
        !t.allocatedThisCycle.isZero() || !d.spent.isZero() || !t.adjustedThisCycle.isZero();
      if (hadActivity) {
        await prisma.budgetCycle.upsert({
          where: { budgetId_index: { budgetId: b.id, index: b.cycleIndex } },
          create: {
            budgetId: b.id,
            index: b.cycleIndex,
            startedAt: b.cycleStartedAt,
            endedAt,
            label: cycleLabel(b.recurrenceUnit, b.recurrenceInterval, b.cycleStartedAt, endedAt),
            openingPlanned: b.cycleOpeningPlanned,
            adjustedAmount: t.adjustedThisCycle,
            plannedAmount: b.plannedAmount,
            carriedIn: d.carriedIn,
            fundedAmount: d.funded,
            spentAmount: d.spent,
            leftoverAmount: d.balance,
            txCount,
          },
          update: {
            endedAt,
            adjustedAmount: t.adjustedThisCycle,
            plannedAmount: b.plannedAmount,
            fundedAmount: d.funded,
            spentAmount: d.spent,
            leftoverAmount: d.balance,
            txCount,
          },
        });
      } else {
        skipped += 1;
      }

      const finished = b.endDate ? endedAt >= b.endDate : false;
      b = await prisma.budget.update({
        where: { id: b.id },
        data: {
          cycleIndex: b.cycleIndex + 1,
          cycleStartedAt: endedAt,
          // The new cycle opens at whatever the plan is set to now, adjustments
          // and all - that figure is what the next cycle will be measured against.
          cycleOpeningPlanned: b.plannedAmount,
          nextResetAt: finished
            ? null
            : addRecurrence(b.recurrenceUnit!, b.recurrenceInterval, endedAt),
          ...(finished ? { state: BudgetState.CLOSED, closedAt: now } : {}),
        },
      });

      carriedForward = d.balance;
      rolls += 1;
      if (finished) break;
    }

    // One notification for the whole catch-up, not one per skipped cycle.
    if (rolls > 0 && carriedForward.gt(0)) {
      await notify(
        userId,
        'budget_cycle_rolled',
        `"${b.name}" started a new ${periodNoun(b.recurrenceUnit!, b.recurrenceInterval)} with ${carriedForward.toFixed(2)} ${b.currency} carried over${
          skipped > 0 ? ` (${skipped} quiet ${skipped === 1 ? 'cycle' : 'cycles'} skipped)` : ''
        }.`,
        `/budgets/${b.id}`,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

export async function list(user: AuthUser, query: ListBudgetsQuery = {}) {
  await ensureUnplanned(user.id);
  await rollDueCycles(user.id);

  const budgets = await prisma.budget.findMany({
    where: {
      userId: user.id,
      ...(query.state ? { state: query.state } : {}),
      ...(query.currency ? { currency: query.currency.toUpperCase() } : {}),
    },
    include: { category: { select: categorySelect } },
    orderBy: [{ state: 'asc' }, { createdAt: 'desc' }],
  });

  const totals = await totalsForMany(budgets);
  const items = budgets
    .map((b) => serialize(b, totals.get(b.id)!))
    // Unplanned is the home base: always first, whatever the sort.
    .sort((a, b) => Number(b.isUnplanned) - Number(a.isUnplanned));

  const real = items.filter((i) => !i.isUnplanned);
  const active = real.filter((i) => i.state === BudgetState.ACTIVE);

  const sum = (rows: SerializedBudget[], pick: (i: SerializedBudget) => string) =>
    rows.reduce((s, i) => s.add(dec(pick(i))), zero).toFixed(2);

  return {
    items,
    totals: {
      planned: sum(active, (i) => i.plannedAmount),
      funded: sum(active, (i) => i.fundedAmount),
      spent: sum(active, (i) => i.spentAmount),
      /** Money locked away in plans right now. */
      locked: sum(active, (i) => i.balance),
      /** Spending that never went through a plan, this cycle. */
      unplannedSpent: sum(items.filter((i) => i.isUnplanned), (i) => i.spentAmount),
      activeCount: active.length,
      closedCount: real.length - active.length,
    },
  };
}

/**
 * The extra "pay from" options on a transaction: every plan that still holds
 * money, plus Unplanned, which is always offered because it has no pot - it
 * spends whatever the chosen account has free.
 */
export async function spendableSources(user: AuthUser, currency?: string) {
  await ensureUnplanned(user.id);
  await rollDueCycles(user.id);

  const budgets = await prisma.budget.findMany({
    where: {
      userId: user.id,
      state: BudgetState.ACTIVE,
      ...(currency ? { currency: currency.toUpperCase() } : {}),
    },
    include: { category: { select: categorySelect } },
    orderBy: { name: 'asc' },
  });

  const totals = await totalsForMany(budgets);
  const offered = budgets
    .map((b) => serialize(b, totals.get(b.id)!))
    .filter((b) => b.isUnplanned || (b.started && Number(b.balance) > 0))
    .sort((a, b) => Number(b.isUnplanned) - Number(a.isUnplanned));

  const items = await Promise.all(
    offered.map(async (b) => ({
      id: b.id,
      name: b.name,
      currency: b.currency,
      balance: b.balance,
      icon: b.icon,
      color: b.color,
      categoryId: b.categoryId,
      category: b.category,
      isUnplanned: b.isUnplanned,
      // Unplanned draws on any account, so the caller picks one; funded plans
      // can only be charged to the accounts that actually filled them.
      sources: b.isUnplanned
        ? []
        : (await sourcesFor(b.id))
            .filter((s) => s.available.gt(0))
            .map((s) => ({ account: s.account, available: s.available.toFixed(2) })),
    })),
  );

  return { items };
}

/** How many timeline entries the detail page gets up front. */
const TIMELINE_LIMIT = 40;

/**
 * The plan detail page's summary. Transactions are deliberately *not* all
 * returned - Unplanned alone can hold years of them. The page pulls those from
 * `/transactions?budgetId=...`, which already paginates, searches and filters.
 */
export async function getById(user: AuthUser, id: string) {
  await rollDueCycles(user.id);

  const budget = await prisma.budget.findFirst({
    where: { id, userId: user.id },
    include: { category: { select: categorySelect } },
  });
  if (!budget) throw new NotFoundError('Budget plan not found');

  const t = await totalsFor(budget.id, budget.cycleIndex);
  const [allocations, recentTx, cycles, sources, txCount, cycleTxCount, firstTx, adjustments] =
    await Promise.all([
    prisma.budgetAllocation.findMany({
      where: { budgetId: budget.id },
      include: { account: { select: accountSelect } },
      orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
      take: TIMELINE_LIMIT,
    }),
    prisma.transaction.findMany({
      where: { budgetId: budget.id },
      include: {
        category: { select: categorySelect },
        account: { select: accountSelect },
      },
      orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
      take: TIMELINE_LIMIT,
    }),
    prisma.budgetCycle.findMany({ where: { budgetId: budget.id }, orderBy: { index: 'desc' } }),
    sourcesFor(budget.id),
    prisma.transaction.count({ where: { budgetId: budget.id } }),
    prisma.transaction.count({
      where: { budgetId: budget.id, kind: TxKind.EXPENSE, budgetCycle: budget.cycleIndex },
    }),
    prisma.transaction.findFirst({
      where: { budgetId: budget.id },
      orderBy: { date: 'asc' },
      select: { date: true },
    }),
    // Raises and cuts are rare next to transactions, so the whole history is
    // cheap to send and lets every cycle section show its own.
    prisma.budgetAdjustment.findMany({
      where: { budgetId: budget.id },
      orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
      take: 500,
    }),
  ]);

  const serializeTx = (tx: (typeof recentTx)[number]) => ({
    id: tx.id,
    amount: tx.amount.toFixed(2),
    currency: tx.currency,
    date: tx.date.toISOString(),
    payee: tx.payee,
    note: tx.note,
    tags: tx.tags,
    category: tx.category,
    account: tx.account,
    budgetCycle: tx.budgetCycle,
  });

  const serializeAlloc = (a: (typeof allocations)[number]) => ({
    id: a.id,
    kind: a.kind,
    amount: a.amount.toFixed(2),
    date: a.date.toISOString(),
    note: a.note,
    account: a.account,
    cycleIndex: a.cycleIndex,
  });

  const serializeAdjustment = (a: (typeof adjustments)[number]) => ({
    id: a.id,
    /** Signed: a raise is positive, a cut negative. */
    amount: a.amount.toFixed(2),
    date: a.date.toISOString(),
    reason: a.reason,
    cycleIndex: a.cycleIndex,
  });

  const adjustmentsByCycle = new Map<number, ReturnType<typeof serializeAdjustment>[]>();
  for (const a of adjustments) {
    const row = adjustmentsByCycle.get(a.cycleIndex) ?? [];
    row.push(serializeAdjustment(a));
    adjustmentsByCycle.set(a.cycleIndex, row);
  }

  // One chronological stream of everything that recently moved money.
  const timeline = [
    ...allocations.map((a) => ({
      type: a.kind === BudgetAllocationKind.FUND ? ('fund' as const) : ('release' as const),
      at: a.date.toISOString(),
      cycleIndex: a.cycleIndex,
      entry: serializeAlloc(a),
    })),
    ...recentTx.map((tx) => ({
      type: 'spend' as const,
      at: tx.date.toISOString(),
      cycleIndex: tx.budgetCycle ?? budget.cycleIndex,
      entry: serializeTx(tx),
    })),
    ...adjustments.map((a) => ({
      type: 'adjust' as const,
      at: a.date.toISOString(),
      cycleIndex: a.cycleIndex,
      entry: serializeAdjustment(a),
    })),
  ]
    .sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0))
    .slice(0, TIMELINE_LIMIT);

  return {
    ...serialize(budget, t),
    timeline,
    timelineTruncated: txCount + allocations.length > TIMELINE_LIMIT,
    allocations: allocations.filter((a) => a.cycleIndex === budget.cycleIndex).map(serializeAlloc),
    /** Raises and cuts made during the cycle that is open right now. */
    adjustments: adjustmentsByCycle.get(budget.cycleIndex) ?? [],
    /** Expenses charged to the cycle that is open right now. */
    cycleTxCount,
    sources: sources.map((s) => ({ account: s.account, available: s.available.toFixed(2) })),
    cycles: cycles.map((c) => ({
      index: c.index,
      label: c.label,
      startedAt: c.startedAt.toISOString(),
      endedAt: c.endedAt.toISOString(),
      /** What the plan was set to when the cycle opened. */
      openingPlanned: c.openingPlanned.toFixed(2),
      /** Net of the raises and cuts made during it. */
      adjustedAmount: c.adjustedAmount.toFixed(2),
      /** Closing figure: opening + adjusted. */
      plannedAmount: c.plannedAmount.toFixed(2),
      carriedIn: c.carriedIn.toFixed(2),
      fundedAmount: c.fundedAmount.toFixed(2),
      spentAmount: c.spentAmount.toFixed(2),
      leftoverAmount: c.leftoverAmount.toFixed(2),
      txCount: c.txCount,
      adjustments: adjustmentsByCycle.get(c.index) ?? [],
    })),
    lifetime: {
      allocated: t.allocated.toFixed(2),
      spent: t.spent.toFixed(2),
      txCount,
      firstTxAt: firstTx?.date.toISOString() ?? null,
      cycleCount: cycles.length + 1,
    },
  };
}

// ---------------------------------------------------------------------------
// Mutations
// ---------------------------------------------------------------------------

async function assertOwned(id: string, userId: string) {
  const budget = await prisma.budget.findFirst({ where: { id, userId } });
  if (!budget) throw new NotFoundError('Budget plan not found');
  return budget;
}

async function assertCategory(categoryId: string, userId: string) {
  const category = await prisma.category.findFirst({ where: { id: categoryId, userId } });
  if (!category) throw new NotFoundError('Category not found');
  return category;
}

/** The built-in plan is structural: it cannot be funded, closed or deleted. */
function refuseIfUnplanned(budget: Budget, action: string): void {
  if (budget.kind === BudgetKind.UNPLANNED) {
    throw new BadRequestError(
      `"${budget.name}" is the built-in catch-all plan and cannot be ${action}. It has no pot - it simply labels spending you did straight from an account.`,
    );
  }
}

export async function create(user: AuthUser, input: CreateBudgetInput) {
  if (input.categoryId) await assertCategory(input.categoryId, user.id);
  const recurring = input.kind === BudgetKind.RECURRING;
  if (recurring && !input.recurrenceUnit) {
    throw new BadRequestError('Pick how often this plan repeats');
  }

  // The user chooses when the plan begins; it is not spendable before then.
  const startsAt = input.startsAt ?? new Date();
  const interval = input.recurrenceInterval ?? 1;

  const budget = await prisma.budget.create({
    data: {
      userId: user.id,
      name: input.name.trim(),
      categoryId: input.categoryId ?? null,
      kind: recurring ? BudgetKind.RECURRING : BudgetKind.ONE_TIME,
      plannedAmount: input.plannedAmount,
      cycleOpeningPlanned: input.plannedAmount,
      currency: input.currency.toUpperCase(),
      icon: input.icon ?? null,
      color: input.color ?? null,
      note: input.note ?? null,
      alertThreshold: input.alertThreshold,
      recurrenceUnit: recurring ? input.recurrenceUnit : null,
      recurrenceInterval: interval,
      startsAt,
      cycleStartedAt: startsAt,
      nextResetAt: recurring ? addRecurrence(input.recurrenceUnit!, interval, startsAt) : null,
      endDate: input.endDate ?? null,
    },
    include: { category: { select: categorySelect } },
  });

  return serialize(budget, await totalsFor(budget.id, budget.cycleIndex));
}

export async function update(user: AuthUser, id: string, input: UpdateBudgetInput) {
  const existing = await assertOwned(id, user.id);
  refuseIfUnplanned(existing, 'edited');
  if (input.categoryId) await assertCategory(input.categoryId, user.id);

  // Shrinking the plan below what is already in the pot would strand money.
  // A direct edit restates the figure the cycle opened with, so the invariant
  // `opening + adjustments = planned` still holds afterwards.
  let openingPlanned: Prisma.Decimal | undefined;
  if (input.plannedAmount !== undefined) {
    const t = await totalsFor(existing.id, existing.cycleIndex);
    const { funded } = derive(existing, t);
    if (dec(input.plannedAmount).lt(funded)) {
      throw new BadRequestError(
        `This plan already holds ${funded.toFixed(2)} ${existing.currency}. Give money back to an account before lowering the planned amount.`,
      );
    }
    openingPlanned = dec(input.plannedAmount).sub(t.adjustedThisCycle);
  }

  const nextKind = input.kind ?? existing.kind;
  const nextUnit = input.recurrenceUnit ?? existing.recurrenceUnit;
  const nextInterval = input.recurrenceInterval ?? existing.recurrenceInterval;
  if (nextKind === BudgetKind.RECURRING && !nextUnit) {
    throw new BadRequestError('Pick how often this plan repeats');
  }

  // Moving the start date re-anchors the current cycle, as long as the plan has
  // not already banked a finished one.
  const nextStartsAt = input.startsAt ?? existing.startsAt;
  const reanchor =
    input.startsAt !== undefined &&
    existing.cycleIndex === 0 &&
    nextStartsAt.getTime() !== existing.startsAt.getTime();

  const budget = await prisma.budget.update({
    where: { id },
    data: {
      ...(input.name !== undefined ? { name: input.name.trim() } : {}),
      ...(input.categoryId !== undefined ? { categoryId: input.categoryId } : {}),
      ...(input.plannedAmount !== undefined
        ? { plannedAmount: input.plannedAmount, cycleOpeningPlanned: openingPlanned! }
        : {}),
      ...(input.icon !== undefined ? { icon: input.icon } : {}),
      ...(input.color !== undefined ? { color: input.color } : {}),
      ...(input.note !== undefined ? { note: input.note } : {}),
      ...(input.alertThreshold !== undefined ? { alertThreshold: input.alertThreshold } : {}),
      ...(input.endDate !== undefined ? { endDate: input.endDate } : {}),
      ...(reanchor ? { startsAt: nextStartsAt, cycleStartedAt: nextStartsAt } : {}),
      ...(input.kind !== undefined ||
      input.recurrenceUnit !== undefined ||
      input.recurrenceInterval !== undefined ||
      reanchor
        ? {
            kind: nextKind,
            recurrenceUnit: nextKind === BudgetKind.RECURRING ? nextUnit : null,
            recurrenceInterval: nextInterval,
            nextResetAt:
              nextKind === BudgetKind.RECURRING
                ? addRecurrence(
                    nextUnit!,
                    nextInterval,
                    reanchor ? nextStartsAt : existing.cycleStartedAt,
                  )
                : null,
          }
        : {}),
    },
    include: { category: { select: categorySelect } },
  });

  return serialize(budget, await totalsFor(budget.id, budget.cycleIndex));
}

/**
 * Raise or cut what a plan is meant to hold, keeping the change as a movement.
 *
 * This is the sanctioned way to change the amount: the cycle keeps the figure
 * it opened with, and the delta is filed against the cycle it happened in, so
 * "what did I plan for March, and what did I change mid-month" both survive.
 */
export async function adjust(user: AuthUser, id: string, input: AdjustBudgetInput) {
  const budget = await assertOwned(id, user.id);
  refuseIfUnplanned(budget, 'adjusted');
  if (budget.state === BudgetState.CLOSED) {
    throw new BadRequestError('This plan is closed. Reopen it before changing its amount.');
  }

  const delta = input.direction === 'DEDUCT' ? dec(input.amount).neg() : dec(input.amount);
  const next = budget.plannedAmount.add(delta);

  if (next.lte(0)) {
    throw new BadRequestError(
      `That would take "${budget.name}" down to ${next.toFixed(2)} ${budget.currency}. A plan has to be worth something - close it instead.`,
    );
  }

  // Cutting below what is already in the pot would strand money there.
  const t = await totalsFor(budget.id, budget.cycleIndex);
  const { funded } = derive(budget, t);
  if (next.lt(funded)) {
    throw new BadRequestError(
      `"${budget.name}" already holds ${funded.toFixed(2)} ${budget.currency}. Give money back to an account before cutting it to ${next.toFixed(2)}.`,
    );
  }

  await prisma.$transaction([
    prisma.budgetAdjustment.create({
      data: {
        userId: user.id,
        budgetId: budget.id,
        amount: delta,
        cycleIndex: budget.cycleIndex,
        reason: input.reason ?? null,
        date: input.date ?? new Date(),
      },
    }),
    prisma.budget.update({ where: { id: budget.id }, data: { plannedAmount: next } }),
  ]);

  return getById(user, budget.id);
}

export async function remove(user: AuthUser, id: string) {
  const budget = await assertOwned(id, user.id);
  refuseIfUnplanned(budget, 'deleted');
  const t = await totalsFor(budget.id, budget.cycleIndex);
  const { balance } = derive(budget, t);
  if (balance.gt(0)) {
    throw new BadRequestError(
      `"${budget.name}" still holds ${balance.toFixed(2)} ${budget.currency}. Give it back to an account first.`,
    );
  }
  // Spent transactions survive as ordinary expenses (budgetId is SET NULL).
  await prisma.budget.delete({ where: { id } });
}

/**
 * Move money from an account into the plan's pot. This is not a transaction:
 * the cash stays in the account but stops counting as available.
 */
export async function fund(user: AuthUser, id: string, input: FundBudgetInput) {
  const budget = await assertOwned(id, user.id);
  refuseIfUnplanned(budget, 'funded');
  if (budget.state === BudgetState.CLOSED) {
    throw new BadRequestError('This plan is closed. Reopen it before adding money.');
  }

  const account = await prisma.account.findFirst({ where: { id: input.accountId, userId: user.id } });
  if (!account) throw new NotFoundError('Account not found');
  if (account.currency !== budget.currency) {
    throw new BadRequestError(
      `"${account.name}" holds ${account.currency}; this plan is in ${budget.currency}.`,
    );
  }

  const t = await totalsFor(budget.id, budget.cycleIndex);
  const { fillable } = derive(budget, t);
  const amount = dec(input.amount);
  if (amount.gt(fillable)) {
    throw new BadRequestError(
      fillable.lte(0)
        ? `"${budget.name}" is already filled to its planned ${budget.plannedAmount.toFixed(2)} ${budget.currency}.`
        : `You can only add ${fillable.toFixed(2)} ${budget.currency} more to "${budget.name}" (planned ${budget.plannedAmount.toFixed(2)}).`,
    );
  }

  // Never reserve money the account does not actually have spare.
  const { availableBalance } = await import('../accounts/accounts.service.js');
  const available = await availableBalance(user.id, account.id);
  if (amount.gt(available)) {
    throw new BadRequestError(
      `"${account.name}" has ${available.toFixed(2)} ${account.currency} available (after money already set aside). Needed ${amount.toFixed(2)}.`,
    );
  }

  await prisma.budgetAllocation.create({
    data: {
      userId: user.id,
      budgetId: budget.id,
      accountId: account.id,
      kind: BudgetAllocationKind.FUND,
      amount,
      cycleIndex: budget.cycleIndex,
      date: input.date ?? new Date(),
      note: input.note ?? null,
    },
  });

  return getById(user, budget.id);
}

/** Give money in the pot back to an account, freeing the reservation. */
export async function release(user: AuthUser, id: string, input: ReleaseBudgetInput) {
  const budget = await assertOwned(id, user.id);
  const amount = dec(input.amount);

  const sources = await sourcesFor(budget.id);
  const target = input.accountId
    ? sources.find((s) => s.account!.id === input.accountId)
    : sources[0];
  if (!target) throw new BadRequestError('This plan has no money to give back.');
  if (amount.gt(target.available)) {
    throw new BadRequestError(
      `Only ${target.available.toFixed(2)} ${budget.currency} of this plan came from "${target.account!.name}".`,
    );
  }

  await prisma.budgetAllocation.create({
    data: {
      userId: user.id,
      budgetId: budget.id,
      accountId: target.account!.id,
      kind: BudgetAllocationKind.RELEASE,
      amount: amount.neg(),
      cycleIndex: budget.cycleIndex,
      date: input.date ?? new Date(),
      note: input.note ?? null,
    },
  });

  return getById(user, budget.id);
}

export async function close(user: AuthUser, id: string) {
  const budget = await assertOwned(id, user.id);
  refuseIfUnplanned(budget, 'closed');
  if (budget.state === BudgetState.CLOSED) return getById(user, id);

  const t = await totalsFor(budget.id, budget.cycleIndex);
  const { balance } = derive(budget, t);
  if (balance.gt(0)) {
    throw new BadRequestError(
      `"${budget.name}" still holds ${balance.toFixed(2)} ${budget.currency}. Give it back to an account before closing.`,
    );
  }

  await prisma.budget.update({
    where: { id },
    data: { state: BudgetState.CLOSED, closedAt: new Date() },
  });
  return getById(user, id);
}

export async function reopen(user: AuthUser, id: string) {
  const budget = await assertOwned(id, user.id);
  const now = new Date();
  await prisma.budget.update({
    where: { id },
    data: {
      state: BudgetState.ACTIVE,
      closedAt: null,
      // A recurring plan that ran past its end date needs a fresh reset clock.
      ...(budget.kind === BudgetKind.RECURRING && !budget.nextResetAt && budget.recurrenceUnit
        ? {
            cycleStartedAt: now,
            nextResetAt: addRecurrence(budget.recurrenceUnit, budget.recurrenceInterval, now),
          }
        : {}),
      ...(budget.endDate && budget.endDate <= now ? { endDate: null } : {}),
    },
  });
  return getById(user, id);
}

// ---------------------------------------------------------------------------
// Hooks called by the transactions module
// ---------------------------------------------------------------------------

export interface PlanCharge {
  budget: Budget;
  /** The funding account whose reservation this spend frees. */
  releaseAccountId: string;
}

/**
 * Is this the built-in Unplanned plan? Returns it when so, `null` when the id
 * belongs to an ordinary funded plan. Unplanned has no pot and no start gate:
 * it spends whatever the chosen account has free, so the caller must supply
 * the account and fall back to the normal overdraw guard.
 */
export async function assertUnplannedSpendable(
  userId: string,
  budgetId: string,
): Promise<{ id: string; cycleIndex: number } | null> {
  const budget = await prisma.budget.findFirst({
    where: { id: budgetId, userId },
    select: { id: true, cycleIndex: true, kind: true },
  });
  if (!budget) throw new NotFoundError('Budget plan not found');
  return budget.kind === BudgetKind.UNPLANNED
    ? { id: budget.id, cycleIndex: budget.cycleIndex }
    : null;
}

/**
 * Validate that `amount` can be paid out of a plan and decide which funding
 * account's reservation it frees.
 *
 * This is *not* the account the cash leaves - the caller picks that freely, and
 * it may be a wallet that never funded the plan. What has to be resolved here is
 * whose reservation comes off, because that money is sitting somewhere specific.
 * `releaseAccountId` names it; with a single funder there is nothing to choose,
 * and otherwise the largest share that covers the spend is assumed.
 *
 * `excludeTxId` lets an edit ignore its own prior effect.
 */
export async function assertSpendable(
  userId: string,
  budgetId: string,
  amount: number,
  releaseAccountId?: string,
  excludeTxId?: string,
): Promise<PlanCharge> {
  const budget = await prisma.budget.findFirst({ where: { id: budgetId, userId } });
  if (!budget) throw new NotFoundError('Budget plan not found');
  if (budget.state === BudgetState.CLOSED) {
    throw new BadRequestError(`"${budget.name}" is closed. Reopen it to spend from it.`);
  }
  if (!hasStarted(budget)) {
    throw new BadRequestError(
      `"${budget.name}" starts on ${budget.startsAt.toISOString().slice(0, 10)} - you cannot spend from it yet.`,
    );
  }

  const spendWhere = { budgetId, kind: TxKind.EXPENSE, ...(excludeTxId ? { id: { not: excludeTxId } } : {}) };
  const [allocAgg, spentAgg] = await Promise.all([
    prisma.budgetAllocation.aggregate({ where: { budgetId }, _sum: { amount: true } }),
    prisma.transaction.aggregate({ where: spendWhere, _sum: { amount: true } }),
  ]);
  const balance = (allocAgg._sum.amount ?? zero).sub(spentAgg._sum.amount ?? zero);

  const want = dec(amount);
  if (want.gt(balance)) {
    throw new BadRequestError(
      `"${budget.name}" only has ${balance.toFixed(2)} ${budget.currency} left. This would take it negative.`,
    );
  }

  // Whose reservation comes off. Shares are keyed by the account that funded
  // them, less what previous spends already released from each.
  const [allocs, spends] = await Promise.all([
    prisma.budgetAllocation.groupBy({ by: ['accountId'], where: { budgetId }, _sum: { amount: true } }),
    prisma.transaction.groupBy({
      by: ['budgetSourceAccountId'],
      where: spendWhere,
      _sum: { amount: true },
    }),
  ]);
  const shares = new Map<string, Prisma.Decimal>();
  for (const a of allocs) shares.set(a.accountId, a._sum.amount ?? zero);
  for (const s of spends) {
    if (!s.budgetSourceAccountId) continue;
    const id = s.budgetSourceAccountId;
    shares.set(id, (shares.get(id) ?? zero).sub(s._sum.amount ?? zero));
  }

  const ranked = [...shares.entries()]
    .filter(([, share]) => share.gt(0))
    .sort((a, b) => b[1].comparedTo(a[1]));

  if (ranked.length === 0) throw new BadRequestError(`"${budget.name}" has no money in it yet.`);

  const chosen = releaseAccountId
    ? ranked.find(([accountId]) => accountId === releaseAccountId)
    : // No choice offered: take the largest share that covers it. With one
      // funder - the common case - this is simply that funder.
      (ranked.find(([, share]) => share.gte(want)) ?? ranked[0]);

  if (!chosen) {
    throw new BadRequestError(
      `None of "${budget.name}" was funded from that account, so there is no reservation there to free.`,
    );
  }
  if (want.gt(chosen[1])) {
    const best = ranked[0]!;
    throw new BadRequestError(
      releaseAccountId
        ? `Only ${chosen[1].toFixed(2)} ${budget.currency} of "${budget.name}" is held against that account. Pick another one to take it off, or use ${best[1].toFixed(2)} from the largest share.`
        : `"${budget.name}" holds money across several accounts; the largest single share is ${best[1].toFixed(2)} ${budget.currency}. Choose which account to take it off, or split the expense.`,
    );
  }

  return { budget, releaseAccountId: chosen[0] };
}

/**
 * After a plan expense lands (or is edited/deleted): warn when the pot runs
 * low, and retire a one-time plan whose money is fully spent.
 *
 * Awaited by the caller so the ACTIVE -> CLOSED transition is part of the
 * write's outcome - nothing else reconciles it, so a dropped call would leave a
 * drained plan open forever. Everything here is best-effort internally, so
 * awaiting it can never fail the transaction.
 */
export async function afterSpend(userId: string, budgetId: string): Promise<void> {
  try {
    const budget = await prisma.budget.findFirst({ where: { id: budgetId, userId } });
    if (!budget || budget.state === BudgetState.CLOSED) return;
    if (budget.kind === BudgetKind.UNPLANNED) return; // no pot to run low or close

    const t = await totalsFor(budget.id, budget.cycleIndex);
    const d = derive(budget, t);

    if (budget.kind === BudgetKind.ONE_TIME && d.balance.lte(0) && t.spent.gt(0)) {
      await prisma.budget.update({
        where: { id: budget.id },
        data: { state: BudgetState.CLOSED, closedAt: new Date() },
      });
      await notify(
        userId,
        'budget_closed',
        `"${budget.name}" is fully spent and has been closed. You can reopen it any time.`,
        `/budgets/${budget.id}`,
      );
      return;
    }

    if (d.funded.gt(0) && d.pctSpentOfFunded >= budget.alertThreshold) {
      const since = budget.cycleStartedAt;
      const existing = await prisma.notification.findFirst({
        where: {
          userId,
          type: 'budget_alert',
          readFlag: false,
          message: { contains: budget.name },
          createdAt: { gte: since },
        },
      });
      if (existing) return;
      await notify(
        userId,
        'budget_alert',
        `You've used ${Math.round(d.pctSpentOfFunded)}% of "${budget.name}" - ${d.balance.toFixed(2)} ${budget.currency} left.`,
        `/budgets/${budget.id}`,
      );
    }
  } catch {
    // Alerts are best-effort; never fail the transaction write.
  }
}
