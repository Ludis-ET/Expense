/**
 * Budget plans (envelopes).
 *
 * A plan is a named pot with a planned amount. You fill it from wallets; that
 * money stays physically where it is but is *reserved*, so it drops out of every
 * "available" figure. Spending against the plan writes an ordinary expense that
 * carries `budgetId`: the real balance goes down and the reservation is freed in
 * the same movement, so nothing is counted twice.
 *
 *   pot(plan)        = SUM over wallets of what each holds for it
 *   held(wallet,plan) = fills - give-backs - spending released against the pair
 *
 * All of that arithmetic lives in `core/money`; this module is presentation,
 * cycles and the plan's own lifecycle.
 *
 * There is no "Unplanned" plan any more. Spending you never reserved for is
 * simply `budgetId = null` on the transaction - one representation instead of
 * two, which is what let the web and the phone disagree about the same action.
 * `unplannedSummary` presents it as a card without it being a row.
 */
import {
  BudgetAllocationKind,
  BudgetKind,
  BudgetState,
  BudgetType,
  AdjustmentDial,
  Prisma,
  TxKind,
  type Budget,
} from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { notify } from '../notifications/notifications.service.js';
import {
  adjustPlan,
  fundPlan,
  loadSnapshot,
  movePlanMoney,
  moveReservation,
  potOf,
  readyToAssign,
  releasePlan,
  sharesOf,
  withMoneyLock,
  ZERO,
  type LedgerSnapshot,
} from '../../core/money/index.js';
import { addRecurrence, cycleLabel, periodNoun, recurrenceLabel } from './budgets.periods.js';
import {
  savingFacts,
  stateForSaving,
  type Contribution,
  type SavingFacts,
} from './budgets.saving.js';
import type {
  AdjustBudgetInput,
  ConvertBudgetInput,
  CreateBudgetInput,
  FundBudgetInput,
  ListBudgetsQuery,
  MovePlanMoneyInput,
  MoveReservationInput,
  ReleaseBudgetInput,
  UpdateBudgetInput,
} from './budgets.schema.js';

export { monthRange, refDate } from './budgets.periods.js';

const dec = (v: Prisma.Decimal | number | string) => new Prisma.Decimal(v);

const categorySelect = { id: true, name: true, icon: true, color: true, kind: true } as const;
const accountSelect = { id: true, name: true, type: true, currency: true, color: true, icon: true } as const;

/**
 * The id the clients use for "no plan". It is not a row - the server turns it
 * into `budgetId: null` on the way in, and presents it as a card on the way out.
 */
export const UNPLANNED_ID = 'unplanned';
export const UNPLANNED_NAME = 'Unplanned';

/** Anything a client sends meaning "no plan" resolves to null. */
export function resolveBudgetId(value: string | null | undefined): string | null {
  if (!value) return null;
  if (value === UNPLANNED_ID) return null;
  // Older builds sent the retired per-user row id. Sideloaded phones live a long
  // time, so this stays until those versions are gone.
  if (value.startsWith('unplanned_')) return null;
  return value;
}

// ---------------------------------------------------------------------------
// Cycle totals
// ---------------------------------------------------------------------------

interface Totals {
  allocated: Prisma.Decimal;
  spent: Prisma.Decimal;
  allocatedThisCycle: Prisma.Decimal;
  spentThisCycle: Prisma.Decimal;
  adjustedThisCycle: Prisma.Decimal;
}

const emptyTotals = (): Totals => ({
  allocated: ZERO,
  spent: ZERO,
  allocatedThisCycle: ZERO,
  spentThisCycle: ZERO,
  adjustedThisCycle: ZERO,
});

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
    allocated: allocAll._sum.amount ?? ZERO,
    spent: spentAll._sum.amount ?? ZERO,
    allocatedThisCycle: allocCycle._sum.amount ?? ZERO,
    spentThisCycle: spentCycle._sum.amount ?? ZERO,
    adjustedThisCycle: adjCycle._sum.amount ?? ZERO,
  };
}

/**
 * Every contribution to one saving plan.
 *
 * Only positive allocations count: a give-back is money leaving, and counting
 * it as a contribution would let someone build a streak by moving the same
 * 2,000 in and out.
 *
 * Deliberately not reusing the timeline's allocation fetch: that one is capped
 * at TIMELINE_LIMIT and includes give-backs, so a rate computed from it would
 * quietly go wrong on any plan with a long history.
 */
async function contributionsFor(budget: Pick<Budget, 'id' | 'type'>): Promise<Contribution[]> {
  if (budget.type !== BudgetType.SAVING) return [];
  const rows = await prisma.budgetAllocation.findMany({
    where: { budgetId: budget.id, amount: { gt: 0 } },
    select: { amount: true, date: true, cycleIndex: true },
    orderBy: { date: 'asc' },
  });
  return rows;
}

