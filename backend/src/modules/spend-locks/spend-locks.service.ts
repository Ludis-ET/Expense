import { Prisma, SpendLockKind, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { lockedTotal as budgetLockedTotal } from '../budgets/budgets.service.js';
import type { CreateSpendLockInput, ListSpendLocksQuery, UpdateSpendLockInput } from './spend-locks.schema.js';

type LockRow = {
  id: string;
  kind: SpendLockKind;
  name: string;
  amount: Prisma.Decimal;
  currency: string;
  active: boolean;
  note: string | null;
  createdAt: Date;
  updatedAt: Date;
};

function serialize(lock: LockRow) {
  return {
    id: lock.id,
    kind: lock.kind,
    name: lock.name,
    amount: lock.amount.toFixed(2),
    lockedAmount: lock.amount.toFixed(2), // what is actually protected right now
    currency: lock.currency,
    active: lock.active,
    note: lock.note,
    createdAt: lock.createdAt,
    updatedAt: lock.updatedAt,
  };
}

/** Money physically held across every account in one currency. */
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

/**
 * Spendable money = what sits in accounts, minus what budget plans hold, minus
 * the locks you set. Budget money is subtracted first: it is already committed.
 */
function overviewFor(
  currency: string,
  locks: LockRow[],
  balance: Prisma.Decimal,
  budgetLocked: Prisma.Decimal,
) {
  const zero = new Prisma.Decimal(0);
  const active = locks.filter((l) => l.active && l.currency === currency);
  const floorLocks = active.filter((l) => l.kind === SpendLockKind.FLOOR);
  const reserveLocks = active.filter((l) => l.kind !== SpendLockKind.FLOOR);
  const floorAmount = floorLocks.reduce((max, l) => (l.amount.gt(max) ? l.amount : max), zero);
  const reservedAmount = reserveLocks.reduce((s, l) => s.add(l.amount), zero);

  const available = balance.sub(budgetLocked); // free of budget plans
  const lockedTotal = floorAmount.add(reservedAmount);
  const spendable = Prisma.Decimal.max(zero, available.sub(lockedTotal));
  const multiFloor = floorLocks.length > 1;
  const overLocked = available.lt(lockedTotal);

  return {
    currency,
    /** Money physically in accounts. */
    balance: balance.toFixed(2),
    /** Held inside budget plans. */
    budgetLocked: budgetLocked.toFixed(2),
    /** Balance minus budget plans - what locks are measured against. */
    available: available.toFixed(2),
    floorAmount: floorAmount.toFixed(2),
    reservedAmount: reservedAmount.toFixed(2),
    lockedTotal: lockedTotal.toFixed(2),
    spendable: spendable.toFixed(2),
    lockCount: active.length,
    conflict: multiFloor || overLocked,
    hint: overLocked
      ? 'Your locks exceed what is left after budget plans - unlock or lower amounts.'
      : multiFloor
        ? 'Multiple floor locks: the highest floor wins; others stay as reminders.'
        : null,
  };
}

export type SpendableRow = ReturnType<typeof overviewFor>;

/** Spendable-money overview for one currency. Shared by wishlist + dashboard. */
export async function spendableFor(userId: string, currency: string): Promise<SpendableRow> {
  const cur = currency.toUpperCase();
  const [locks, balance, budgetLocked] = await Promise.all([
    prisma.spendLock.findMany({ where: { userId, currency: cur, active: true } }) as Promise<LockRow[]>,
    accountBalance(userId, cur),
    budgetLockedTotal(userId, cur),
  ]);
  return overviewFor(cur, locks, balance, budgetLocked);
}

export async function list(user: AuthUser, query: ListSpendLocksQuery) {
  const currency = query.currency?.toUpperCase();
  const locks = (await prisma.spendLock.findMany({
    where: {
      userId: user.id,
      ...(currency ? { currency } : {}),
      ...(query.active === 'true' ? { active: true } : query.active === 'false' ? { active: false } : {}),
    },
    orderBy: [{ active: 'desc' }, { createdAt: 'desc' }],
  })) as LockRow[];

  const currencies = currency ? [currency] : [...new Set(locks.map((l) => l.currency))];
  if (currencies.length === 0) {
    const userRow = await prisma.user.findUnique({ where: { id: user.id }, select: { currency: true } });
    currencies.push(userRow?.currency ?? 'ETB');
  }

  const overview = await Promise.all(
    currencies.map(async (cur) =>
      overviewFor(cur, locks, await accountBalance(user.id, cur), await budgetLockedTotal(user.id, cur)),
    ),
  );

  return { items: locks.map(serialize), overview };
}

export async function create(user: AuthUser, input: CreateSpendLockInput) {
  const name =
    input.name.trim() || (input.kind === SpendLockKind.FLOOR ? 'Safety floor' : 'Reserve');

  const lock = (await prisma.spendLock.create({
    data: {
      userId: user.id,
      kind: input.kind,
      name,
      amount: input.amount,
      currency: input.currency.toUpperCase(),
      note: input.note,
      active: input.active ?? true,
    },
  })) as LockRow;

  return serialize(lock);
}

export async function update(user: AuthUser, id: string, input: UpdateSpendLockInput) {
  const existing = await prisma.spendLock.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new NotFoundError('Lock not found');

  const lock = (await prisma.spendLock.update({
    where: { id },
    data: {
      ...(input.name !== undefined ? { name: input.name.trim() } : {}),
      ...(input.amount !== undefined ? { amount: input.amount } : {}),
      ...(input.note !== undefined ? { note: input.note } : {}),
      ...(input.active !== undefined ? { active: input.active } : {}),
    },
  })) as LockRow;

  return serialize(lock);
}

export async function remove(user: AuthUser, id: string) {
  const existing = await prisma.spendLock.findFirst({ where: { id, userId: user.id } });
  if (!existing) throw new NotFoundError('Lock not found');
  await prisma.spendLock.delete({ where: { id } });
}

/** Reject expenses that would break active spend locks for that currency. */
export async function assertExpenseAllowed(userId: string, currency: string, expenseAmount: number) {
  const row = await spendableFor(userId, currency);
  if (row.lockCount === 0) return;
  if (expenseAmount > Number(row.spendable) + 0.001) {
    throw new BadRequestError(
      `Spend lock: only ${row.spendable} ${currency.toUpperCase()} is unlocked. Locked: ${row.lockedTotal} (floor ${row.floorAmount} + reserved ${row.reservedAmount}), plus ${row.budgetLocked} held in budget plans.`,
    );
  }
}
