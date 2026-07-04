'use client';

import { useMemo, useState } from 'react';
import useSWR from 'swr';
import {
  BarChart3,
  Flame,
  Layers,
  PieChart,
  TrendingDown,
  TrendingUp,
  Users,
  Wallet,
  Zap,
} from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Skeleton, EmptyState } from '@/components/ui/misc';
import { Donut } from '@/components/charts/donut';
import { BarChart } from '@/components/charts/bar';
import { IncomeExpenseLine } from '@/components/charts/line';
import { SpendHeatmap } from '@/components/charts/heatmap';
import { BurnRateChart } from '@/components/charts/burn-rate';
import { DateRangePicker } from '@/components/finance/date-range-picker';
import { useMoney } from '@/lib/amount-visibility';
import { useAuth } from '@/lib/auth';
import { cn } from '@/lib/utils';
import { rangeFromPreset, toApiQuery, type DateRange } from '@/lib/date-range';
import type { CategoryBreakdownItem, SeriesPoint, UnnecessaryStats } from '@/lib/types';

type Granularity = 'day' | 'week' | 'month';

interface SeriesResp { granularity: Granularity; points: SeriesPoint[] }
interface CategoriesResp { total: string; items: CategoryBreakdownItem[] }
interface IncomeVsExpenseResp {
  points: { month: string; income: string; expense: string; savingsRate: number | null }[];
}
interface HeatmapResp { year: number; days: { date: string; total: string }[] }
interface PayeesResp { items: { payee: string | null; total: string; count: number }[] }
interface BurnResp { points: { date: string; cumulative: string }[]; totalPlanned: string }

function ChartCard({
  title,
  subtitle,
  icon,
  accent = 'primary',
  loading,
  children,
  className,
}: {
  title: string;
  subtitle?: string;
  icon: React.ReactNode;
  accent?: 'primary' | 'emerald' | 'amber' | 'violet' | 'rose';
  loading?: boolean;
  children: React.ReactNode;
  className?: string;
}) {
  const accents = {
    primary: 'from-primary/10 to-primary/0 text-primary',
    emerald: 'from-emerald-500/10 to-emerald-500/0 text-emerald-600 dark:text-emerald-400',
    amber: 'from-amber-500/10 to-amber-500/0 text-amber-600 dark:text-amber-400',
    violet: 'from-violet-500/10 to-violet-500/0 text-violet-600 dark:text-violet-400',
    rose: 'from-rose-500/10 to-rose-500/0 text-rose-600 dark:text-rose-400',
  };

  return (
    <Card className={cn('overflow-hidden transition-shadow hover:shadow-md', className)}>
      <div className={cn('border-b border-border bg-gradient-to-r px-5 py-4', accents[accent])}>
        <div className="flex items-start gap-3">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-surface/80 shadow-sm backdrop-blur-sm">
            {icon}
          </span>
          <div>
            <h3 className="font-semibold text-foreground">{title}</h3>
            {subtitle && <p className="mt-0.5 text-xs text-muted">{subtitle}</p>}
          </div>
        </div>
      </div>
      <CardContent className="relative p-5">
        {loading && (
          <div className="absolute inset-0 z-10 flex items-center justify-center bg-surface/60 backdrop-blur-[1px]">
            <div className="h-8 w-8 animate-spin rounded-full border-2 border-primary border-t-transparent" />
          </div>
        )}
        {children}
      </CardContent>
    </Card>
  );
}

function KpiTile({
  label,
  value,
  icon,
  tone,
  loading,
}: {
  label: string;
  value: string;
  icon: React.ReactNode;
  tone?: 'up' | 'down' | 'neutral';
  loading?: boolean;
}) {
  return (
    <div className="card relative overflow-hidden p-5">
      {loading && <Skeleton className="absolute inset-0 rounded-xl" />}
      <div className={cn('relative', loading && 'opacity-0')}>
        <div className="flex items-center justify-between">
          <p className="text-xs font-medium uppercase tracking-wide text-muted">{label}</p>
          <span className="text-muted">{icon}</span>
        </div>
        <p
          className={cn(
            'mt-2 text-2xl font-bold tabular-nums tracking-tight',
            tone === 'up' && 'text-emerald-600 dark:text-emerald-400',
            tone === 'down' && 'text-red-600 dark:text-red-400',
          )}
        >
          {value}
        </p>
      </div>
    </div>
  );
}

