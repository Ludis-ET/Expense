'use client';

import { TrendingDown, TrendingUp } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { cn } from '@/lib/utils';

interface StatCardProps {
  label: string;
  value: string;
  deltaPct?: number | null;
  invertDelta?: boolean;
  icon?: React.ReactNode;
  hint?: string;
  accent?: 'default' | 'income' | 'expense' | 'net';
}

const accentStyles = {
  default: 'from-primary/5 to-transparent',
  income: 'from-emerald-500/8 to-transparent',
  expense: 'from-red-500/8 to-transparent',
  net: 'from-teal-500/8 to-transparent',
};

export function StatCard({ label, value, deltaPct, invertDelta, icon, hint, accent = 'default' }: StatCardProps) {
  const up = (deltaPct ?? 0) >= 0;
  const good = invertDelta ? !up : up;

  return (
    <Card className="group overflow-hidden transition-all hover:shadow-md">
      <CardContent className={cn('relative bg-gradient-to-br p-5', accentStyles[accent])}>
        <div className="flex items-center justify-between">
          <p className="text-sm font-medium text-muted">{label}</p>
          {icon && (
            <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-surface-muted/80 text-muted transition-colors group-hover:bg-primary/10 group-hover:text-primary">
              {icon}
            </span>
          )}
        </div>
        <p className="mt-2 text-2xl font-bold tabular-nums tracking-tight">{value}</p>
        <div className="mt-1.5 flex items-center gap-2 text-xs">
          {deltaPct !== null && deltaPct !== undefined && (
            <span
              className={cn(
                'inline-flex items-center gap-0.5 rounded-full px-1.5 py-0.5 font-medium',
                good
                  ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
                  : 'bg-red-500/10 text-red-600 dark:text-red-400',
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
