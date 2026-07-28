import { Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { ConflictError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type { CreateAccountInput, UpdateAccountInput } from './accounts.schema.js';

async function assertOwnedAccount(id: string, userId: string) {
  const account = await prisma.account.findFirst({ where: { id, userId } });
  if (!account) throw new NotFoundError('Account not found');
  return account;
}

/**
 * All accounts with computed balances.
 *
 * `realBalance` is the money physically in the account:
 * opening + income − expense − transfers-out + transfers-in.
 *
 * `lockedAmount` is the slice of it reserved by budget plans. `balance` is what
 * is left over — the figure every "available to spend" surface should use.
 */
export async function list(user: AuthUser) {
  const accounts = await prisma.account.findMany({
    where: { userId: user.id },
    orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
  });

  const { lockedByAccount } = await import('../budgets/budgets.service.js');
  const [sums, transfersIn, locked] = await Promise.all([
    prisma.transaction.groupBy({
      by: ['accountId', 'kind'],
      where: { userId: user.id },
      _sum: { amount: true },
    }),
    prisma.transaction.groupBy({
      by: ['transferAccountId'],
      where: { userId: user.id, kind: TxKind.TRANSFER, transferAccountId: { not: null } },
      _sum: { amount: true },
    }),
    lockedByAccount(user.id),
  ]);

  const zero = new Prisma.Decimal(0);
  const rows = accounts.map((a) => {
    let real = new Prisma.Decimal(a.openingBalance);
    for (const s of sums) {
      if (s.accountId !== a.id) continue;
      const amt = s._sum.amount ?? zero;
      if (s.kind === TxKind.INCOME) real = real.add(amt);
      else real = real.sub(amt); // EXPENSE and TRANSFER both leave the source account
    }
    for (const t of transfersIn) {
      if (t.transferAccountId === a.id) real = real.add(t._sum.amount ?? zero);
    }
    const lockedAmount = locked.get(a.id) ?? zero;
    return {
      ...a,
      openingBalance: a.openingBalance.toFixed(2),
      realBalance: real.toFixed(2),
      lockedAmount: lockedAmount.toFixed(2),
      balance: real.sub(lockedAmount).toFixed(2),
    };
  });

  return { items: rows };
}

/**
 * Money physically in a single account. Pass `excludeTxId` to compute the
 * balance as if a given transaction didn't exist (used when editing it).
 */
export async function accountBalance(
  userId: string,
  accountId: string,
  excludeTxId?: string,
): Promise<Prisma.Decimal> {
  const account = await prisma.account.findFirst({ where: { id: accountId, userId } });
  if (!account) throw new NotFoundError('Account not found');

  const exclude = excludeTxId ? { id: { not: excludeTxId } } : {};
  const zero = new Prisma.Decimal(0);
  const [sums, transfersIn] = await Promise.all([
    prisma.transaction.groupBy({
      by: ['kind'],
      where: { userId, accountId, ...exclude },
      _sum: { amount: true },
    }),
    prisma.transaction.groupBy({
      by: ['transferAccountId'],
      where: { userId, kind: TxKind.TRANSFER, transferAccountId: accountId, ...exclude },
      _sum: { amount: true },
    }),
  ]);

  let balance = new Prisma.Decimal(account.openingBalance);
  for (const s of sums) {
    const amt = s._sum.amount ?? zero;
    if (s.kind === TxKind.INCOME) balance = balance.add(amt);
    else balance = balance.sub(amt); // EXPENSE and TRANSFER both leave the source
  }
  for (const t of transfersIn) balance = balance.add(t._sum.amount ?? zero);
  return balance;
}

/**
 * Real balance minus whatever budget plans have reserved out of this account.
 * This is what an ordinary expense or a new plan fill-up may draw on.
 */
export async function availableBalance(
  userId: string,
  accountId: string,
  excludeTxId?: string,
): Promise<Prisma.Decimal> {
  const { lockedByAccount } = await import('../budgets/budgets.service.js');
  const [real, locked] = await Promise.all([
    accountBalance(userId, accountId, excludeTxId),
    lockedByAccount(userId),
  ]);
  return real.sub(locked.get(accountId) ?? new Prisma.Decimal(0));
}

/**
 * Total money genuinely free to spend in one currency: everything sitting in
 * unarchived accounts, minus whatever budget plans have reserved.
 */
export async function availableTotal(userId: string, currency: string): Promise<Prisma.Decimal> {
  const cur = currency.toUpperCase();
  const accounts = await prisma.account.findMany({
    where: { userId, currency: cur, archived: false },
    select: { id: true, openingBalance: true },
  });
  if (accounts.length === 0) return new Prisma.Decimal(0);

  const { lockedByAccount } = await import('../budgets/budgets.service.js');
  const zero = new Prisma.Decimal(0);
  const ids = accounts.map((a) => a.id);

  const [sums, transfersIn, locked] = await Promise.all([
    prisma.transaction.groupBy({
      by: ['accountId', 'kind'],
      where: { userId, accountId: { in: ids } },
      _sum: { amount: true },
    }),
    prisma.transaction.groupBy({
      by: ['transferAccountId'],
      where: { userId, kind: TxKind.TRANSFER, transferAccountId: { in: ids } },
      _sum: { amount: true },
    }),
    lockedByAccount(userId),
  ]);

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
    total = total.add(balance.sub(locked.get(a.id) ?? zero));
  }
  return total;
}

export async function create(user: AuthUser, input: CreateAccountInput) {
  if (input.isDefault) {
    await prisma.account.updateMany({ where: { userId: user.id }, data: { isDefault: false } });
  }
  return prisma.account.create({ data: { ...input, userId: user.id } });
}

export async function update(user: AuthUser, id: string, input: UpdateAccountInput) {
  await assertOwnedAccount(id, user.id);
  if (input.isDefault) {
    await prisma.account.updateMany({ where: { userId: user.id }, data: { isDefault: false } });
  }
  return prisma.account.update({ where: { id }, data: input });
}

export async function remove(user: AuthUser, id: string) {
  await assertOwnedAccount(id, user.id);
  const allocations = await prisma.budgetAllocation.count({ where: { accountId: id } });
  if (allocations > 0) {
    throw new ConflictError('This account has money set aside in budget plans. Give it back first.');
  }
  const txCount = await prisma.transaction.count({
    where: { OR: [{ accountId: id }, { transferAccountId: id }] },
  });
  if (txCount > 0) {
    throw new ConflictError('This account has transactions. Archive it instead of deleting.');
  }
  await prisma.account.delete({ where: { id } });
}
