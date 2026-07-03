import { CategoryKind, TxKind } from '../../core/prisma.js';
import type { AuthUser } from '../../core/context.js';
import { prisma } from '../../core/db.js';
import * as accounts from '../accounts/accounts.service.js';
import * as analytics from '../analytics/analytics.service.js';
import * as budgets from '../budgets/budgets.service.js';
import * as goals from '../goals/goals.service.js';
import { monthRange } from '../budgets/budgets.service.js';
import { FAMILY_SUPPORT_CATEGORY_NAME } from '../categories/default-categories.js';
import * as household from '../household/household.service.js';

function weekBounds(firstDayOfWeek: number) {
  const now = new Date();
  const day = now.getDay();
  const diff = (day - firstDayOfWeek + 7) % 7;
  const weekStart = new Date(now);
  weekStart.setHours(0, 0, 0, 0);
  weekStart.setDate(weekStart.getDate() - diff);
  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekEnd.getDate() + 7);
  const prevStart = new Date(weekStart);
  prevStart.setDate(prevStart.getDate() - 7);
  return { weekStart, weekEnd, prevStart };
}

async function sumRange(userId: string, start: Date, end: Date) {
  const rows = await prisma.transaction.groupBy({
    by: ['kind'],
    where: { userId, date: { gte: start, lt: end }, kind: { in: [TxKind.INCOME, TxKind.EXPENSE] } },
    _sum: { amount: true },
  });
  const income = Number(rows.find((r) => r.kind === TxKind.INCOME)?._sum.amount ?? 0);
  const expense = Number(rows.find((r) => r.kind === TxKind.EXPENSE)?._sum.amount ?? 0);
  return { income, expense, net: income - expense };
}

async function weeklySnapshot(user: AuthUser) {
  const u = await prisma.user.findUnique({ where: { id: user.id }, select: { firstDayOfWeek: true } });
  const { weekStart, weekEnd, prevStart } = weekBounds(u?.firstDayOfWeek ?? 1);
  const [current, previous] = await Promise.all([
    sumRange(user.id, weekStart, weekEnd),
    sumRange(user.id, prevStart, weekStart),
  ]);
  const delta = (now: number, before: number) =>
    before > 0 ? Number((((now - before) / before) * 100).toFixed(1)) : null;

  return {
    weekStart: weekStart.toISOString().slice(0, 10),
    income: current.income.toFixed(2),
    expense: current.expense.toFixed(2),
    net: current.net.toFixed(2),
    prevIncome: previous.income.toFixed(2),
    prevExpense: previous.expense.toFixed(2),
    incomeDeltaPct: delta(current.income, previous.income),
    expenseDeltaPct: delta(current.expense, previous.expense),
  };
}

async function spendingStreak(user: AuthUser) {
  const summary = await analytics.summary(user);
  const avgDaily = Number(summary.avgDailySpend) || 0;
  const maxDays = 60;
  const start = new Date();
  start.setDate(start.getDate() - maxDays);
  start.setHours(0, 0, 0, 0);

  const rows = await prisma.transaction.findMany({
    where: { userId: user.id, kind: TxKind.EXPENSE, date: { gte: start } },
    select: { amount: true, date: true },
  });

  const byDay = new Map<string, number>();
  for (const r of rows) {
    const key = r.date.toISOString().slice(0, 10);
    byDay.set(key, (byDay.get(key) ?? 0) + Number(r.amount));
  }

  let streak = 0;
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  for (let i = 0; i < maxDays; i++) {
    const d = new Date(today);
    d.setDate(d.getDate() - i);
    const key = d.toISOString().slice(0, 10);
    const spent = byDay.get(key) ?? 0;
    if (avgDaily > 0 && spent <= avgDaily * 1.05) streak++;
    else if (avgDaily === 0 && spent === 0) streak++;
    else break;
  }

  const bestStreak = Math.max(streak, streak > 0 ? streak : 0);
  return {
    currentDays: streak,
    label: streak >= 7 ? 'On fire!' : streak >= 3 ? 'Building momentum' : streak > 0 ? 'Keep going' : 'Start today',
    avgDailyLimit: avgDaily.toFixed(2),
    bestStreak,
  };
}

