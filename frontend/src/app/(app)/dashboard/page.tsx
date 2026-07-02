'use client';

import useSWR from 'swr';
import Link from 'next/link';
import { ArrowRight, Flame, PiggyBank, TrendingDown, TrendingUp, Wallet } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { PageHeader, ProgressBar, Skeleton, EmptyState } from '@/components/ui/misc';
import { Donut } from '@/components/charts/donut';
import { StatCard } from '@/components/finance/stat-card';
import { TransactionList } from '@/components/finance/transaction-list';
import { CategoryBadge } from '@/components/finance/category-badge';
import { financeIcon } from '@/components/finance/icons';
import { formatMoney } from '@/lib/format';
import { useAuth } from '@/lib/auth';
import type { DashboardData } from '@/lib/types';

export default function DashboardPage() {
  const { user } = useAuth();
  const currency = user?.currency ?? 'ETB';
  const { data } = useSWR<DashboardData>('/dashboard');
  const money = (v: number | string) => formatMoney(v, currency);

  if (!data) {
    return (
      <div>
        <PageHeader title="Dashboard" description="Your money at a glance." />
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-28" />)}
        </div>
        <Skeleton className="mt-6 h-80" />
      </div>
    );
  }

  const donutData = data.topCategories
    .filter((c) => c.category)
    .map((c) => ({ label: c.category!.name, value: Number(c.amount), color: c.category!.color }));

  return (
    <div>
      <PageHeader title={`Welcome back, ${user?.name?.split(' ')[0] ?? ''}`} description="Here's how your money looks." />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard label="Total balance" value={money(data.totalBalance)} icon={<Wallet className="h-4 w-4" />} />
        <StatCard
          label="Income this month"
          value={money(data.month.income)}
          deltaPct={data.month.incomeDeltaPct}
          icon={<TrendingUp className="h-4 w-4" />}
        />
        <StatCard
          label="Spent this month"
          value={money(data.month.expense)}
          deltaPct={data.month.expenseDeltaPct}
          invertDelta
          icon={<TrendingDown className="h-4 w-4" />}
        />
        <StatCard label="Net this month" value={money(data.month.net)} hint={`avg ${money(data.month.avgDailySpend)}/day`} />
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Recent transactions</CardTitle>
            <Link href="/transactions" className="text-sm font-medium text-primary hover:underline">
              View all
            </Link>
          </CardHeader>
          <CardContent>
            {data.recentTransactions.length === 0 ? (
              <EmptyState title="No transactions yet" description="Add your first income or expense to get started." />
            ) : (
              <TransactionList items={data.recentTransactions} compact />
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Top spending</CardTitle>
          </CardHeader>
          <CardContent>
            {donutData.length === 0 ? (
              <EmptyState title="No spending yet" />
            ) : (
              <Donut data={donutData} format={(v) => money(v)} centerLabel="spent" />
            )}
          </CardContent>
        </Card>
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle>Budgets at risk</CardTitle>
            <Link href="/budgets" className="text-sm font-medium text-primary hover:underline">Manage</Link>
          </CardHeader>
          <CardContent className="space-y-4">
            {data.budgetsAtRisk.length === 0 ? (
              <p className="py-6 text-center text-sm text-muted">Everything is within budget. 🎉</p>
            ) : (
              data.budgetsAtRisk.map((b) => (
                <div key={b.id}>
                  <div className="mb-1 flex items-center justify-between text-sm">
                    <CategoryBadge category={b.category} />
                    <span className="tabular-nums text-muted">
                      {money(b.spent)} / {money(b.amount)}
                    </span>
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
            <Link href="/goals" className="text-sm font-medium text-primary hover:underline">All goals</Link>
          </CardHeader>
          <CardContent className="space-y-4">
            {data.goals.length === 0 ? (
              <EmptyState icon={<PiggyBank className="h-5 w-5" />} title="No goals yet" />
            ) : (
              data.goals.map((g) => (
                <div key={g.id}>
                  <div className="mb-1 flex items-center justify-between text-sm">
                    <span className="font-medium">{g.name}</span>
                    <span className="tabular-nums text-muted">{g.pct}%</span>
                  </div>
                  <ProgressBar value={g.pct} tone="success" />
                  <p className="mt-1 text-xs text-muted">
                    {money(g.saved)} of {money(g.targetAmount)}
                  </p>
                </div>
              ))
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Upcoming & unnecessary</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="rounded-lg border border-border bg-surface-muted/40 p-3">
              <div className="flex items-center gap-2 text-sm">
                <Flame className="h-4 w-4 text-orange-500" />
                <span className="font-medium">Unnecessary this month</span>
              </div>
              <p className="mt-1 text-xl font-bold tabular-nums">{money(data.unnecessary.total)}</p>
              {data.unnecessary.deltaPct !== null && (
                <p className="text-xs text-muted">
                  {data.unnecessary.deltaPct >= 0 ? '↑' : '↓'} {Math.abs(data.unnecessary.deltaPct)}% vs last month
                </p>
              )}
            </div>
            <div>
              <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted">Upcoming (7 days)</p>
              {data.upcomingRecurring.length === 0 ? (
                <p className="text-sm text-muted">Nothing scheduled.</p>
              ) : (
                <ul className="space-y-2">
                  {data.upcomingRecurring.map((r) => {
                    const Icon = financeIcon(r.category?.icon);
                    return (
                      <li key={r.id} className="flex items-center gap-2 text-sm">
                        <Icon className="h-4 w-4 text-muted" />
                        <span className="flex-1 truncate">{r.name}</span>
                        <span className="tabular-nums text-muted">{money(r.amount)}</span>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          </CardContent>
        </Card>
      </div>

      <Link
        href="/analytics"
        className="mt-6 flex items-center justify-between rounded-xl border border-border bg-surface px-5 py-4 text-sm font-medium transition-colors hover:bg-surface-muted"
      >
        <span>See full analytics — trends, heatmap, top payees and more</span>
        <ArrowRight className="h-4 w-4" />
      </Link>
    </div>
  );
}
