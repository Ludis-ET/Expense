'use client';

export interface BarDatum {
  label: string;
  value: number;
}

/** Minimal responsive vertical bar chart (no charting dependency). */
export function BarChart({ data, color = 'var(--primary)', height = 180 }: { data: BarDatum[]; color?: string; height?: number }) {
  const max = Math.max(1, ...data.map((d) => d.value));
  if (!data.length) return <p className="py-8 text-center text-sm text-muted">No data.</p>;

  return (
    <div className="flex items-end gap-2" style={{ height }}>
      {data.map((d) => (
        <div key={d.label} className="flex flex-1 flex-col items-center gap-1.5">
          <span className="text-xs font-medium tabular-nums text-muted">{d.value}</span>
          <div
            className="w-full rounded-t-md transition-all"
            style={{ height: `${(d.value / max) * (height - 44)}px`, backgroundColor: color, minHeight: 2 }}
            title={`${d.label}: ${d.value}`}
          />
          <span className="w-full truncate text-center text-[11px] text-muted" title={d.label}>
            {d.label}
          </span>
        </div>
      ))}
    </div>
  );
}
