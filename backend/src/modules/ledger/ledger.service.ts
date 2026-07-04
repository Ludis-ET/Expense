import {
  CategoryKind,
  LedgerKind,
  LedgerStatus,
  Prisma,
  TxKind,
} from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import { BadRequestError, NotFoundError } from '../../core/errors.js';
import type { AuthUser } from '../../core/context.js';
import { notify } from '../notifications/notifications.service.js';
import type {
  CreateLedgerInput,
  ListLedgerQuery,
  RecordPaymentInput,
  UpdateLedgerInput,
} from './ledger.schema.js';

const zero = new Prisma.Decimal(0);

const entryInclude = {
  category: { select: { id: true, name: true, icon: true, color: true, kind: true } },
  payments: { orderBy: { date: 'desc' as const } },
} satisfies Prisma.LedgerEntryInclude;

type EntryWithPayments = Prisma.LedgerEntryGetPayload<{ include: typeof entryInclude }>;

function paidAmount(entry: EntryWithPayments) {
  return entry.payments.reduce((s, p) => s.add(p.amount), zero);
}

function serializeEntry(entry: EntryWithPayments) {
  const paid = paidAmount(entry);
  const remaining = Prisma.Decimal.max(zero, entry.totalAmount.sub(paid));
  const pct = entry.totalAmount.gt(0)
    ? Number(paid.div(entry.totalAmount).mul(100).toFixed(1))
    : 0;
  const now = new Date();
  const isOverdue =
    entry.status === LedgerStatus.OPEN &&
    !!entry.dueDate &&
    entry.dueDate < now &&
    remaining.gt(0);

  return {
    id: entry.id,
    kind: entry.kind,
    counterparty: entry.counterparty,
    title: entry.title,
    totalAmount: entry.totalAmount.toFixed(2),
    paid: paid.toFixed(2),
    remaining: remaining.toFixed(2),
    pct: Math.min(100, pct),
    currency: entry.currency,
    dueDate: entry.dueDate,
    note: entry.note,
    status: entry.status,
    settledAt: entry.settledAt,
    isOverdue,
    category: entry.category,
    payments: entry.payments.map((p) => ({
      id: p.id,
      amount: p.amount.toFixed(2),
      date: p.date,
      note: p.note,
      transactionId: p.transactionId,
    })),
    createdAt: entry.createdAt,
    updatedAt: entry.updatedAt,
  };
}

async function assertOwnedEntry(id: string, userId: string) {
  const entry = await prisma.ledgerEntry.findFirst({ where: { id, userId }, include: entryInclude });
  if (!entry) throw new NotFoundError('Tab entry not found');
  return entry;
}

async function assertOwnedAccount(id: string, userId: string) {
  const account = await prisma.account.findFirst({ where: { id, userId, archived: false } });
  if (!account) throw new NotFoundError('Account not found');
  return account;
}

async function resolveCategory(
  userId: string,
  categoryId: string | undefined,
  kind: LedgerKind,
  txKind: TxKind,
) {
  if (categoryId) {
    const category = await prisma.category.findFirst({ where: { id: categoryId, userId } });
    if (!category) throw new NotFoundError('Category not found');
    const expected = txKind === TxKind.INCOME ? CategoryKind.INCOME : CategoryKind.EXPENSE;
    if (category.kind !== expected) {
      throw new BadRequestError(`Category must be ${expected.toLowerCase()}`);
    }
    return category.id;
  }

  const fallbackName =
    kind === LedgerKind.EXPECTED_IN
      ? 'Freelance'
      : txKind === TxKind.INCOME
        ? 'Loan Repayment'
        : 'Debt & Loans';

  const category = await prisma.category.findFirst({
    where: { userId, name: fallbackName, kind: txKind === TxKind.INCOME ? CategoryKind.INCOME : CategoryKind.EXPENSE },
  });
  if (!category) throw new BadRequestError('Pick a category for this movement');
  return category.id;
}