/** The same for a whole list, in one query. Spending plans are skipped. */
async function contributionsForMany(budgets: Budget[]): Promise<Map<string, Contribution[]>> {
  const map = new Map<string, Contribution[]>();
  const savingIds = budgets.filter((b) => b.type === BudgetType.SAVING).map((b) => b.id);
  if (savingIds.length === 0) return map;

  for (const id of savingIds) map.set(id, []);

  const rows = await prisma.budgetAllocation.findMany({
    where: { budgetId: { in: savingIds }, amount: { gt: 0 } },
    select: { budgetId: true, amount: true, date: true, cycleIndex: true },
    orderBy: { date: 'asc' },
  });

  for (const r of rows) {
    map.get(r.budgetId)?.push({ amount: r.amount, date: r.date, cycleIndex: r.cycleIndex });
  }
  return map;
}

/** Batched `totalsFor` for a whole list of plans. */
async function totalsForMany(budgets: Budget[]): Promise<Map<string, Totals>> {
  const ids = budgets.map((b) => b.id);
  const map = new Map<string, Totals>();
  for (const b of budgets) map.set(b.id, emptyTotals());
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
    const t = map.get(row.budgetId);
    if (!t) continue;
    const amt = row._sum.amount ?? ZERO;
    t.allocated = t.allocated.add(amt);
    if (row.cycleIndex === cycleOf.get(row.budgetId)) {
      t.allocatedThisCycle = t.allocatedThisCycle.add(amt);
    }
  }
  for (const row of spends) {
    if (!row.budgetId) continue;
    const t = map.get(row.budgetId);
    if (!t) continue;
    const amt = row._sum.amount ?? ZERO;
    t.spent = t.spent.add(amt);
    if (row.budgetCycle === cycleOf.get(row.budgetId)) {
      t.spentThisCycle = t.spentThisCycle.add(amt);
    }
  }
  for (const row of adjustments) {
    const t = map.get(row.budgetId);
    if (!t) continue;
    if (row.cycleIndex === cycleOf.get(row.budgetId)) {
      t.adjustedThisCycle = t.adjustedThisCycle.add(row._sum.amount ?? ZERO);
    }
  }
  return map;
}

/**
 * The numbers every view of a plan needs.
 *
 * `balance` comes from the money core rather than being recomputed here, so the
 * plan page and the wallet page can never tell different stories about the same
 * reservation.
 */
