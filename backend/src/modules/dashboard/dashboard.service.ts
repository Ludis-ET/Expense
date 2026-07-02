import { CategoryKind, TxKind } from '@prisma/client';
import type { AuthUser } from '../../core/context.js';
import { prisma } from '../../core/db.js';
import * as accounts from '../accounts/accounts.service.js';
import * as analytics from '../analytics/analytics.service.js';
import * as budgets from '../budgets/budgets.service.js';
import * as goals from '../goals/goals.service.js';

/** Everything the dashboard needs in one round trip. */
export async function overview(user: AuthUser) {
  const in7Days = new Date(Date.now() + 7 * 86_400_000);

  const [accountList, summary, budgetList, goalList, recent, topCategories, upcoming] =
    await Promise.all([
      accounts.list(user),
      analytics.summary(user),
      budgets.list(user),
      goals.list(user),
      prisma.transaction.findMany({
        where: { userId: user.id },
        orderBy: [{ date: 'desc' }, { createdAt: 'desc' }],
        take: 8,
        include: {
          category: { select: { id: true, name: true, icon: true, color: true } },
          account: { select: { id: true, name: true } },
          transferAccount: { select: { id: true, name: true } },
        },
      }),
      analytics.byCategory(user, CategoryKind.EXPENSE),
      prisma.recurringRule.findMany({
        where: { userId: user.id, active: true, nextRun: { lte: in7Days } },
        orderBy: { nextRun: 'asc' },
        take: 5,
        include: { category: { select: { name: true, icon: true, color: true } } },
      }),
    ]);

  const totalBalance = accountList.items
    .filter((a) => !a.archived)
    .reduce((s, a) => s + Number(a.balance), 0);

  return {
    totalBalance: totalBalance.toFixed(2),
    accounts: accountList.items,
    month: summary,
    budgetsAtRisk: budgetList.items.filter((b) => b.status !== 'ok').slice(0, 4),
    goals: goalList.items.slice(0, 3),
    recentTransactions: recent.map((t) => ({ ...t, amount: t.amount.toFixed(2) })),
    topCategories: topCategories.items.slice(0, 5),
    upcomingRecurring: upcoming.map((r) => ({ ...r, amount: r.amount.toFixed(2) })),
    unnecessary: await analytics.unnecessary(user),
  };
}
