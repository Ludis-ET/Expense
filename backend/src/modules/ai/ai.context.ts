import { LedgerStatus, Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';

const zero = new Prisma.Decimal(0);

/**
 * Compact, grounded snapshot of a user's finances - compact aggregates rather
 * than raw rows to keep prompt size (and token cost) low.
 */
export async function buildFinanceSnapshot(userId: string) {
  const now = new Date();
  const threeMonthsAgo = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 2, 1));

  const [user, accounts, categories, transactions, budgets, goals, payees, tabEntries] = await Promise.all([
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
    prisma.ledgerEntry.findMany({
      where: { userId, status: LedgerStatus.OPEN },
      include: {
        payments: { select: { amount: true } },
        category: { select: { name: true } },
      },
      orderBy: [{ dueDate: 'asc' }, { createdAt: 'desc' }],
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

  const moneyTab = tabEntries.map((e) => {
    const paid = e.payments.reduce((s, p) => s.add(p.amount), zero);
    const remaining = e.totalAmount.sub(paid);
    return {
      kind: e.kind,
      counterparty: e.counterparty,
      title: e.title,
      total: Number(e.totalAmount),
      remaining: Number(remaining),
      dueDate: e.dueDate?.toISOString().slice(0, 10) ?? null,
      overdue: e.dueDate ? e.dueDate < now && remaining.gt(0) : false,
      category: e.category?.name ?? null,
    };
  });

  const tabOwedToUser = moneyTab
    .filter((e) => e.kind === 'LENT' || e.kind === 'EXPECTED_IN')
    .reduce((s, e) => s + e.remaining, 0);
  const tabUserOwes = moneyTab
    .filter((e) => e.kind === 'BORROWED' || e.kind === 'EXPECTED_OUT')
    .reduce((s, e) => s + e.remaining, 0);

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
    moneyTab: {
      summary: {
        owedToUser: Math.round(tabOwedToUser * 100) / 100,
        userOwes: Math.round(tabUserOwes * 100) / 100,
        net: Math.round((tabOwedToUser - tabUserOwes) * 100) / 100,
        openEntries: moneyTab.length,
      },
      openEntries: moneyTab,
      byPerson: Object.values(
        moneyTab.reduce<Record<string, { counterparty: string; netRemaining: number; entries: typeof moneyTab }>>(
          (acc, e) => {
            const key = e.counterparty.trim().toLowerCase();
            acc[key] ??= { counterparty: e.counterparty, netRemaining: 0, entries: [] };
            acc[key].entries.push(e);
            const sign = e.kind === 'LENT' || e.kind === 'EXPECTED_IN' ? 1 : -1;
            acc[key].netRemaining += e.remaining * sign;
            return acc;
          },
          {},
        ),
      ).map((g) => ({
        counterparty: g.counterparty,
        netRemaining: Math.round(g.netRemaining * 100) / 100,
        entries: g.entries.length,
      })),
    },
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
