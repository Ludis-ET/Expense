'use client';

import Link from 'next/link';
import useSWR from 'swr';
import { ExternalLink, Repeat, RefreshCw, TrendingDown, TrendingUp } from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { ProgressBar, Skeleton } from '@/components/ui/misc';
import { CategoryBadge } from '@/components/finance/category-badge';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type { BudgetHistory, BudgetPeriod, BudgetRow } from '@/lib/types';

const PERIOD_NOUN: Record<BudgetPeriod, string> = {
  WEEKLY: 'week',
  MONTHLY: 'month',
  QUARTERLY: 'quarter',
  YEARLY: 'year',
};

const PERIOD_LABEL: Record<BudgetPeriod, string> = {
  WEEKLY: 'Weekly',
  MONTHLY: 'Monthly',
  QUARTERLY: 'Quarterly',
  YEARLY: 'Yearly',
};

function tone(status: BudgetRow['status']) {
  return status === 'over' ? 'danger' : status === 'warning' ? 'warning' : 'success';
}

export function BudgetDetailModal({
  row,
  onClose,
  onEdit,
}: {
  row: BudgetRow | null;
  onClose: () => void;
  onEdit: () => void;
}) {
  const { money } = useMoney();
  const { data: history } = useSWR<BudgetHistory>(
    row ? `/budgets/${row.categoryId}/history?periods=8` : null,
  );

  if (!row) return null;

  const spent = Number(row.spent);
  const limit = Number(row.effectiveLimit);
  const remaining = Number(row.remaining);
  const carry = Number(row.carryIn);
  const isOver = remaining < 0;
  const inactive = row.status === 'upcoming' || row.status === 'ended';

  return (
    <Modal open={!!row} onClose={onClose} title="Budget Details">
      <div className="space-y-5">
        {/* Header */}
        <div className="flex items-start justify-between gap-3">
          <div className="space-y-1.5">
            <CategoryBadge category={row.category} className="text-base font-semibold" />
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="inline-flex items-center gap-1 rounded-full bg-surface-muted px-2 py-0.5 text-xs font-medium text-muted">
                <Repeat className="h-3 w-3" /> {PERIOD_LABEL[row.period]}
              </span>
              {row.rollover && (
                <span className="inline-flex items-center gap-1 rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary">
                  <RefreshCw className="h-3 w-3" /> Rollover
                </span>
              )}
              {inactive && (
                <span className="rounded-full bg-surface-muted px-2 py-0.5 text-xs text-muted">
                  {row.status === 'upcoming' ? 'Upcoming' : 'Ended'}
                </span>
              )}
            </div>
          </div>
          <button
            type="button"
            onClick={() => { onClose(); onEdit(); }}
            className="rounded-lg border border-border px-3 py-1.5 text-xs font-medium text-muted hover:bg-surface-muted"
          >
            Edit
          </button>
        </div>

        {/* Progress hero */}
        {!inactive && (
          <div className="rounded-2xl border border-border bg-surface-muted/30 p-5 space-y-4">
            <div className="flex items-end justify-between">
              <div>
                <p className="text-3xl font-bold tabular-nums">{money(spent)}</p>
                <p className="text-sm text-muted mt-0.5">of {money(limit)} limit</p>
              </div>
              <div className="text-right">
                <p className={cn(
                  'text-lg font-bold tabular-nums',
                  isOver ? 'text-danger' : 'text-emerald-600 dark:text-emerald-400',
                )}>
                  {isOver ? `${money(Math.abs(remaining))} over` : `${money(remaining)} left`}
                </p>
                <p className="text-xs text-muted">{row.pct}% used</p>
              </div>
            </div>

            <ProgressBar value={Math.min(row.pct, 100)} tone={tone(row.status)} />

            <div className="text-xs text-muted">{row.periodLabel}</div>

            {row.rollover && carry !== 0 && (
              <p className="text-xs text-muted flex items-center gap-1">
                {carry > 0
                  ? <TrendingUp className="h-3 w-3 text-emerald-500" />
                  : <TrendingDown className="h-3 w-3 text-warning" />}
                {carry > 0
                  ? `+${money(carry)} rolled over from previous ${PERIOD_NOUN[row.period]}`
                  : `${money(Math.abs(carry))} overspend carried in`}
                {' · '} Base: {money(row.amount)}/{PERIOD_NOUN[row.period]}
              </p>
            )}
          </div>
        )}

        {/* Period dates */}
        <div className="grid grid-cols-2 gap-3">
          <div className="rounded-xl border border-border p-3">
            <p className="text-xs text-muted mb-0.5">Period start</p>
            <p className="text-sm font-medium">{new Date(row.periodStart).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}</p>
          </div>
          <div className="rounded-xl border border-border p-3">
            <p className="text-xs text-muted mb-0.5">Period end</p>
            <p className="text-sm font-medium">{new Date(row.periodEnd).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}</p>
          </div>
        </div>

        {/* View transactions link */}
        <Link
          href={`/transactions?categoryId=${row.categoryId}`}
          onClick={onClose}
          className="flex items-center justify-between rounded-xl border border-border px-4 py-3 text-sm font-medium hover:bg-surface-muted transition-colors"
        >
          <span>View transactions in this category</span>
          <ExternalLink className="h-4 w-4 text-muted" />
        </Link>

        {/* History */}
        <div>
          <p className="text-sm font-semibold mb-3">History</p>
          {!history ? (
            <div className="space-y-2">{Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-14" />)}</div>
          ) : history.items.length === 0 ? (
            <p className="py-4 text-center text-sm text-muted">No history yet.</p>
          ) : (
            <ul className="space-y-2">
              {history.items.map((p) => {
                const rem = Number(p.remaining);
                return (
                  <li key={p.index} className={cn('rounded-xl border border-border p-3', p.current && 'border-primary/40 bg-primary/5')}>
                    <div className="mb-1.5 flex items-center justify-between text-sm">
                      <span className="font-medium">
                        {p.label}
                        {p.current && <span className="ml-2 text-xs text-primary">current</span>}
                      </span>
                      <span className="tabular-nums text-muted">{money(p.spent)} / {money(p.effectiveLimit)}</span>
                    </div>
                    <ProgressBar value={Math.min(p.pct, 100)} tone={p.status === 'over' ? 'danger' : p.status === 'warning' ? 'warning' : 'success'} />
                    <div className="mt-1 flex items-center justify-between text-xs text-muted">
                      <span>{p.pct}% used</span>
                      <span className={rem < 0 ? 'font-medium text-danger' : ''}>
                        {rem >= 0 ? `${money(rem)} left` : `${money(Math.abs(rem))} over`}
                      </span>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      </div>
    </Modal>
  );
}
