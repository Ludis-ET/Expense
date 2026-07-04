'use client';

import useSWR from 'swr';
import Link from 'next/link';
import { Flame, Lightbulb, PiggyBank, TrendingDown, TrendingUp, BarChart3, ArrowRight } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { PageHeader, ProgressBar, Skeleton, EmptyState } from '@/components/ui/misc';
import { HeroBalance } from '@/components/finance/hero-balance';
import { FinancialHealth } from '@/components/finance/financial-health';
import { SpendingPace } from '@/components/finance/spending-pace';
import { WeeklySnapshot } from '@/components/finance/weekly-snapshot';
import { SpendingStreaks } from '@/components/finance/spending-streaks';
import { CategoryHeatAlerts } from '@/components/finance/category-heat-alerts';
import { FamilySupportTracker } from '@/components/finance/family-support-tracker';
import { HouseholdWidget } from '@/components/finance/household-widget';
import { TabWidget } from '@/components/finance/tab-widget';
import { TransactionList } from '@/components/finance/transaction-list';
import { CategoryBadge } from '@/components/finance/category-badge';
import { financeIcon } from '@/components/finance/icons';
import { formatMoney } from '@/lib/format';
import { useAuth } from '@/lib/auth';
import type { DashboardData } from '@/lib/types';

function SmartInsight({ data, money }: { data: DashboardData; money: (v: number | string) => string }) {
  const insights: string[] = [];
  const net = Number(data.month.net);
  const income = Number(data.month.income);

  if (data.budgetsAtRisk.some((b) => b.status === 'over')) {
    insights.push('One or more budgets are over limit — review your spending categories.');
  } else if (data.budgetsAtRisk.length > 0) {
    insights.push(`${data.budgetsAtRisk.length} budget${data.budgetsAtRisk.length > 1 ? 's are' : ' is'} approaching the limit.`);
  }
  if (income > 0 && net / income < 0.1) {
    insights.push('Your savings rate is below 10% this month. Consider cutting unnecessary expenses.');
  } else if (net > 0) {
    insights.push(`You're saving ${money(net)} this month — keep it up!`);
  }
  if (Number(data.unnecessary.total) > 0) {
    insights.push(`${money(data.unnecessary.total)} went to "unnecessary" spending.`);
  }
  if (data.categoryHeatAlerts.length > 0) {
    insights.push(`${data.categoryHeatAlerts[0]!.category?.name} spending is up ${data.categoryHeatAlerts[0]!.deltaPct}% vs last month.`);
  }
  if (insights.length === 0) {
    insights.push('Add transactions and set budgets to unlock personalized insights.');
  }

  return (
    <div className="card flex gap-3 p-4">
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
        <Lightbulb className="h-4.5 w-4.5" />
      </div>
      <div>
        <p className="text-xs font-semibold uppercase tracking-wide text-muted">Smart insight</p>
        <p className="mt-1 text-sm leading-relaxed">{insights[0]}</p>
      </div>
    </div>
  );
}