async function createLinkedTransaction(
  user: AuthUser,
  entry: EntryWithPayments,
  input: { amount: Prisma.Decimal; date: Date; accountId: string; categoryId?: string; note?: string },
) {
  const txKind =
    entry.kind === LedgerKind.BORROWED ? TxKind.EXPENSE : TxKind.INCOME;
  const categoryId = await resolveCategory(user.id, input.categoryId ?? entry.categoryId ?? undefined, entry.kind, txKind);

  const label = entry.title?.trim() || entry.counterparty;
  const tx = await prisma.transaction.create({
    data: {
      userId: user.id,
      kind: txKind,
      amount: input.amount,
      currency: entry.currency,
      date: input.date,
      accountId: input.accountId,
      categoryId,
      payee: entry.counterparty,
      note: input.note ?? `${entry.kind === LedgerKind.EXPECTED_IN ? 'Received' : 'Settlement'}: ${label}`,
      tags: ['tab'],
    },
  });
  return tx.id;
}

async function maybeSettle(entryId: string, totalAmount: Prisma.Decimal, paid: Prisma.Decimal) {
  if (paid.gte(totalAmount)) {
    await prisma.ledgerEntry.update({
      where: { id: entryId },
      data: { status: LedgerStatus.SETTLED, settledAt: new Date() },
    });
  }
}

export async function list(user: AuthUser, query: ListLedgerQuery) {
  const where: Prisma.LedgerEntryWhereInput = {
    userId: user.id,
    ...(query.kind ? { kind: query.kind } : {}),
    ...(query.status === 'open'
      ? { status: LedgerStatus.OPEN }
      : query.status === 'settled'
        ? { status: LedgerStatus.SETTLED }
        : {}),
  };

  const entries = await prisma.ledgerEntry.findMany({
    where,
    orderBy: [{ status: 'asc' }, { dueDate: 'asc' }, { createdAt: 'desc' }],
    include: entryInclude,
  });

  return { items: entries.map(serializeEntry) };
}

export async function summary(user: AuthUser) {
  const entries = await prisma.ledgerEntry.findMany({
    where: { userId: user.id, status: LedgerStatus.OPEN },
    include: entryInclude,
    orderBy: [{ dueDate: 'asc' }, { createdAt: 'desc' }],
  });

  const serialized = entries.map(serializeEntry);
  const sumRemaining = (kinds: LedgerKind[]) =>
    serialized
      .filter((e) => kinds.includes(e.kind as LedgerKind))
      .reduce((s, e) => s + Number(e.remaining), 0);

  const receivable = sumRemaining([LedgerKind.LENT]);
  const payable = sumRemaining([LedgerKind.BORROWED]);
  const expectedIn = sumRemaining([LedgerKind.EXPECTED_IN]);
  const overdue = serialized.filter((e) => e.isOverdue);
  const dueSoon = serialized.filter((e) => {
    if (!e.dueDate || e.isOverdue) return false;
    const days = (new Date(e.dueDate).getTime() - Date.now()) / 86_400_000;
    return days >= 0 && days <= 14;
  });

  return {
    receivable: receivable.toFixed(2),
    payable: payable.toFixed(2),
    expectedIn: expectedIn.toFixed(2),
    netPosition: (receivable + expectedIn - payable).toFixed(2),
    openCount: serialized.length,
    overdueCount: overdue.length,
    highlights: serialized.slice(0, 5),
    overdue: overdue.slice(0, 3),
    dueSoon: dueSoon.slice(0, 3),
  };
}

export async function create(user: AuthUser, input: CreateLedgerInput) {
  if (input.kind === LedgerKind.EXPECTED_IN && input.recordMovement) {
    throw new BadRequestError('Expected income is recorded when you receive it, not when you create the entry');
  }

  if (input.recordMovement && !input.sourceAccountId) {
    throw new BadRequestError('Pick an account to record the initial movement');
  }

  if (input.categoryId) {
    if (input.kind !== LedgerKind.EXPECTED_IN) {
      throw new BadRequestError('Category applies to expected income entries only');
    }
    const cat = await prisma.category.findFirst({ where: { id: input.categoryId, userId: user.id } });
    if (!cat || cat.kind !== CategoryKind.INCOME) {
      throw new BadRequestError('Expected income entries need an income category');
    }
  }

  const entry = await prisma.ledgerEntry.create({
    data: {
      userId: user.id,
      kind: input.kind,
      counterparty: input.counterparty.trim(),
      title: input.title?.trim() || null,
      totalAmount: input.totalAmount,
      dueDate: input.dueDate,
      note: input.note,
      categoryId: input.categoryId,
    },
    include: entryInclude,
  });

  if (input.recordMovement && input.sourceAccountId) {
    await assertOwnedAccount(input.sourceAccountId, user.id);
    const txKind = input.kind === LedgerKind.BORROWED ? TxKind.INCOME : TxKind.EXPENSE;
    await createLinkedTransaction(user, entry, {
      amount: new Prisma.Decimal(input.totalAmount),
      date: new Date(),
      accountId: input.sourceAccountId,
      categoryId: input.categoryId,
      note: input.kind === LedgerKind.LENT ? `Lent to ${entry.counterparty}` : `Borrowed from ${entry.counterparty}`,
    });
  }

  const fresh = await prisma.ledgerEntry.findUniqueOrThrow({ where: { id: entry.id }, include: entryInclude });
  return serializeEntry(fresh);
}

