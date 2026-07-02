'use client';

import { TrendingDown, TrendingUp } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { cn } from '@/lib/utils';

interface StatCardProps {
  label: string;
  value: string;
  /** Percentage change vs. the previous period; null hides the trend. */
  deltaPct?: number | null;
  /** For spending, an increase is bad — flips the delta color. */
  invertDelta?: boolean;
  icon?: React.ReactNode;
  hint?: string;
}

export function StatCard({ label, value, deltaPct, invertDelta, icon, hint }: StatCardProps) {
  const up = (deltaPct ?? 0) >= 0;
  const good = invertDelta ? !up : up;

  return (
    <Card>
      <CardContent className="p-5">
        <div className="flex items-center justify-between">
          <p className="text-sm text-muted">{label}</p>
          {icon && <span className="text-muted">{icon}</span>}
        </div>
        <p className="mt-1.5 text-2xl font-bold tabular-nums tracking-tight">{value}</p>
        <div className="mt-1 flex items-center gap-2 text-xs">
          {deltaPct !== null && deltaPct !== undefined && (
            <span
              className={cn(
                'inline-flex items-center gap-0.5 font-medium',
                good ? 'text-emerald-600 dark:text-emerald-400' : 'text-red-600 dark:text-red-400',
              )}
            >
              {up ? <TrendingUp className="h-3 w-3" /> : <TrendingDown className="h-3 w-3" />}
              {Math.abs(deltaPct)}%
            </span>
          )}
          {hint && <span className="text-muted">{hint}</span>}
        </div>
      </CardContent>
    </Card>
  );
}
