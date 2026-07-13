import { CategoryKind, Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { notify } from '../notifications/notifications.service.js';
import type {
  CreateTransactionInput,
  ListTransactionsQuery,
  UpdateTransactionInput,
} from './transactions.schema.js';

const txInclude = {
  category: { select: { id: true, name: true, kind: true, icon: true, color: true } },
  account: { select: { id: true, name: true, type: true, currency: true } },
  transferAccount: { select: { id: true, name: true, type: true } },
} satisfies Prisma.TransactionInclude;

function serialize(tx: { amount: Prisma.Decimal } & Record<string, unknown>) {
  return { ...tx, amount: tx.amount.toFixed(2) };
}

async function assertOwnedTransaction(id: string, userId: string) {
  const tx = await prisma.transaction.findFirst({ where: { id, userId } });
  if (!tx) throw new NotFoundError('Transaction not found');
  return tx;
}

async function assertOwnedAccount(id: string, userId: string) {
  const account = await prisma.account.findFirst({ where: { id, userId } });
  if (!account) throw new NotFoundError('Account not found');
  return account;
}

/**
 * Money leaving an account (expense or transfer-out) may not overdraw it.
 * `excludeTxId` lets an edit ignore its own prior effect on the balance.
 */
async function assertSufficientBalance(
  userId: string,
  accountId: string,
  accountName: string,
  outflow: number,
  excludeTxId?: string,
) {
  const { accountBalance } = await import('../accounts/accounts.service.js');
  const available = await accountBalance(userId, accountId, excludeTxId);
  if (new Prisma.Decimal(outflow).gt(available)) {
    throw new BadRequestError(
      `Not enough balance in "${accountName}": available ${available.toFixed(2)}, needed ${outflow.toFixed(2)}. This would overdraw the account.`,
    );
  }
}

async function assertCategoryMatches(categoryId: string, userId: string, kind: TxKind) {
  const category = await prisma.category.findFirst({ where: { id: categoryId, userId } });
  if (!category) throw new NotFoundError('Category not found');
  const expected = kind === TxKind.INCOME ? CategoryKind.INCOME : CategoryKind.EXPENSE;
  if (category.kind !== expected) {
    throw new BadRequestError(`"${category.name}" is a ${category.kind.toLowerCase()} category`);
  }
  return category;
}

export async function list(user: AuthUser, query: ListTransactionsQuery) {
  const where: Prisma.TransactionWhereInput = {
    userId: user.id,
    ...(query.from || query.to
      ? { date: { ...(query.from ? { gte: query.from } : {}), ...(query.to ? { lte: query.to } : {}) } }
      : {}),
    ...(query.kind ? { kind: query.kind } : {}),
    ...(query.categoryId ? { categoryId: query.categoryId } : {}),
    ...(query.accountId
      ? { OR: [{ accountId: query.accountId }, { transferAccountId: query.accountId }] }
      : {}),
    ...(query.currency ? { currency: query.currency } : {}),
    ...(query.tag ? { tags: { has: query.tag } } : {}),
    ...(query.q
      ? {
          OR: [
            { note: { contains: query.q, mode: 'insensitive' } },
            { payee: { contains: query.q, mode: 'insensitive' } },
          ],
        }
      : {}),
    ...(query.min !== undefined || query.max !== undefined
      ? {
          amount: {
            ...(query.min !== undefined ? { gte: query.min } : {}),
            ...(query.max !== undefined ? { lte: query.max } : {}),
          },
        }
      : {}),
  };

  const orderBy: Prisma.TransactionOrderByWithRelationInput =
    query.sort === 'date_asc'
      ? { date: 'asc' }
      : query.sort === 'amount_desc'
        ? { amount: 'desc' }
        : query.sort === 'amount_asc'
          ? { amount: 'asc' }
          : { date: 'desc' };

  const [items, total] = await Promise.all([
    prisma.transaction.findMany({
      where,
      orderBy: [orderBy, { createdAt: 'desc' }],
      skip: (query.page - 1) * query.pageSize,
      take: query.pageSize,
      include: txInclude,
    }),
    prisma.transaction.count({ where }),
  ]);

  return { items: items.map(serialize), total, page: query.page, pageSize: query.pageSize };
}

export async function getById(user: AuthUser, id: string) {
  const tx = await prisma.transaction.findFirst({ where: { id, userId: user.id }, include: txInclude });
  if (!tx) throw new NotFoundError('Transaction not found');
  return serialize(tx);
}

/** Distinct tags across the user's transactions, for autocomplete. */
export async function listTags(user: AuthUser) {
  const rows = await prisma.transaction.findMany({
    where: { userId: user.id, tags: { isEmpty: false } },
    select: { tags: true },
    orderBy: { date: 'desc' },
    take: 500,
  });
  return { tags: [...new Set(rows.flatMap((r) => r.tags))].sort() };
}

export async function create(user: AuthUser, input: CreateTransactionInput) {
  const account = await assertOwnedAccount(input.accountId, user.id);

  let categoryId: string | null = null;
  if (input.kind === TxKind.TRANSFER) {
    await assertOwnedAccount(input.transferAccountId, user.id);
  } else {
    await assertCategoryMatches(input.categoryId, user.id, input.kind);
    categoryId = input.categoryId;
  }

  // Money leaving an account may not push it negative.
  if (input.kind === TxKind.EXPENSE || input.kind === TxKind.TRANSFER) {
    await assertSufficientBalance(user.id, account.id, account.name, input.amount);
  }

  if (input.kind === TxKind.EXPENSE) {
    const { assertExpenseAllowed } = await import('../spend-locks/spend-locks.service.js');
    await assertExpenseAllowed(user.id, input.currency, input.amount);
  }

  const tx = await prisma.transaction.create({
    data: {
      userId: user.id,
      kind: input.kind,
      amount: input.amount,
      currency: input.currency,
      date: input.date,
      accountId: input.accountId,
      transferAccountId: input.kind === TxKind.TRANSFER ? input.transferAccountId : null,
      categoryId,
      note: input.note,
      payee: input.payee,
      tags: input.tags,
      receiptUrl: input.receiptUrl,
    },
    include: txInclude,
  });

  if (tx.kind === TxKind.EXPENSE && tx.categoryId) {
    void checkBudgetAlert(user.id, tx.categoryId, tx.date);
  }
  return serialize(tx);
}

export async function update(user: AuthUser, id: string, input: UpdateTransactionInput) {
  const existing = await assertOwnedTransaction(id, user.id);

  if (input.accountId) await assertOwnedAccount(input.accountId, user.id);
  if (input.transferAccountId) {
    if (existing.kind !== TxKind.TRANSFER) {
      throw new BadRequestError('Only transfers have a destination account');
    }
    await assertOwnedAccount(input.transferAccountId, user.id);
    if ((input.accountId ?? existing.accountId) === input.transferAccountId) {
      throw new BadRequestError('Transfer destination must be a different account');
    }
  }
  if (input.categoryId) {
    if (existing.kind === TxKind.TRANSFER) {
      throw new BadRequestError('Transfers do not have a category');
    }
    await assertCategoryMatches(input.categoryId, user.id, existing.kind);
  }

  // Re-check the balance guard for outflows, ignoring this transaction's own
  // prior effect so an unchanged edit can't falsely trip.
  if (existing.kind === TxKind.EXPENSE || existing.kind === TxKind.TRANSFER) {
    const sourceId = input.accountId ?? existing.accountId;
    const outflow = Number(input.amount ?? existing.amount);
    const source = await assertOwnedAccount(sourceId, user.id);
    await assertSufficientBalance(user.id, sourceId, source.name, outflow, id);
  }

  const tx = await prisma.transaction.update({ where: { id }, data: input, include: txInclude });

  if (tx.kind === TxKind.EXPENSE && tx.categoryId) {
    void checkBudgetAlert(user.id, tx.categoryId, tx.date);
  }
  return serialize(tx);
}

export async function remove(user: AuthUser, id: string) {
  await assertOwnedTransaction(id, user.id);
  await prisma.transaction.delete({ where: { id } });
}

/**
 * After an expense is written, check whether its category's monthly budget
 * crossed the alert threshold (or 100%) and notify once per category/month
 * while an unread alert exists.
 */
async function checkBudgetAlert(userId: string, categoryId: string, date: Date) {
  try {
    const budget = await prisma.budget.findFirst({
      where: { categoryId, userId },
      include: { category: { select: { name: true } } },
    });
    if (!budget) return;

    const monthStart = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
    const monthEnd = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1));

    const spent = await prisma.transaction.aggregate({
      where: { userId, categoryId, kind: TxKind.EXPENSE, date: { gte: monthStart, lt: monthEnd } },
      _sum: { amount: true },
    });
    const spentAmt = spent._sum.amount ?? new Prisma.Decimal(0);
    const pct = new Prisma.Decimal(spentAmt).div(budget.amount).mul(100).toNumber();
    if (pct < budget.alertThreshold) return;

    const existing = await prisma.notification.findFirst({
      where: {
        userId,
        type: 'budget_alert',
        readFlag: false,
        message: { contains: budget.category.name },
        createdAt: { gte: monthStart },
      },
    });
    if (existing) return;

    const over = pct >= 100;
    await notify(
      userId,
      'budget_alert',
      over
        ? `You've exceeded your ${budget.category.name} budget this month (${Math.round(pct)}%).`
        : `You've used ${Math.round(pct)}% of your ${budget.category.name} budget this month.`,
      '/budgets',
    );
  } catch {
    // Alerts are best-effort; never fail the transaction write.
  }
}