export function DashboardAnalytics() {
  const { user } = useAuth();
  const { money } = useMoney();

  const [range, setRange] = useState<DateRange>(() => rangeFromPreset('30d'));
  const [granularity, setGranularity] = useState<Granularity>('day');
  const heatYear = range.to.getFullYear();

  const q = toApiQuery(range);

  const { data: series, isLoading: seriesLoading, isValidating: seriesValidating } = useSWR<SeriesResp>(
    `/analytics/series?granularity=${granularity}&${q}`,
  );
  const { data: expenses, isLoading: expLoading, isValidating: expValidating } = useSWR<CategoriesResp>(
    `/analytics/categories?kind=EXPENSE&${q}`,
  );
  const { data: income, isLoading: incLoading, isValidating: incValidating } = useSWR<CategoriesResp>(
    `/analytics/categories?kind=INCOME&${q}`,
  );
  const { data: ive } = useSWR<IncomeVsExpenseResp>('/analytics/income-vs-expense?months=12');
  const { data: heat, isValidating: heatValidating } = useSWR<HeatmapResp>(`/analytics/heatmap?year=${heatYear}`);
  const { data: payees, isValidating: payeesValidating } = useSWR<PayeesResp>(`/analytics/payees?limit=10&${q}`);
  const { data: unnecessary } = useSWR<UnnecessaryStats>('/analytics/unnecessary');
  const { data: burn, isValidating: burnValidating } = useSWR<BurnResp>('/analytics/burn-rate');

  const rangeBusy = seriesValidating || expValidating || incValidating;

  const totalIncome = Number(income?.total ?? 0);
  const totalExpense = Number(expenses?.total ?? 0);
  const net = totalIncome - totalExpense;
  const savingsRate = totalIncome > 0 ? Math.round((net / totalIncome) * 100) : null;

  const linePoints = (series?.points ?? []).map((p) => ({
    label: p.bucket.slice(5),
    income: Number(p.income),
    expense: Number(p.expense),
  }));

  const iveLine = (ive?.points ?? []).map((p) => ({
    label: p.month.slice(5),
    income: Number(p.income),
    expense: Number(p.expense),
  }));

  const avgSavings = useMemo(() => {
    if (!ive?.points.length) return null;
    const valid = ive.points.filter((p) => p.savingsRate !== null);
    if (!valid.length) return null;
    return Math.round(valid.reduce((s, p) => s + (p.savingsRate ?? 0), 0) / valid.length);
  }, [ive]);

  const expenseDonut = (expenses?.items ?? [])
    .filter((c) => c.category)
    .slice(0, 8)
    .map((c) => ({ label: c.category!.name, value: Number(c.amount), color: c.category!.color }));

  const incomeDonut = (income?.items ?? [])
    .filter((c) => c.category)
    .slice(0, 6)
    .map((c) => ({ label: c.category!.name, value: Number(c.amount), color: c.category!.color }));

  const barData = (expenses?.items ?? []).slice(0, 8).map((c) => ({
    label: c.category?.name?.slice(0, 12) ?? '?',
    value: Number(c.amount),
  }));

  return (
    <div className="space-y-6">
      <DateRangePicker value={range} onChange={setRange} loading={rangeBusy} />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <KpiTile
          label="Income"
          value={money(totalIncome)}
          icon={<TrendingUp className="h-4 w-4" />}
          tone="up"
          loading={incLoading}
        />
        <KpiTile
          label="Expenses"
          value={money(totalExpense)}
          icon={<TrendingDown className="h-4 w-4" />}
          tone="down"
          loading={expLoading}
        />
        <KpiTile
          label="Net"
          value={money(net)}
          icon={<Wallet className="h-4 w-4" />}
          tone={net >= 0 ? 'up' : 'down'}
          loading={incLoading || expLoading}
        />
        <KpiTile
          label="Savings rate"
          value={savingsRate !== null ? `${savingsRate}%` : '-'}
          icon={<Zap className="h-4 w-4" />}
          loading={incLoading || expLoading}
        />
      </div>

      <ChartCard
        title="Cash flow"
        subtitle="Income vs expenses over your selected range"
        icon={<BarChart3 className="h-4.5 w-4.5" />}
        loading={seriesLoading || seriesValidating}
      >
        <div className="mb-4 flex gap-1 rounded-xl border border-border bg-surface-muted/50 p-1 w-fit">
          {(['day', 'week', 'month'] as Granularity[]).map((g) => (
            <button
              key={g}
              type="button"
              onClick={() => setGranularity(g)}
              className={cn(
                'rounded-lg px-3.5 py-1.5 text-xs font-medium capitalize transition-all active:scale-95',
                granularity === g
                  ? 'bg-primary text-primary-foreground shadow-sm'
                  : 'text-muted hover:text-foreground',
              )}
            >
              {g}
            </button>
          ))}
        </div>
        {seriesLoading ? <Skeleton className="h-56" /> : <IncomeExpenseLine points={linePoints} format={money} />}
      </ChartCard>

      <div className="grid gap-6 lg:grid-cols-2">
        <ChartCard
          title="Where it went"
          subtitle="Expense breakdown"
          icon={<PieChart className="h-4.5 w-4.5" />}
          accent="amber"
          loading={expValidating}
        >
          {expenseDonut.length === 0 ? (
            <EmptyState title="No spending in this range" />
          ) : (
            <Donut data={expenseDonut} format={money} centerLabel="spent" />
          )}
        </ChartCard>

        <ChartCard
          title="Where it came from"
          subtitle="Income sources"
          icon={<Wallet className="h-4.5 w-4.5" />}
          accent="emerald"
          loading={incValidating}
        >
          {incomeDonut.length === 0 ? (
            <EmptyState title="No income in this range" />
          ) : (
            <Donut data={incomeDonut} format={money} centerLabel="earned" />
          )}
        </ChartCard>
      </div>

      <ChartCard
        title="Category comparison"
        subtitle="Top spending categories"
        icon={<Layers className="h-4.5 w-4.5" />}
        accent="violet"
        loading={expValidating}
      >
        {barData.length === 0 ? <EmptyState title="No data" /> : <BarChart data={barData} format={money} />}
      </ChartCard>

      <div className="grid gap-6 lg:grid-cols-2">
        <ChartCard
          title="Top payees"
          subtitle="Who you paid most"
          icon={<Users className="h-4.5 w-4.5" />}
          loading={payeesValidating}
        >
          {!payees?.items.length ? (
            <EmptyState title="No payees in this range" />
          ) : (
            <ul className="space-y-3">
              {payees.items.map((p, i) => (
                <li key={p.payee ?? i} className="flex items-center gap-3">
                  <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-surface-muted text-xs font-bold text-muted">
                    {i + 1}
                  </span>
                  <span className="min-w-0 flex-1 truncate text-sm font-medium">{p.payee}</span>
                  <span className="shrink-0 text-sm tabular-nums text-muted">
                    {money(p.total)} <span className="text-xs">· {p.count}×</span>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </ChartCard>

        <ChartCard
          title="Impulse spend"
          subtitle="Unnecessary category · this month"
          icon={<Flame className="h-4.5 w-4.5" />}
          accent="rose"
        >
          {!unnecessary ? (
            <Skeleton className="h-24" />
          ) : (
            <div className="flex items-center gap-5">
              <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-orange-500/10">
                <Flame className="h-8 w-8 text-orange-500" />
              </div>
              <div>
                <p className="text-3xl font-bold tabular-nums">{money(unnecessary.total)}</p>
                <p className="text-sm text-muted">{unnecessary.count} purchases</p>
                {unnecessary.deltaPct !== null && (
                  <p className={cn('mt-1 text-sm font-medium', unnecessary.deltaPct <= 0 ? 'text-emerald-500' : 'text-red-500')}>
                    {unnecessary.deltaPct <= 0 ? '↓' : '↑'} {Math.abs(unnecessary.deltaPct)}% vs last month
                  </p>
                )}
              </div>
            </div>
          )}
        </ChartCard>
      </div>

      <ChartCard
        title="12-month trajectory"
        subtitle={avgSavings !== null ? `${avgSavings}% average savings rate` : 'Long-term income vs expense'}
        icon={<TrendingUp className="h-4.5 w-4.5" />}
        accent="emerald"
      >
        {!ive ? <Skeleton className="h-52" /> : <IncomeExpenseLine points={iveLine} format={money} />}
      </ChartCard>

      <div className="grid gap-6 lg:grid-cols-2">
        <ChartCard
          title="Budget burn rate"
          subtitle="Cumulative spend vs monthly budget"
          icon={<Zap className="h-4.5 w-4.5" />}
          loading={burnValidating}
        >
          {!burn ? (
            <Skeleton className="h-48" />
          ) : (
            <BurnRateChart
              points={burn.points.map((p) => ({ date: p.date, cumulative: Number(p.cumulative) }))}
              totalPlanned={Number(burn.totalPlanned)}
              currency={user?.currency ?? 'ETB'}
            />
          )}
        </ChartCard>

        <ChartCard
          title={`Spending heatmap · ${heatYear}`}
          subtitle="Daily intensity"
          icon={<BarChart3 className="h-4.5 w-4.5" />}
          loading={heatValidating}
        >
          {!heat ? (
            <Skeleton className="h-32" />
          ) : (
            <SpendHeatmap
              year={heat.year}
              days={heat.days.map((d) => ({ date: d.date, total: Number(d.total) }))}
              format={money}
            />
          )}
        </ChartCard>
      </div>
    </div>
  );
}
