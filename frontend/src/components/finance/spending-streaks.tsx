'use client';

import { useMemo, useState } from 'react';
import useSWR from 'swr';
import {
  CalendarRange,
  ChevronLeft,
  ChevronRight,
  Flame,
  Maximize2,
  TrendingDown,
  X,
} from 'lucide-react';
import { Skeleton } from '@/components/ui/misc';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type { DailySpending, SpendDay, SpendingStreak } from '@/lib/types';

/** Colour a day by how it sits against the pace. */
function dayTone(d: SpendDay): string {
  if (!d.spent) return 'bg-surface-muted';
  return d.under ? 'bg-emerald-500/70' : 'bg-amber-500/80';
}

function dayTitle(d: SpendDay, money: (v: string | number) => string): string {
  const when = new Date(d.date).toLocaleDateString(undefined, {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  });
  if (!d.spent) return `${when}: nothing spent`;
  return `${when}: ${money(d.amount)}${d.under ? ' (under pace)' : ' (over pace)'}`;
}

/**
 * Average daily spend front and centre, then the streak, then the whole window
 * as a strip - broken days included, so the run reads honestly.
 */
export function SpendingStreaks({ data }: { data: SpendingStreak }) {
  const { money } = useMoney();
  const [open, setOpen] = useState(false);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="card group w-full p-5 text-left transition-all hover:-translate-y-0.5 hover:shadow-md"
      >
        <div className="flex items-start justify-between gap-2">
          <p className="text-sm font-medium text-muted">Daily spending</p>
          <Maximize2 className="h-3.5 w-3.5 shrink-0 text-muted opacity-0 transition-opacity group-hover:opacity-100" />
        </div>

        <p
          title={money(data.avgDailySpend)}
          className="mt-2 truncate text-3xl font-bold tabular-nums"
        >
          {money(data.avgDailySpend, { compact: true })}
        </p>
        <p className="text-xs text-muted">average a day over {data.dayCount} days</p>

        <div className="mt-3 flex items-center gap-2">
          <span
            className={cn(
              'inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold',
              data.currentDays > 0
                ? 'bg-emerald-500/12 text-emerald-600 dark:text-emerald-400'
                : 'bg-surface-muted text-muted',
            )}
          >
            <Flame className="h-3.5 w-3.5" />
            {data.currentDays} day streak
          </span>
          <span className="truncate text-xs text-muted">{data.label}</span>
        </div>

        {/* The full window, one cell a day. */}
        <div className="mt-4 flex items-end gap-[3px]">
          {data.days.map((d) => (
            <span
              key={d.date}
              title={dayTitle(d, money)}
              className={cn('h-7 min-w-0 flex-1 rounded-sm transition-colors', dayTone(d))}
            />
          ))}
        </div>
        <div className="mt-1.5 flex items-center justify-between text-[10px] text-muted">
          <span>{data.daysUnder} days under pace</span>
          <span>best {data.bestStreak}</span>
        </div>
      </button>

      {open && <SpendingModal onClose={() => setOpen(false)} />}
    </>
  );
}

const monthKey = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;

