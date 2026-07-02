'use client';

import { useMemo } from 'react';
import { formatMoney } from '@/lib/format';

interface Point {
  date: string;
  cumulative: number;
}

/**
 * Cumulative spend (solid) vs. planned budget (dashed line), with a dotted
 * projection of when the budget runs out at the current burn rate.
 */
export function BurnRateChart({
  points,
  totalPlanned,
  currency,
}: {
  points: Point[];
  totalPlanned: number;
  currency: string;
}) {
  const W = 560;
  const H = 220;
  const pad = { l: 8, r: 8, t: 12, b: 22 };

  const model = useMemo(() => {
    if (points.length === 0) return null;
    const first = new Date(points[0].date).getTime();
    const last = new Date(points[points.length - 1].date).getTime();
    const spent = points[points.length - 1].cumulative;

    // Linear burn rate (spend per day) from first to last expense.
    const days = Math.max(1, (last - first) / 86_400_000);
    const perDay = spent / days;
    const remaining = Math.max(0, totalPlanned - spent);
    const daysToExhaust = perDay > 0 ? remaining / perDay : Infinity;
    const projEnd = isFinite(daysToExhaust) ? last + daysToExhaust * 86_400_000 : last;

    const maxY = Math.max(totalPlanned, spent) * 1.1 || 1;
    const minX = first;
    const maxX = Math.max(last, projEnd);
    const x = (t: number) => pad.l + ((t - minX) / Math.max(1, maxX - minX)) * (W - pad.l - pad.r);
    const y = (v: number) => H - pad.b - (v / maxY) * (H - pad.t - pad.b);

    const line = points.map((p) => `${x(new Date(p.date).getTime())},${y(p.cumulative)}`).join(' ');
    return {
      line,
      plannedY: y(totalPlanned),
      projection: isFinite(daysToExhaust)
        ? `${x(last)},${y(spent)} ${x(projEnd)},${y(totalPlanned)}`
        : null,
      daysToExhaust,
      perDay,
      x,
      y,
      lastX: x(last),
      lastY: y(spent),
    };
  }, [points, totalPlanned]);

  if (!model) return <p className="py-10 text-center text-sm text-muted">No approved expenses yet.</p>;

  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full">
        {/* planned budget line */}
        <line
          x1={pad.l}
          x2={W - pad.r}
          y1={model.plannedY}
          y2={model.plannedY}
          stroke="var(--muted)"
          strokeDasharray="5 5"
          strokeWidth={1.5}
        />
        <text x={pad.l} y={model.plannedY - 5} className="fill-muted text-[10px]">
          Planned {formatMoney(totalPlanned, currency)}
        </text>
        {/* projection to exhaustion */}
        {model.projection && (
          <polyline points={model.projection} fill="none" stroke="var(--warning)" strokeDasharray="3 4" strokeWidth={2} />
        )}
        {/* cumulative spend */}
        <polyline points={model.line} fill="none" stroke="var(--primary)" strokeWidth={2.5} strokeLinejoin="round" />
        <circle cx={model.lastX} cy={model.lastY} r={3.5} fill="var(--primary)" />
      </svg>
      <p className="mt-1 text-xs text-muted">
        {isFinite(model.daysToExhaust)
          ? `At ~${formatMoney(Math.round(model.perDay), currency)}/day, the budget is exhausted in about ${Math.round(model.daysToExhaust)} days.`
          : 'Not enough spend history to forecast a burn rate yet.'}
      </p>
    </div>
  );
}
