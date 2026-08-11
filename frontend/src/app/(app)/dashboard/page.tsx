'use client';

import { useEffect, useMemo } from 'react';
import useSWR from 'swr';
import Link from 'next/link';
import { Flame, Lightbulb, PiggyBank, TrendingDown, TrendingUp, BarChart3, ArrowRight } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { PageHeader, ProgressBar, Skeleton, EmptyState } from '@/components/ui/misc';
import { InfoHint } from '@/components/ui/info-hint';
import { HeroBalance } from '@/components/finance/hero-balance';
import { CurrencyBadge, currencyScopeHint } from '@/components/finance/currency-badge';
import { FinancialHealth } from '@/components/finance/financial-health';
import { SpendingPace } from '@/components/finance/spending-pace';
import { WeeklySnapshot } from '@/components/finance/weekly-snapshot';
import { SpendingStreaks } from '@/components/finance/spending-streaks';
import { CategoryHeatAlerts } from '@/components/finance/category-heat-alerts';
import { FamilySupportTracker } from '@/components/finance/family-support-tracker';
import { HouseholdWidget } from '@/components/finance/household-widget';
import { TabWidget } from '@/components/finance/tab-widget';
import { WishlistWidget } from '@/components/finance/wishlist-widget';
import { TransactionList } from '@/components/finance/transaction-list';
import { financeIcon } from '@/components/finance/icons';
import { useAuth } from '@/lib/auth';
import { useMoney } from '@/lib/amount-visibility';
import { useCurrencyView } from '@/lib/currency-view-context';
import type { DashboardData } from '@/lib/types';

