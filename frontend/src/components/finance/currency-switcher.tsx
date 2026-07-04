'use client';

import { ChevronLeft, ChevronRight, Coins } from 'lucide-react';
import { cn } from '@/lib/utils';
import { useCurrencyView } from '@/lib/currency-view-context';

interface CurrencySwitcherProps {
  className?: string;
  compact?: boolean;
  showConvertedHint?: boolean;
}

export function CurrencySwitcher({ className, compact, showConvertedHint }: CurrencySwitcherProps) {
  const { activeCurrency, currencies, activeIndex, nextCurrency, prevCurrency, hasMultiple, convertedTotal } =
    useCurrencyView();

  if (!hasMultiple && !showConvertedHint) {
    return (
      <span className={cn('inline-flex items-center gap-1.5 rounded-full bg-surface-muted px-2.5 py-1 text-xs font-medium text-muted', className)}>
        <Coins className="h-3.5 w-3.5" />
        {activeCurrency}
      </span>
    );
  }

  return (
    <div className={cn('flex flex-col gap-1', className)}>
      <div className="inline-flex items-center gap-1 rounded-xl border border-border bg-surface p-0.5">
        <button
          type="button"
          onClick={prevCurrency}
          disabled={!hasMultiple}
          className="rounded-lg p-1.5 text-muted transition-colors hover:bg-surface-muted hover:text-foreground disabled:opacity-30"
          aria-label="Previous currency"
        >
          <ChevronLeft className="h-4 w-4" />
        </button>
        <span className={cn('min-w-[4.5rem] text-center font-semibold tabular-nums', compact ? 'text-xs' : 'text-sm')}>
          {activeCurrency}
        </span>
        <button
          type="button"
          onClick={nextCurrency}
          disabled={!hasMultiple}
          className="rounded-lg p-1.5 text-muted transition-colors hover:bg-surface-muted hover:text-foreground disabled:opacity-30"
          aria-label="Next currency"
        >
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>
      {hasMultiple && (
        <p className="text-[10px] text-muted">
          {activeIndex + 1} of {currencies.length} currencies · amounts not merged
        </p>
      )}
      {showConvertedHint && convertedTotal && !convertedTotal.complete && convertedTotal.missingRates.length > 0 && (
        <p className="text-[10px] text-warning">
          Add rates for {convertedTotal.missingRates.join(', ')} in Settings to see a combined total.
        </p>
      )}
    </div>
  );
}
