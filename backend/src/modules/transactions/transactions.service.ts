/**
 * Transactions.
 *
 * Reading is this module's job; writing is not. Every mutation delegates to
 * `core/money/postings`, which holds the lock, applies the guards and proves the
 * books still balance afterwards. That is why deleting an income that a plan was
 * funded from now fails with an explanation instead of silently leaving the
 * wallet promising money it no longer has.
 */
import { Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import {
  deleteTransaction,
  patchTransaction,
  postTransaction,
} from '../../core/money/postings.js';
import { resolveBudgetId } from '../budgets/budgets.service.js';
import type {
  CreateTransactionInput,
  ListTransactionsQuery,
  UpdateTransactionInput,
} from './transactions.schema.js';

const txInclude = {
  category: { select: { id: true, name: true, kind: true, icon: true, color: true } },
  account: { select: { id: true, name: true, type: true, currency: true } },
  transferAccount: { select: { id: true, name: true, type: true, currency: true } },
  budget: { select: { id: true, name: true, icon: true, color: true, currency: true } },
  // Only differs from `account` when a plan was filled from one wallet and paid
  // from another - worth showing, because that wallet fronted the money.
  budgetSourceAccount: { select: { id: true, name: true, type: true } },
} satisfies Prisma.TransactionInclude;

type Serializable = {
  amount: Prisma.Decimal;
  transferAmount?: Prisma.Decimal | null;
  transferRate?: Prisma.Decimal | null;
  accountId?: string;
  budgetSourceAccountId?: string | null;
};

function serialize<T extends Serializable>(tx: T) {
  return {
    ...tx,
    amount: tx.amount.toFixed(2),
    transferAmount: tx.transferAmount ? tx.transferAmount.toFixed(2) : null,
    transferRate: tx.transferRate ? tx.transferRate.toString() : null,
    /**
     * True when the wallet that paid is not the wallet holding the plan's money.
     * The paying wallet fronted it; the plan's own wallet freed the reservation.
     * Surfacing this is the difference between an honest ledger and a confusing
     * one - the money really did move between wallets.
     */
    fronted:
      tx.budgetSourceAccountId != null &&
      tx.accountId != null &&
      tx.budgetSourceAccountId !== tx.accountId,
  };
}

async function assertOwnedTransaction(id: string, userId: string) {
  const tx = await prisma.transaction.findFirst({ where: { id, userId } });
  if (!tx) throw new NotFoundError('Transaction not found');
  return tx;
}

export async function list(user: AuthUser, query: ListTransactionsQuery) {
  // "unplanned" is a view, not a row: filtering by it means budgetId IS NULL.
  const budgetFilter =
    query.budgetId === undefined
      ? {}
      : resolveBudgetId(query.budgetId) === null
        ? { budgetId: null, kind: TxKind.EXPENSE }
        : { budgetId: resolveBudgetId(query.budgetId)! };

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
    ...budgetFilter,
    ...(query.budgetCycle !== undefined ? { budgetCycle: query.budgetCycle } : {}),
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
  const budgetId =
    input.kind === TxKind.EXPENSE ? resolveBudgetId(input.budgetId) : null;

  const created = await postTransaction(user.id, {
    kind: input.kind,
    amount: input.amount,
    currency: input.currency,
    date: input.date,
    accountId: input.accountId!,
    transferAccountId: input.kind === TxKind.TRANSFER ? input.transferAccountId : null,
    transferAmount: input.kind === TxKind.TRANSFER ? (input.transferAmount ?? null) : null,
    categoryId: input.kind === TxKind.TRANSFER ? null : input.categoryId,
    budgetId,
    budgetSourceAccountId:
      input.kind === TxKind.EXPENSE ? (input.budgetSourceAccountId ?? null) : null,
    cover: input.kind === TxKind.EXPENSE ? (input.cover ?? null) : null,
    note: input.note ?? null,
    payee: input.payee ?? null,
    tags: input.tags,
    receiptUrl: input.receiptUrl ?? null,
    clientOpId: input.clientOpId ?? null,
  });

  if (created.budgetId) {
    const { afterSpend } = await import('../budgets/budgets.service.js');
    await afterSpend(user.id, created.budgetId);
  }

  // Payday. Income landing is the moment plans are meant to be filled, and doing
  // it by hand every month is why plans go stale.
  let payday = null;
  if (created.kind === TxKind.INCOME) {
    try {
      const { onIncome } = await import('../funding/funding.service.js');
      const result = await onIncome(user.id, {
        accountId: created.accountId,
        amount: created.amount,
        currency: created.currency,
        kind: created.kind,
      });
      payday = result.suggestion ? { ...result.suggestion, ran: result.ran } : null;
    } catch {
      // A payday rule is a convenience. It must never fail the income itself.
    }
  }

  const full = await prisma.transaction.findUniqueOrThrow({
    where: { id: created.id },
    include: txInclude,
  });
  return { ...serialize(full), payday };
}

export async function update(user: AuthUser, id: string, input: UpdateTransactionInput) {
  await assertOwnedTransaction(id, user.id);

  const updated = await patchTransaction(user.id, id, {
    amount: input.amount,
    currency: input.currency,
    date: input.date,
    accountId: input.accountId,
    transferAccountId: input.transferAccountId,
    transferAmount: input.transferAmount,
    categoryId: input.categoryId,
    budgetSourceAccountId: input.budgetSourceAccountId,
    note: input.note,
    payee: input.payee,
    tags: input.tags,
    receiptUrl: input.receiptUrl,
  });

  if (updated.budgetId) {
    const { afterSpend } = await import('../budgets/budgets.service.js');
    await afterSpend(user.id, updated.budgetId);
  }

  const full = await prisma.transaction.findUniqueOrThrow({
    where: { id },
    include: txInclude,
  });
  return serialize(full);
}

export async function remove(user: AuthUser, id: string) {
  const { budgetId } = await deleteTransaction(user.id, id);
  if (budgetId) {
    const { afterSpend } = await import('../budgets/budgets.service.js');
    await afterSpend(user.id, budgetId);
  }
}
