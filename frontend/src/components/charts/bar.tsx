'use client';

import { cn } from '@/lib/utils';

export interface BarDatum {
  label: string;
  value: number;
}

/** Minimal responsive vertical bar chart with clickable bars. */
export function BarChart({
  data,
  color = 'var(--primary)',
  height = 180,
  format,
  selectedIndex = null,
  onSelect,
}: {
  data: BarDatum[];
  color?: string;
  height?: number;
  format?: (value: number) => string;
  selectedIndex?: number | null;
  onSelect?: (item: BarDatum, index: number) => void;
}) {
  const max = Math.max(1, ...data.map((d) => d.value));
  const fmt = format ?? ((v: number) => String(v));
  if (!data.length) return <p className="py-8 text-center text-sm text-muted">No data.</p>;

  return (
    <div className="flex items-end gap-2" style={{ height }}>
      {data.map((d, i) => (
        <button
          key={d.label}
          type="button"
          onClick={() => onSelect?.(d, i)}
          className={cn(
            'group flex flex-1 flex-col items-center gap-1.5 rounded-t-md transition-opacity focus:outline-none focus-visible:ring-2 focus-visible:ring-ring',
            selectedIndex !== null && selectedIndex !== i && 'opacity-40',
          )}
          aria-label={`${d.label}: ${fmt(d.value)}`}
        >
          <span className="text-xs font-medium tabular-nums text-muted">{fmt(d.value)}</span>
          <div
            className="w-full rounded-t-md transition-all group-hover:brightness-110"
            style={{
              height: `${(d.value / max) * (height - 44)}px`,
              backgroundColor: selectedIndex === i ? color : color,
              minHeight: 2,
              boxShadow: selectedIndex === i ? `0 0 0 2px ${color}` : undefined,
            }}
          />
          <span className="w-full truncate text-center text-[11px] text-muted" title={d.label}>
            {d.label}
          </span>
        </button>
      ))}
    </div>
  );
}

/**
 * A bar chart for figures that can go below zero.
 *
 * The plain `BarChart` scales height as `value / max`, so a negative bar
 * collapses to the 2px minimum and reads identically to zero - which is the
 * opposite of the truth for a net figure. Here bars grow away from a drawn
 * baseline in both directions, and the sign is carried by direction and by the
 * printed number, never by colour alone.
 */
export function SignedBarChart({
  data,
  height = 170,
  format,
  positive = 'bg-emerald-500',
  negative = 'bg-rose-500',
}: {
  data: BarDatum[];
  height?: number;
  format?: (value: number) => string;
  positive?: string;
  negative?: string;
}) {
  const fmt = format ?? ((v: number) => String(v));
  if (!data.length) return <p className="py-8 text-center text-sm text-muted">No data.</p>;

  const maxAbs = Math.max(1, ...data.map((d) => Math.abs(d.value)));
  const anyNegative = data.some((d) => d.value < 0);

  return (
    <div className="flex items-stretch gap-2" style={{ height }}>
      {data.map((d) => {
        const share = `${(Math.abs(d.value) / maxAbs) * 100}%`;
        return (
          <div key={d.label} className="flex min-w-0 flex-1 flex-col items-center gap-1">
            <span className="truncate text-[10px] font-medium tabular-nums text-muted">
              {fmt(d.value)}
            </span>

            <div className="flex w-full flex-1 flex-col">
              <div className="flex w-full flex-1 flex-col justify-end">
                {d.value > 0 && (
                  <div
                    className={cn('w-full rounded-t-md transition-all', positive)}
                    style={{ height: share, minHeight: 2 }}
                  />
                )}
              </div>
              {/* The zero line only earns its space when something crosses it. */}
              {anyNegative && <div className="h-px w-full shrink-0 bg-border" />}
              <div className={cn('flex w-full flex-col justify-start', anyNegative && 'flex-1')}>
                {d.value < 0 && (
                  <div
                    className={cn('w-full rounded-b-md transition-all', negative)}
                    style={{ height: share, minHeight: 2 }}
                  />
                )}
              </div>
            </div>

            <span className="w-full truncate text-center text-[11px] text-muted" title={d.label}>
              {d.label}
            </span>
          </div>
        );
      })}
    </div>
  );
}
