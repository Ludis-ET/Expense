import { CategoryKind, Prisma, TxKind } from '../../core/prisma.js';
import { prisma } from '../../core/db.js';
import type { AuthUser } from '../../core/context.js';
import { resolveCurrency } from '../../core/currency.service.js';
import { monthRange } from '../budgets/budgets.service.js';
import * as budgets from '../budgets/budgets.service.js';
import { UNNECESSARY_CATEGORY_NAME } from '../categories/default-categories.js';
import { bucketKey, enumerateBuckets, type Granularity } from './analytics.buckets.js';

const zero = new Prisma.Decimal(0);

async function getFirstDayOfWeek(userId: string): Promise<number> {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { firstDayOfWeek: true } });
  return user?.firstDayOfWeek ?? 1;
}

/** Month at a glance: income, expense, net, deltas vs the previous month (single currency only). */
export async function summary(user: AuthUser, month?: string, currency?: string) {
  const cur = await resolveCurrency(user.id, currency);
  const { start, end } = monthRange(month);
  const prevStart = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() - 1, 1));
  const currencyWhere = { currency: cur };

  const [current, previous, biggest] = await Promise.all([
    prisma.transaction.groupBy({
      by: ['kind'],
      where: { userId: user.id, ...currencyWhere, date: { gte: start, lt: end }, kind: { in: [TxKind.INCOME, TxKind.EXPENSE] } },
      _sum: { amount: true },
    }),
    prisma.transaction.groupBy({
      by: ['kind'],
      where: { userId: user.id, ...currencyWhere, date: { gte: prevStart, lt: start }, kind: { in: [TxKind.INCOME, TxKind.EXPENSE] } },
      _sum: { amount: true },
    }),
    prisma.transaction.findFirst({
      where: { userId: user.id, ...currencyWhere, kind: TxKind.EXPENSE, date: { gte: start, lt: end } },
      orderBy: { amount: 'desc' },
      include: { category: { select: { name: true, icon: true, color: true } } },
    }),
  ]);

  const pick = (rows: typeof current, kind: TxKind) =>
    rows.find((r) => r.kind === kind)?._sum.amount ?? zero;

  const income = pick(current, TxKind.INCOME);
  const expense = pick(current, TxKind.EXPENSE);
  const prevIncome = pick(previous, TxKind.INCOME);
  const prevExpense = pick(previous, TxKind.EXPENSE);

  const deltaPct = (now: Prisma.Decimal, before: Prisma.Decimal) =>
    before.gt(0) ? Number(now.sub(before).div(before).mul(100).toFixed(1)) : null;

  // Average daily spend over elapsed days (whole month if it's in the past).
  const now = new Date();
  const elapsedDays =
    now >= end
      ? (end.getTime() - start.getTime()) / 86_400_000
      : Math.max(1, Math.ceil((now.getTime() - start.getTime()) / 86_400_000));

  return {
    currency: cur,
    month: start.toISOString().slice(0, 7),
    income: income.toFixed(2),
    expense: expense.toFixed(2),
    net: income.sub(expense).toFixed(2),
    incomeDeltaPct: deltaPct(income, prevIncome),
    expenseDeltaPct: deltaPct(expense, prevExpense),
    avgDailySpend: expense.div(elapsedDays).toFixed(2),
    biggestExpense: biggest
      ? {
          id: biggest.id,
          amount: biggest.amount.toFixed(2),
          payee: biggest.payee,
          note: biggest.note,
          date: biggest.date,
          category: biggest.category,
        }
      : null,
  };
}

