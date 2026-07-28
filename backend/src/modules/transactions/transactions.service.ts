import { CategoryKind, Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import type {
  CreateTransactionInput,
  ListTransactionsQuery,
  UpdateTransactionInput,
} from './transactions.schema.js';

const txInclude = {
  category: { select: { id: true, name: true, kind: true, icon: true, color: true } },
  account: { select: { id: true, name: true, type: true, currency: true } },
  transferAccount: { select: { id: true, name: true, type: true } },
  budget: { select: { id: true, name: true, icon: true, color: true, currency: true } },
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
 * Money leaving an account (expense or transfer-out) may not overdraw it, and
 * may not eat into what budget plans have already reserved.
 * `excludeTxId` lets an edit ignore its own prior effect on the balance.
 */
async function assertSufficientBalance(
  userId: string,
  accountId: string,
  accountName: string,
  outflow: number,
  excludeTxId?: string,
) {
  const { availableBalance } = await import('../accounts/accounts.service.js');
  const available = await availableBalance(userId, accountId, excludeTxId);
  if (new Prisma.Decimal(outflow).gt(available)) {
    throw new BadRequestError(
      `Not enough available balance in "${accountName}": ${available.toFixed(2)} free (after money set aside in budget plans), needed ${outflow.toFixed(2)}.`,
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
    ...(query.budgetId ? { budgetId: query.budgetId } : {}),
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
  const planId = input.kind === TxKind.EXPENSE ? input.budgetId : undefined;

  // Spending from a plan: the plan's pot must cover it, and it decides which
  // account the real money leaves from (the one that funded that share).
  let plan: { id: string; cycleIndex: number } | null = null;
  let accountId = input.accountId;
  if (planId) {
    const { assertSpendable } = await import('../budgets/budgets.service.js');
    const charge = await assertSpendable(user.id, planId, input.amount, input.accountId);
    plan = { id: charge.budget.id, cycleIndex: charge.budget.cycleIndex };
    accountId = charge.accountId;
  }

  if (!accountId) throw new BadRequestError('Pick an account or a budget plan to pay from');
  const account = await assertOwnedAccount(accountId, user.id);

  let categoryId: string | null = null;
  if (input.kind === TxKind.TRANSFER) {
    await assertOwnedAccount(input.transferAccountId, user.id);
  } else {
    await assertCategoryMatches(input.categoryId, user.id, input.kind);
    categoryId = input.categoryId;
  }

  // Money leaving an account may not push it negative. A plan expense is
  // already covered by its own reservation, so it only needs the real balance.
  if (input.kind === TxKind.TRANSFER || (input.kind === TxKind.EXPENSE && !plan)) {
    await assertSufficientBalance(user.id, account.id, account.name, input.amount);
  } else if (plan) {
    const { accountBalance } = await import('../accounts/accounts.service.js');
    const real = await accountBalance(user.id, account.id);
    if (new Prisma.Decimal(input.amount).gt(real)) {
      throw new BadRequestError(
        `"${account.name}" only holds ${real.toFixed(2)} ${account.currency} right now.`,
      );
    }
  }

  // Spend locks guard free money; plan money is already ring-fenced elsewhere.
  if (input.kind === TxKind.EXPENSE && !plan) {
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
      accountId: account.id,
      transferAccountId: input.kind === TxKind.TRANSFER ? input.transferAccountId : null,
      categoryId,
      budgetId: plan?.id ?? null,
      budgetCycle: plan?.cycleIndex ?? null,
      note: input.note,
      payee: input.payee,
      tags: input.tags,
      receiptUrl: input.receiptUrl,
    },
    include: txInclude,
  });

  if (tx.budgetId) {
    const { afterSpend } = await import('../budgets/budgets.service.js');
    void afterSpend(user.id, tx.budgetId);
  }
  return serialize(tx);
}

export async function update(user: AuthUser, id: string, input: UpdateTransactionInput) {
  const existing = await assertOwnedTransaction(id, user.id);

  if (input.accountId && existing.budgetId && input.accountId !== existing.accountId) {
    throw new BadRequestError(
      'This expense is paid from a budget plan; the plan decides which account it comes out of.',
    );
  }
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
    const outflow = Number(input.amount ?? existing.amount);
    if (existing.budgetId) {
      // Plan expenses are capped by the plan's pot, not by free account money.
      const { assertSpendable } = await import('../budgets/budgets.service.js');
      await assertSpendable(user.id, existing.budgetId, outflow, existing.accountId, id);
    } else {
      const sourceId = input.accountId ?? existing.accountId;
      const source = await assertOwnedAccount(sourceId, user.id);
      await assertSufficientBalance(user.id, sourceId, source.name, outflow, id);
    }
  }

  const tx = await prisma.transaction.update({ where: { id }, data: input, include: txInclude });

  if (tx.budgetId) {
    const { afterSpend } = await import('../budgets/budgets.service.js');
    void afterSpend(user.id, tx.budgetId);
  }
  return serialize(tx);
}

export async function remove(user: AuthUser, id: string) {
  const existing = await assertOwnedTransaction(id, user.id);
  await prisma.transaction.delete({ where: { id } });
  // Deleting a plan expense hands the money back to the pot.
  if (existing.budgetId) {
    const { afterSpend } = await import('../budgets/budgets.service.js');
    void afterSpend(user.id, existing.budgetId);
  }
}