function SmartInsight({ data, money }: { data: DashboardData; money: (v: number | string) => string }) {
  const insights: string[] = [];
  const net = Number(data.month.net);
  const income = Number(data.month.income);

  const drained = data.budgetsAtRisk.filter((b) => b.health === 'drained').length;
  if (drained > 0) {
    insights.push(`${drained} budget plan${drained > 1 ? 's are' : ' is'} empty - top up or hold off until the next cycle.`);
  } else if (data.budgetsAtRisk.length > 0) {
    insights.push(`${data.budgetsAtRisk.length} budget plan${data.budgetsAtRisk.length > 1 ? 's are' : ' is'} running low.`);
  }
  if (Number(data.budgetLocked ?? 0) > 0) {
    insights.push(`${money(data.budgetLocked!)} is set aside in budget plans and excluded from your available balance.`);
  }
  if (income > 0 && net / income < 0.1) {
    insights.push('Your savings rate is below 10% this month. Consider cutting unnecessary expenses.');
  } else if (net > 0) {
    insights.push(`You're saving ${money(net)} this month - keep it up!`);
  }
  if (Number(data.unnecessary.total) > 0) {
    insights.push(`${money(data.unnecessary.total)} went to "unnecessary" spending.`);
  }
  if (data.categoryHeatAlerts.length > 0) {
    insights.push(`${data.categoryHeatAlerts[0]!.category?.name} spending is up ${data.categoryHeatAlerts[0]!.deltaPct}% vs last month.`);
  }
  if (data.tab?.openCount && data.tab.openCount > 0 && data.tab.forecast) {
    const forecast = Number(data.tab.forecast.netIfOnTime);
    if (forecast !== 0) {
      insights.push(
        forecast > 0
          ? `Your Money Tab forecast: +${money(forecast)} if due items settle this month.`
          : `Your Money Tab forecast: ${money(forecast)} outflow if due tabs settle this month.`,
      );
    } else if ((data.tab?.overdueCount ?? 0) > 0) {
      const overdue = data.tab?.overdueCount ?? 0;
      insights.push(`${overdue} Money Tab item${overdue > 1 ? 's are' : ' is'} overdue - check /tab.`);
    }
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
  const { activeCurrency, activeBreakdown, setFromDashboard } = useCurrencyView();
  const { money } = useMoney();
  const { data } = useSWR<DashboardData>('/dashboard');
  const firstName = user?.name?.split(' ')[0];

  useEffect(() => {
    if (!data) return;
    setFromDashboard(
      data.currencies ?? [data.displayCurrency ?? user?.currency ?? 'ETB'],
      (data.currencyBreakdown ?? []) as Parameters<typeof setFromDashboard>[1],
      data.convertedTotal ?? null,
    );
  }, [data, setFromDashboard, user?.currency]);

  const viewData = useMemo(() => {
    if (!data) return null;
    if (!activeBreakdown) return data;
    return {
      ...data,
      totalBalance: activeBreakdown.totalBalance,
      month: { ...data.month, ...activeBreakdown.month },
    };
  }, [data, activeBreakdown]);

  const month = viewData?.month;

  if (!data || !viewData || !month) {
    return (
      <div>
        <PageHeader
          title="Dashboard"
          description={currencyScopeHint(activeCurrency)}
          badge={<CurrencyBadge />}
        />
        <Skeleton className="h-52 rounded-2xl" />
        <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-28" />)}
        </div>
      </div>
    );
  }

  return (
    <div className="animate-in space-y-6">
      <PageHeader
        title="Dashboard"
        description={currencyScopeHint(activeCurrency)}
        badge={<CurrencyBadge />}
      />
      <div className="grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <HeroBalance data={data} money={money} userName={firstName} />
        </div>
        <FinancialHealth data={viewData} />
      </div>

      <SmartInsight data={viewData} money={money} />

      <div className="grid items-start gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <WeeklySnapshot data={data.weeklySnapshot} money={money} />
        <SpendingStreaks data={data.spendingStreak} />
        <TabWidget tab={data.tab} money={money} />
        <WishlistWidget wishlist={data.wishlist} />
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <FamilySupportTracker data={data.familySupport} money={money} />
        <CategoryHeatAlerts alerts={data.categoryHeatAlerts} money={money} />
      </div>

      <HouseholdWidget household={data.household} money={money} />

      <div className="grid items-start gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatMini label="Net this month" value={money(month.net)} icon={<TrendingUp className="h-4 w-4" />} positive={Number(month.net) >= 0} />
        <StatMini label="Avg daily spend" value={money(month.avgDailySpend)} icon={<TrendingDown className="h-4 w-4" />} />
        <StatMini label="Unnecessary" value={money(data.unnecessary.total)} icon={<Flame className="h-4 w-4" />} warning={Number(data.unnecessary.total) > 0} />
        <StatMini label="Upcoming bills" value={String(data.upcomingRecurring.length)} icon={<PiggyBank className="h-4 w-4" />} hint="next 7 days" />
      </div>

      <SpendingPace month={month} money={money} />

      <div className="grid gap-6 lg:grid-cols-5">
        <Card className="lg:col-span-3">
          <CardHeader>
            <CardTitle>Recent transactions</CardTitle>
            <Link href="/transactions" className="text-xs font-medium text-primary hover:underline">View all →</Link>
          </CardHeader>
          <CardContent>
            {data.recentTransactions.filter((tx) => tx.currency === activeCurrency).length === 0 ? (
              <EmptyState title="No transactions yet" />
            ) : (
              <TransactionList items={data.recentTransactions.filter((tx) => tx.currency === activeCurrency)} compact />
            )}
          </CardContent>
        </Card>

        <div className="space-y-6 lg:col-span-2">
          <Card>
            <CardHeader>
              <CardTitle>Budget plans</CardTitle>
              <Link href="/budgets" className="text-xs font-medium text-primary hover:underline">Manage</Link>
            </CardHeader>
            <CardContent className="space-y-4">
              {data.budgets.length === 0 ? (
                <EmptyState
                  icon={<PiggyBank className="h-5 w-5" />}
                  title="No plans yet"
                  description="Set money aside for what you intend to spend."
                />
              ) : (
                data.budgets.map((b) => {
                  const planned = Math.max(Number(b.plannedAmount), 0.01);
                  const spentPct = Math.min(100, (Number(b.spentAmount) / planned) * 100);
                  return (
                    <Link key={b.id} href={`/budgets/${b.id}`} className="block">
                      <div className="mb-1 flex items-center justify-between gap-2 text-sm">
                        <span className="truncate font-medium">{b.name}</span>
                        <span className="shrink-0 tabular-nums text-xs text-muted">
                          {money(b.balance)} left
                        </span>
                      </div>
                      <ProgressBar
                        value={spentPct}
                        tone={b.health === 'drained' ? 'danger' : b.health === 'low' ? 'warning' : 'primary'}
                      />
                      <p className="mt-1 text-xs text-muted">
                        {money(b.spentAmount)} spent of {money(b.fundedAmount)} filled
                      </p>
                    </Link>
                  );
                })
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div className="flex items-center gap-1.5">
                <CardTitle>Set aside</CardTitle>
                <InfoHint label="About set aside">
                  Every balance on this page is shown after this money is taken out.
                </InfoHint>
              </div>
              <Link href="/budgets" className="text-xs font-medium text-primary hover:underline">All plans</Link>
            </CardHeader>
            <CardContent className="space-y-3">
              <div>
                <p className="text-2xl font-bold tabular-nums text-primary">
                  {money(data.budgetTotals.locked)}
                </p>
                <p className="text-xs text-muted">
                  locked in {data.budgetTotals.activeCount} active plan
                  {data.budgetTotals.activeCount === 1 ? '' : 's'}
                </p>
              </div>
              <dl className="grid grid-cols-2 gap-3 text-xs">
                <div>
                  <dt className="text-muted">Filled this cycle</dt>
                  <dd className="font-semibold tabular-nums">{money(data.budgetTotals.funded)}</dd>
                </div>
                <div>
                  <dt className="text-muted">Spent from plans</dt>
                  <dd className="font-semibold tabular-nums">{money(data.budgetTotals.spent)}</dd>
                </div>
              </dl>
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