/** Full-screen breakdown: pick any month, see the stats and the daily graph. */
function SpendingModal({ onClose }: { onClose: () => void }) {
  const { money } = useMoney();
  const [month, setMonth] = useState(() => monthKey(new Date()));

  const { data, isLoading } = useSWR<DailySpending>(`/analytics/daily?month=${month}`);

  const [y, m] = month.split('-').map(Number);
  const isCurrentMonth = month === monthKey(new Date());

  function shift(by: number) {
    const d = new Date(Date.UTC(y!, (m ?? 1) - 1 + by, 1));
    if (d.getTime() > Date.now()) return; // never walk into the future
    setMonth(monthKey(new Date(d.getUTCFullYear(), d.getUTCMonth(), 1)));
  }

  const peak = useMemo(
    () => Math.max(1, ...(data?.days ?? []).map((d) => Number(d.amount))),
    [data?.days],
  );

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-background animate-in">
      <header className="flex items-center justify-between gap-3 border-b border-border px-4 py-3 sm:px-6">
        <div className="flex min-w-0 items-center gap-2">
          <CalendarRange className="h-5 w-5 shrink-0 text-primary" />
          <h2 className="truncate text-lg font-bold">Daily spending</h2>
        </div>
        <button
          type="button"
          onClick={onClose}
          aria-label="Close"
          className="rounded-lg p-2 text-muted transition-colors hover:bg-surface-muted hover:text-foreground"
        >
          <X className="h-5 w-5" />
        </button>
      </header>

      <div className="flex-1 overflow-y-auto px-4 py-5 sm:px-6">
        <div className="mx-auto max-w-4xl space-y-6">
          {/* Month navigation */}
          <div className="flex items-center justify-center gap-2">
            <button
              type="button"
              onClick={() => shift(-1)}
              aria-label="Previous month"
              className="rounded-lg border border-border p-2 text-muted transition-colors hover:bg-surface-muted hover:text-foreground"
            >
              <ChevronLeft className="h-4 w-4" />
            </button>
            <p className="min-w-44 text-center text-sm font-semibold">
              {data?.label ?? '…'}
            </p>
            <button
              type="button"
              onClick={() => shift(1)}
              disabled={isCurrentMonth}
              aria-label="Next month"
              className={cn(
                'rounded-lg border border-border p-2 text-muted transition-colors',
                isCurrentMonth ? 'opacity-40' : 'hover:bg-surface-muted hover:text-foreground',
              )}
            >
              <ChevronRight className="h-4 w-4" />
            </button>
          </div>

          {isLoading || !data ? (
            <div className="space-y-4">
              <Skeleton className="h-24" />
              <Skeleton className="h-64" />
            </div>
          ) : data.days.length === 0 ? (
            <p className="py-16 text-center text-sm text-muted">
              Nothing recorded in {data.label}.
            </p>
          ) : (
            <>
              {/* Headline */}
              <div className="rounded-2xl border border-border bg-gradient-to-br from-primary/5 to-transparent p-5">
                <p className="text-xs font-semibold uppercase tracking-widest text-muted">
                  Average a day
                </p>
                <p
                  title={money(data.stats.pace)}
                  className="mt-1 text-4xl font-bold tabular-nums"
                >
                  {money(data.stats.pace, { compact: true })}
                </p>
                <p className="mt-1 text-sm text-muted">
                  {money(data.stats.total, { compact: true })} over {data.stats.dayCount} days
                </p>
              </div>

              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                <Stat
                  label="Current streak"
                  value={`${data.stats.currentStreak}`}
                  sub="days under pace"
                  tone="emerald"
                />
                <Stat
                  label="Best streak"
                  value={`${data.stats.bestStreak}`}
                  sub="in this month"
                  tone="primary"
                />
                <Stat
                  label="Days under"
                  value={`${data.stats.daysUnder} / ${data.stats.dayCount}`}
                  sub={`${data.stats.daysOver} over`}
                />
                <Stat
                  label="No-spend days"
                  value={`${data.stats.noSpendDays}`}
                  sub="nothing went out"
                />
              </div>

              {/* Daily graph */}
              <div className="rounded-2xl border border-border p-4 sm:p-5">
                <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
                  <h3 className="text-sm font-semibold">Every day</h3>
                  <div className="flex flex-wrap items-center gap-3 text-[11px] text-muted">
                    <Legend className="bg-emerald-500/70" label="under pace" />
                    <Legend className="bg-amber-500/80" label="over pace" />
                    <Legend className="bg-surface-muted" label="no spend" />
                  </div>
                </div>

                <div className="relative">
                  {/* The pace line, so "under" is visually obvious. */}
                  <div
                    className="pointer-events-none absolute inset-x-0 border-t border-dashed border-primary/50"
                    style={{ bottom: `${(Number(data.stats.pace) / peak) * 100}%` }}
                  >
                    <span className="absolute -top-4 right-0 rounded bg-primary/10 px-1.5 text-[10px] font-medium text-primary">
                      pace {money(data.stats.pace, { compact: true })}
                    </span>
                  </div>

                  <div className="flex h-56 items-end gap-[3px]">
                    {data.days.map((d) => (
                      <div
                        key={d.date}
                        title={dayTitle(d, money)}
                        className="flex h-full min-w-0 flex-1 items-end"
                      >
                        <span
                          className={cn(
                            'w-full rounded-sm transition-all duration-500',
                            dayTone(d),
                          )}
                          style={{
                            height: `${Math.max(2, (Number(d.amount) / peak) * 100)}%`,
                          }}
                        />
                      </div>
                    ))}
                  </div>
                </div>

                <div className="mt-2 flex justify-between text-[10px] text-muted">
                  <span>{new Date(data.start).getDate()}</span>
                  <span>{new Date(data.end).getDate()}</span>
                </div>
              </div>

              {data.stats.biggestDay && Number(data.stats.biggestDay.amount) > 0 && (
                <p className="flex items-center gap-2 rounded-xl bg-surface-muted/50 px-4 py-3 text-sm text-muted">
                  <TrendingDown className="h-4 w-4 shrink-0 text-warning" />
                  Biggest day was{' '}
                  <strong className="text-foreground">
                    {new Date(data.stats.biggestDay.date).toLocaleDateString(undefined, {
                      day: 'numeric',
                      month: 'long',
                    })}
                  </strong>{' '}
                  at{' '}
                  <strong className="text-foreground">
                    {money(data.stats.biggestDay.amount)}
                  </strong>
                  .
                </p>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function Stat({
  label,
  value,
  sub,
  tone,
}: {
  label: string;
  value: string;
  sub: string;
  tone?: 'emerald' | 'primary';
}) {
  return (
    <div className="rounded-2xl border border-border bg-surface p-4">
      <p className="text-xs font-medium uppercase tracking-wide text-muted">{label}</p>
      <p
        className={cn(
          'mt-1 text-2xl font-bold tabular-nums',
          tone === 'emerald' && 'text-emerald-600 dark:text-emerald-400',
          tone === 'primary' && 'text-primary',
        )}
      >
        {value}
      </p>
      <p className="mt-0.5 text-xs text-muted">{sub}</p>
    </div>
  );
}

function Legend({ className, label }: { className: string; label: string }) {
  return (
    <span className="inline-flex items-center gap-1">
      <span className={cn('h-2.5 w-2.5 rounded-sm', className)} />
      {label}
    </span>
  );
}
