'use client';

import Link from 'next/link';
import useSWR from 'swr';
import { Wallet } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { StatusBadge } from '@/components/ui/badge';
import { EmptyState, PageHeader, ProgressBar, Skeleton } from '@/components/ui/misc';
import { formatMoney } from '@/lib/format';
import type { ProjectStatus } from '@/lib/types';

interface OverviewRow {
  id: string;
  title: string;
  status: ProjectStatus;
  currency: string;
  lines: number;
  planned: string;
  spent: string;
  remaining: string;
  utilization: number;
}

interface Overview {
  rows: OverviewRow[];
  totals: { planned: string; spent: string };
}

export default function BudgetPage() {
  const { data, isLoading } = useSWR<Overview>('/budget-overview');

  const totalPlanned = Number(data?.totals.planned ?? 0);
  const totalSpent = Number(data?.totals.spent ?? 0);
  const utilization = totalPlanned > 0 ? Math.round((totalSpent / totalPlanned) * 100) : 0;

  return (
    <div>
      <PageHeader title="Budget" description="Planned versus approved spend across all projects." />

      <div className="mb-6 grid gap-4 sm:grid-cols-3">
        <SummaryCard label="Total planned" value={isLoading ? null : formatMoney(totalPlanned, 'ETB')} />
        <SummaryCard label="Total spent" value={isLoading ? null : formatMoney(totalSpent, 'ETB')} accent="text-emerald-500" />
        <SummaryCard
          label="Overall utilisation"
          value={isLoading ? null : `${utilization}%`}
        />
      </div>

      {isLoading ? (
        <Skeleton className="h-64 w-full" />
      ) : !data?.rows.length ? (
        <EmptyState
          icon={<Wallet className="h-6 w-6" />}
          title="No budgets yet"
          description="Open a project and add budget lines to see the portfolio view here."
        />
      ) : (
        <Card>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left text-xs uppercase tracking-wide text-muted">
                  <th className="px-5 py-3 font-medium">Project</th>
                  <th className="px-5 py-3 font-medium">Status</th>
                  <th className="px-5 py-3 text-right font-medium">Planned</th>
                  <th className="px-5 py-3 text-right font-medium">Spent</th>
                  <th className="hidden px-5 py-3 font-medium md:table-cell">Utilisation</th>
                </tr>
              </thead>
              <tbody>
                {data.rows.map((r) => (
                  <tr key={r.id} className="border-b border-border last:border-0 hover:bg-surface-muted/50">
                    <td className="px-5 py-3">
                      <Link href={`/projects/${r.id}`} className="font-medium hover:text-primary">
                        {r.title}
                      </Link>
                      <div className="text-xs text-muted">{r.lines} budget lines</div>
                    </td>
                    <td className="px-5 py-3">
                      <StatusBadge.Project status={r.status} />
                    </td>
                    <td className="px-5 py-3 text-right tabular-nums">{formatMoney(r.planned, r.currency)}</td>
                    <td className="px-5 py-3 text-right tabular-nums text-emerald-500">
                      {formatMoney(r.spent, r.currency)}
                    </td>
                    <td className="hidden px-5 py-3 md:table-cell">
                      <div className="flex items-center gap-2">
                        <div className="w-28">
                          <ProgressBar
                            value={r.utilization}
                            tone={r.utilization > 90 ? 'danger' : r.utilization > 70 ? 'warning' : 'primary'}
                          />
                        </div>
                        <span className="w-10 text-xs tabular-nums text-muted">{r.utilization}%</span>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}
    </div>
  );
}

function SummaryCard({ label, value, accent }: { label: string; value: string | null; accent?: string }) {
  return (
    <Card>
      <CardContent>
        <div className="text-xs text-muted">{label}</div>
        <div className={`mt-1.5 text-2xl font-bold ${accent ?? ''}`}>
          {value === null ? <Skeleton className="h-7 w-24" /> : value}
        </div>
      </CardContent>
    </Card>
  );
}
