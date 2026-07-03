'use client';

import { Flame, Zap } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { SpendingStreak } from '@/lib/types';

export function SpendingStreaks({ data, money }: { data: SpendingStreak; money: (v: number | string) => string }) {
  const flames = Math.min(5, Math.ceil(data.currentDays / 2));

  return (
    <div className="card p-5">
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium text-muted">Spending streak</p>
        <span className="text-xs font-semibold text-primary">{data.label}</span>
      </div>

      <div className="mt-4 flex items-end gap-3">
        <p className="text-4xl font-bold tabular-nums text-primary">{data.currentDays}</p>
        <div>
          <p className="text-sm font-medium">days under pace</p>
          <p className="text-xs text-muted">≤ {money(data.avgDailyLimit)}/day avg</p>
        </div>
      </div>

      <div className="mt-4 flex gap-1">
        {Array.from({ length: 5 }).map((_, i) => (
          <div
            key={i}
            className={cn(
              'flex h-8 flex-1 items-center justify-center rounded-lg transition-colors',
              i < flames ? 'bg-primary/15 text-primary' : 'bg-surface-muted text-muted/40',
            )}
          >
            {i < flames ? <Flame className="h-4 w-4" /> : <Zap className="h-3.5 w-3.5" />}
          </div>
        ))}
      </div>

      {data.currentDays === 0 && (
        <p className="mt-3 text-xs text-muted">Stay under your daily average to build a streak.</p>
      )}
    </div>
  );
}
