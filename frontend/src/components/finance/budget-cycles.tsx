'use client';

import { useMemo, useState } from 'react';
import { ArrowDownRight, ArrowUpRight, CircleDot, Minus, Plus, Repeat } from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { InfoHint } from '@/components/ui/info-hint';
import { BudgetTransactions } from '@/components/finance/budget-transactions';
import { CalendarDate } from '@/components/calendar-date';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type { BudgetAdjustment, BudgetCycleSnapshot, BudgetDetail, Transaction } from '@/lib/types';

/**
 * One cycle of a recurring plan, whether it is running or already banked.
 * The open cycle has no snapshot row yet, so the detail payload's live figures
 * are folded into the same shape.
 */
export interface CycleView extends BudgetCycleSnapshot {
  /** The cycle that is running right now, rather than a frozen one. */
  current: boolean;
}

/** Live figures for the open cycle, in the shape a banked one arrives in. */
function currentCycleView(plan: BudgetDetail): CycleView {
  return {
    index: plan.cycleIndex,
    label: plan.cycleLabel ?? 'This cycle',
    startedAt: plan.cycleStartedAt,
    endedAt: plan.nextResetAt ?? plan.cycleStartedAt,
    openingPlanned: plan.openingPlanned,
    adjustedAmount: plan.adjustedThisCycle,
    plannedAmount: plan.plannedAmount,
    carriedIn: plan.carriedIn,
    fundedAmount: plan.fundedAmount,
    spentAmount: plan.spentAmount,
    leftoverAmount: plan.balance,
    txCount: plan.cycleTxCount,
    adjustments: plan.adjustments,
    current: true,
  };
}

/**
 * A recurring plan reads as a run of periods, not one long ledger. Each cycle
 * is a card carrying the amount it opened with, what was added or cut during
 * it, and what actually happened; its transactions live behind the card.
 */
export function BudgetCycleSections({
  plan,
  onViewTx,
}: {
  plan: BudgetDetail;
  onViewTx?: (tx: Transaction) => void;
}) {
  const [openCycle, setOpenCycle] = useState<CycleView | null>(null);

  const cycles = useMemo<CycleView[]>(
    () => [
      currentCycleView(plan),
      ...plan.cycles.map((c) => ({ ...c, current: false })),
    ],
    [plan],
  );

  return (
    <>
      <div className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="flex items-center gap-2 text-sm font-semibold">
            <Repeat className="h-4 w-4 text-muted" />
            Every {plan.periodNoun ?? 'cycle'}
            <InfoHint label="About cycles">
              Each {plan.periodNoun ?? 'cycle'} keeps the amount it opened with, so raising or
              cutting the plan later never rewrites what an earlier one was meant to hold. Open a
              card to search and filter that {plan.periodNoun ?? 'cycle'}&apos;s own spending.
            </InfoHint>
          </h2>
          <span className="text-xs text-muted">
            {cycles.length} {cycles.length === 1 ? 'period' : 'periods'}
          </span>
        </div>

        {cycles.map((c) => (
          <CycleCard key={c.index} cycle={c} onOpen={() => setOpenCycle(c)} />
        ))}

        {plan.cycles.length === 0 && (
          <p className="text-xs text-muted">
            Finished {plan.periodNoun ?? 'cycle'}s appear here once this one rolls over. Quiet
            periods where nothing moved are skipped.
          </p>
        )}
      </div>

      <CycleTransactionsModal
        plan={plan}
        cycle={openCycle}
        onClose={() => setOpenCycle(null)}
        onViewTx={onViewTx}
      />
    </>
  );
}

function CycleCard({ cycle, onOpen }: { cycle: CycleView; onOpen: () => void }) {
  const { money } = useMoney();
  const opening = Math.max(Number(cycle.openingPlanned), 0.01);
  const spentPct = Math.min(100, (Number(cycle.spentAmount) / opening) * 100);
  const fundedPct = Math.min(100, (Number(cycle.fundedAmount) / opening) * 100);
  const adjusted = Number(cycle.adjustedAmount);

  return (
    <button
      type="button"
      onClick={onOpen}
      className={cn(
        'card group w-full p-4 text-left transition-all hover:-translate-y-0.5 hover:shadow-md',
        cycle.current && 'border-primary/40',
      )}
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="flex flex-wrap items-center gap-2 font-semibold">
            {cycle.label}
            {cycle.current && (
              <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-primary">
                Running
              </span>
            )}
          </p>
          <p className="mt-0.5 flex flex-wrap items-center gap-x-1.5 text-xs text-muted">
            <CalendarDate value={cycle.startedAt} />
            <span>→</span>
            <CalendarDate value={cycle.endedAt} />
            <span>· {cycle.txCount} expense{cycle.txCount === 1 ? '' : 's'}</span>
          </p>
        </div>

        <div className="shrink-0 text-right">
          <p className="text-lg font-bold tabular-nums">{money(cycle.openingPlanned)}</p>
          <p className="text-[11px] text-muted">planned at the start</p>
        </div>
      </div>

      {adjusted !== 0 && <AdjustmentChip amount={cycle.adjustedAmount} className="mt-3" />}

      {/* Filled sits behind spent, so one bar reads as "of what I set out to hold". */}
      <div className="relative mt-3 h-2 w-full overflow-hidden rounded-full bg-surface-muted">
        <div
          className="absolute inset-y-0 left-0 rounded-full bg-primary/25 transition-all duration-500"
          style={{ width: `${fundedPct}%` }}
        />
        <div
          className="absolute inset-y-0 left-0 rounded-full bg-primary transition-all duration-500"
          style={{ width: `${spentPct}%` }}
        />
      </div>

      <dl className="mt-3 grid grid-cols-2 gap-3 text-xs sm:grid-cols-4">
        <CycleStat label="Filled" value={money(cycle.fundedAmount)} />
        <CycleStat label="Spent" value={money(cycle.spentAmount)} />
        <CycleStat label="Carried in" value={money(cycle.carriedIn)} />
        <CycleStat
          label={cycle.current ? 'Left' : 'Carried out'}
          value={money(cycle.leftoverAmount)}
        />
      </dl>
    </button>
  );
}

