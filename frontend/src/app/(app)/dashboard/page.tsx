'use client';

import useSWR from 'swr';
import Link from 'next/link';
import { ArrowRight, Flame, Lightbulb, PiggyBank, Sparkles, TrendingDown, TrendingUp } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { PageHeader, ProgressBar, Skeleton, EmptyState } from '@/components/ui/misc';
import { Donut } from '@/components/charts/donut';
import { HeroBalance } from '@/components/finance/hero-balance';
import { FinancialHealth } from '@/components/finance/financial-health';
import { SpendingPace } from '@/components/finance/spending-pace';
import { QuickActions } from '@/components/finance/quick-actions';
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
    insights.push(`${money(data.unnecessary.total)} went to "unnecessary" spending. That's money you could redirect to goals.`);
  }

  if (data.goals.some((g) => g.pct >= 100)) {
    insights.push('Congratulations! You hit a savings goal. 🎉');
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
        <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
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
    <div className="animate-in space-y-6">
      <QuickActions />

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <HeroBalance data={data} money={money} userName={firstName} />
        </div>
        <FinancialHealth data={data} />
      </div>

      <SmartInsight data={data} money={money} />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4 stagger-children">
        <StatMini
          label="Net this month"
          value={money(data.month.net)}
          icon={<TrendingUp className="h-4 w-4" />}
          positive={Number(data.month.net) >= 0}
        />
        <StatMini
          label="Avg daily spend"
          value={money(data.month.avgDailySpend)}
          icon={<TrendingDown className="h-4 w-4" />}
        />
        <StatMini
          label="Unnecessary"
          value={money(data.unnecessary.total)}
          icon={<Flame className="h-4 w-4" />}
          warning={Number(data.unnecessary.total) > 0}
        />
        <StatMini
          label="Upcoming bills"
          value={String(data.upcomingRecurring.length)}
          icon={<PiggyBank className="h-4 w-4" />}
          hint="next 7 days"
        />
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <SpendingPace month={data.month} money={money} />

        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Top spending</CardTitle>
            <Link href="/analytics" className="text-xs font-medium text-primary hover:underline">
              Full analytics →
            </Link>
          </CardHeader>
          <CardContent>
            {donutData.length === 0 ? (
              <EmptyState title="No spending yet" description="Your category breakdown will appear here." />
            ) : (
              <Donut data={donutData} format={(v) => money(v)} centerLabel="spent" />
            )}
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 lg:grid-cols-5">
        <Card className="lg:col-span-3">
          <CardHeader>
            <CardTitle>Recent transactions</CardTitle>
            <Link href="/transactions" className="text-xs font-medium text-primary hover:underline">
              View all →
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
                      <span className="tabular-nums text-xs text-muted">
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
              <Link href="/goals" className="text-xs font-medium text-primary hover:underline">All goals</Link>
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
                    <p className="mt-1 text-xs text-muted">
                      {money(g.saved)} of {money(g.targetAmount)}
                    </p>
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
            <Link href="/recurring" className="text-xs font-medium text-primary hover:underline">Manage</Link>
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
        href="/assistant"
        className="group flex items-center justify-between rounded-2xl border border-border bg-gradient-to-r from-primary/5 via-transparent to-accent/5 px-6 py-5 transition-all hover:border-primary/30 hover:shadow-md"
      >
        <div className="flex items-center gap-4">
          <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-primary/10 text-primary">
            <Sparkles className="h-5 w-5" />
          </span>
          <div>
            <p className="font-semibold">Ask your AI money assistant</p>
            <p className="text-sm text-muted">Get personalized insights about your spending habits</p>
          </div>
        </div>
        <ArrowRight className="h-5 w-5 text-muted transition-transform group-hover:translate-x-1 group-hover:text-primary" />
      </Link>
    </div>
  );
}

function StatMini({
  label,
  value,
  icon,
  hint,
  positive,
  warning,
}: {
  label: string;
  value: string;
  icon: React.ReactNode;
  hint?: string;
  positive?: boolean;
  warning?: boolean;
}) {
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
