'use client';

import { useMemo } from 'react';

interface HeatDay {
  date: string; // YYYY-MM-DD
  total: number;
}

const CELL = 11;
const GAP = 2;
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** GitHub-style calendar heatmap of daily spend (SVG, no dependency). */
export function SpendHeatmap({
  days,
  year,
  format,
}: {
  days: HeatDay[];
  year: number;
  format?: (v: number) => string;
}) {
  const model = useMemo(() => {
    const byDate = new Map(days.map((d) => [d.date, d.total]));
    const max = Math.max(1, ...days.map((d) => d.total));
    const start = new Date(Date.UTC(year, 0, 1));
    const end = new Date(Date.UTC(year + 1, 0, 1));

    // Align the grid so column 0 starts on the Monday on/before Jan 1.
    const startDow = (start.getUTCDay() + 6) % 7; // Monday = 0
    const cells: { x: number; y: number; date: string; total: number }[] = [];
    const monthLabels: { x: number; label: string }[] = [];
    let lastMonth = -1;

    const cursor = new Date(start);
    let index = startDow;
    while (cursor < end) {
      const week = Math.floor(index / 7);
      const dow = index % 7;
      const date = cursor.toISOString().slice(0, 10);
      cells.push({
        x: week * (CELL + GAP),
        y: dow * (CELL + GAP),
        date,
        total: byDate.get(date) ?? 0,
      });
      if (cursor.getUTCMonth() !== lastMonth && dow === 0) {
        lastMonth = cursor.getUTCMonth();
        monthLabels.push({ x: week * (CELL + GAP), label: MONTHS[lastMonth]! });
      }
      cursor.setUTCDate(cursor.getUTCDate() + 1);
      index += 1;
    }

    const weeks = Math.ceil(index / 7);
    return { cells, monthLabels, max, width: weeks * (CELL + GAP) };
  }, [days, year]);

  const fmt = format ?? ((v: number) => String(v));

  const intensity = (total: number) => {
    if (total <= 0) return 'var(--surface-muted, #e2e8f0)';
    const t = Math.min(1, total / model.max);
    const alpha = 0.25 + t * 0.75;
    return `color-mix(in srgb, var(--primary) ${Math.round(alpha * 100)}%, transparent)`;
  };

  return (
    <div className="overflow-x-auto">
      <svg width={model.width} height={7 * (CELL + GAP) + 18} className="min-w-full">
        {model.monthLabels.map((m) => (
          <text key={m.label + m.x} x={m.x} y={10} className="fill-muted text-[9px]">
            {m.label}
          </text>
        ))}
        <g transform="translate(0, 14)">
          {model.cells.map((c) => (
            <rect
              key={c.date}
              x={c.x}
              y={c.y}
              width={CELL}
              height={CELL}
              rx={2}
              fill={intensity(c.total)}
            >
              <title>{`${c.date}: ${c.total > 0 ? fmt(c.total) : 'no spending'}`}</title>
            </rect>
          ))}
        </g>
      </svg>
    </div>
  );
}