export default function DashboardPage() {
  const { user } = useAuth();
  const currency = user?.currency ?? 'ETB';
  const { data } = useSWR<DashboardData>('/dashboard');
  const money = (v: number | string) => formatMoney(v, currency);
  const firstName = user?.name?.split(' ')[0];

  if (!data) {
    return (
      <div>
        <PageHeader title="Dashboard" description="Your money at a glance." />
        <Skeleton className="h-52 rounded-2xl" />
        <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-28" />)}
        </div>
      </div>
    );
  }

  return (
    <div className="animate-in space-y-6">
      <div className="grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <HeroBalance data={data} money={money} userName={firstName} />
        </div>
        <FinancialHealth data={data} />
      </div>

      <SmartInsight data={data} money={money} />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <WeeklySnapshot data={data.weeklySnapshot} money={money} />
        <SpendingStreaks data={data.spendingStreak} money={money} />
        <TabWidget tab={data.tab} money={money} />
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <FamilySupportTracker data={data.familySupport} money={money} />
        <CategoryHeatAlerts alerts={data.categoryHeatAlerts} money={money} />
      </div>

      <HouseholdWidget household={data.household} money={money} />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatMini label="Net this month" value={money(data.month.net)} icon={<TrendingUp className="h-4 w-4" />} positive={Number(data.month.net) >= 0} />
        <StatMini label="Avg daily spend" value={money(data.month.avgDailySpend)} icon={<TrendingDown className="h-4 w-4" />} />
        <StatMini label="Unnecessary" value={money(data.unnecessary.total)} icon={<Flame className="h-4 w-4" />} warning={Number(data.unnecessary.total) > 0} />
        <StatMini label="Upcoming bills" value={String(data.upcomingRecurring.length)} icon={<PiggyBank className="h-4 w-4" />} hint="next 7 days" />
      </div>

      <SpendingPace month={data.month} money={money} />

      <div className="grid gap-6 lg:grid-cols-5">
        <Card className="lg:col-span-3">
          <CardHeader>
            <CardTitle>Recent transactions</CardTitle>
            <Link href="/transactions" className="text-xs font-medium text-primary hover:underline">View all →</Link>
          </CardHeader>
          <CardContent>
            {data.recentTransactions.length === 0 ? (
              <EmptyState title="No transactions yet" />
            ) : (
              <TransactionList items={data.recentTransactions} compact />
            )}
          </CardContent>
        </Card>

        <div className="space-y-6 lg:col-span-2">
          <Card>
            <CardHeader>
              <CardTitle>Budgets at risk</CardTitle>
              <Link href="/budgets" className="text-xs font-medium text-primary hover:underline">Manage</Link>
            </CardHeader>
            <CardContent className="space-y-4">
              {data.budgetsAtRisk.length === 0 ? (
                <p className="py-4 text-center text-sm text-muted">All budgets on track ✓</p>
              ) : (
                data.budgetsAtRisk.map((b) => (
                  <div key={b.id}>
                    <div className="mb-1 flex items-center justify-between text-sm">
                      <CategoryBadge category={b.category} />
                      <span className="tabular-nums text-xs text-muted">{money(b.spent)} / {money(b.amount)}</span>
                    </div>
                    <ProgressBar value={b.pct} tone={b.status === 'over' ? 'danger' : 'warning'} />
                  </div>
                ))
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Goals</CardTitle>
              <Link href="/budgets?tab=goals" className="text-xs font-medium text-primary hover:underline">All goals</Link>
            </CardHeader>
            <CardContent className="space-y-4">
              {data.goals.length === 0 ? (
                <EmptyState icon={<PiggyBank className="h-5 w-5" />} title="No goals yet" />
              ) : (
                data.goals.map((g) => (
                  <div key={g.id}>
                    <div className="mb-1 flex items-center justify-between text-sm">
                      <span className="font-medium">{g.name}</span>
                      <span className="tabular-nums text-xs text-muted">{g.pct}%</span>
                    </div>
                    <ProgressBar value={g.pct} tone="success" />
                    <p className="mt-1 text-xs text-muted">{money(g.saved)} of {money(g.targetAmount)}</p>
                  </div>
                ))
              )}
            </CardContent>
          </Card>
        </div>
      </div>

      {data.upcomingRecurring.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle>Upcoming recurring (7 days)</CardTitle>
            <Link href="/transactions?tab=recurring" className="text-xs font-medium text-primary hover:underline">Manage</Link>
          </CardHeader>
          <CardContent>
            <ul className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {data.upcomingRecurring.map((r) => {
                const Icon = financeIcon(r.category?.icon);
                return (
                  <li key={r.id} className="flex items-center gap-3 rounded-xl border border-border bg-surface-muted/40 px-4 py-3">
                    <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-surface text-muted">
                      <Icon className="h-4 w-4" />
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium">{r.name}</p>
                      <p className="text-xs text-muted">{new Date(r.nextRun).toLocaleDateString()}</p>
                    </div>
                    <span className="text-sm font-semibold tabular-nums">{money(r.amount)}</span>
                  </li>
                );
              })}
            </ul>
          </CardContent>
        </Card>
      )}

      <Link
        href="/analytics"
        className="group flex items-center justify-between rounded-2xl border border-border bg-surface px-6 py-5 transition-all hover:border-primary/30 hover:shadow-md"
      >
        <div className="flex items-center gap-4">
          <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-primary/10 text-primary">
            <BarChart3 className="h-5 w-5" />
          </span>
          <div>
            <p className="font-semibold">Full analytics</p>
            <p className="text-sm text-muted">Trends, heatmap, burn rate, payees & more</p>
          </div>
        </div>
        <ArrowRight className="h-5 w-5 text-muted transition-transform group-hover:translate-x-1 group-hover:text-primary" />
      </Link>
    </div>
  );
}

function StatMini({ label, value, icon, hint, positive, warning }: { label: string; value: string; icon: React.ReactNode; hint?: string; positive?: boolean; warning?: boolean }) {
  return (
    <div className="card p-4">
      <div className="flex items-center justify-between">
        <p className="text-xs font-medium text-muted">{label}</p>
        <span className="text-muted">{icon}</span>
      </div>
      <p className={`mt-1.5 text-xl font-bold tabular-nums ${positive === true ? 'text-emerald-600 dark:text-emerald-400' : positive === false ? 'text-red-600 dark:text-red-400' : warning ? 'text-warning' : ''}`}>
        {value}
      </p>
      {hint && <p className="mt-0.5 text-[10px] text-muted">{hint}</p>}
    </div>
  );
}
