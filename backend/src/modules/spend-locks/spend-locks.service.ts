import { Prisma, SpendLockKind, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type { CreateSpendLockInput, ListSpendLocksQuery, UpdateSpendLockInput } from './spend-locks.schema.js';

function serialize(lock: {
  id: string;
  kind: SpendLockKind;
  name: string;
  amount: Prisma.Decimal;
  currency: string;
  active: boolean;
  note: string | null;
  goalId: string | null;
  goal?: { id: string; name: string; targetAmount: Prisma.Decimal; color: string | null; icon: string | null } | null;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: lock.id,
    kind: lock.kind,
    name: lock.name,
    amount: lock.amount.toFixed(2),
    currency: lock.currency,
    active: lock.active,
    note: lock.note,
    goalId: lock.goalId,
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
  locks: Awaited<ReturnType<typeof prisma.spendLock.findMany>>,
  balance: Prisma.Decimal,
) {
  const active = locks.filter((l) => l.active && l.currency === currency);
  const floorLocks = active.filter((l) => l.kind === SpendLockKind.FLOOR);
  const reserveLocks = active.filter((l) => l.kind !== SpendLockKind.FLOOR);
  const floorAmount = floorLocks.reduce(
    (max, l) => (l.amount.gt(max) ? l.amount : max),
    new Prisma.Decimal(0),
  );
  const reservedAmount = reserveLocks.reduce((s, l) => s.add(l.amount), new Prisma.Decimal(0));
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

export async function list(user: AuthUser, query: ListSpendLocksQuery) {
  const currency = query.currency?.toUpperCase();
  const locks = await prisma.spendLock.findMany({
    where: {
      userId: user.id,
      ...(currency ? { currency } : {}),
      ...(query.active === 'true' ? { active: true } : query.active === 'false' ? { active: false } : {}),
    },
    include,
    orderBy: [{ active: 'desc' }, { createdAt: 'desc' }],
  });

  const currencies = currency
    ? [currency]
    : [...new Set(locks.map((l) => l.currency))];
  if (currencies.length === 0) {
    const userRow = await prisma.user.findUnique({ where: { id: user.id }, select: { currency: true } });
    currencies.push(userRow?.currency ?? 'ETB');
  }

  const overview = await Promise.all(
    currencies.map(async (cur) => overviewFor(cur, locks, await accountBalance(user.id, cur))),
  );

  return { items: locks.map(serialize), overview };
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

  const lock = await prisma.spendLock.create({
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
  });

  return serialize(lock);
}

export async function update(user: AuthUser, id: string, input: UpdateSpendLockInput) {
  const existing = await prisma.spendLock.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new NotFoundError('Lock not found');

  if (input.goalId) {
    const goal = await prisma.savingsGoal.findFirst({ where: { id: input.goalId, userId: user.id } });
    if (!goal) throw new NotFoundError('Goal not found');
  }

  const lock = await prisma.spendLock.update({
    where: { id },
    data: {
      ...(input.name !== undefined ? { name: input.name.trim() } : {}),
      ...(input.amount !== undefined ? { amount: input.amount } : {}),
      ...(input.note !== undefined ? { note: input.note } : {}),
      ...(input.active !== undefined ? { active: input.active } : {}),
      ...(input.goalId !== undefined ? { goalId: input.goalId } : {}),
    },
    include,
  });

  return serialize(lock);
}

export async function remove(user: AuthUser, id: string) {
  const existing = await prisma.spendLock.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new NotFoundError('Lock not found');
  await prisma.spendLock.delete({ where: { id } });
}

/** Reject expenses that would break active spend locks for that currency. */
export async function assertExpenseAllowed(userId: string, currency: string, expenseAmount: number) {
  const locks = await prisma.spendLock.findMany({
    where: { userId, currency: currency.toUpperCase(), active: true },
  });
  if (locks.length === 0) return;

  const balance = await accountBalance(userId, currency.toUpperCase());
  const row = overviewFor(currency.toUpperCase(), locks, balance);
  if (expenseAmount > Number(row.spendable) + 0.001) {
    throw new BadRequestError(
      `Spend lock: only ${row.spendable} ${currency} is unlocked. Locked: ${row.lockedTotal} (floor ${row.floorAmount} + reserved ${row.reservedAmount}).`,
    );
  }
}
