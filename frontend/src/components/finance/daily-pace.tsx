'use client';

import useSWR from 'swr';
import { InfoHint } from '@/components/ui/info-hint';
import { useMoney } from '@/lib/amount-visibility';
import { useCurrencyView } from '@/lib/currency-view-context';
import { cn } from '@/lib/utils';
import type { DailySpending } from '@/lib/types';

/**
 * A slim read of how fast money is leaving, for the month in view.
 *
 * Deliberately small: it sits above a list that is the real content, so it gets
 * one line and a strip of hairline bars rather than a chart. A day above the
 * average is drawn taller *and* tinted, so the shape survives without colour.
 * Renders nothing at all when there is no spending - an empty strip would be
 * noise where a list is about to appear.
 */
export function DailyPace({ month }: { month: string }) {
  const { money } = useMoney();
  const { activeCurrency } = useCurrencyView();
  const { data } = useSWR<DailySpending>(
    `/analytics/daily?month=${month}&currency=${encodeURIComponent(activeCurrency)}`,
  );

  if (!data || data.stats.dayCount === 0 || Number(data.stats.total) === 0) return null;

  const pace = Number(data.stats.pace);
  const peak = Math.max(...data.days.map((d) => Number(d.amount)), 1);

  return (
    <div className="mb-4 flex flex-wrap items-center gap-x-4 gap-y-2 rounded-xl border border-border bg-surface-muted/30 px-3 py-2">
      <div className="flex items-baseline gap-1.5">
        <span className="text-[10px] font-semibold uppercase tracking-widest text-muted">
          A day
        </span>
        <span className="text-base font-bold tabular-nums">{money(pace)}</span>
        <InfoHint label="About the daily average">
          Spending in {data.label.toLowerCase()} divided by the {data.stats.dayCount} days counted
          so far    a month still running stops at today rather than dividing by days that have not
          happened. Income and transfers are not in it. Each bar is one day; taller and tinted ones
          are above the average.
        </InfoHint>
      </div>

      {/* One hairline per day. Purely a shape - the numbers are beside it. */}
      <div
        className="flex h-6 min-w-0 flex-1 items-end gap-px"
        role="img"
        aria-label={`Daily spending for ${data.label}, averaging ${money(pace)} a day`}
      >
        {data.days.map((d) => {
          const amount = Number(d.amount);
          return (
            <span
              key={d.date}
              title={`${d.date}: ${money(amount)}`}
              className={cn(
                'min-w-0 flex-1 rounded-sm transition-colors',
                amount === 0
                  ? 'bg-border'
                  : d.under
                    ? 'bg-primary/35'
                    : 'bg-primary',
              )}
              style={{ height: `${Math.max(2, (amount / peak) * 24)}px` }}
            />
          );
        })}
      </div>

      <span className="shrink-0 text-[11px] text-muted">
        {data.stats.noSpendDays > 0 && (
          <>
            <strong className="text-foreground tabular-nums">{data.stats.noSpendDays}</strong> no-spend
            {' '}day{data.stats.noSpendDays === 1 ? '' : 's'}
          </>
        )}
        {data.stats.noSpendDays > 0 && data.stats.biggestDay && ' · '}
        {data.stats.biggestDay && (
          <>
            peak <strong className="text-foreground tabular-nums">{money(data.stats.biggestDay.amount)}</strong>
          </>
        )}
      </span>
    </div>
  );
}