function derive(budget: Budget, t: Totals, snap: LedgerSnapshot) {
  const balance = potOf(snap, budget.id);
  const carriedIn = t.allocated.sub(t.allocatedThisCycle).sub(t.spent.sub(t.spentThisCycle));
  const funded = carriedIn.add(t.allocatedThisCycle);
  const fillable = Prisma.Decimal.max(ZERO, budget.plannedAmount.sub(funded));
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

function health(budget: Budget, d: ReturnType<typeof derive>, facts: SavingFacts | null): Health {
  if (budget.state === BudgetState.CLOSED) return 'closed';
  if (!hasStarted(budget)) return 'scheduled';

  // A saving plan is judged on progress, never on how much of it is gone.
  // Running the spending ladder over one would call a healthy pot "drained"
  // the moment it was emptied into the thing it was saved for.
  if (facts) {
    if (facts.goalMet) return 'ready';
    if (d.funded.lte(0)) return 'empty';
    if (facts.pace === 'behind') return 'low';
    return 'spending';
  }

  if (d.funded.lte(0)) return 'empty';
  if (d.balance.lte(0)) return 'drained';
  if (d.spent.lte(0)) return d.fillable.gt(0) ? 'partly-funded' : 'ready';
  return d.pctSpentOfFunded >= budget.alertThreshold ? 'low' : 'spending';
}

type BudgetWithCategory = Budget & { category?: { id: string; name: string } | null };

function serialize(
  budget: BudgetWithCategory,
  t: Totals,
  snap: LedgerSnapshot,
  contributions: Contribution[] = [],
) {
  const d = derive(budget, t, snap);
  const saving = savingFacts(budget, d.balance, contributions);
  return {
    id: budget.id,
    name: budget.name,
    categoryId: budget.categoryId,
    category: budget.category ?? null,
    kind: budget.kind,
    /** Retained for older clients; nothing is an unplanned *plan* any more. */
    isUnplanned: false,
    recurrenceUnit: budget.recurrenceUnit,
    recurrenceInterval: budget.recurrenceInterval,
    recurrenceLabel: budget.recurrenceUnit
      ? recurrenceLabel(budget.recurrenceUnit, budget.recurrenceInterval)
      : null,
    periodNoun: budget.recurrenceUnit
      ? periodNoun(budget.recurrenceUnit, budget.recurrenceInterval)
      : null,
    currency: budget.currency,
    icon: budget.icon,
    color: budget.color,
    note: budget.note,
    alertThreshold: budget.alertThreshold,

    /** SPENDING or SAVING - what this plan's money is for. */
    type: budget.type,

    /**
     * Derived rather than read, so the badge can never disagree with the
     * numbers beside it: a pot at or past its goal reads COMPLETED, and drops
     * back to ACTIVE the moment the goal is raised above it.
     */
    state: stateForSaving(budget, d.balance),
    closedAt: budget.closedAt ? budget.closedAt.toISOString() : null,

    /** Everything a saving plan needs and a spending plan has no use for. */
    saving,

    plannedAmount: budget.plannedAmount.toFixed(2),
    openingPlanned: budget.cycleOpeningPlanned.toFixed(2),
    adjustedThisCycle: t.adjustedThisCycle.toFixed(2),
    fundedAmount: d.funded.toFixed(2),
    carriedIn: d.carriedIn.toFixed(2),
    fillable: d.fillable.toFixed(2),
    spentAmount: d.spent.toFixed(2),
    balance: d.balance.toFixed(2),

    pctFunded: Math.min(100, d.pctFunded),
    pctOfPlan: Math.min(100, d.pctOfPlan),
    pctSpentOfFunded: Math.min(100, d.pctSpentOfFunded),
    health: health(budget, d, saving),

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
// Unplanned, as a view rather than a row
// ---------------------------------------------------------------------------

/**
 * One definition of unplanned spending, used by the budgets page, the analytics
 * page and the outlook. There used to be three, which is why those three screens
 * quoted three different numbers.
 */
export const UNPLANNED_WHERE = {
  kind: TxKind.EXPENSE,
  budgetId: null,
} satisfies Prisma.TransactionWhereInput;

/** The catch-all card: real spending, no pot, presented like a plan. */
export async function unplannedSummary(userId: string, currency: string, since: Date) {
  const cur = currency.toUpperCase();
  const [cycle, lifetime, count] = await Promise.all([
    prisma.transaction.aggregate({
      where: { userId, ...UNPLANNED_WHERE, currency: cur, date: { gte: since } },
      _sum: { amount: true },
    }),
    prisma.transaction.aggregate({
      where: { userId, ...UNPLANNED_WHERE, currency: cur },
      _sum: { amount: true },
    }),
    prisma.transaction.count({
      where: { userId, ...UNPLANNED_WHERE, currency: cur, date: { gte: since } },
    }),
  ]);

  return {
    id: UNPLANNED_ID,
    name: UNPLANNED_NAME,
    currency: cur,
    icon: 'circle-ellipsis',
    color: '#64748b',
    note: 'Everything you spent without setting money aside first.',
    /** Spent this month with no plan behind it. */
    spentAmount: (cycle._sum.amount ?? ZERO).toFixed(2),
    lifetimeSpent: (lifetime._sum.amount ?? ZERO).toFixed(2),
    txCount: count,
  };
}

// ---------------------------------------------------------------------------
// Reservation lookups, kept for callers outside this module
// ---------------------------------------------------------------------------

export async function lockedByAccount(userId: string): Promise<Map<string, Prisma.Decimal>> {
  const snap = await loadSnapshot(userId);
  return snap.heldPerAccount;
}

export async function lockedTotal(userId: string, currency: string): Promise<Prisma.Decimal> {
  const snap = await loadSnapshot(userId);
  const cur = currency.toUpperCase();
  let total = ZERO;
  for (const account of snap.accounts) {
    if (account.archived || account.currency.toUpperCase() !== cur) continue;
    total = total.add(snap.heldPerAccount.get(account.id) ?? ZERO);
  }
  return total;
}

/** Where one plan's money is sitting, largest share first. */
export async function sourcesFor(budgetId: string, userId?: string) {
  const owner =
    userId ??
    (await prisma.budget.findUnique({ where: { id: budgetId }, select: { userId: true } }))?.userId;
  if (!owner) return [];

  const snap = await loadSnapshot(owner);
  const shares = sharesOf(snap, budgetId).filter((s) => s.amount.gt(0));
  if (shares.length === 0) return [];

  const accounts = await prisma.account.findMany({
    where: { id: { in: shares.map((s) => s.accountId) } },
    select: accountSelect,
  });
  const byId = new Map(accounts.map((a) => [a.id, a]));

  return shares
    .map((s) => ({ account: byId.get(s.accountId) ?? null, available: s.amount }))
    .filter((r) => r.account !== null);
}

// ---------------------------------------------------------------------------
// Recurring cycles
// ---------------------------------------------------------------------------

const MAX_ROLLS = 800;

/**
 * Close out every cycle whose reset time has passed: freeze a snapshot of what
 * was planned, funded and spent, then open the next one. Leftover money is not
 * moved anywhere - the pot is cumulative, so it simply carries in.
 *
 * A plan that reaches its end date holding money stays *open*. Closing it would
 * strand the money: locked in the wallet, invisible in every plan total. That is
 * exactly what `close()` refuses to do by hand, and the roller has no business
 * doing it silently either.
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
  if (due.length === 0) return;

  for (const budget of due) {
    let b = budget;
    let rolls = 0;
    let carriedForward = ZERO;
    let skipped = 0;
    let strandedAtEnd = false;

    while (b.nextResetAt && b.nextResetAt <= now && rolls < MAX_ROLLS) {
      const snap = await loadSnapshot(userId);
      const t = await totalsFor(b.id, b.cycleIndex);
      const d = derive(b, t, snap);
      const txCount = await prisma.transaction.count({
        where: { budgetId: b.id, budgetCycle: b.cycleIndex, kind: TxKind.EXPENSE },
      });

      const endedAt = b.nextResetAt;

      // A fast cadence left dormant would mint a snapshot per empty cycle. Only
      // cycles where something happened are worth keeping.
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

      const reachedEnd = b.endDate ? endedAt >= b.endDate : false;
      const holdsMoney = d.balance.gt(0);
      const finished = reachedEnd && !holdsMoney;
      if (reachedEnd && holdsMoney) strandedAtEnd = true;

      b = await prisma.budget.update({
        where: { id: b.id },
        data: {
          cycleIndex: b.cycleIndex + 1,
          cycleStartedAt: endedAt,
          cycleOpeningPlanned: b.plannedAmount,
          nextResetAt:
            finished || reachedEnd
              ? null
              : addRecurrence(b.recurrenceUnit!, b.recurrenceInterval, endedAt),
          ...(finished ? { state: BudgetState.CLOSED, closedAt: now } : {}),
        },
      });

      carriedForward = d.balance;
      rolls += 1;
      if (reachedEnd) break;
    }

    if (strandedAtEnd) {
      await notify(
        userId,
        'budget_ended_with_money',
        `"${b.name}" reached its end date still holding ${carriedForward.toFixed(2)} ${b.currency}. It is staying open so you can decide where that goes.`,
        `/budgets/${b.id}`,
      );
    } else if (rolls > 0 && carriedForward.gt(0)) {
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
  await rollDueCycles(user.id);

  const currency = query.currency?.toUpperCase();
  const [budgets, snap] = await Promise.all([
    prisma.budget.findMany({
      where: {
        userId: user.id,
        ...(query.state ? { state: query.state } : {}),
        ...(currency ? { currency } : {}),
      },
      include: { category: { select: categorySelect } },
      orderBy: [{ state: 'asc' }, { createdAt: 'desc' }],
    }),
    loadSnapshot(user.id),
  ]);

  const totals = await totalsForMany(budgets);
  const contributions = await contributionsForMany(budgets);
  const items = budgets.map((b) =>
    serialize(b, totals.get(b.id)!, snap, contributions.get(b.id) ?? []),
  );
  const active = items.filter((i) => i.state === BudgetState.ACTIVE);

  const sum = (rows: SerializedBudget[], pick: (i: SerializedBudget) => string) =>
    rows.reduce((s, i) => s.add(dec(pick(i))), ZERO).toFixed(2);

  const displayCurrency = currency ?? items[0]?.currency ?? 'ETB';
  const monthStart = new Date();
  monthStart.setUTCDate(1);
  monthStart.setUTCHours(0, 0, 0, 0);

  const [unplanned, free] = await Promise.all([
    unplannedSummary(user.id, displayCurrency, monthStart),
    Promise.resolve(readyToAssign(snap, displayCurrency)),
  ]);

  return {
    items,
    unplanned,
    totals: {
      planned: sum(active, (i) => i.plannedAmount),
      funded: sum(active, (i) => i.fundedAmount),
      spent: sum(active, (i) => i.spentAmount),
      /** Money locked away in plans right now. */
      locked: sum(active, (i) => i.balance),
      /** Spending that never went through a plan, this month. */
      unplannedSpent: unplanned.spentAmount,
      /**
       * Money you have that is not in any plan. The number envelope budgeting is
       * actually built around, and the one the page asks you to act on.
       */
      readyToAssign: free.toFixed(2),
      currency: displayCurrency,
      activeCount: active.length,
      closedCount: items.length - active.length,
    },
  };
}

