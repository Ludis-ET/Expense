'use client';

import { Coins, ChevronDown } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useCurrencyView } from '@/lib/currency-view-context';

interface CurrencySelectorProps {
  className?: string;
  /** Compact styling for the top bar */
  variant?: 'header' | 'inline';
}

/** Global currency picker — lives in the app header. */
export function CurrencySelector({ className, variant = 'header' }: CurrencySelectorProps) {
  const { activeCurrency, currencies, setActiveCurrency, hasMultiple } = useCurrencyView();

  if (!hasMultiple) {
    return (
      <span
        className={cn(
          'inline-flex items-center gap-1.5 rounded-xl border border-border bg-surface-muted/60 px-3 py-2 text-sm font-semibold tabular-nums',
          className,
        )}
        title="Active currency"
      >
        <Coins className="h-4 w-4 text-primary" aria-hidden />
        {activeCurrency}
      </span>
    );
  }

  return (
    <label
      className={cn(
        'relative inline-flex items-center gap-1.5 rounded-xl border border-border bg-surface-muted/60 transition-colors hover:bg-surface-muted',
        variant === 'header' ? 'px-2.5 py-1.5' : 'px-3 py-2',
        className,
      )}
    >
      <Coins className="h-4 w-4 shrink-0 text-primary" aria-hidden />
      <select
        value={activeCurrency}
        onChange={(e) => setActiveCurrency(e.target.value)}
        className={cn(
          'cursor-pointer appearance-none bg-transparent pr-6 font-semibold tabular-nums outline-none',
          variant === 'header' ? 'text-sm' : 'text-sm',
        )}
        aria-label="Select currency view"
      >
        {currencies.map((c) => (
          <option key={c} value={c}>
            {c}
          </option>
        ))}
      </select>
      <ChevronDown className="pointer-events-none absolute right-2 h-3.5 w-3.5 text-muted" aria-hidden />
    </label>
  );
}
