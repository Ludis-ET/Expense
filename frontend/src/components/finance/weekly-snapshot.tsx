'use client';

import { CalendarDays, TrendingDown, TrendingUp } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { WeeklySnapshot } from '@/lib/types';

export function WeeklySnapshot({ data, money }: { data: WeeklySnapshot; money: (v: number | string) => string }) {
  return (
    <div className="card p-5">
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium text-muted">Weekly snapshot</p>
        <CalendarDays className="h-4 w-4 text-muted" />
      </div>
      <p className="mt-1 text-[10px] text-muted">Since {new Date(data.weekStart).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}</p>

      <div className="mt-4 grid grid-cols-3 gap-2">
        <div className="rounded-xl bg-surface-muted/60 p-3">
          <p className="text-[10px] font-medium uppercase tracking-wide text-muted">Income</p>
          <p className="mt-1 text-lg font-bold tabular-nums">{money(data.income)}</p>
          {data.incomeDeltaPct !== null && (
            <p className={cn('mt-0.5 flex items-center gap-0.5 text-[10px] font-medium', data.incomeDeltaPct >= 0 ? 'text-emerald-500' : 'text-red-500')}>
              <TrendingUp className="h-3 w-3" /> {data.incomeDeltaPct >= 0 ? '+' : ''}{data.incomeDeltaPct}%
            </p>
          )}
        </div>
        <div className="rounded-xl bg-surface-muted/60 p-3">
          <p className="text-[10px] font-medium uppercase tracking-wide text-muted">Spent</p>
          <p className="mt-1 text-lg font-bold tabular-nums">{money(data.expense)}</p>
          {data.expenseDeltaPct !== null && (
            <p className={cn('mt-0.5 flex items-center gap-0.5 text-[10px] font-medium', data.expenseDeltaPct <= 0 ? 'text-emerald-500' : 'text-warning')}>
              <TrendingDown className="h-3 w-3" /> {data.expenseDeltaPct >= 0 ? '+' : ''}{data.expenseDeltaPct}%
            </p>
          )}
        </div>
        <div className="rounded-xl bg-surface-muted/60 p-3">
          <p className="text-[10px] font-medium uppercase tracking-wide text-muted">Net</p>
          <p className={cn('mt-1 text-lg font-bold tabular-nums', Number(data.net) >= 0 ? 'text-emerald-500' : 'text-red-500')}>
            {money(data.net)}
          </p>
        </div>
      </div>
    </div>
  );
}