/** Income + expense per day/week/month bucket, gap-filled for charting (single currency). */
export async function series(user: AuthUser, granularity: Granularity, from?: Date, to?: Date, currency?: string) {
  const cur = await resolveCurrency(user.id, currency);
  const end = to ?? new Date();
  const defaultSpan = granularity === 'day' ? 30 : granularity === 'week' ? 7 * 12 : 365;
  const start = from ?? new Date(end.getTime() - defaultSpan * 86_400_000);
  const firstDayOfWeek = await getFirstDayOfWeek(user.id);

  const rows = await prisma.transaction.findMany({
    where: {
      userId: user.id,
      currency: cur,
      kind: { in: [TxKind.INCOME, TxKind.EXPENSE] },
      date: { gte: start, lte: end },
    },
    select: { kind: true, amount: true, date: true },
  });

  const buckets = new Map<string, { income: Prisma.Decimal; expense: Prisma.Decimal }>();
  for (const key of enumerateBuckets(start, end, granularity, firstDayOfWeek)) {
    buckets.set(key, { income: zero, expense: zero });
  }
  for (const row of rows) {
    const key = bucketKey(row.date, granularity, firstDayOfWeek);
    const bucket = buckets.get(key);
    if (!bucket) continue;
    if (row.kind === TxKind.INCOME) bucket.income = bucket.income.add(row.amount);
    else bucket.expense = bucket.expense.add(row.amount);
  }

  return {
    currency: cur,
    granularity,
    points: [...buckets.entries()].map(([key, v]) => ({
      bucket: key,
      income: v.income.toFixed(2),
      expense: v.expense.toFixed(2),
    })),
  };
}

/** Per-category totals within a range (donut/bar payload, single currency). */
export async function byCategory(user: AuthUser, kind: CategoryKind, from?: Date, to?: Date, currency?: string) {
  const cur = await resolveCurrency(user.id, currency);
  const end = to ?? new Date();
  const start = from ?? monthRange().start;
  const txKind = kind === CategoryKind.INCOME ? TxKind.INCOME : TxKind.EXPENSE;

  const grouped = await prisma.transaction.groupBy({
    by: ['categoryId'],
    where: { userId: user.id, currency: cur, kind: txKind, date: { gte: start, lte: end } },
    _sum: { amount: true },
    _count: true,
  });

  const categories = await prisma.category.findMany({
    where: { id: { in: grouped.map((g) => g.categoryId).filter((id): id is string => !!id) } },
    select: { id: true, name: true, icon: true, color: true },
  });
  const byId = new Map(categories.map((c) => [c.id, c]));

  const total = grouped.reduce((s, g) => s.add(g._sum.amount ?? zero), zero);
  const items = grouped
    .map((g) => {
      const amount = g._sum.amount ?? zero;
      return {
        category: g.categoryId ? (byId.get(g.categoryId) ?? null) : null,
        amount: amount.toFixed(2),
        count: g._count,
        pct: total.gt(0) ? Number(amount.div(total).mul(100).toFixed(1)) : 0,
      };
    })
    .sort((a, b) => Number(b.amount) - Number(a.amount));

  return { currency: cur, total: total.toFixed(2), items };
}

/** Monthly income/expense pairs + savings rate for the last N months (single currency). */
export async function incomeVsExpense(user: AuthUser, months: number, currency?: string) {
  const cur = await resolveCurrency(user.id, currency);
  const now = new Date();
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - (months - 1), 1));

  const rows = await prisma.transaction.findMany({
    where: { userId: user.id, currency: cur, kind: { in: [TxKind.INCOME, TxKind.EXPENSE] }, date: { gte: start } },
    select: { kind: true, amount: true, date: true },
  });

  const buckets = new Map<string, { income: Prisma.Decimal; expense: Prisma.Decimal }>();
  for (let i = 0; i < months; i++) {
    const d = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + i, 1));
    buckets.set(d.toISOString().slice(0, 7), { income: zero, expense: zero });
  }
  for (const row of rows) {
    const bucket = buckets.get(row.date.toISOString().slice(0, 7));
    if (!bucket) continue;
    if (row.kind === TxKind.INCOME) bucket.income = bucket.income.add(row.amount);
    else bucket.expense = bucket.expense.add(row.amount);
  }

  const points = [...buckets.entries()].map(([month, v]) => ({
    month,
    income: v.income.toFixed(2),
    expense: v.expense.toFixed(2),
    savingsRate: v.income.gt(0)
      ? Number(v.income.sub(v.expense).div(v.income).mul(100).toFixed(1))
      : null,
  }));

  return { currency: cur, points };
}

