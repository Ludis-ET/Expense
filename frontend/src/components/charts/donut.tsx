'use client';

import { cn } from '@/lib/utils';

export interface DonutSlice {
  label: string;
  value: number;
  color: string;
}

interface DonutProps {
  data: DonutSlice[];
  size?: number;
  thickness?: number;
  format?: (value: number) => string;
  centerLabel?: string;
  selectedIndex?: number | null;
  onSelect?: (slice: DonutSlice, index: number) => void;
}

/** Lightweight SVG donut chart with clickable segments. */
export function Donut({
  data,
  size = 160,
  thickness = 22,
  format,
  centerLabel = 'total',
  selectedIndex = null,
  onSelect,
}: DonutProps) {
  const total = data.reduce((s, d) => s + d.value, 0);
  const radius = (size - thickness) / 2;
  const circumference = 2 * Math.PI * radius;
  const fmt = format ?? ((v: number) => String(v));
  let offset = 0;

  const centerValue =
    selectedIndex !== null && selectedIndex >= 0 && data[selectedIndex]
      ? data[selectedIndex]!.value
      : total;
  const centerText =
    selectedIndex !== null && selectedIndex >= 0 && data[selectedIndex]
      ? data[selectedIndex]!.label
      : centerLabel;

  return (
    <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:gap-6">
      <div className="relative mx-auto sm:mx-0" style={{ width: size, height: size }}>
        <svg width={size} height={size} className="-rotate-90" role="img" aria-label="Donut chart">
          <circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            fill="none"
            strokeWidth={thickness}
            className="stroke-surface-muted"
          />
          {total > 0 &&
            data.map((d, i) => {
              const len = (d.value / total) * circumference;
              const seg = (
                <circle
                  key={d.label}
                  cx={size / 2}
                  cy={size / 2}
                  r={radius}
                  fill="none"
                  stroke={d.color}
                  strokeWidth={selectedIndex === i ? thickness + 4 : thickness}
                  strokeDasharray={`${len} ${circumference - len}`}
                  strokeDashoffset={-offset}
                  strokeLinecap="butt"
                  className={cn(
                    'cursor-pointer transition-opacity',
                    selectedIndex !== null && selectedIndex !== i && 'opacity-40',
                  )}
                  onClick={() => onSelect?.(d, i)}
                  onKeyDown={(e) => e.key === 'Enter' && onSelect?.(d, i)}
                  tabIndex={0}
                  role="button"
                  aria-label={`${d.label}: ${fmt(d.value)}`}
                />
              );
              offset += len;
              return seg;
            })}
        </svg>
        <button
          type="button"
          onClick={() => onSelect?.(null as unknown as DonutSlice, -1)}
          className="absolute inset-0 flex flex-col items-center justify-center rounded-full"
          aria-label="Show total"
        >
          <span className="max-w-[70%] truncate text-lg font-bold tabular-nums">{fmt(centerValue)}</span>
          <span className="max-w-[80%] truncate text-xs text-muted">{centerText}</span>
        </button>
      </div>
      <ul className="space-y-1.5">
        {data.map((d, i) => {
          const pct = total > 0 ? Math.round((d.value / total) * 100) : 0;
          return (
            <li key={d.label}>
              <button
                type="button"
                onClick={() => onSelect?.(d, i)}
                className={cn(
                  'flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm transition-colors hover:bg-surface-muted',
                  selectedIndex === i && 'bg-primary/10 ring-1 ring-primary/30',
                )}
              >
                <span className="h-2.5 w-2.5 shrink-0 rounded-sm" style={{ backgroundColor: d.color }} />
                <span className="min-w-0 flex-1 truncate text-muted">{d.label}</span>
                <span className="shrink-0 font-semibold tabular-nums">{fmt(d.value)}</span>
                <span className="w-8 shrink-0 text-right text-xs text-muted">{pct}%</span>
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
