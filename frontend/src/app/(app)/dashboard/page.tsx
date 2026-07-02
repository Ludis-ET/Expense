'use client';

import Link from 'next/link';
import useSWR from 'swr';
import { BookOpen, Database, FolderKanban, Lightbulb, Receipt, TrendingUp } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { StatusBadge } from '@/components/ui/badge';
import { ProgressBar, Skeleton, PageHeader } from '@/components/ui/misc';
import { Donut, type DonutSlice } from '@/components/charts/donut';
import { AskWidget } from '@/components/ai/ask-widget';
import { CalendarDate } from '@/components/calendar-date';
import { formatMoney, relativeTime } from '@/lib/format';
import { useAuth } from '@/lib/auth';
import type { DashboardStats, ProjectStatus } from '@/lib/types';

const STATUS_COLORS: Record<ProjectStatus, string> = {
  PLANNING: '#0ea5e9',
  ACTIVE: '#10b981',
  ON_HOLD: '#f59e0b',
  COMPLETED: '#6366f1',
  CANCELLED: '#ef4444',
};

export default function DashboardPage() {
  const { user } = useAuth();
  const { data, isLoading } = useSWR<DashboardStats>('/dashboard/stats');

  const statCards = [
    { label: 'Projects', value: data?.counts.projects, icon: FolderKanban, tone: 'text-sky-500' },
    { label: 'Publications', value: data?.counts.publications, icon: BookOpen, tone: 'text-violet-500' },
    { label: 'Datasets', value: data?.counts.datasets, icon: Database, tone: 'text-emerald-500' },
    { label: 'Open ideas', value: data?.counts.openIdeas, icon: Lightbulb, tone: 'text-amber-500' },
    { label: 'Pending expenses', value: data?.counts.pendingExpenses, icon: Receipt, tone: 'text-rose-500' },
  ];

  const donutData: DonutSlice[] =
    data?.projectsByStatus.map((s) => ({
      label: s.status.replace(/_/g, ' ').toLowerCase().replace(/^\w/, (c) => c.toUpperCase()),
      value: s.count,
      color: STATUS_COLORS[s.status],
    })) ?? [];

  const firstName = user?.name?.split(' ')[0] ?? 'there';

  return (
    <div>
      <PageHeader title={`Welcome back, ${firstName}`} description="Here's what's happening across your workspace." />

      <div className="mb-6">
        <AskWidget />
      </div>

      {/* Stat cards */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-5">
        {statCards.map((s) => (
          <Card key={s.label} className="p-4">
            <div className="flex items-center justify-between">
              <s.icon className={`h-5 w-5 ${s.tone}`} />
            </div>
            <div className="mt-3 text-2xl font-bold tabular-nums">
              {isLoading ? <Skeleton className="h-7 w-10" /> : (s.value ?? 0)}
            </div>
            <div className="mt-0.5 text-xs text-muted">{s.label}</div>
          </Card>
        ))}
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-3">
        {/* Budget overview */}
        <Card className="lg:col-span-1">
          <CardHeader>
            <CardTitle>Budget overview</CardTitle>
            <TrendingUp className="h-5 w-5 text-muted" />
          </CardHeader>
          <CardContent className="space-y-5">
            {isLoading || !data ? (
              <Skeleton className="h-32 w-full" />
            ) : (
              <>
                <div>
                  <div className="flex items-baseline justify-between">
                    <span className="text-sm text-muted">Utilisation</span>
                    <span className="text-lg font-bold">{data.budget.utilization}%</span>
                  </div>
                  <div className="mt-2">
                    <ProgressBar
                      value={data.budget.utilization}
                      tone={data.budget.utilization > 90 ? 'danger' : data.budget.utilization > 70 ? 'warning' : 'success'}
                    />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div className="rounded-lg bg-surface-muted p-3">
                    <div className="text-xs text-muted">Planned</div>
                    <div className="mt-1 font-semibold">{formatMoney(data.budget.totalPlanned, 'ETB')}</div>
                  </div>
                  <div className="rounded-lg bg-surface-muted p-3">
                    <div className="text-xs text-muted">Spent</div>
                    <div className="mt-1 font-semibold">{formatMoney(data.budget.totalSpent, 'ETB')}</div>
                  </div>
                </div>
              </>
            )}
          </CardContent>
        </Card>

        {/* Projects by status */}
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>Projects by status</CardTitle>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <Skeleton className="h-40 w-full" />
            ) : donutData.length === 0 ? (
              <p className="py-8 text-center text-sm text-muted">No projects yet.</p>
            ) : (
              <Donut data={donutData} />
            )}
          </CardContent>
        </Card>
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-2">
        {/* Recent projects */}
        <Card>
          <CardHeader>
            <CardTitle>Recent projects</CardTitle>
            <Link href="/projects" className="text-sm text-primary hover:underline">
              View all
            </Link>
          </CardHeader>
          <CardContent className="space-y-1 pt-0">
            {isLoading ? (
              <Skeleton className="h-24 w-full" />
            ) : !data?.recentProjects.length ? (
              <p className="py-6 text-center text-sm text-muted">No projects yet.</p>
            ) : (
              data.recentProjects.map((p) => (
                <Link
                  key={p.id}
                  href={`/projects/${p.id}`}
                  className="flex items-center justify-between rounded-lg px-3 py-2.5 transition-colors hover:bg-surface-muted"
                >
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">{p.title}</p>
                    <p className="text-xs text-muted">Updated {relativeTime(p.updatedAt)}</p>
                  </div>
                  <StatusBadge.Project status={p.status} />
                </Link>
              ))
            )}
          </CardContent>
        </Card>

        {/* Upcoming milestones */}
        <Card>
          <CardHeader>
            <CardTitle>Upcoming milestones</CardTitle>
          </CardHeader>
          <CardContent className="space-y-1 pt-0">
            {isLoading ? (
              <Skeleton className="h-24 w-full" />
            ) : !data?.upcomingMilestones.length ? (
              <p className="py-6 text-center text-sm text-muted">Nothing due soon.</p>
            ) : (
              data.upcomingMilestones.map((m) => (
                <div key={m.id} className="flex items-center justify-between rounded-lg px-3 py-2.5 hover:bg-surface-muted">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium">{m.description}</p>
                    <Link href={`/projects/${m.project.id}`} className="text-xs text-muted hover:text-primary">
                      {m.project.title}
                    </Link>
                  </div>
                  <CalendarDate value={m.dueDate} className="shrink-0 text-xs text-muted" />
                </div>
              ))
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
