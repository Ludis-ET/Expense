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
import { Card, CardContent } from '@/components/ui/card';
import { Skeleton, EmptyState } from '@/components/ui/misc';
import { ChartInsightPanel, type ChartInsight } from '@/components/analytics/chart-insight-panel';
import { CurrencySwitcher } from '@/components/finance/currency-switcher';
import { Donut } from '@/components/charts/donut';
import { BarChart } from '@/components/charts/bar';
import { IncomeExpenseLine } from '@/components/charts/line';
import { SpendHeatmap } from '@/components/charts/heatmap';
import { BurnRateChart } from '@/components/charts/burn-rate';
import { DateRangePicker } from '@/components/finance/date-range-picker';
import { useMoney } from '@/lib/amount-visibility';
import { useCurrencyView } from '@/lib/currency-view-context';
import { cn } from '@/lib/utils';
import { rangeFromPreset, toApiQuery, type DateRange } from '@/lib/date-range';
import type { CategoryBreakdownItem, SeriesPoint, UnnecessaryStats } from '@/lib/types';

type Granularity = 'day' | 'week' | 'month';

interface SeriesResp { granularity: Granularity; points: SeriesPoint[]; currency?: string }
interface CategoriesResp { total: string; items: CategoryBreakdownItem[]; currency?: string }
interface IncomeVsExpenseResp {
  currency?: string;
  points: { month: string; income: string; expense: string; savingsRate: number | null }[];
}
interface HeatmapResp { year: number; currency?: string; days: { date: string; total: string }[] }
interface PayeesResp { currency?: string; items: { payee: string | null; total: string; count: number }[] }
interface BurnResp { currency?: string; points: { date: string; cumulative: string }[]; totalPlanned: string }

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

function pct(part: number, whole: number) {
  if (whole <= 0) return 0;
  return Math.round((part / whole) * 100);
}

