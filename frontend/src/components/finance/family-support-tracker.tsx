'use client';

import Link from 'next/link';
import { Heart, TrendingDown, TrendingUp, Users } from 'lucide-react';
import { cn } from '@/lib/utils';
import { formatDate } from '@/lib/format';
import type { FamilySupportStats } from '@/lib/types';

export function FamilySupportTracker({
  data,
  money,
}: {
  data: FamilySupportStats;
  money: (v: number | string) => string;
}) {
  const up = (data.deltaPct ?? 0) > 0;

  return (
    <div className="card overflow-hidden">
      <div className="flex items-center gap-3 border-b border-border bg-gradient-to-r from-violet-500/10 to-purple-500/5 px-5 py-4">
        <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-violet-500/15 text-violet-600 dark:text-violet-400">
          <Users className="h-5 w-5" />
        </span>
        <div>
          <p className="font-semibold">Family support & remittances</p>
          <p className="text-xs text-muted">Tracking {data.category?.name ?? 'Family Support'} category</p>
        </div>
      </div>

      <div className="p-5">
        <div className="flex items-end justify-between">
          <div>
            <p className="text-3xl font-bold tabular-nums">{money(data.total)}</p>
            <p className="text-sm text-muted">this month · {data.count} transfer{data.count !== 1 ? 's' : ''}</p>
          </div>
          {data.deltaPct !== null && (
            <span className={cn('flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold', up ? 'bg-warning/10 text-warning' : 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400')}>
              {up ? <TrendingUp className="h-3.5 w-3.5" /> : <TrendingDown className="h-3.5 w-3.5" />}
              {Math.abs(data.deltaPct)}% vs last month
            </span>
          )}
        </div>

        <p className="mt-2 text-xs text-muted">
          Last month: {money(data.prevTotal)}
          {Number(data.total) > Number(data.prevTotal) && (
            <span className="ml-1 text-warning">- consider budgeting remittances</span>
          )}
        </p>

        {data.recent.length > 0 && (
          <ul className="mt-4 space-y-2 border-t border-border pt-4">
            {data.recent.map((t) => (
              <li key={t.id} className="flex items-center justify-between text-sm">
                <span className="flex items-center gap-2 truncate">
                  <Heart className="h-3.5 w-3.5 shrink-0 text-violet-500" />
                  {t.payee || t.note || 'Remittance'}
                </span>
                <span className="shrink-0 tabular-nums text-muted">
                  {money(t.amount)} · {formatDate(t.date)}
                </span>
              </li>
            ))}
          </ul>
        )}

        <Link href="/transactions" className="mt-4 inline-block text-xs font-medium text-primary hover:underline">
          View all family support transactions →
        </Link>
      </div>
    </div>
  );
}
