'use client';

import useSWR from 'swr';
import { BookOpen, Quote, TrendingDown } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { PageHeader, Skeleton } from '@/components/ui/misc';
import { BurnRateChart } from '@/components/charts/burn-rate';
import { BarChart } from '@/components/charts/bar';
import { NetworkGraph } from '@/components/charts/network';

interface BurnRate {
  points: { date: string; cumulative: number }[];
  totalPlanned: number;
  currency: string;
}
interface Impact {
  totals: { publications: number; citations: number };
  byYear: { year: string; count: number }[];
  recent: { title: string; journal: string | null; citations: number; project: string }[];
}
interface NetworkData {
  nodes: { id: string; label: string; type: 'member' | 'project'; status?: string }[];
  links: { source: string; target: string }[];
}

export default function InsightsPage() {
  const { data: burn } = useSWR<BurnRate>('/insights/burn-rate');
  const { data: impact } = useSWR<Impact>('/insights/impact');
  const { data: network } = useSWR<NetworkData>('/insights/network');

  return (
    <div>
      <PageHeader title="Insights" description="Forecasts, impact metrics and how your collaborators connect." />

      <div className="grid gap-6 lg:grid-cols-2">
        {/* Burn-rate forecast */}
        <Card>
          <CardHeader>
            <CardTitle>Budget burn-rate forecast</CardTitle>
            <TrendingDown className="h-5 w-5 text-muted" />
          </CardHeader>
          <CardContent>
            {!burn ? (
              <Skeleton className="h-56 w-full" />
            ) : (
              <BurnRateChart points={burn.points} totalPlanned={burn.totalPlanned} currency={burn.currency} />
            )}
          </CardContent>
        </Card>

        {/* Research impact */}
        <Card>
          <CardHeader>
            <CardTitle>Research impact</CardTitle>
            <BookOpen className="h-5 w-5 text-muted" />
          </CardHeader>
          <CardContent>
            {!impact ? (
              <Skeleton className="h-56 w-full" />
            ) : (
              <>
                <div className="mb-4 grid grid-cols-2 gap-3">
                  <div className="rounded-lg bg-surface-muted p-3">
                    <div className="text-xs text-muted">Publications</div>
                    <div className="mt-0.5 text-2xl font-bold">{impact.totals.publications}</div>
                  </div>
                  <div className="rounded-lg bg-surface-muted p-3">
                    <div className="flex items-center gap-1 text-xs text-muted">
                      <Quote className="h-3 w-3" /> Citations
                    </div>
                    <div className="mt-0.5 text-2xl font-bold">{impact.totals.citations}</div>
                  </div>
                </div>
                {impact.byYear.length > 0 ? (
                  <BarChart data={impact.byYear.map((y) => ({ label: y.year, value: y.count }))} color="var(--accent)" />
                ) : (
                  <p className="py-6 text-center text-sm text-muted">No dated publications yet.</p>
                )}
              </>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Collaboration network */}
      <Card className="mt-6">
        <CardHeader>
          <div>
            <CardTitle>Collaboration network</CardTitle>
            <p className="mt-1 text-sm text-muted">Who works on what across your workspace.</p>
          </div>
          <div className="flex items-center gap-3 text-xs text-muted">
            <span className="flex items-center gap-1.5">
              <span className="h-2.5 w-2.5 rounded-full bg-primary" /> Member
            </span>
            <span className="flex items-center gap-1.5">
              <span className="h-2.5 w-2.5 rounded-full bg-accent" /> Project
            </span>
          </div>
        </CardHeader>
        <CardContent>
          {!network ? <Skeleton className="h-80 w-full" /> : <NetworkGraph nodes={network.nodes} links={network.links} />}
        </CardContent>
      </Card>

      {impact?.recent && impact.recent.length > 0 && (
        <Card className="mt-6">
          <CardHeader>
            <CardTitle>Recent publications</CardTitle>
          </CardHeader>
          <CardContent className="space-y-1 pt-0">
            {impact.recent.map((p, i) => (
              <div key={i} className="flex items-center justify-between gap-3 rounded-lg px-3 py-2.5 hover:bg-surface-muted">
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium">{p.title}</p>
                  <p className="truncate text-xs text-muted">
                    {p.journal ?? 'Unpublished'} · {p.project}
                  </p>
                </div>
                <span className="flex shrink-0 items-center gap-1 text-xs text-muted">
                  <Quote className="h-3 w-3" /> {p.citations}
                </span>
              </div>
            ))}
          </CardContent>
        </Card>
      )}
    </div>
  );
}
