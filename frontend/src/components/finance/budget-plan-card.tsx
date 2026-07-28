'use client';

import Link from 'next/link';
import { ArchiveRestore, Repeat, Wallet } from 'lucide-react';
import { financeIcon } from './icons';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type { BudgetHealth, BudgetRow } from '@/lib/types';

export const HEALTH_META: Record<
  BudgetHealth,
  { label: string; chip: string; bar: string }
> = {
  empty: {
    label: 'Empty',
    chip: 'bg-slate-500/12 text-slate-600 dark:text-slate-300',
    bar: 'bg-slate-400',
  },
  'partly-funded': {
    label: 'Partly filled',
    chip: 'bg-sky-500/12 text-sky-600 dark:text-sky-400',
    bar: 'bg-sky-500',
  },
  ready: {
    label: 'Ready',
    chip: 'bg-emerald-500/12 text-emerald-600 dark:text-emerald-400',
    bar: 'bg-emerald-500',
  },
  spending: {
    label: 'In use',
    chip: 'bg-primary/12 text-primary',
    bar: 'bg-primary',
  },
  low: {
    label: 'Running low',
    chip: 'bg-amber-500/12 text-amber-600 dark:text-amber-400',
    bar: 'bg-amber-500',
  },
  drained: {
    label: 'Empty pot',
    chip: 'bg-red-500/12 text-red-600 dark:text-red-400',
    bar: 'bg-red-500',
  },
  closed: {
    label: 'Closed',
    chip: 'bg-surface-muted text-muted',
    bar: 'bg-slate-400',
  },
};

/**
 * One plan at a glance: a single bar that reads left-to-right as
 * spent → still in the pot → not yet filled.
 */
export function BudgetPlanCard({ plan }: { plan: BudgetRow }) {
  const { money } = useMoney();
  const Icon = financeIcon(plan.icon ?? 'wallet');
  const meta = HEALTH_META[plan.health];
  const closed = plan.state === 'CLOSED';

  const planned = Math.max(Number(plan.plannedAmount), 0.01);
  const spentPct = Math.min(100, (Number(plan.spentAmount) / planned) * 100);
  const balancePct = Math.min(100 - spentPct, (Number(plan.balance) / planned) * 100);

  return (
    <Link
      href={`/budgets/${plan.id}`}
      className={cn(
        'card group flex flex-col gap-3 p-4 transition-all hover:-translate-y-0.5 hover:shadow-md',
        closed && 'opacity-70',
      )}
    >
      <div className="flex items-start gap-3">
        <span
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl"
          style={{
            backgroundColor: `${plan.color ?? '#6366f1'}1f`,
            color: plan.color ?? '#6366f1',
          }}
        >
          <Icon className="h-5 w-5" />
        </span>

        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <h3 className="truncate font-semibold leading-snug">{plan.name}</h3>
            <span
              className={cn(
                'shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide',
                meta.chip,
              )}
            >
              {meta.label}
            </span>
          </div>
          <p className="mt-0.5 flex flex-wrap items-center gap-x-1.5 gap-y-0.5 text-xs text-muted">
            {plan.kind === 'RECURRING' ? (
              <span className="inline-flex items-center gap-1">
                <Repeat className="h-3 w-3" /> every {plan.periodNoun}
              </span>
            ) : (
              <span>one-time</span>
            )}
            {plan.category && <span>· {plan.category.name}</span>}
            {plan.cycleLabel && <span>· {plan.cycleLabel}</span>}
          </p>
        </div>
      </div>

      <div>
        <div className="mb-1.5 flex items-baseline justify-between gap-2">
          <span className="text-xl font-bold tabular-nums">{money(plan.balance)}</span>
          <span className="text-xs text-muted">
            left of {money(plan.fundedAmount)} filled
          </span>
        </div>

        {/* spent | remaining in pot | not yet filled */}
        <div className="flex h-2 w-full overflow-hidden rounded-full bg-surface-muted">
          <div
            className="h-full bg-foreground/25 transition-all duration-500"
            style={{ width: `${spentPct}%` }}
            title={`${money(plan.spentAmount)} spent`}
          />
          <div
            className={cn('h-full transition-all duration-500', meta.bar)}
            style={{ width: `${Math.max(0, balancePct)}%` }}
            title={`${money(plan.balance)} still in the pot`}
          />
        </div>

        <div className="mt-1.5 flex items-center justify-between text-xs text-muted">
          <span>
            {money(plan.spentAmount)} spent · plan {money(plan.plannedAmount)}
          </span>
          {closed ? (
            <span className="inline-flex items-center gap-1 font-medium">
              <ArchiveRestore className="h-3 w-3" /> closed
            </span>
          ) : Number(plan.fillable) > 0 ? (
            <span className="inline-flex items-center gap-1 font-medium text-primary">
              <Wallet className="h-3 w-3" /> add {money(plan.fillable)}
            </span>
          ) : (
            <span>fully filled</span>
          )}
        </div>

        {Number(plan.carriedIn) > 0 && (
          <p className="mt-1 text-[11px] text-muted">
            {money(plan.carriedIn)} carried over from the last {plan.periodNoun}
          </p>
        )}
      </div>
    </Link>
  );
}