function CycleStat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-muted">{label}</dt>
      <dd className="font-semibold tabular-nums">{value}</dd>
    </div>
  );
}

/** A signed change to the plan amount, coloured by direction. */
export function AdjustmentChip({ amount, className }: { amount: string; className?: string }) {
  const { money } = useMoney();
  const n = Number(amount);
  const up = n > 0;
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold',
        up
          ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
          : 'bg-amber-500/10 text-amber-600 dark:text-amber-400',
        className,
      )}
    >
      {up ? <ArrowUpRight className="h-3 w-3" /> : <ArrowDownRight className="h-3 w-3" />}
      {up ? 'Raised' : 'Cut'} by {money(Math.abs(n))}
    </span>
  );
}

/** The raises and cuts inside one cycle, newest first. */
export function AdjustmentList({ items }: { items: BudgetAdjustment[] }) {
  const { money } = useMoney();
  if (items.length === 0) return null;

  return (
    <ul className="space-y-2">
      {items.map((a) => {
        const n = Number(a.amount);
        const up = n > 0;
        return (
          <li
            key={a.id}
            className="flex items-start justify-between gap-3 rounded-xl bg-surface-muted/50 px-3 py-2.5"
          >
            <span className="flex min-w-0 items-start gap-2">
              <span
                className={cn(
                  'mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full',
                  up
                    ? 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400'
                    : 'bg-amber-500/15 text-amber-600 dark:text-amber-400',
                )}
              >
                {up ? <Plus className="h-3 w-3" /> : <Minus className="h-3 w-3" />}
              </span>
              <span className="min-w-0">
                <span className="block text-sm font-medium">
                  {up ? 'Added to' : 'Deducted from'} the plan amount
                </span>
                <span className="block text-xs text-muted">
                  <CalendarDate value={a.date} />
                  {a.reason && <> · {a.reason}</>}
                </span>
              </span>
            </span>
            <span
              className={cn(
                'shrink-0 text-sm font-semibold tabular-nums',
                up
                  ? 'text-emerald-600 dark:text-emerald-400'
                  : 'text-amber-600 dark:text-amber-400',
              )}
            >
              {up ? '+' : '−'}
              {money(Math.abs(n))}
            </span>
          </li>
        );
      })}
    </ul>
  );
}

/**
 * One cycle in full: the figures it opened with, what was added or cut, and its
 * own searchable, filterable transaction list.
 */
function CycleTransactionsModal({
  plan,
  cycle,
  onClose,
  onViewTx,
}: {
  plan: BudgetDetail;
  cycle: CycleView | null;
  onClose: () => void;
  onViewTx?: (tx: Transaction) => void;
}) {
  const { money } = useMoney();
  if (!cycle) return null;

  const closing = Number(cycle.plannedAmount);
  const adjusted = Number(cycle.adjustedAmount);

  return (
    <Modal
      open
      onClose={onClose}
      title={cycle.label}
      description={`What ${plan.name} was set to hold for this ${plan.periodNoun ?? 'cycle'}, and everything charged to it.`}
      className="sm:max-w-3xl"
    >
      <div className="space-y-5">
        <div className="rounded-2xl border border-border bg-surface-muted/40 p-4">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <p className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-widest text-muted">
                <CircleDot className="h-3 w-3" /> Planned at the start
              </p>
              <p className="mt-1 text-3xl font-bold tabular-nums">{money(cycle.openingPlanned)}</p>
            </div>
            {adjusted !== 0 && (
              <div className="text-right">
                <AdjustmentChip amount={cycle.adjustedAmount} />
                <p className="mt-1 text-xs text-muted">
                  now {money(closing)} for this {plan.periodNoun ?? 'cycle'}
                </p>
              </div>
            )}
          </div>

          <dl className="mt-4 grid grid-cols-2 gap-3 text-xs sm:grid-cols-4">
            <CycleStat label="Carried in" value={money(cycle.carriedIn)} />
            <CycleStat label="Filled" value={money(cycle.fundedAmount)} />
            <CycleStat label="Spent" value={money(cycle.spentAmount)} />
            <CycleStat
              label={cycle.current ? 'Left' : 'Carried out'}
              value={money(cycle.leftoverAmount)}
            />
          </dl>
        </div>

        {cycle.adjustments.length > 0 && (
          <div className="space-y-2">
            <h3 className="text-sm font-semibold">Changes to the amount</h3>
            <AdjustmentList items={cycle.adjustments} />
          </div>
        )}

        <BudgetTransactions
          plan={plan}
          lockedCycle={cycle.index}
          heading={`Spending in ${cycle.label}`}
          onView={onViewTx}
        />
      </div>
    </Modal>
  );
}
