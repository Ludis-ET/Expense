import { Prisma, TxKind } from '@prisma/client';
import { prisma } from '../../core/db.js';

const zero = new Prisma.Decimal(0);

/**
 * Compact, grounded snapshot of a user's finances — compact aggregates rather
 * than raw rows to keep prompt size (and token cost) low.
 */
export async function buildFinanceSnapshot(userId: string) {
  const now = new Date();
  const threeMonthsAgo = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 2, 1));

  const [user, accounts, categories, transactions, budgets, goals, payees] = await Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { name: true, currency: true } }),
    prisma.account.findMany({
      where: { userId, archived: false },
      select: { name: true, type: true, currency: true, openingBalance: true },
    }),
    prisma.category.findMany({
      where: { userId },
      select: { id: true, name: true, kind: true },
    }),
    prisma.transaction.findMany({
      where: { userId, date: { gte: threeMonthsAgo }, kind: { in: [TxKind.INCOME, TxKind.EXPENSE] } },
      select: { kind: true, amount: true, date: true, categoryId: true, payee: true },
    }),
    prisma.budget.findMany({
      where: { userId },
      select: { amount: true, alertThreshold: true, category: { select: { name: true } } },
    }),
    prisma.savingsGoal.findMany({
      where: { userId },
      select: {
        name: true,
        targetAmount: true,
        deadline: true,
        achievedAt: true,
        contributions: { select: { amount: true } },
      },
    }),
    prisma.transaction.groupBy({
      by: ['payee'],
      where: { userId, kind: TxKind.EXPENSE, payee: { not: null }, date: { gte: threeMonthsAgo } },
      _sum: { amount: true },
      orderBy: { _sum: { amount: 'desc' } },
      take: 10,
    }),
  ]);

  const categoryById = new Map(categories.map((c) => [c.id, c]));

  // Per-category totals per month: { '2026-06': { Transport: 1200, ... } }
  const monthly: Record<string, { income: number; expense: number; byCategory: Record<string, number> }> = {};
  for (const tx of transactions) {
    const month = tx.date.toISOString().slice(0, 7);
    monthly[month] ??= { income: 0, expense: 0, byCategory: {} };
    const amt = Number(tx.amount);
    if (tx.kind === TxKind.INCOME) monthly[month].income += amt;
    else {
      monthly[month].expense += amt;
      const name = tx.categoryId ? (categoryById.get(tx.categoryId)?.name ?? 'Other') : 'Other';
      monthly[month].byCategory[name] = (monthly[month].byCategory[name] ?? 0) + amt;
    }
  }

  // Current-month spend per category, to pair with budgets.
  const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const currentSpend: Record<string, number> = {};
  for (const tx of transactions) {
    if (tx.kind !== TxKind.EXPENSE || tx.date < monthStart || !tx.categoryId) continue;
    const name = categoryById.get(tx.categoryId)?.name ?? 'Other';
    currentSpend[name] = (currentSpend[name] ?? 0) + Number(tx.amount);
  }

  return {
    user: user?.name,
    defaultCurrency: user?.currency ?? 'ETB',
    today: now.toISOString().slice(0, 10),
    accounts: accounts.map((a) => ({ name: a.name, type: a.type, currency: a.currency })),
    categories: categories.map((c) => ({ name: c.name, kind: c.kind })),
    monthlyTotals: monthly,
    budgets: budgets.map((b) => ({
      category: b.category.name,
      monthlyLimit: Number(b.amount),
      spentThisMonth: Math.round((currentSpend[b.category.name] ?? 0) * 100) / 100,
      alertThresholdPct: b.alertThreshold,
    })),
    goals: goals.map((g) => ({
      name: g.name,
      target: Number(g.targetAmount),
      saved: Number(g.contributions.reduce((s, c) => s.add(c.amount), zero)),
      deadline: g.deadline?.toISOString().slice(0, 10) ?? null,
      achieved: Boolean(g.achievedAt),
    })),
    topPayees: payees.map((p) => ({ payee: p.payee, total: Number(p._sum.amount ?? zero) })),
  };
}

/** The user's category list in a form the categorizer prompt can choose from. */
export async function listUserCategories(userId: string) {
  return prisma.category.findMany({
    where: { userId, archived: false },
    select: { id: true, name: true, kind: true },
    orderBy: [{ kind: 'asc' }, { name: 'asc' }],
  });
}
