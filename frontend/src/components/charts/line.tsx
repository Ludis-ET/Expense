'use client';

import { useMemo } from 'react';

export interface LinePoint {
  label: string;
  income: number;
  expense: number;
}

const W = 560;
const H = 220;
const pad = { l: 8, r: 8, t: 12, b: 24 };

/** Dual-series income/expense line chart (SVG, no dependency). */
export function IncomeExpenseLine({
  points,
  format,
}: {
  points: LinePoint[];
  format?: (v: number) => string;
}) {
  const model = useMemo(() => {
    if (points.length === 0) return null;
    const maxY = Math.max(1, ...points.map((p) => Math.max(p.income, p.expense))) * 1.1;
    const x = (i: number) =>
      pad.l + (points.length === 1 ? 0.5 : i / (points.length - 1)) * (W - pad.l - pad.r);
    const y = (v: number) => H - pad.b - (v / maxY) * (H - pad.t - pad.b);

    const line = (key: 'income' | 'expense') =>
      points.map((p, i) => `${x(i)},${y(p[key])}`).join(' ');

    // Show at most ~8 x-axis labels.
    const step = Math.max(1, Math.ceil(points.length / 8));
    const labels = points
      .map((p, i) => ({ label: p.label, i }))
      .filter(({ i }) => i % step === 0 || i === points.length - 1);

    return { incomeLine: line('income'), expenseLine: line('expense'), x, labels };
  }, [points]);

  if (!model) return <p className="py-10 text-center text-sm text-muted">No data yet.</p>;
  const fmt = format ?? ((v: number) => String(v));

  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full">
        <polyline
          points={model.expenseLine}
          fill="none"
          stroke="var(--danger, #ef4444)"
          strokeWidth={2}
          strokeLinejoin="round"
        />
        <polyline
          points={model.incomeLine}
          fill="none"
          stroke="var(--success, #10b981)"
          strokeWidth={2.5}
          strokeLinejoin="round"
        />
        {model.labels.map(({ label, i }) => (
          <text
            key={i}
            x={model.x(i)}
            y={H - 6}
            textAnchor="middle"
            className="fill-muted text-[10px]"
          >
            {label}
          </text>
        ))}
      </svg>
      <div className="mt-1 flex items-center gap-4 text-xs text-muted">
        <span className="flex items-center gap-1.5">
          <span className="h-2 w-4 rounded-sm" style={{ background: 'var(--success, #10b981)' }} /> Income
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-2 w-4 rounded-sm" style={{ background: 'var(--danger, #ef4444)' }} /> Expense
        </span>
        <span className="ml-auto tabular-nums">
          peak {fmt(Math.max(...points.map((p) => Math.max(p.income, p.expense))))}
        </span>
      </div>
    </div>
  );
}