/** Daily spend totals for a calendar-heatmap year (single currency). */
export async function heatmap(user: AuthUser, year?: number, currency?: string) {
  const cur = await resolveCurrency(user.id, currency);
  const y = year ?? new Date().getUTCFullYear();
  const start = new Date(Date.UTC(y, 0, 1));
  const end = new Date(Date.UTC(y + 1, 0, 1));

  const rows = await prisma.transaction.findMany({
    where: { userId: user.id, currency: cur, kind: TxKind.EXPENSE, date: { gte: start, lt: end } },
    select: { amount: true, date: true },
  });

  const days = new Map<string, Prisma.Decimal>();
  for (const row of rows) {
    const key = row.date.toISOString().slice(0, 10);
    days.set(key, (days.get(key) ?? zero).add(row.amount));
  }

  return {
    currency: cur,
    year: y,
    days: [...days.entries()].map(([date, total]) => ({ date, total: total.toFixed(2) })),
  };
}

/** Top payees by total spend in a range (single currency). */
export async function topPayees(user: AuthUser, limit: number, from?: Date, to?: Date, currency?: string) {
  const cur = await resolveCurrency(user.id, currency);
  const end = to ?? new Date();
  const start = from ?? new Date(end.getTime() - 90 * 86_400_000);

  const grouped = await prisma.transaction.groupBy({
    by: ['payee'],
    where: {
      userId: user.id,
      currency: cur,
      kind: TxKind.EXPENSE,
      payee: { not: null },
      date: { gte: start, lte: end },
    },
    _sum: { amount: true },
    _count: true,
    orderBy: { _sum: { amount: 'desc' } },
    take: limit,
  });

  return {
    currency: cur,
    items: grouped.map((g) => ({
      payee: g.payee,
      total: (g._sum.amount ?? zero).toFixed(2),
      count: g._count,
    })),
  };
}

/** Spend in the "Unnecessary" category this month vs last (single currency). */
export async function unnecessary(user: AuthUser, month?: string, currency?: string) {
  const cur = await resolveCurrency(user.id, currency);
  const category = await prisma.category.findFirst({
    where: { userId: user.id, name: UNNECESSARY_CATEGORY_NAME, kind: CategoryKind.EXPENSE },
  });
  if (!category) return { currency: cur, category: null, total: '0.00', prevTotal: '0.00', deltaPct: null, count: 0 };

  const { start, end } = monthRange(month);
  const prevStart = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() - 1, 1));

  const [current, previous] = await Promise.all([
    prisma.transaction.aggregate({
      where: { userId: user.id, currency: cur, categoryId: category.id, date: { gte: start, lt: end } },
      _sum: { amount: true },
      _count: true,
    }),
    prisma.transaction.aggregate({
      where: { userId: user.id, currency: cur, categoryId: category.id, date: { gte: prevStart, lt: start } },
      _sum: { amount: true },
    }),
  ]);

  const total = current._sum.amount ?? zero;
  const prevTotal = previous._sum.amount ?? zero;

  return {
    currency: cur,
    category: { id: category.id, name: category.name, icon: category.icon, color: category.color },
    total: total.toFixed(2),
    prevTotal: prevTotal.toFixed(2),
    deltaPct: prevTotal.gt(0) ? Number(total.sub(prevTotal).div(prevTotal).mul(100).toFixed(1)) : null,
    count: current._count,
  };
}

/** Cumulative spend this month vs total budgeted (single currency). */
export async function burnRate(user: AuthUser, currency?: string) {
  const cur = await resolveCurrency(user.id, currency);
  const budgetList = await budgets.list(user);
  const { start, end } = monthRange();
  const rows = await prisma.transaction.findMany({
    where: { userId: user.id, currency: cur, kind: TxKind.EXPENSE, date: { gte: start, lt: end } },
    orderBy: { date: 'asc' },
    select: { amount: true, date: true },
  });
  let cumulative = 0;
  const points = rows.map((r) => {
    cumulative += Number(r.amount);
    return { date: r.date.toISOString().slice(0, 10), cumulative: cumulative.toFixed(2) };
  });
  return { currency: cur, points, totalPlanned: budgetList.totals.budgeted };
}