/**
 * The "pay from" options on a transaction: every plan that still holds money,
 * plus Unplanned, which is always offered because it has no pot - it spends
 * whatever the chosen wallet has free.
 *
 * Saving plans are excluded at the query, not filtered later. `postTransaction`
 * refuses to spend from one, so offering it here would be showing a choice that
 * the next screen rejects.
 */
export async function spendableSources(user: AuthUser, currency?: string) {
  await rollDueCycles(user.id);

  const [budgets, snap] = await Promise.all([
    prisma.budget.findMany({
      where: {
        userId: user.id,
        state: BudgetState.ACTIVE,
        type: BudgetType.SPENDING,
        ...(currency ? { currency: currency.toUpperCase() } : {}),
      },
      include: { category: { select: categorySelect } },
      orderBy: { name: 'asc' },
    }),
    loadSnapshot(user.id),
  ]);

  const accounts = await prisma.account.findMany({
    where: { userId: user.id, archived: false },
    select: accountSelect,
  });
  const accountById = new Map(accounts.map((a) => [a.id, a]));

  const totals = await totalsForMany(budgets);
  const items = budgets
    // No contributions needed: only spending plans reach here, and saving facts
    // are null for those anyway.
    .map((b) => ({ budget: b, view: serialize(b, totals.get(b.id)!, snap) }))
    .filter(({ view }) => view.started && Number(view.balance) > 0)
    .map(({ budget, view }) => ({
      id: view.id,
      name: view.name,
      currency: view.currency,
      balance: view.balance,
      icon: view.icon,
      color: view.color,
      categoryId: view.categoryId,
      category: view.category,
      isUnplanned: false,
      sources: sharesOf(snap, budget.id)
        .filter((s) => s.amount.gt(0) && accountById.has(s.accountId))
        .map((s) => ({ account: accountById.get(s.accountId)!, available: s.amount.toFixed(2) })),
    }));

  // Unplanned leads the list: it is the honest default for an expense you did not
  // set money aside for, and it draws on whatever wallet you pick.
  const cur = (currency ?? items[0]?.currency ?? 'ETB').toUpperCase();
  return {
    items: [
      {
        id: UNPLANNED_ID,
        name: UNPLANNED_NAME,
        currency: cur,
        /** No pot, so nothing to run out of. Never a negative number again. */
        balance: null as string | null,
        icon: 'circle-ellipsis',
        color: '#64748b',
        categoryId: null,
        category: null,
        isUnplanned: true,
        sources: [] as Array<{ account: unknown; available: string }>,
      },
      ...items,
    ],
  };
}

