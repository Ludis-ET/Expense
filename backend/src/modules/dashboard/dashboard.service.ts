import { CategoryKind } from '../../core/prisma.js';
import type { AuthUser } from '../../core/context.js';
import { prisma } from '../../core/db.js';
import * as accounts from '../accounts/accounts.service.js';
import * as analytics from '../analytics/analytics.service.js';
import * as budgets from '../budgets/budgets.service.js';
import { monthRange } from '../budgets/budgets.periods.js';
import { FAMILY_SUPPORT_CATEGORY_NAME } from '../categories/default-categories.js';
import * as household from '../household/household.service.js';
import * as ledger from '../ledger/ledger.service.js';
import * as wishlist from '../wishlist/wishlist.service.js';
import * as weeks from '../analytics/analytics.weeks.js';
import * as currency from '../../core/currency.service.js';

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
  const defaultCur = await currency.resolveCurrency(user.id);

  const [accountList, summary, budgetList, recent, topCategories, upcoming, weekly, streak, heatAlerts, family, householdData, tabSummary, wishlistDigest] =
    await Promise.all([
      accounts.list(user),
      analytics.summary(user, undefined, defaultCur),
      budgets.list(user, { currency: defaultCur }),
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
      analytics.byCategory(user, CategoryKind.EXPENSE, undefined, undefined, defaultCur),
      prisma.recurringRule.findMany({
        where: { userId: user.id, active: true, nextRun: { lte: in7Days } },
        orderBy: { nextRun: 'asc' },
        take: 5,
        include: { category: { select: { name: true, icon: true, color: true } } },
      }),
      weeks.weeklySnapshot(user, defaultCur),
      weeks.spendingStreak(user, defaultCur),
      categoryHeatAlerts(user),
      familySupport(user),
      household.overview(user),
      ledger.summary(user),
      wishlist.dashboard(user),
    ]);

  // Every balance below is the *available* figure: real money minus whatever
  // budget plans are holding.
  const totalBalance = accountList.items
    .filter((a) => !a.archived)
    .reduce((s, a) => s + Number(a.balance), 0);

  const currencies = await currency.listUserCurrencies(user.id);
  const currencyBreakdown = await Promise.all(
    currencies.map(async (cur) => {
      const accountsInCur = accountList.items.filter((a) => a.currency === cur && !a.archived);
      const bal = accountsInCur.reduce((s, a) => s + Number(a.balance), 0);
      const real = accountsInCur.reduce((s, a) => s + Number(a.realBalance), 0);
      const month = await analytics.summary(user, undefined, cur);
      return {
        currency: cur,
        totalBalance: bal.toFixed(2),
        realBalance: real.toFixed(2),
        budgetLocked: (real - bal).toFixed(2),
        accountCount: accountsInCur.length,
        month,
      };
    }),
  );

  const convertedTotal = await currency.convertedTotal(
    user,
    currencyBreakdown.map((b) => ({ currency: b.currency, amount: Number(b.totalBalance) })),
  );

  const primaryCurrency = currencies[0] ?? (await currency.resolveCurrency(user.id));
  const primaryBreakdown = currencyBreakdown.find((b) => b.currency === primaryCurrency) ?? currencyBreakdown[0];

  return {
    totalBalance: primaryBreakdown?.totalBalance ?? totalBalance.toFixed(2),
    realBalance: primaryBreakdown?.realBalance ?? totalBalance.toFixed(2),
    budgetLocked: primaryBreakdown?.budgetLocked ?? '0.00',
    displayCurrency: primaryBreakdown?.currency ?? primaryCurrency,
    currencies,
    currencyBreakdown,
    convertedTotal,
    accounts: accountList.items,
    month: primaryBreakdown?.month ?? summary,
    budgetTotals: budgetList.totals,
    /** Active plans nearest to running dry, plus anything already drained. */
    budgetsAtRisk: budgetList.items
      .filter((b) => b.state === 'ACTIVE' && (b.health === 'low' || b.health === 'drained'))
      .slice(0, 4),
    budgets: budgetList.items.filter((b) => b.state === 'ACTIVE').slice(0, 4),
    recentTransactions: recent.map((t) => ({ ...t, amount: t.amount.toFixed(2) })),
    topCategories: topCategories.items.slice(0, 5),
    upcomingRecurring: upcoming.map((r) => ({ ...r, amount: r.amount.toFixed(2) })),
    unnecessary: await analytics.unnecessary(user, undefined, defaultCur),
    weeklySnapshot: weekly,
    spendingStreak: streak,
    categoryHeatAlerts: heatAlerts,
    familySupport: family,
    household: householdData,
    tab: tabSummary,
    wishlist: wishlistDigest,
  };
}
