import { Prisma, SpendLockKind, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type { CreateSpendLockInput, ListSpendLocksQuery, UpdateSpendLockInput } from './spend-locks.schema.js';

type LockRow = {
  id: string;
  kind: SpendLockKind;
  name: string;
  amount: Prisma.Decimal;
  currency: string;
  active: boolean;
  note: string | null;
  goalId: string | null;
  goal?: {
    id: string;
    name: string;
    targetAmount: Prisma.Decimal;
    color: string | null;
    icon: string | null;
  } | null;
  createdAt: Date;
  updatedAt: Date;
};

/**
 * The amount a lock actually protects. GOAL locks track the linked goal's real
 * saved balance (capped by the reserve amount you set), so the vault grows as
 * you contribute and never over-locks past the target. Other kinds use their
 * own amount verbatim.
 */
function effectiveAmount(lock: LockRow, goalSaved: Map<string, Prisma.Decimal>): Prisma.Decimal {
  if (lock.kind === SpendLockKind.GOAL && lock.goalId) {
    const saved = goalSaved.get(lock.goalId) ?? new Prisma.Decimal(0);
    return Prisma.Decimal.min(saved, lock.amount);
  }
  return lock.amount;
}

function serialize(lock: LockRow, goalSaved: Map<string, Prisma.Decimal>) {
  const locked = effectiveAmount(lock, goalSaved);
  const saved = lock.goalId ? goalSaved.get(lock.goalId) ?? null : null;
  return {
    id: lock.id,
    kind: lock.kind,
    name: lock.name,
    amount: lock.amount.toFixed(2),
    lockedAmount: locked.toFixed(2), // what is actually protected right now
    currency: lock.currency,
    active: lock.active,
    note: lock.note,
    goalId: lock.goalId,
    goalSaved: saved ? saved.toFixed(2) : null,
    goal: lock.goal
      ? {
          id: lock.goal.id,
          name: lock.goal.name,
          targetAmount: lock.goal.targetAmount.toFixed(2),
          color: lock.goal.color,
          icon: lock.goal.icon,
        }
      : null,
    createdAt: lock.createdAt,
    updatedAt: lock.updatedAt,
  };
}

const include = {
  goal: { select: { id: true, name: true, targetAmount: true, color: true, icon: true } },
} satisfies Prisma.SpendLockInclude;

/** Real saved amounts (sum of contributions) for the given goals. */
async function goalSavedMap(userId: string, goalIds: string[]) {
  const ids = [...new Set(goalIds.filter(Boolean))];
  const map = new Map<string, Prisma.Decimal>();
  if (ids.length === 0) return map;
  const rows = await prisma.goalContribution.groupBy({
    by: ['goalId'],
    where: { goalId: { in: ids }, goal: { userId } },
    _sum: { amount: true },
  });
  for (const r of rows) map.set(r.goalId, r._sum.amount ?? new Prisma.Decimal(0));
  return map;
}

async function accountBalance(userId: string, currency: string) {
  const accounts = await prisma.account.findMany({
    where: { userId, currency, archived: false },
  });
  if (accounts.length === 0) return new Prisma.Decimal(0);

  const [sums, transfersIn] = await Promise.all([
    prisma.transaction.groupBy({
      by: ['accountId', 'kind'],
      where: { userId },
      _sum: { amount: true },
    }),
    prisma.transaction.groupBy({
      by: ['transferAccountId'],
      where: { userId, kind: TxKind.TRANSFER, transferAccountId: { not: null } },
      _sum: { amount: true },
    }),
  ]);

  const zero = new Prisma.Decimal(0);
  let total = zero;
  for (const a of accounts) {
    let balance = new Prisma.Decimal(a.openingBalance);
    for (const s of sums) {
      if (s.accountId !== a.id) continue;
      const amt = s._sum.amount ?? zero;
      if (s.kind === TxKind.INCOME) balance = balance.add(amt);
      else balance = balance.sub(amt);
    }
    for (const t of transfersIn) {
      if (t.transferAccountId === a.id) balance = balance.add(t._sum.amount ?? zero);
    }
    total = total.add(balance);
  }
  return total;
}

function overviewFor(
  currency: string,
  locks: LockRow[],
  balance: Prisma.Decimal,
  goalSaved: Map<string, Prisma.Decimal>,
) {
  const active = locks.filter((l) => l.active && l.currency === currency);
  const floorLocks = active.filter((l) => l.kind === SpendLockKind.FLOOR);
  const reserveLocks = active.filter((l) => l.kind !== SpendLockKind.FLOOR);
  const floorAmount = floorLocks.reduce(
    (max, l) => (l.amount.gt(max) ? l.amount : max),
    new Prisma.Decimal(0),
  );
  const reservedAmount = reserveLocks.reduce(
    (s, l) => s.add(effectiveAmount(l, goalSaved)),
    new Prisma.Decimal(0),
  );
  const lockedTotal = floorAmount.add(reservedAmount);
  const spendable = Prisma.Decimal.max(new Prisma.Decimal(0), balance.sub(lockedTotal));
  const multiFloor = floorLocks.length > 1;
  const overLocked = balance.lt(lockedTotal);

  return {
    currency,
    balance: balance.toFixed(2),
    floorAmount: floorAmount.toFixed(2),
    reservedAmount: reservedAmount.toFixed(2),
    lockedTotal: lockedTotal.toFixed(2),
    spendable: spendable.toFixed(2),
    lockCount: active.length,
    conflict: multiFloor || overLocked,
    hint: overLocked
      ? 'Your locks exceed balance - unlock or lower amounts.'
      : multiFloor
        ? 'Multiple floor locks: the highest floor wins; others stay as reminders.'
        : null,
  };
}

export type SpendableRow = ReturnType<typeof overviewFor>;

/** Spendable-money overview for one currency. Shared by wishlist + dashboard. */
export async function spendableFor(userId: string, currency: string): Promise<SpendableRow> {
  const cur = currency.toUpperCase();
  const locks = (await prisma.spendLock.findMany({
    where: { userId, currency: cur, active: true },
    include,
  })) as LockRow[];
  const [balance, goalSaved] = await Promise.all([
    accountBalance(userId, cur),
    goalSavedMap(userId, locks.map((l) => l.goalId ?? '')),
  ]);
  return overviewFor(cur, locks, balance, goalSaved);
}

export async function list(user: AuthUser, query: ListSpendLocksQuery) {
  const currency = query.currency?.toUpperCase();
  const locks = (await prisma.spendLock.findMany({
    where: {
      userId: user.id,
      ...(currency ? { currency } : {}),
      ...(query.active === 'true' ? { active: true } : query.active === 'false' ? { active: false } : {}),
    },
    include,
    orderBy: [{ active: 'desc' }, { createdAt: 'desc' }],
  })) as LockRow[];

  const goalSaved = await goalSavedMap(user.id, locks.map((l) => l.goalId ?? ''));

  const currencies = currency ? [currency] : [...new Set(locks.map((l) => l.currency))];
  if (currencies.length === 0) {
    const userRow = await prisma.user.findUnique({ where: { id: user.id }, select: { currency: true } });
    currencies.push(userRow?.currency ?? 'ETB');
  }

  const overview = await Promise.all(
    currencies.map(async (cur) => overviewFor(cur, locks, await accountBalance(user.id, cur), goalSaved)),
  );

  return { items: locks.map((l) => serialize(l, goalSaved)), overview };
}

export async function create(user: AuthUser, input: CreateSpendLockInput) {
  if (input.goalId) {
    const goal = await prisma.savingsGoal.findFirst({ where: { id: input.goalId, userId: user.id } });
    if (!goal) throw new NotFoundError('Goal not found');
  }

  const name =
    input.name.trim() ||
    (input.kind === SpendLockKind.FLOOR
      ? 'Safety floor'
      : input.kind === SpendLockKind.GOAL
        ? 'Goal vault'
        : 'Reserve');

  const lock = (await prisma.spendLock.create({
    data: {
      userId: user.id,
      kind: input.kind,
      name,
      amount: input.amount,
      currency: input.currency.toUpperCase(),
      note: input.note,
      goalId: input.goalId,
      active: input.active ?? true,
    },
    include,
  })) as LockRow;

  const goalSaved = await goalSavedMap(user.id, [lock.goalId ?? '']);
  return serialize(lock, goalSaved);
}

export async function update(user: AuthUser, id: string, input: UpdateSpendLockInput) {
  const existing = await prisma.spendLock.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new NotFoundError('Lock not found');

  if (input.goalId) {
    const goal = await prisma.savingsGoal.findFirst({ where: { id: input.goalId, userId: user.id } });
    if (!goal) throw new NotFoundError('Goal not found');
  }

  const lock = (await prisma.spendLock.update({
    where: { id },
    data: {
      ...(input.name !== undefined ? { name: input.name.trim() } : {}),
      ...(input.amount !== undefined ? { amount: input.amount } : {}),
      ...(input.note !== undefined ? { note: input.note } : {}),
      ...(input.active !== undefined ? { active: input.active } : {}),
      ...(input.goalId !== undefined ? { goalId: input.goalId } : {}),
    },
    include,
  })) as LockRow;

  const goalSaved = await goalSavedMap(user.id, [lock.goalId ?? '']);
  return serialize(lock, goalSaved);
}

export async function remove(user: AuthUser, id: string) {
  const existing = await prisma.spendLock.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new NotFoundError('Lock not found');
  await prisma.spendLock.delete({ where: { id } });
}

/** Deactivate any GOAL locks tied to a goal - used when its reserve is spent as intended. */
export async function releaseGoalLocks(userId: string, goalId: string) {
  await prisma.spendLock.updateMany({
    where: { userId, goalId, kind: SpendLockKind.GOAL, active: true },
    data: { active: false },
  });
}

/** Reject expenses that would break active spend locks for that currency. */
export async function assertExpenseAllowed(userId: string, currency: string, expenseAmount: number) {
  const row = await spendableFor(userId, currency);
  if (row.lockCount === 0) return;
  if (expenseAmount > Number(row.spendable) + 0.001) {
    throw new BadRequestError(
      `Spend lock: only ${row.spendable} ${currency.toUpperCase()} is unlocked. Locked: ${row.lockedTotal} (floor ${row.floorAmount} + reserved ${row.reservedAmount}).`,
    );
  }
}