const TIMELINE_LIMIT = 40;

export async function getById(user: AuthUser, id: string) {
  await rollDueCycles(user.id);

  const budget = await prisma.budget.findFirst({
    where: { id, userId: user.id },
    include: { category: { select: categorySelect } },
  });
  if (!budget) throw new NotFoundError('Budget plan not found');

  const snap = await loadSnapshot(user.id);
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
          budgetSourceAccount: { select: accountSelect },
        },
        orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
        take: TIMELINE_LIMIT,
      }),
      prisma.budgetCycle.findMany({ where: { budgetId: budget.id }, orderBy: { index: 'desc' } }),
      sourcesFor(budget.id, user.id),
      prisma.transaction.count({ where: { budgetId: budget.id } }),
      prisma.transaction.count({
        where: { budgetId: budget.id, kind: TxKind.EXPENSE, budgetCycle: budget.cycleIndex },
      }),
      prisma.transaction.findFirst({
        where: { budgetId: budget.id },
        orderBy: { date: 'asc' },
        select: { date: true },
      }),
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
    /** Set when another wallet fronted the money for this plan's spend. */
    frontedBy:
      tx.budgetSourceAccountId && tx.budgetSourceAccountId !== tx.accountId ? tx.account : null,
    heldIn: tx.budgetSourceAccount,
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
    /** Both halves of a move share this, and are undone together. */
    groupId: a.groupId,
  });

  const serializeAdjustment = (a: (typeof adjustments)[number]) => ({
    id: a.id,
    amount: a.amount.toFixed(2),
    date: a.date.toISOString(),
    reason: a.reason,
    cycleIndex: a.cycleIndex,
    automatic: a.automatic,
  });

  const adjustmentsByCycle = new Map<number, ReturnType<typeof serializeAdjustment>[]>();
  for (const a of adjustments) {
    const row = adjustmentsByCycle.get(a.cycleIndex) ?? [];
    row.push(serializeAdjustment(a));
    adjustmentsByCycle.set(a.cycleIndex, row);
  }

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
    ...serialize(budget, t, snap, await contributionsFor(budget)),
    timeline,
    timelineTruncated: txCount + allocations.length > TIMELINE_LIMIT,
    allocations: allocations.filter((a) => a.cycleIndex === budget.cycleIndex).map(serializeAlloc),
    adjustments: adjustmentsByCycle.get(budget.cycleIndex) ?? [],
    cycleTxCount,
    sources: sources.map((s) => ({ account: s.account, available: s.available.toFixed(2) })),
    cycles: cycles.map((c) => ({
      index: c.index,
      label: c.label,
      startedAt: c.startedAt.toISOString(),
      endedAt: c.endedAt.toISOString(),
      openingPlanned: c.openingPlanned.toFixed(2),
      adjustedAmount: c.adjustedAmount.toFixed(2),
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

export async function create(user: AuthUser, input: CreateBudgetInput) {
  if (input.categoryId) await assertCategory(input.categoryId, user.id);
  const recurring = input.kind === BudgetKind.RECURRING;
  if (recurring && !input.recurrenceUnit) {
    throw new BadRequestError('Pick how often this plan repeats');
  }

  const startsAt = input.startsAt ?? new Date();
  const interval = input.recurrenceInterval ?? 1;

  const budget = await prisma.budget.create({
    data: {
      userId: user.id,
      name: input.name.trim(),
      categoryId: input.categoryId ?? null,
      kind: recurring ? BudgetKind.RECURRING : BudgetKind.ONE_TIME,
      type: input.type,
      plannedAmount: input.plannedAmount,
      // A one-time saving plan's target and its goal are the same thing, so the
      // form shows one field and it lands in both. Only a recurring saving plan
      // genuinely has two numbers to keep apart.
      goalAmount:
        input.type === BudgetType.SAVING
          ? (input.goalAmount ?? (recurring ? null : input.plannedAmount))
          : null,
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

  const snap = await loadSnapshot(user.id);
  return serialize(
    budget,
    await totalsFor(budget.id, budget.cycleIndex),
    snap,
    await contributionsFor(budget),
  );
}

export async function update(user: AuthUser, id: string, input: UpdateBudgetInput) {
  const existing = await assertOwned(id, user.id);
  if (input.categoryId) await assertCategory(input.categoryId, user.id);

  let openingPlanned: Prisma.Decimal | undefined;
  if (input.plannedAmount !== undefined) {
    const snap = await loadSnapshot(user.id);
    const t = await totalsFor(existing.id, existing.cycleIndex);
    const { funded } = derive(existing, t, snap);

    // A spending plan's planned amount is the cap the pot sits under, so it
    // cannot drop below what the pot already holds. A saving plan's is a target
    // to reach - dropping "2,000 a month" to "1,000 a month" while 30,000 is
    // already saved is an ordinary thing to want, and refusing it would make
    // the number impossible to lower once the pot outgrew it.
    if (existing.type === BudgetType.SPENDING && dec(input.plannedAmount).lt(funded)) {
      throw new BadRequestError(
        `This plan already holds ${funded.toFixed(2)} ${existing.currency}. Give money back to a wallet before lowering the planned amount.`,
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
      // Explicit null removes the finish line, turning a goal back into an
      // open-ended habit. Only meaningful on a saving plan.
      ...(input.goalAmount !== undefined && existing.type === BudgetType.SAVING
        ? { goalAmount: input.goalAmount ?? null }
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

  const snap = await loadSnapshot(user.id);
  return serialize(
    budget,
    await totalsFor(budget.id, budget.cycleIndex),
    snap,
    await contributionsFor(budget),
  );
}

/** Raise or cut what a plan is meant to hold, kept as a movement, not an edit. */
export async function adjust(user: AuthUser, id: string, input: AdjustBudgetInput) {
  const delta = input.direction === 'DEDUCT' ? dec(input.amount).neg() : dec(input.amount);

  // Moving the goal is a different operation from moving the planned amount.
  // `adjustPlan` lives in the money core because a planned amount is the cap
  // the funding guard tests against; a goal caps nothing, so it is a plain
  // column write and does not belong there.
  if (input.dial === AdjustmentDial.GOAL) {
    const budget = await assertOwned(id, user.id);
    if (budget.type !== BudgetType.SAVING) {
      throw new BadRequestError('Only a saving plan has a goal to move.');
    }

    const before = budget.goalAmount ?? ZERO;
    const after = before.add(delta);
    if (after.lte(0)) {
      throw new BadRequestError(
        'A goal has to stay above zero. Remove the goal instead if the plan should run open-ended.',
      );
    }

    await prisma.$transaction([
      prisma.budget.update({ where: { id }, data: { goalAmount: after } }),
      prisma.budgetAdjustment.create({
        data: {
          userId: user.id,
          budgetId: id,
          amount: delta,
          dial: AdjustmentDial.GOAL,
          cycleIndex: budget.cycleIndex,
          reason: input.reason ?? null,
          date: input.date ?? new Date(),
          clientOpId: input.clientOpId ?? null,
        },
      }),
    ]);

    // The state is derived from the numbers on read, so raising the goal past
    // the pot re-opens a completed plan without a separate re-open button that
    // could disagree with them.
    return getById(user, id);
  }

  await adjustPlan(user.id, id, delta, {
    reason: input.reason ?? null,
    date: input.date,
    clientOpId: input.clientOpId ?? null,
  });
  return getById(user, id);
}

/**
 * Turn a plan from one kind into the other.
 *
 * Moves no money - the pot keeps its balance - but changes what every number on
 * the plan means, so it is recorded rather than silently toggled. Repeatable by
 * design: a holiday fund can become a monthly travel budget and back again, and
 * the log keeps the whole story.
 */
export async function convert(user: AuthUser, id: string, input: ConvertBudgetInput) {
  const budget = await assertOwned(id, user.id);

  if (budget.type === input.type) {
    throw new BadRequestError(
      input.type === BudgetType.SAVING
        ? 'This is already a saving plan.'
        : 'This is already a spending plan.',
    );
  }

  const snap = await loadSnapshot(user.id);
  const balance = potOf(snap, budget.id);

  const toSaving = input.type === BudgetType.SAVING;
  const nextKind = input.kind ?? (toSaving ? BudgetKind.ONE_TIME : budget.kind);
  const recurring = nextKind === BudgetKind.RECURRING;

  // Becoming a spending plan means the balance lands in a cycle that has a
  // ceiling. If it does not fit, opening the plan already over its own line is
  // the worst outcome - so the surplus is offered back to a wallet first.
  const planned = dec(input.plannedAmount ?? Number(budget.plannedAmount));
  let released: string | null = null;
  if (!toSaving && balance.gt(planned) && input.releaseSurplusTo) {
    const surplus = balance.sub(planned);
    await releasePlan(user.id, budget.id, {
      accountId: input.releaseSurplusTo,
      amount: surplus,
      note: `Surplus when "${budget.name}" became a spending plan`,
    });
    released = surplus.toFixed(2);
  }

  const goalAfter = toSaving ? (input.goalAmount ?? null) : null;

  await prisma.$transaction([
    prisma.budget.update({
      where: { id },
      data: {
        type: input.type,
        plannedAmount: planned,
        goalAmount: goalAfter === null ? null : dec(goalAfter),
        kind: nextKind,
        recurrenceUnit: recurring ? (input.recurrenceUnit ?? budget.recurrenceUnit) : null,
        recurrenceInterval: input.recurrenceInterval ?? budget.recurrenceInterval,
        endDate: input.endDate === undefined ? budget.endDate : (input.endDate ?? null),
        // A completed saving plan becoming a spending plan is the deliberate
        // route for "I saved for it, now let me spend it against the plan".
        state: BudgetState.ACTIVE,
        // The new shape's cycle opens with what is already in the pot.
        cycleOpeningPlanned: planned,
      },
    }),
    prisma.budgetTypeChange.create({
      data: {
        userId: user.id,
        budgetId: id,
        fromType: budget.type,
        toType: input.type,
        balanceAtChange: balance,
        plannedBefore: budget.plannedAmount,
        plannedAfter: planned,
        goalBefore: budget.goalAmount,
        goalAfter: goalAfter === null ? null : dec(goalAfter),
        cycleIndexAtChange: budget.cycleIndex,
        reason: input.reason ?? null,
      },
    }),
  ]);

  const view = await getById(user, id);
  return { ...view, releasedSurplus: released };
}

/** Every time this plan changed what it was for, newest first. */
export async function typeChanges(user: AuthUser, id: string) {
  await assertOwned(id, user.id);
  const rows = await prisma.budgetTypeChange.findMany({
    where: { budgetId: id, userId: user.id },
    orderBy: { at: 'desc' },
    take: 50,
  });
  return {
    items: rows.map((r) => ({
      id: r.id,
      fromType: r.fromType,
      toType: r.toType,
      balanceAtChange: r.balanceAtChange.toFixed(2),
      plannedBefore: r.plannedBefore.toFixed(2),
      plannedAfter: r.plannedAfter.toFixed(2),
      goalBefore: r.goalBefore ? r.goalBefore.toFixed(2) : null,
      goalAfter: r.goalAfter ? r.goalAfter.toFixed(2) : null,
      reason: r.reason,
      at: r.at.toISOString(),
    })),
  };
}

export async function remove(user: AuthUser, id: string) {
  const budget = await assertOwned(id, user.id);
  const snap = await loadSnapshot(user.id);
  const balance = potOf(snap, budget.id);
  if (balance.gt(0)) {
    throw new BadRequestError(
      `"${budget.name}" still holds ${balance.toFixed(2)} ${budget.currency}. Give it back to a wallet first.`,
    );
  }
  // Spending survives as ordinary unplanned expenses: budgetId is set null, and
  // the reservation column goes with it or the database check would refuse.
  await withMoneyLock(user.id, async (tx) => {
    await tx.transaction.updateMany({
      where: { budgetId: id },
      data: { budgetId: null, budgetCycle: null, budgetSourceAccountId: null },
    });
    await tx.budget.delete({ where: { id } });
  });
}

export async function fund(user: AuthUser, id: string, input: FundBudgetInput) {
  await fundPlan(user.id, id, {
    accountId: input.accountId,
    amount: input.amount,
    date: input.date,
    note: input.note ?? null,
    clientOpId: input.clientOpId ?? null,
  });
  return getById(user, id);
}

export async function release(user: AuthUser, id: string, input: ReleaseBudgetInput) {
  await releasePlan(user.id, id, {
    accountId: input.accountId,
    amount: input.amount,
    date: input.date,
    note: input.note ?? null,
    clientOpId: input.clientOpId ?? null,
  });
  return getById(user, id);
}

/** Move money straight from one plan to another, in one step. */
export async function moveMoney(user: AuthUser, id: string, input: MovePlanMoneyInput) {
  await movePlanMoney(user.id, id, input.toBudgetId, input.amount, {
    date: input.date,
    raiseTarget: input.raiseTarget ?? false,
    clientOpId: input.clientOpId ?? null,
  });
  return getById(user, id);
}

/** Move a plan's reservation between wallets, so the envelope follows the cash. */
export async function moveHolding(user: AuthUser, id: string, input: MoveReservationInput) {
  await moveReservation(user.id, id, input.fromAccountId, input.toAccountId, input.amount, {
    date: input.date,
    clientOpId: input.clientOpId ?? null,
  });
  return getById(user, id);
}

export async function close(user: AuthUser, id: string) {
  const budget = await assertOwned(id, user.id);
  if (budget.state === BudgetState.CLOSED) return getById(user, id);

  const snap = await loadSnapshot(user.id);
  const balance = potOf(snap, budget.id);
  if (balance.gt(0)) {
    throw new BadRequestError(
      `"${budget.name}" still holds ${balance.toFixed(2)} ${budget.currency}. Give it back to a wallet before closing.`,
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
// Hooks called after a plan expense lands, is edited, or is removed
// ---------------------------------------------------------------------------

/**
 * Warn when a pot runs low, retire a one-time plan whose money is spent - and
 * bring it back when that spending is undone.
 *
 * The reopen half matters more than it looks: without it, deleting the expense
 * that drained a plan left the refunded money sitting in a closed plan, still
 * locked against the wallet but missing from every plan total.
 */
export async function afterSpend(userId: string, budgetId: string): Promise<void> {
  try {
    const budget = await prisma.budget.findFirst({ where: { id: budgetId, userId } });
    if (!budget) return;

    const snap = await loadSnapshot(userId);
    const balance = potOf(snap, budget.id);

    if (budget.state === BudgetState.CLOSED) {
      const autoClosed = budget.kind === BudgetKind.ONE_TIME && balance.gt(0);
      if (autoClosed) {
        await prisma.budget.update({
          where: { id: budget.id },
          data: { state: BudgetState.ACTIVE, closedAt: null },
        });
        await notify(
          userId,
          'budget_reopened',
          `"${budget.name}" has ${balance.toFixed(2)} ${budget.currency} in it again, so it is open once more.`,
          `/budgets/${budget.id}`,
        );
      }
      return;
    }

    const t = await totalsFor(budget.id, budget.cycleIndex);
    const d = derive(budget, t, snap);

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
      const existing = await prisma.notification.findFirst({
        where: {
          userId,
          type: 'budget_alert',
          readFlag: false,
          message: { contains: budget.name },
          createdAt: { gte: budget.cycleStartedAt },
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
    // Alerts are best-effort; never fail the write that triggered them.
  }
}
