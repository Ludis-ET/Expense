'use client';

import { useState } from 'react';
import useSWR from 'swr';
import { Flame, TrendingUp } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { PageHeader, Skeleton, EmptyState } from '@/components/ui/misc';
import { Donut } from '@/components/charts/donut';
import { BarChart } from '@/components/charts/bar';
import { IncomeExpenseLine } from '@/components/charts/line';
import { SpendHeatmap } from '@/components/charts/heatmap';
import { CategoryBadge } from '@/components/finance/category-badge';
import { formatMoney, formatMonth } from '@/lib/format';
import { useAuth } from '@/lib/auth';
import type { CategoryBreakdownItem, SeriesPoint, UnnecessaryStats } from '@/lib/types';

type Granularity = 'day' | 'week' | 'month';

interface SeriesResp { granularity: Granularity; points: SeriesPoint[] }
interface CategoriesResp { total: string; items: CategoryBreakdownItem[] }
interface IncomeVsExpenseResp {
  points: { month: string; income: string; expense: string; savingsRate: number | null }[];
}
interface HeatmapResp { year: number; days: { date: string; total: string }[] }
interface PayeesResp { items: { payee: string | null; total: string; count: number }[] }

export default function AnalyticsPage() {
  const { user } = useAuth();
  const currency = user?.currency ?? 'ETB';
  const money = (v: number | string) => formatMoney(v, currency);
  const year = new Date().getFullYear();

  const [granularity, setGranularity] = useState<Granularity>('day');

  const { data: series } = useSWR<SeriesResp>(`/analytics/series?granularity=${granularity}`);
  const { data: categories } = useSWR<CategoriesResp>('/analytics/categories?kind=EXPENSE');
  const { data: ive } = useSWR<IncomeVsExpenseResp>('/analytics/income-vs-expense?months=12');
  const { data: heat } = useSWR<HeatmapResp>(`/analytics/heatmap?year=${year}`);
  const { data: payees } = useSWR<PayeesResp>('/analytics/payees?limit=8');
  const { data: unnecessary } = useSWR<UnnecessaryStats>('/analytics/unnecessary');

  const linePoints = (series?.points ?? []).map((p) => ({
    label: granularity === 'month' ? p.bucket.slice(5) : p.bucket.slice(5),
    income: Number(p.income),
    expense: Number(p.expense),
  }));

  const iveLine = (ive?.points ?? []).map((p) => ({
    label: p.month.slice(5),
    income: Number(p.income),
    expense: Number(p.expense),
  }));

  const avgSavings =
    ive && ive.points.length > 0
      ? Math.round(
          ive.points.filter((p) => p.savingsRate !== null).reduce((s, p) => s + (p.savingsRate ?? 0), 0) /
            Math.max(1, ive.points.filter((p) => p.savingsRate !== null).length),
        )
      : null;

  const donutData = (categories?.items ?? [])
    .filter((c) => c.category)
    .slice(0, 8)
    .map((c) => ({ label: c.category!.name, value: Number(c.amount), color: c.category!.color }));

  return (
    <div>
      <PageHeader title="Analytics" description="Trends, breakdowns, and where your money really goes." />

      <Card className="mb-6">
        <CardHeader>
          <CardTitle>Income vs. expense</CardTitle>
          <div className="flex gap-1 rounded-lg border border-border p-0.5">
            {(['day', 'week', 'month'] as Granularity[]).map((g) => (
              <button
                key={g}
                onClick={() => setGranularity(g)}
                className={
                  'rounded-md px-3 py-1 text-xs font-medium capitalize transition-colors ' +
                  (granularity === g ? 'bg-primary text-primary-foreground' : 'text-muted hover:bg-surface-muted')
                }
              >
                {g}
              </button>
            ))}
          </div>
        </CardHeader>
        <CardContent>
          {!series ? <Skeleton className="h-56" /> : <IncomeExpenseLine points={linePoints} format={(v) => money(v)} />}
        </CardContent>
      </Card>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Spending by category</CardTitle>
          </CardHeader>
          <CardContent>
            {!categories ? (
              <Skeleton className="h-52" />
            ) : donutData.length === 0 ? (
              <EmptyState title="No spending this period" />
            ) : (
              <Donut data={donutData} format={(v) => money(v)} centerLabel="spent" />
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Top payees</CardTitle>
          </CardHeader>
          <CardContent>
            {!payees ? (
              <Skeleton className="h-52" />
            ) : payees.items.length === 0 ? (
              <EmptyState title="No payees yet" />
            ) : (
              <ul className="space-y-2.5">
                {payees.items.map((p) => (
                  <li key={p.payee} className="flex items-center justify-between text-sm">
                    <span className="truncate">{p.payee}</span>
                    <span className="tabular-nums text-muted">
                      {money(p.total)} <span className="text-xs">· {p.count}×</span>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Monthly income vs. expense (12 mo)</CardTitle>
            {avgSavings !== null && (
              <span className="inline-flex items-center gap-1 text-sm text-emerald-600 dark:text-emerald-400">
                <TrendingUp className="h-4 w-4" /> {avgSavings}% avg savings rate
              </span>
            )}
          </CardHeader>
          <CardContent>
            {!ive ? <Skeleton className="h-52" /> : <IncomeExpenseLine points={iveLine} format={(v) => money(v)} />}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Flame className="h-4 w-4 text-orange-500" /> Unnecessary spend
            </CardTitle>
          </CardHeader>
          <CardContent>
            {!unnecessary ? (
              <Skeleton className="h-40" />
            ) : (
              <div>
                <p className="text-3xl font-bold tabular-nums">{money(unnecessary.total)}</p>
                <p className="text-sm text-muted">this month · {unnecessary.count} purchases</p>
                {unnecessary.deltaPct !== null && (
                  <p className={'mt-2 text-sm ' + (unnecessary.deltaPct <= 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400')}>
                    {unnecessary.deltaPct <= 0 ? '↓' : '↑'} {Math.abs(unnecessary.deltaPct)}% vs last month
                  </p>
                )}
                <p className="mt-3 text-xs text-muted">
                  Last month you spent {money(unnecessary.prevTotal)} on impulse buys.
                </p>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Spending heatmap · {year}</CardTitle>
        </CardHeader>
        <CardContent>
          {!heat ? (
            <Skeleton className="h-32" />
          ) : (
            <SpendHeatmap
              year={heat.year}
              days={heat.days.map((d) => ({ date: d.date, total: Number(d.total) }))}
              format={(v) => money(v)}
            />
          )}
        </CardContent>
      </Card>
    </div>
  );
}
