'use client';

import { CalendarDays, Minus, TrendingDown, TrendingUp } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { MoneyFormatOpts } from '@/lib/format';
import type { WeeklySnapshot as WeeklySnapshotData } from '@/lib/types';

type Money = (v: number | string, opts?: MoneyFormatOpts) => string;

const dayRange = (start: string, end: string) => {
  const fmt = (d: string) =>
    new Date(d).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  const last = new Date(new Date(end).getTime() - 86_400_000).toISOString();
  return `${fmt(start)} - ${fmt(last)}`;
};

/**
 * This week against last week, from the stored Sunday-boundary snapshots.
 * Amounts use compact notation so a long figure cannot push past the card;
 * the exact value is always in the tooltip.
 */
export function WeeklySnapshot({ data, money }: { data: WeeklySnapshotData; money: Money }) {
  const { current, previous, delta } = data;
  const spentMore = Number(delta.expenseAmount) > 0;
  const netUp = Number(delta.netAmount) >= 0;

  // Bar widths compare the two weeks against whichever spent more.
  const peak = Math.max(Number(current.expense), Number(previous.expense), 1);
  const pct = (v: string) => Math.max(2, Math.round((Number(v) / peak) * 100));

  return (
    <div className="card flex flex-col p-5">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-sm font-medium text-muted">Weekly snapshot</p>
          <p className="mt-0.5 truncate text-[10px] text-muted">
            {dayRange(current.weekStart, current.weekEnd)}
          </p>
        </div>
        <CalendarDays className="h-4 w-4 shrink-0 text-muted" />
      </div>

      <div className="mt-4 space-y-2">
        <Row
          label="Income"
          value={current.income}
          money={money}
          deltaPct={delta.income}
          good={(d) => d >= 0}
        />
        <Row
          label="Spent"
          value={current.expense}
          money={money}
          deltaPct={delta.expense}
          good={(d) => d <= 0}
        />
        <Row
          label="Net"
          value={current.net}
          money={money}
          emphasise
          tone={Number(current.net) >= 0 ? 'good' : 'bad'}
        />
      </div>

      {/* This week vs last, on the same scale. */}
      <div className="mt-4 space-y-1.5 border-t border-border pt-3">
        <Bar label="This week" value={current.expense} pct={pct(current.expense)} money={money} active />
        <Bar label="Last week" value={previous.expense} pct={pct(previous.expense)} money={money} />
      </div>

      <p className="mt-3 text-[11px] leading-snug text-muted">
        {Number(previous.expense) === 0 && Number(current.expense) === 0 ? (
          'No spending either week.'
        ) : (
          <>
            You have spent{' '}
            <strong className={cn(spentMore ? 'text-warning' : 'text-emerald-500')}>
              {money(Math.abs(Number(delta.expenseAmount)), { compact: true })} {spentMore ? 'more' : 'less'}
            </strong>{' '}
            than last week
            {current.topCategory && <> · mostly {current.topCategory}</>}
          </>
        )}
      </p>

      {!netUp && Number(previous.net) > 0 && (
        <p className="mt-1 text-[11px] text-muted">
          Net is down {money(Math.abs(Number(delta.netAmount)), { compact: true })} on last week.
        </p>
      )}
    </div>
  );
}

function Row({
  label,
  value,
  money,
  deltaPct,
  good,
  emphasise,
  tone,
}: {
  label: string;
  value: string;
  money: Money;
  deltaPct?: number | null;
  good?: (d: number) => boolean;
  emphasise?: boolean;
  tone?: 'good' | 'bad';
}) {
  const full = money(value, { decimals: true });
  const positive = deltaPct != null && good ? good(deltaPct) : undefined;

  return (
    <div className="flex items-center justify-between gap-2 rounded-xl bg-surface-muted/60 px-3 py-2">
      <span className="shrink-0 text-[10px] font-medium uppercase tracking-wide text-muted">
        {label}
      </span>
      <span className="flex min-w-0 items-baseline gap-1.5">
        <span
          title={full}
          className={cn(
            'truncate font-bold tabular-nums',
            emphasise ? 'text-base' : 'text-sm',
            tone === 'good' && 'text-emerald-500',
            tone === 'bad' && 'text-red-500',
          )}
        >
          {money(value, { compact: true })}
        </span>
        {deltaPct != null && (
          <span
            className={cn(
              'flex shrink-0 items-center gap-0.5 text-[10px] font-medium',
              positive ? 'text-emerald-500' : 'text-warning',
            )}
          >
            {deltaPct === 0 ? (
              <Minus className="h-2.5 w-2.5" />
            ) : deltaPct > 0 ? (
              <TrendingUp className="h-2.5 w-2.5" />
            ) : (
              <TrendingDown className="h-2.5 w-2.5" />
            )}
            {Math.abs(deltaPct)}%
          </span>
        )}
      </span>
    </div>
  );
}

function Bar({
  label,
  value,
  pct,
  money,
  active,
}: {
  label: string;
  value: string;
  pct: number;
  money: Money;
  active?: boolean;
}) {
  return (
    <div className="flex items-center gap-2">
      <span className="w-16 shrink-0 text-[10px] text-muted">{label}</span>
      <span className="h-1.5 min-w-0 flex-1 overflow-hidden rounded-full bg-surface-muted">
        <span
          className={cn(
            'block h-full rounded-full transition-all duration-700',
            active ? 'bg-primary' : 'bg-muted/40',
          )}
          style={{ width: `${pct}%` }}
        />
      </span>
      <span
        title={money(value, { decimals: true })}
        className="w-16 shrink-0 truncate text-right text-[10px] font-medium tabular-nums"
      >
        {money(value, { compact: true })}
      </span>
    </div>
  );
}
