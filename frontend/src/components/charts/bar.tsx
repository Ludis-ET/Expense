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
