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
import { addPeriod, cycleLabel, PERIOD_NOUN } from './budgets.periods.js';
import type {
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
}

async function totalsFor(budgetId: string, cycleIndex: number): Promise<Totals> {
  const [allocAll, allocCycle, spentAll, spentCycle] = await Promise.all([
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
  ]);
  return {
    allocated: allocAll._sum.amount ?? zero,
    spent: spentAll._sum.amount ?? zero,
    allocatedThisCycle: allocCycle._sum.amount ?? zero,
    spentThisCycle: spentCycle._sum.amount ?? zero,
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
    });
  }
  if (ids.length === 0) return map;

  const cycleOf = new Map(budgets.map((b) => [b.id, b.cycleIndex]));
  const [allocs, spends] = await Promise.all([
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

type Health = 'empty' | 'partly-funded' | 'ready' | 'spending' | 'low' | 'drained' | 'closed';

function health(budget: Budget, d: ReturnType<typeof derive>): Health {
  if (budget.state === BudgetState.CLOSED) return 'closed';
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
    period: budget.period,
    periodNoun: budget.period ? PERIOD_NOUN[budget.period] : null,
    currency: budget.currency,
    icon: budget.icon,
    color: budget.color,
    note: budget.note,
    alertThreshold: budget.alertThreshold,
    state: budget.state,
    closedAt: budget.closedAt ? budget.closedAt.toISOString() : null,

    plannedAmount: budget.plannedAmount.toFixed(2),
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
    cycleStartedAt: budget.cycleStartedAt.toISOString(),
    nextResetAt: budget.nextResetAt ? budget.nextResetAt.toISOString() : null,
    endDate: budget.endDate ? budget.endDate.toISOString() : null,
    cycleLabel: budget.period
      ? cycleLabel(budget.period, budget.cycleStartedAt, budget.nextResetAt ?? budget.cycleStartedAt)
      : null,

    createdAt: budget.createdAt.toISOString(),
    updatedAt: budget.updatedAt.toISOString(),
  };
}

export type SerializedBudget = ReturnType<typeof serialize>;

// ---------------------------------------------------------------------------
// Reservation lookups (used by accounts / transactions / spend locks)
// ---------------------------------------------------------------------------

/**
 * How much of each account's balance is currently tied up in plans.
 * `SUM(allocations from the account) - SUM(plan expenses charged to it)`.
 */
export async function lockedByAccount(userId: string): Promise<Map<string, Prisma.Decimal>> {
  const [allocs, spends] = await Promise.all([
    prisma.budgetAllocation.groupBy({
      by: ['accountId'],
      where: { userId },
      _sum: { amount: true },
    }),
    prisma.transaction.groupBy({
      by: ['accountId'],
      where: { userId, kind: TxKind.EXPENSE, budgetId: { not: null } },
      _sum: { amount: true },
    }),
  ]);

  const map = new Map<string, Prisma.Decimal>();
  for (const a of allocs) map.set(a.accountId, a._sum.amount ?? zero);
  for (const s of spends) {
    map.set(s.accountId, (map.get(s.accountId) ?? zero).sub(s._sum.amount ?? zero));
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

/** Per-account remaining share of one plan's pot, largest first. */
export async function sourcesFor(budgetId: string) {
  const [allocs, spends] = await Promise.all([
    prisma.budgetAllocation.groupBy({
      by: ['accountId'],
      where: { budgetId },
      _sum: { amount: true },
    }),
    prisma.transaction.groupBy({
      by: ['accountId'],
      where: { budgetId, kind: TxKind.EXPENSE },
      _sum: { amount: true },
    }),
  ]);

  const shares = new Map<string, Prisma.Decimal>();
  for (const a of allocs) shares.set(a.accountId, a._sum.amount ?? zero);
  for (const s of spends) shares.set(s.accountId, (shares.get(s.accountId) ?? zero).sub(s._sum.amount ?? zero));

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

/** Runaway guard when catching up a long-dormant plan. */
const MAX_ROLLS = 60;

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

    while (b.nextResetAt && b.nextResetAt <= now && rolls < MAX_ROLLS) {
      const t = await totalsFor(b.id, b.cycleIndex);
      const d = derive(b, t);
      const txCount = await prisma.transaction.count({
        where: { budgetId: b.id, budgetCycle: b.cycleIndex, kind: TxKind.EXPENSE },
      });

      const endedAt = b.nextResetAt;
      await prisma.budgetCycle.upsert({
        where: { budgetId_index: { budgetId: b.id, index: b.cycleIndex } },
        create: {
          budgetId: b.id,
          index: b.cycleIndex,
          startedAt: b.cycleStartedAt,
          endedAt,
          label: cycleLabel(b.period, b.cycleStartedAt, endedAt),
          plannedAmount: b.plannedAmount,
          carriedIn: d.carriedIn,
          fundedAmount: d.funded,
          spentAmount: d.spent,
          leftoverAmount: d.balance,
          txCount,
        },
        update: {
          endedAt,
          fundedAmount: d.funded,
          spentAmount: d.spent,
          leftoverAmount: d.balance,
          txCount,
        },
      });

      const finished = b.endDate ? endedAt >= b.endDate : false;
      b = await prisma.budget.update({
        where: { id: b.id },
        data: {
          cycleIndex: b.cycleIndex + 1,
          cycleStartedAt: endedAt,
          nextResetAt: finished ? null : addPeriod(b.period!, endedAt),
          ...(finished ? { state: BudgetState.CLOSED, closedAt: now } : {}),
        },
      });

      if (Number(d.balance) > 0) {
        await notify(
          userId,
          'budget_cycle_rolled',
          `"${b.name}" started a new ${PERIOD_NOUN[b.period!]} with ${d.balance.toFixed(2)} ${b.currency} carried over.`,
          `/budgets/${b.id}`,
        );
      }
      rolls += 1;
      if (finished) break;
    }
  }
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

export async function list(user: AuthUser, query: ListBudgetsQuery = {}) {
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
  const items = budgets.map((b) => serialize(b, totals.get(b.id)!));
  const active = items.filter((i) => i.state === BudgetState.ACTIVE);

  const sum = (pick: (i: SerializedBudget) => string) =>
    active.reduce((s, i) => s.add(dec(pick(i))), zero).toFixed(2);

  return {
    items,
    totals: {
      planned: sum((i) => i.plannedAmount),
      funded: sum((i) => i.fundedAmount),
      spent: sum((i) => i.spentAmount),
      /** Money locked away in plans right now. */
      locked: sum((i) => i.balance),
      activeCount: active.length,
      closedCount: items.length - active.length,
    },
  };
}

/** Plans that still hold money - the extra "pay from" options on a transaction. */
export async function spendableSources(user: AuthUser, currency?: string) {
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
  const withMoney = budgets
    .map((b) => serialize(b, totals.get(b.id)!))
    .filter((b) => Number(b.balance) > 0);

  const items = await Promise.all(
    withMoney.map(async (b) => ({
      id: b.id,
      name: b.name,
      currency: b.currency,
      balance: b.balance,
      icon: b.icon,
      color: b.color,
      categoryId: b.categoryId,
      category: b.category,
      sources: (await sourcesFor(b.id))
        .filter((s) => s.available.gt(0))
        .map((s) => ({ account: s.account, available: s.available.toFixed(2) })),
    })),
  );

  return { items };
}

/** Everything the plan detail page shows. */
export async function getById(user: AuthUser, id: string) {
  await rollDueCycles(user.id);

  const budget = await prisma.budget.findFirst({
    where: { id, userId: user.id },
    include: { category: { select: categorySelect } },
  });
  if (!budget) throw new NotFoundError('Budget plan not found');

  const t = await totalsFor(budget.id, budget.cycleIndex);
  const [allocations, transactions, cycles, sources] = await Promise.all([
    prisma.budgetAllocation.findMany({
      where: { budgetId: budget.id },
      include: { account: { select: accountSelect } },
      orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
    }),
    prisma.transaction.findMany({
      where: { budgetId: budget.id },
      include: {
        category: { select: categorySelect },
        account: { select: accountSelect },
      },
      orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
    }),
    prisma.budgetCycle.findMany({ where: { budgetId: budget.id }, orderBy: { index: 'desc' } }),
    sourcesFor(budget.id),
  ]);

  const txByCycle = new Map<number, typeof transactions>();
  for (const tx of transactions) {
    const key = tx.budgetCycle ?? budget.cycleIndex;
    const bucket = txByCycle.get(key) ?? [];
    bucket.push(tx);
    txByCycle.set(key, bucket);
  }

  const serializeTx = (tx: (typeof transactions)[number]) => ({
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

  // One chronological stream of everything that moved money in or out.
  const timeline = [
    ...allocations.map((a) => ({
      type: a.kind === BudgetAllocationKind.FUND ? ('fund' as const) : ('release' as const),
      at: a.date.toISOString(),
      cycleIndex: a.cycleIndex,
      entry: serializeAlloc(a),
    })),
    ...transactions.map((tx) => ({
      type: 'spend' as const,
      at: tx.date.toISOString(),
      cycleIndex: tx.budgetCycle ?? budget.cycleIndex,
      entry: serializeTx(tx),
    })),
  ].sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0));

  return {
    ...serialize(budget, t),
    timeline,
    transactions: (txByCycle.get(budget.cycleIndex) ?? []).map(serializeTx),
    allocations: allocations.filter((a) => a.cycleIndex === budget.cycleIndex).map(serializeAlloc),
    sources: sources.map((s) => ({ account: s.account, available: s.available.toFixed(2) })),
    cycles: cycles.map((c) => ({
      index: c.index,
      label: c.label,
      startedAt: c.startedAt.toISOString(),
      endedAt: c.endedAt.toISOString(),
      plannedAmount: c.plannedAmount.toFixed(2),
      carriedIn: c.carriedIn.toFixed(2),
      fundedAmount: c.fundedAmount.toFixed(2),
      spentAmount: c.spentAmount.toFixed(2),
      leftoverAmount: c.leftoverAmount.toFixed(2),
      txCount: c.txCount,
      transactions: (txByCycle.get(c.index) ?? []).map(serializeTx),
      allocations: allocations.filter((a) => a.cycleIndex === c.index).map(serializeAlloc),
    })),
    lifetime: {
      allocated: t.allocated.toFixed(2),
      spent: t.spent.toFixed(2),
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
  if (input.kind === BudgetKind.RECURRING && !input.period) {
    throw new BadRequestError('Pick how often this plan repeats');
  }

  const startedAt = input.startDate ?? new Date();
  const budget = await prisma.budget.create({
    data: {
      userId: user.id,
      name: input.name.trim(),
      categoryId: input.categoryId ?? null,
      kind: input.kind,
      period: input.kind === BudgetKind.RECURRING ? input.period : null,
      plannedAmount: input.plannedAmount,
      currency: input.currency.toUpperCase(),
      icon: input.icon ?? null,
      color: input.color ?? null,
      note: input.note ?? null,
      alertThreshold: input.alertThreshold,
      cycleStartedAt: startedAt,
      nextResetAt:
        input.kind === BudgetKind.RECURRING ? addPeriod(input.period!, startedAt) : null,
      endDate: input.endDate ?? null,
    },
    include: { category: { select: categorySelect } },
  });

  return serialize(budget, await totalsFor(budget.id, budget.cycleIndex));
}

export async function update(user: AuthUser, id: string, input: UpdateBudgetInput) {
  const existing = await assertOwned(id, user.id);
  if (input.categoryId) await assertCategory(input.categoryId, user.id);

  // Shrinking the plan below what is already in the pot would strand money.
  if (input.plannedAmount !== undefined) {
    const t = await totalsFor(existing.id, existing.cycleIndex);
    const { funded } = derive(existing, t);
    if (dec(input.plannedAmount).lt(funded)) {
      throw new BadRequestError(
        `This plan already holds ${funded.toFixed(2)} ${existing.currency}. Give money back to an account before lowering the planned amount.`,
      );
    }
  }

  const nextKind = input.kind ?? existing.kind;
  const nextPeriod = input.period ?? existing.period;
  if (nextKind === BudgetKind.RECURRING && !nextPeriod) {
    throw new BadRequestError('Pick how often this plan repeats');
  }

  const budget = await prisma.budget.update({
    where: { id },
    data: {
      ...(input.name !== undefined ? { name: input.name.trim() } : {}),
      ...(input.categoryId !== undefined ? { categoryId: input.categoryId } : {}),
      ...(input.plannedAmount !== undefined ? { plannedAmount: input.plannedAmount } : {}),
      ...(input.icon !== undefined ? { icon: input.icon } : {}),
      ...(input.color !== undefined ? { color: input.color } : {}),
      ...(input.note !== undefined ? { note: input.note } : {}),
      ...(input.alertThreshold !== undefined ? { alertThreshold: input.alertThreshold } : {}),
      ...(input.endDate !== undefined ? { endDate: input.endDate } : {}),
      ...(input.kind !== undefined || input.period !== undefined
        ? {
            kind: nextKind,
            period: nextKind === BudgetKind.RECURRING ? nextPeriod : null,
            nextResetAt:
              nextKind === BudgetKind.RECURRING
                ? (existing.nextResetAt ?? addPeriod(nextPeriod!, existing.cycleStartedAt))
                : null,
          }
        : {}),
    },
    include: { category: { select: categorySelect } },
  });

  return serialize(budget, await totalsFor(budget.id, budget.cycleIndex));
}

export async function remove(user: AuthUser, id: string) {
  const budget = await assertOwned(id, user.id);
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
  await prisma.budget.update({
    where: { id },
    data: {
      state: BudgetState.ACTIVE,
      closedAt: null,
      // A recurring plan that ran past its end date needs a fresh reset clock.
      ...(budget.kind === BudgetKind.RECURRING && !budget.nextResetAt && budget.period
        ? { cycleStartedAt: new Date(), nextResetAt: addPeriod(budget.period, new Date()) }
        : {}),
      ...(budget.endDate && budget.endDate <= new Date() ? { endDate: null } : {}),
    },
  });
  return getById(user, id);
}

// ---------------------------------------------------------------------------
// Hooks called by the transactions module
// ---------------------------------------------------------------------------

export interface PlanCharge {
  budget: Budget;
  accountId: string;
}

/**
 * Validate that `amount` can be paid out of a plan and decide which account the
 * real money leaves from. Returns the resolved source; throws with a readable
 * message when the pot (or one account's share of it) is too small.
 *
 * `excludeTxId` lets an edit ignore its own prior effect.
 */
export async function assertSpendable(
  userId: string,
  budgetId: string,
  amount: number,
  preferredAccountId?: string,
  excludeTxId?: string,
): Promise<PlanCharge> {
  const budget = await prisma.budget.findFirst({ where: { id: budgetId, userId } });
  if (!budget) throw new NotFoundError('Budget plan not found');
  if (budget.state === BudgetState.CLOSED) {
    throw new BadRequestError(`"${budget.name}" is closed. Reopen it to spend from it.`);
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

  // Pick the funding account that can cover the whole spend.
  const [allocs, spends] = await Promise.all([
    prisma.budgetAllocation.groupBy({ by: ['accountId'], where: { budgetId }, _sum: { amount: true } }),
    prisma.transaction.groupBy({ by: ['accountId'], where: spendWhere, _sum: { amount: true } }),
  ]);
  const shares = new Map<string, Prisma.Decimal>();
  for (const a of allocs) shares.set(a.accountId, a._sum.amount ?? zero);
  for (const s of spends) shares.set(s.accountId, (shares.get(s.accountId) ?? zero).sub(s._sum.amount ?? zero));

  const ranked = [...shares.entries()].sort((a, b) => b[1].comparedTo(a[1]));
  const chosen = preferredAccountId
    ? ranked.find(([accountId]) => accountId === preferredAccountId)
    : ranked[0];

  if (!chosen) throw new BadRequestError(`"${budget.name}" has no money in it yet.`);
  if (want.gt(chosen[1])) {
    const best = ranked[0];
    throw new BadRequestError(
      preferredAccountId
        ? `Only ${chosen[1].toFixed(2)} ${budget.currency} of "${budget.name}" came from that account.`
        : `"${budget.name}" holds money across several accounts; the largest single share is ${best![1].toFixed(2)} ${budget.currency}. Split the expense or move money between accounts first.`,
    );
  }

  return { budget, accountId: chosen[0] };
}

/**
 * After a plan expense lands: warn when the pot runs low, and retire a one-time
 * plan whose money is fully spent.
 */
export async function afterSpend(userId: string, budgetId: string): Promise<void> {
  try {
    const budget = await prisma.budget.findFirst({ where: { id: budgetId, userId } });
    if (!budget || budget.state === BudgetState.CLOSED) return;

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
        `You've used ${Math.round(d.pctSpentOfFunded)}% of "${budget.name}" — ${d.balance.toFixed(2)} ${budget.currency} left.`,
        `/budgets/${budget.id}`,
      );
    }
  } catch {
    // Alerts are best-effort; never fail the transaction write.
  }
}
