'use client';

import { AlertTriangle, Gauge, TrendingUp } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { MonthSummary } from '@/lib/types';

interface SpendingPaceProps {
  month: MonthSummary;
  money: (v: number | string) => string;
}

export function SpendingPace({ month, money }: SpendingPaceProps) {
  const now = new Date();
  const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
  const dayOfMonth = now.getDate();
  const pctThroughMonth = (dayOfMonth / daysInMonth) * 100;

  const expense = Number(month.expense);
  const avgDaily = Number(month.avgDailySpend);
  const projectedTotal = avgDaily * daysInMonth;
  const expectedAtPace = (expense / dayOfMonth) * daysInMonth;

  const paceRatio = dayOfMonth > 0 ? expense / (avgDaily * dayOfMonth || 1) : 1;
  const isAhead = paceRatio > 1.1;
  const isOnTrack = paceRatio >= 0.85 && paceRatio <= 1.1;

  let status = 'On track';
  let statusColor = 'text-primary';
  let barColor = 'bg-primary';
  let Icon = Gauge;

  if (isAhead) {
    status = 'Spending fast';
    statusColor = 'text-warning';
    barColor = 'bg-warning';
    Icon = AlertTriangle;
  } else if (!isOnTrack && paceRatio < 0.85) {
    status = 'Under pace';
    statusColor = 'text-emerald-500';
    barColor = 'bg-emerald-500';
    Icon = TrendingUp;
  }

  return (
    <div className="card p-5">
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium text-muted">Spending pace</p>
        <span className={cn('flex items-center gap-1 text-xs font-semibold', statusColor)}>
          <Icon className="h-3.5 w-3.5" />
          {status}
        </span>
      </div>

      <div className="mt-4">
        <div className="mb-1.5 flex justify-between text-xs text-muted">
          <span>Day {dayOfMonth} of {daysInMonth}</span>
          <span>{Math.round(pctThroughMonth)}% through month</span>
        </div>
        <div className="relative h-2.5 w-full overflow-hidden rounded-full bg-surface-muted">
          <div
            className="absolute inset-y-0 left-0 rounded-full bg-border"
            style={{ width: `${pctThroughMonth}%` }}
          />
          <div
            className={cn('absolute inset-y-0 left-0 rounded-full transition-all duration-700', barColor)}
            style={{ width: `${Math.min(100, (expense / (expectedAtPace || 1)) * pctThroughMonth)}%` }}
          />
        </div>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-3">
        <div className="rounded-lg bg-surface-muted/60 px-3 py-2.5">
          <p className="text-[10px] font-medium uppercase tracking-wide text-muted">Avg / day</p>
          <p className="mt-0.5 text-sm font-bold tabular-nums">{money(avgDaily)}</p>
        </div>
        <div className="rounded-lg bg-surface-muted/60 px-3 py-2.5">
          <p className="text-[10px] font-medium uppercase tracking-wide text-muted">Projected</p>
          <p className="mt-0.5 text-sm font-bold tabular-nums">{money(projectedTotal)}</p>
        </div>
      </div>

      {month.biggestExpense && (
        <p className="mt-3 text-xs text-muted">
          Biggest spend: <span className="font-medium text-foreground">{money(month.biggestExpense.amount)}</span>
          {month.biggestExpense.payee && <> on {month.biggestExpense.payee}</>}
        </p>
      )}
    </div>
  );
}
