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
 * All accounts with computed balances:
 * opening + income − expense − transfers-out + transfers-in.
 */
export async function list(user: AuthUser) {
  const accounts = await prisma.account.findMany({
    where: { userId: user.id },
    orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
  });

  const [sums, transfersIn] = await Promise.all([
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
  ]);

  const zero = new Prisma.Decimal(0);
  const rows = accounts.map((a) => {
    let balance = new Prisma.Decimal(a.openingBalance);
    for (const s of sums) {
      if (s.accountId !== a.id) continue;
      const amt = s._sum.amount ?? zero;
      if (s.kind === TxKind.INCOME) balance = balance.add(amt);
      else balance = balance.sub(amt); // EXPENSE and TRANSFER both leave the source account
    }
    for (const t of transfersIn) {
      if (t.transferAccountId === a.id) balance = balance.add(t._sum.amount ?? zero);
    }
    return { ...a, openingBalance: a.openingBalance.toFixed(2), balance: balance.toFixed(2) };
  });

  return { items: rows };
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
  const txCount = await prisma.transaction.count({
    where: { OR: [{ accountId: id }, { transferAccountId: id }] },
  });
  if (txCount > 0) {
    throw new ConflictError('This account has transactions. Archive it instead of deleting.');
  }
  await prisma.account.delete({ where: { id } });
}
