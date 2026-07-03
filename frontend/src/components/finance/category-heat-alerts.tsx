'use client';

import { AlertTriangle, TrendingUp } from 'lucide-react';
import { CategoryBadge } from './category-badge';
import { cn } from '@/lib/utils';
import type { CategoryHeatAlert } from '@/lib/types';

const severityStyle = {
  high: 'border-danger/30 bg-danger/5',
  medium: 'border-warning/30 bg-warning/5',
  low: 'border-border bg-surface-muted/40',
};

export function CategoryHeatAlerts({
  alerts,
  money,
}: {
  alerts: CategoryHeatAlert[];
  money: (v: number | string) => string;
}) {
  if (alerts.length === 0) {
    return (
      <div className="card p-5">
        <p className="text-sm font-medium text-muted">Category heat alerts</p>
        <p className="mt-3 text-sm text-muted">No unusual spikes vs last month. Spending looks steady.</p>
      </div>
    );
  }

  return (
    <div className="card p-5">
      <div className="mb-4 flex items-center gap-2">
        <AlertTriangle className="h-4 w-4 text-warning" />
        <p className="text-sm font-medium">Category heat alerts</p>
      </div>
      <ul className="space-y-2">
        {alerts.map((a) => (
          <li
            key={a.category?.id ?? a.amount}
            className={cn('flex items-center justify-between rounded-xl border px-3 py-2.5', severityStyle[a.severity])}
          >
            <div className="flex items-center gap-2">
              {a.category && <CategoryBadge category={a.category} />}
              <span className="text-xs text-muted">{money(a.amount)}</span>
            </div>
            <span className={cn('flex items-center gap-0.5 text-xs font-semibold', a.severity === 'high' ? 'text-danger' : 'text-warning')}>
              <TrendingUp className="h-3 w-3" /> +{a.deltaPct}%
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