export function DashboardAnalytics() {
  const { activeCurrency } = useCurrencyView();
  const { money } = useMoney(activeCurrency);
  const cur = encodeURIComponent(activeCurrency);

  const [range, setRange] = useState<DateRange>(() => rangeFromPreset('30d'));
  const [granularity, setGranularity] = useState<Granularity>('day');
  const [insight, setInsight] = useState<ChartInsight | null>(null);
  const [selectedSeries, setSelectedSeries] = useState<number | null>(null);
  const [selectedExpenseDonut, setSelectedExpenseDonut] = useState<number | null>(null);
  const [selectedIncomeDonut, setSelectedIncomeDonut] = useState<number | null>(null);
  const [selectedBar, setSelectedBar] = useState<number | null>(null);
  const [selectedIve, setSelectedIve] = useState<number | null>(null);
  const [selectedPayee, setSelectedPayee] = useState<number | null>(null);
  const [selectedHeatDate, setSelectedHeatDate] = useState<string | null>(null);

  const heatYear = range.to.getFullYear();
  const q = toApiQuery(range);

  const { data: series, isLoading: seriesLoading, isValidating: seriesValidating } = useSWR<SeriesResp>(
    `/analytics/series?granularity=${granularity}&currency=${cur}&${q}`,
  );
  const { data: expenses, isLoading: expLoading, isValidating: expValidating } = useSWR<CategoriesResp>(
    `/analytics/categories?kind=EXPENSE&currency=${cur}&${q}`,
  );
  const { data: income, isLoading: incLoading, isValidating: incValidating } = useSWR<CategoriesResp>(
    `/analytics/categories?kind=INCOME&currency=${cur}&${q}`,
  );
  const { data: ive } = useSWR<IncomeVsExpenseResp>(`/analytics/income-vs-expense?months=12&currency=${cur}`);
  const { data: heat, isValidating: heatValidating } = useSWR<HeatmapResp>(
    `/analytics/heatmap?year=${heatYear}&currency=${cur}`,
  );
  const { data: payees, isValidating: payeesValidating } = useSWR<PayeesResp>(
    `/analytics/payees?limit=10&currency=${cur}&${q}`,
  );
  const { data: unnecessary } = useSWR<UnnecessaryStats>(`/analytics/unnecessary?currency=${cur}`);
  const { data: burn, isValidating: burnValidating } = useSWR<BurnResp>(`/analytics/burn-rate?currency=${cur}`);

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
    savingsRate: p.savingsRate,
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
    fullLabel: c.category?.name ?? '?',
  }));

  const heatMax = Math.max(1, ...(heat?.days.map((d) => Number(d.total)) ?? [1]));

  function clearSelections() {
    setSelectedSeries(null);
    setSelectedExpenseDonut(null);
    setSelectedIncomeDonut(null);
    setSelectedBar(null);
    setSelectedIve(null);
    setSelectedPayee(null);
    setSelectedHeatDate(null);
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p className="text-sm font-medium">Viewing analytics in {activeCurrency}</p>
          <p className="text-xs text-muted">Amounts are never merged across currencies. Use Settings to add exchange rates.</p>
        </div>
        <CurrencySwitcher showConvertedHint />
      </div>

      <ChartInsightPanel insight={insight} onClose={() => { setInsight(null); clearSelections(); }} />

      <DateRangePicker value={range} onChange={(r) => { setRange(r); setInsight(null); clearSelections(); }} loading={rangeBusy} />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <KpiTile label={`Income · ${activeCurrency}`} value={money(totalIncome)} icon={<TrendingUp className="h-4 w-4" />} tone="up" loading={incLoading} />
        <KpiTile label={`Expenses · ${activeCurrency}`} value={money(totalExpense)} icon={<TrendingDown className="h-4 w-4" />} tone="down" loading={expLoading} />
        <KpiTile label="Net" value={money(net)} icon={<Wallet className="h-4 w-4" />} tone={net >= 0 ? 'up' : 'down'} loading={incLoading || expLoading} />
        <KpiTile label="Savings rate" value={savingsRate !== null ? `${savingsRate}%` : '-'} icon={<Zap className="h-4 w-4" />} loading={incLoading || expLoading} />
      </div>

      <ChartCard title="Cash flow" subtitle={`Income vs expenses · ${activeCurrency} · tap a point`} icon={<BarChart3 className="h-4.5 w-4.5" />} loading={seriesLoading || seriesValidating}>
        <div className="mb-4 flex gap-1 rounded-xl border border-border bg-surface-muted/50 p-1 w-fit">
          {(['day', 'week', 'month'] as Granularity[]).map((g) => (
            <button key={g} type="button" onClick={() => setGranularity(g)} className={cn('rounded-lg px-3.5 py-1.5 text-xs font-medium capitalize transition-all active:scale-95 min-h-[36px]', granularity === g ? 'bg-primary text-primary-foreground shadow-sm' : 'text-muted hover:text-foreground')}>
              {g}
            </button>
          ))}
        </div>
        {seriesLoading ? <Skeleton className="h-56" /> : (
          <IncomeExpenseLine points={linePoints} format={money} selectedIndex={selectedSeries} onSelect={(point, i) => {
            const next = selectedSeries === i ? null : i;
            setSelectedSeries(next);
            if (next === null) { setInsight(null); return; }
            const pNet = point.income - point.expense;
            setInsight({ title: point.label, subtitle: `${granularity} · ${activeCurrency}`, value: money(pNet), detail: `Income ${money(point.income)} · Expenses ${money(point.expense)} · Net ${money(pNet)}.`, tone: pNet >= 0 ? 'income' : 'expense' });
          }} />
        )}
      </ChartCard>

      <div className="grid gap-6 lg:grid-cols-2">
        <ChartCard title="Where it went" subtitle="Tap a slice" icon={<PieChart className="h-4.5 w-4.5" />} accent="amber" loading={expValidating}>
          {expenseDonut.length === 0 ? <EmptyState title="No spending in this range" /> : (
            <Donut data={expenseDonut} format={money} centerLabel="spent" selectedIndex={selectedExpenseDonut} onSelect={(slice, i) => {
              const next = selectedExpenseDonut === i ? null : i;
              setSelectedExpenseDonut(next);
              if (next === null) { setInsight(null); return; }
              setInsight({ title: slice.label, subtitle: 'Expense', value: money(slice.value), detail: `${pct(slice.value, totalExpense)}% of ${money(totalExpense)} in range.`, tone: 'expense', action: { label: 'Browse transactions', href: '/transactions' } });
            }} />
          )}
        </ChartCard>
        <ChartCard title="Where it came from" subtitle="Tap a slice" icon={<Wallet className="h-4.5 w-4.5" />} accent="emerald" loading={incValidating}>
          {incomeDonut.length === 0 ? <EmptyState title="No income in this range" /> : (
            <Donut data={incomeDonut} format={money} centerLabel="earned" selectedIndex={selectedIncomeDonut} onSelect={(slice, i) => {
              const next = selectedIncomeDonut === i ? null : i;
              setSelectedIncomeDonut(next);
              if (next === null) { setInsight(null); return; }
              setInsight({ title: slice.label, subtitle: 'Income', value: money(slice.value), detail: `${pct(slice.value, totalIncome)}% of ${money(totalIncome)} in range.`, tone: 'income', action: { label: 'Browse transactions', href: '/transactions' } });
            }} />
          )}
        </ChartCard>
      </div>

      <ChartCard title="Category comparison" subtitle="Tap a bar" icon={<Layers className="h-4.5 w-4.5" />} accent="violet" loading={expValidating}>
        {barData.length === 0 ? <EmptyState title="No data" /> : (
          <BarChart data={barData} format={money} selectedIndex={selectedBar} onSelect={(item, i) => {
            const next = selectedBar === i ? null : i;
            setSelectedBar(next);
            if (next === null) { setInsight(null); return; }
            const top = barData[0]?.value ?? 0;
            setInsight({ title: barData[i]?.fullLabel ?? item.label, subtitle: `Rank #${i + 1}`, value: money(item.value), detail: `${top > 0 ? Math.round((item.value / top) * 100) : 0}% of top category · ${pct(item.value, totalExpense)}% of all spending.`, tone: 'expense' });
          }} />
        )}
      </ChartCard>

      <div className="grid gap-6 lg:grid-cols-2">
        <ChartCard title="Top payees" subtitle="Tap a row" icon={<Users className="h-4.5 w-4.5" />} loading={payeesValidating}>
          {!payees?.items.length ? <EmptyState title="No payees in this range" /> : (
            <ul className="space-y-2">
              {payees.items.map((p, i) => (
                <li key={p.payee ?? i}>
                  <button type="button" onClick={() => {
                    const next = selectedPayee === i ? null : i;
                    setSelectedPayee(next);
                    if (next === null) { setInsight(null); return; }
                    const avg = p.count > 0 ? Number(p.total) / p.count : 0;
                    setInsight({ title: p.payee ?? 'Unknown', subtitle: `${p.count} payments`, value: money(p.total), detail: `Average ${money(avg)} per payment · rank #${i + 1}.`, tone: 'expense' });
                  }} className={cn('flex w-full items-center gap-3 rounded-xl px-2 py-2 text-left transition-colors hover:bg-surface-muted min-h-[44px]', selectedPayee === i && 'bg-surface-muted ring-1 ring-primary/30')}>
                    <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-surface-muted text-xs font-bold text-muted">{i + 1}</span>
                    <span className="min-w-0 flex-1 truncate text-sm font-medium">{p.payee}</span>
                    <span className="shrink-0 text-sm tabular-nums text-muted">{money(p.total)} <span className="text-xs">· {p.count}×</span></span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </ChartCard>
        <ChartCard title="Impulse spend" subtitle={`${activeCurrency} · this month`} icon={<Flame className="h-4.5 w-4.5" />} accent="rose">
          {!unnecessary ? <Skeleton className="h-24" /> : (
            <button type="button" className="flex w-full items-center gap-5 rounded-xl p-1 text-left min-h-[44px] hover:bg-surface-muted/50" onClick={() => setInsight({ title: 'Impulse spending', subtitle: unnecessary.category?.name ?? 'Unnecessary', value: money(unnecessary.total), detail: `${unnecessary.count} purchases in ${activeCurrency}.`, tone: 'warning', action: { label: 'Review transactions', href: '/transactions' } })}>
              <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-orange-500/10"><Flame className="h-8 w-8 text-orange-500" /></div>
              <div>
                <p className="text-3xl font-bold tabular-nums">{money(unnecessary.total)}</p>
                <p className="text-sm text-muted">{unnecessary.count} purchases · tap for details</p>
              </div>
            </button>
          )}
        </ChartCard>
      </div>

      <ChartCard title="12-month trajectory" subtitle={avgSavings !== null ? `${avgSavings}% avg savings · tap a month` : 'Tap a month'} icon={<TrendingUp className="h-4.5 w-4.5" />} accent="emerald">
        {!ive ? <Skeleton className="h-52" /> : (
          <IncomeExpenseLine points={iveLine} format={money} selectedIndex={selectedIve} onSelect={(point, i) => {
            const next = selectedIve === i ? null : i;
            setSelectedIve(next);
            if (next === null) { setInsight(null); return; }
            const pNet = point.income - point.expense;
            const sr = iveLine[i]?.savingsRate;
            setInsight({ title: `Month ${point.label}`, subtitle: activeCurrency, value: sr !== null && sr !== undefined ? `${sr}% saved` : money(pNet), detail: `Income ${money(point.income)} · Expenses ${money(point.expense)}.`, tone: pNet >= 0 ? 'income' : 'expense' });
          }} />
        )}
      </ChartCard>

      <div className="grid gap-6 lg:grid-cols-2">
        <ChartCard title="Budget burn rate" subtitle={activeCurrency} icon={<Zap className="h-4.5 w-4.5" />} loading={burnValidating}>
          {!burn ? <Skeleton className="h-48" /> : <BurnRateChart points={burn.points.map((p) => ({ date: p.date, cumulative: Number(p.cumulative) }))} totalPlanned={Number(burn.totalPlanned)} currency={activeCurrency} />}
        </ChartCard>
        <ChartCard title={`Spending heatmap · ${heatYear}`} subtitle="Tap a day" icon={<BarChart3 className="h-4.5 w-4.5" />} loading={heatValidating}>
          {!heat ? <Skeleton className="h-32" /> : (
            <SpendHeatmap year={heat.year} days={heat.days.map((d) => ({ date: d.date, total: Number(d.total) }))} format={money} selectedDate={selectedHeatDate} onSelect={(day) => {
              const next = selectedHeatDate === day.date ? null : day.date;
              setSelectedHeatDate(next);
              if (!next) { setInsight(null); return; }
              setInsight({ title: new Date(day.date + 'T12:00:00').toLocaleDateString(undefined, { weekday: 'long', month: 'short', day: 'numeric' }), subtitle: activeCurrency, value: money(day.total), detail: day.total > 0 ? `${pct(day.total, heatMax)}% of your busiest day.` : 'No expenses recorded.', tone: day.total > heatMax * 0.6 ? 'expense' : 'default' });
            }} />
          )}
        </ChartCard>
      </div>
    </div>
  );
}