export async function update(user: AuthUser, id: string, input: UpdateLedgerInput) {
  const existing = await assertOwnedEntry(id, user.id);
  if (existing.status === LedgerStatus.SETTLED) {
    throw new BadRequestError('Settled entries cannot be edited');
  }

  if (input.categoryId) {
    const cat = await prisma.category.findFirst({ where: { id: input.categoryId, userId: user.id } });
    if (!cat || cat.kind !== CategoryKind.INCOME) {
      throw new BadRequestError('Tab income entries use income categories only');
    }
  }

  const paid = paidAmount(existing);
  if (input.totalAmount !== undefined && new Prisma.Decimal(input.totalAmount).lt(paid)) {
    throw new BadRequestError('Total cannot be less than what is already recorded');
  }

  const entry = await prisma.ledgerEntry.update({
    where: { id },
    data: {
      counterparty: input.counterparty?.trim(),
      title: input.title === null ? null : input.title?.trim(),
      totalAmount: input.totalAmount,
      dueDate: input.dueDate === null ? null : input.dueDate,
      note: input.note === null ? null : input.note,
      categoryId: input.categoryId === null ? null : input.categoryId,
    },
    include: entryInclude,
  });

  return serializeEntry(entry);
}

export async function cancel(user: AuthUser, id: string) {
  const entry = await assertOwnedEntry(id, user.id);
  if (entry.status === LedgerStatus.SETTLED) {
    throw new BadRequestError('Already settled');
  }
  await prisma.ledgerEntry.update({
    where: { id },
    data: { status: LedgerStatus.CANCELLED },
  });
}

export async function remove(user: AuthUser, id: string) {
  await assertOwnedEntry(id, user.id);
  await prisma.ledgerEntry.delete({ where: { id } });
}

export async function recordPayment(user: AuthUser, id: string, input: RecordPaymentInput) {
  const entry = await assertOwnedEntry(id, user.id);
  if (entry.status !== LedgerStatus.OPEN) {
    throw new BadRequestError('Only open entries accept payments');
  }

  const paid = paidAmount(entry);
  const remaining = entry.totalAmount.sub(paid);
  const amount = new Prisma.Decimal(input.amount);

  if (amount.gt(remaining)) {
    throw new BadRequestError(`Amount exceeds remaining ${remaining.toFixed(2)}`);
  }

  const shouldRecord =
    input.recordTransaction !== false && !!input.accountId;

  let transactionId: string | null = null;
  if (shouldRecord && input.accountId) {
    await assertOwnedAccount(input.accountId, user.id);
    transactionId = await createLinkedTransaction(user, entry, {
      amount,
      date: input.date ?? new Date(),
      accountId: input.accountId,
      categoryId: input.categoryId,
      note: input.note,
    });
  }

  await prisma.ledgerPayment.create({
    data: {
      ledgerEntryId: id,
      amount,
      date: input.date ?? new Date(),
      note: input.note,
      transactionId,
    },
  });

  const newPaid = paid.add(amount);
  await maybeSettle(id, entry.totalAmount, newPaid);

  if (newPaid.gte(entry.totalAmount)) {
    const label = entry.title?.trim() || entry.counterparty;
    await notify(
      user.id,
      'tab_settled',
      entry.kind === LedgerKind.EXPECTED_IN
        ? `💰 Received expected payment from ${entry.counterparty} (${label}).`
        : entry.kind === LedgerKind.LENT
          ? `✅ ${entry.counterparty} settled what they owed you.`
          : `✅ You finished paying back ${entry.counterparty}.`,
      '/tab',
    );
  }

  const updated = await prisma.ledgerEntry.findUniqueOrThrow({ where: { id }, include: entryInclude });
  return serializeEntry(updated);
}
