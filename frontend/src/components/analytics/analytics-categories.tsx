'use client';

import { useState } from 'react';
import useSWR from 'swr';
import { ArrowDownRight, ArrowUpRight, PieChart, Store } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/misc';
import { InfoHint } from '@/components/ui/info-hint';
import { Donut } from '@/components/charts/donut';
import { financeIcon } from '@/components/finance/icons';
import { useMoney } from '@/lib/amount-visibility';
import { formatMonth } from '@/lib/format';
import { cn } from '@/lib/utils';
import type { CategoryMovers, CategoryTotals, TopPayees } from '@/lib/types';

/** First and last day of a YYYY-MM, as the API expects them. */
function monthBounds(month: string) {
  const [y, m] = month.split('-').map(Number);
  const from = new Date(Date.UTC(y!, (m ?? 1) - 1, 1));
  const to = new Date(Date.UTC(y!, m ?? 1, 0));
  return { from: from.toISOString().slice(0, 10), to: to.toISOString().slice(0, 10) };
}

/**
 * Where the money went, and    more usefully    what changed. The breakdown says
 * what is big; the movers say what is different, which is the part you can act
 * on before it becomes a habit.
 */
export function AnalyticsCategories({ month, currency }: { month: string; currency: string }) {
  const { money } = useMoney();
  const [kind, setKind] = useState<'EXPENSE' | 'INCOME'>('EXPENSE');
  const { from, to } = monthBounds(month);
  const cur = encodeURIComponent(currency);

  const { data: totals } = useSWR<CategoryTotals>(
    `/analytics/categories?kind=${kind}&from=${from}&to=${to}&currency=${cur}`,
  );
  const { data: movers } = useSWR<CategoryMovers>(
    `/analytics/movers?month=${month}&currency=${cur}`,
  );
  const { data: payees } = useSWR<TopPayees>(
    `/analytics/payees?limit=6&from=${from}&to=${to}&currency=${cur}`,
  );

  if (!totals) return <Skeleton className="h-80 rounded-2xl" />;

  const slices = totals.items.slice(0, 8).map((i) => ({
    label: i.category?.name ?? 'Uncategorised',
    value: Number(i.amount),
    color: i.category?.color ?? '#94a3b8',
  }));

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="flex items-center gap-2 text-sm font-semibold">
          <PieChart className="h-4 w-4 text-muted" />
          {formatMonth(month)} by category
          <InfoHint label="About the breakdown">
            Only the month in view, in {currency}. Transfers never appear    they have no category
            and move money between your own accounts rather than in or out.
          </InfoHint>
        </h2>
        <div className="flex items-center gap-1 rounded-xl border border-border bg-surface-muted/40 p-1">
          {(['EXPENSE', 'INCOME'] as const).map((k) => (
            <button
              key={k}
              type="button"
              onClick={() => setKind(k)}
              className={cn(
                'rounded-lg px-3 py-1.5 text-xs font-semibold capitalize transition-all',
                kind === k ? 'bg-foreground text-background shadow-sm' : 'text-muted hover:text-foreground',
              )}
            >
              {k === 'EXPENSE' ? 'Spending' : 'Income'}
            </button>
          ))}
        </div>
      </div>

      <Card>
        <CardContent className="p-4 sm:p-5">
          {totals.items.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted">
              Nothing {kind === 'EXPENSE' ? 'spent' : 'earned'} this month.
            </p>
          ) : (
            <div className="flex flex-col items-center gap-5 sm:flex-row sm:items-start">
              <Donut
                data={slices}
                format={(v) => money(v)}
                centerLabel={kind === 'EXPENSE' ? 'spent' : 'earned'}
              />
              <ul className="w-full min-w-0 flex-1 space-y-1.5">
                {totals.items.slice(0, 8).map((i) => {
                  const Icon = financeIcon(i.category?.icon);
                  return (
                    <li key={i.category?.id ?? 'none'} className="flex items-center gap-2 text-sm">
                      <Icon
                        className="h-3.5 w-3.5 shrink-0"
                        style={{ color: i.category?.color ?? undefined }}
                      />
                      <span className="min-w-0 flex-1 truncate">
                        {i.category?.name ?? 'Uncategorised'}
                      </span>
                      <span className="shrink-0 tabular-nums">{money(i.amount)}</span>
                      <span className="w-10 shrink-0 text-right text-xs text-muted">{i.pct}%</span>
                    </li>
                  );
                })}
              </ul>
            </div>
          )}
        </CardContent>
      </Card>

      {/* What changed, which is the part worth acting on. */}
      <Card>
        <CardContent className="p-4 sm:p-5">
          <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold">
            What moved since last month
            <InfoHint label="About movers">
              Ranked by how much the amount changed, not by how big it is. A category that doubled
              off a small base is news; a large steady one is just the cost of living.
            </InfoHint>
          </h3>

          {!movers ? (
            <Skeleton className="h-24" />
          ) : !movers.hasPrevious ? (
            <p className="text-sm text-muted">
              No spending last month to compare against    this is your first month of history here.
            </p>
          ) : movers.up.length === 0 && movers.down.length === 0 ? (
            <p className="text-sm text-muted">Spending was flat across every category.</p>
          ) : (
            <div className="grid gap-4 sm:grid-cols-2">
              <MoverList title="Up" items={movers.up} tone="up" />
              <MoverList title="Down" items={movers.down} tone="down" />
            </div>
          )}
        </CardContent>
      </Card>

      {payees && payees.items.length > 0 && (
        <Card>
          <CardContent className="p-4 sm:p-5">
            <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold">
              <Store className="h-4 w-4 text-muted" />
              Who you paid most
              <InfoHint label="About payees">
                Only transactions where you filled in a payee. Blank ones are left out rather than
                lumped into an &quot;unknown&quot; bucket that would outrank everything.
              </InfoHint>
            </h3>
            <ul className="space-y-1.5">
              {payees.items.map((p) => (
                <li key={p.payee} className="flex items-center justify-between gap-3 text-sm">
                  <span className="min-w-0 truncate">{p.payee}</span>
                  <span className="shrink-0 tabular-nums text-muted">
                    {money(p.total)}
                    <span className="ml-1.5 text-xs">
                      ({p.count}×)
                    </span>
                  </span>
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      )}
    </div>
  );
}

function MoverList({
  title,
  items,
  tone,
}: {
  title: string;
  items: CategoryMovers['up'];
  tone: 'up' | 'down';
}) {
  const { money } = useMoney();
  const up = tone === 'up';
  const Icon = up ? ArrowUpRight : ArrowDownRight;

  return (
    <div>
      <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted">{title}</p>
      {items.length === 0 ? (
        <p className="text-xs text-muted">Nothing {up ? 'rose' : 'fell'}.</p>
      ) : (
        <ul className="space-y-1.5">
          {items.map((m) => (
            <li key={m.category?.id ?? 'none'} className="flex items-center justify-between gap-2 text-sm">
              <span className="min-w-0 flex-1 truncate">
                {m.category?.name ?? 'Uncategorised'}
                {m.isNew && (
                  <span className="ml-1.5 rounded-full bg-primary/10 px-1.5 py-0.5 text-[10px] font-semibold text-primary">
                    new
                  </span>
                )}
                {m.stopped && (
                  <span className="ml-1.5 rounded-full bg-surface-muted px-1.5 py-0.5 text-[10px] font-semibold text-muted">
                    stopped
                  </span>
                )}
              </span>
              <span
                className={cn(
                  'inline-flex shrink-0 items-center gap-0.5 text-xs font-semibold tabular-nums',
                  up ? 'text-rose-600 dark:text-rose-400' : 'text-emerald-600 dark:text-emerald-400',
                )}
              >
                <Icon className="h-3 w-3" />
                {money(Math.abs(Number(m.change)))}
                {m.changePct !== null && <span className="text-muted"> ({Math.abs(m.changePct)}%)</span>}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
