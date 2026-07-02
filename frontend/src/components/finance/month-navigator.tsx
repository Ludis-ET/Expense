'use client';

import { ChevronLeft, ChevronRight } from 'lucide-react';
import { formatMonth } from '@/lib/format';
import { formatEthiopian } from '@/lib/ethiopian-calendar';
import { useAuth } from '@/lib/auth';

function shiftMonth(yyyyMm: string, delta: number): string {
  const [y, m] = yyyyMm.split('-').map(Number);
  const d = new Date(Date.UTC(y!, (m ?? 1) - 1 + delta, 1));
  return d.toISOString().slice(0, 7);
}

export function currentMonth(): string {
  return new Date().toISOString().slice(0, 7);
}

/** ‹ July 2026 › with an Ethiopian-calendar subtitle when that preference is set. */
export function MonthNavigator({ month, onChange }: { month: string; onChange: (m: string) => void }) {
  const { user } = useAuth();
  const isCurrent = month >= currentMonth();

  return (
    <div className="flex items-center gap-1">
      <button
        onClick={() => onChange(shiftMonth(month, -1))}
        className="rounded-lg p-1.5 text-muted transition-colors hover:bg-surface-muted hover:text-foreground"
        aria-label="Previous month"
      >
        <ChevronLeft className="h-4 w-4" />
      </button>
      <div className="min-w-32 text-center">
        <p className="text-sm font-semibold">{formatMonth(month)}</p>
        {user?.calendar === 'ethiopian' && (
          <p className="text-[11px] text-muted">{formatEthiopian(new Date(`${month}-15`))}</p>
        )}
      </div>
      <button
        onClick={() => onChange(shiftMonth(month, 1))}
        disabled={isCurrent}
        className="rounded-lg p-1.5 text-muted transition-colors hover:bg-surface-muted hover:text-foreground disabled:pointer-events-none disabled:opacity-30"
        aria-label="Next month"
      >
        <ChevronRight className="h-4 w-4" />
      </button>
    </div>
  );
}