async function categoryHeatAlerts(user: AuthUser) {
  const { start, end } = monthRange();
  const prevStart = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() - 1, 1));

  const [current, previous] = await Promise.all([
    analytics.byCategory(user, CategoryKind.EXPENSE, start, end),
    analytics.byCategory(user, CategoryKind.EXPENSE, prevStart, start),
  ]);

  const prevMap = new Map(previous.items.map((i) => [i.category?.id ?? '', Number(i.amount)]));

  const alerts = current.items
    .filter((i) => i.category)
    .map((i) => {
      const now = Number(i.amount);
      const before = prevMap.get(i.category!.id) ?? 0;
      const deltaPct = before > 0 ? Number((((now - before) / before) * 100).toFixed(1)) : now > 0 ? 100 : 0;
      return {
        category: i.category,
        amount: i.amount,
        prevAmount: before.toFixed(2),
        deltaPct,
        severity: deltaPct >= 50 ? 'high' as const : deltaPct >= 25 ? 'medium' as const : 'low' as const,
      };
    })
    .filter((a) => a.deltaPct >= 20 && Number(a.amount) > 0)
    .sort((a, b) => b.deltaPct - a.deltaPct)
    .slice(0, 6);

  return alerts;
}

async function familySupport(user: AuthUser) {
  const category = await prisma.category.findFirst({
    where: { userId: user.id, name: FAMILY_SUPPORT_CATEGORY_NAME, kind: CategoryKind.EXPENSE },
  });
  if (!category) {
    return { category: null, total: '0.00', prevTotal: '0.00', deltaPct: null, count: 0, recent: [] };
  }

  const { start, end } = monthRange();
  const prevStart = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() - 1, 1));

  const [current, previous, recent] = await Promise.all([
    prisma.transaction.aggregate({
      where: { userId: user.id, categoryId: category.id, date: { gte: start, lt: end } },
      _sum: { amount: true },
      _count: true,
    }),
    prisma.transaction.aggregate({
      where: { userId: user.id, categoryId: category.id, date: { gte: prevStart, lt: start } },
      _sum: { amount: true },
    }),
    prisma.transaction.findMany({
      where: { userId: user.id, categoryId: category.id },
      orderBy: { date: 'desc' },
      take: 5,
      select: { id: true, amount: true, date: true, payee: true, note: true },
    }),
  ]);

  const total = Number(current._sum.amount ?? 0);
  const prevTotal = Number(previous._sum.amount ?? 0);

  return {
    category: { id: category.id, name: category.name, icon: category.icon, color: category.color },
    total: total.toFixed(2),
    prevTotal: prevTotal.toFixed(2),
    deltaPct: prevTotal > 0 ? Number((((total - prevTotal) / prevTotal) * 100).toFixed(1)) : null,
    count: current._count,
    recent: recent.map((t) => ({
      id: t.id,
      amount: t.amount.toFixed(2),
      date: t.date,
      payee: t.payee,
      note: t.note,
    })),
  };
}

/** Everything the dashboard needs in one round trip. */
export async function overview(user: AuthUser) {
  const in7Days = new Date(Date.now() + 7 * 86_400_000);

  const [accountList, summary, budgetList, goalList, recent, topCategories, upcoming, weekly, streak, heatAlerts, family, householdData] =
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
      weeklySnapshot(user),
      spendingStreak(user),
      categoryHeatAlerts(user),
      familySupport(user),
      household.overview(user),
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
    weeklySnapshot: weekly,
    spendingStreak: streak,
    categoryHeatAlerts: heatAlerts,
    familySupport: family,
    household: householdData,
  };
}
