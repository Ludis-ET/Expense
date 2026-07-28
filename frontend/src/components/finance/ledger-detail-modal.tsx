'use client';

import { ArrowDownLeft, ArrowUpRight, CalendarDays, CalendarCheck, FileText, Coins, Sparkles, CalendarClock, CheckCircle2, AlertTriangle } from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { ProgressBar } from '@/components/ui/misc';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import { formatDate } from '@/lib/format';
import type { LedgerEntry } from '@/lib/types';

const kindConfig = {
  LENT: {
    label: 'They owe you',
    icon: ArrowDownLeft,
    color: 'text-emerald-600 dark:text-emerald-400',
    bg: 'bg-emerald-500/10',
    progressTone: 'success' as const,
    progressLabel: 'settled',
  },
  BORROWED: {
    label: 'You owe',
    icon: ArrowUpRight,
    color: 'text-amber-600 dark:text-amber-400',
    bg: 'bg-amber-500/10',
    progressTone: 'warning' as const,
    progressLabel: 'paid',
  },
  EXPECTED_IN: {
    label: 'Expected in',
    icon: Sparkles,
    color: 'text-sky-600 dark:text-sky-400',
    bg: 'bg-sky-500/10',
    progressTone: 'primary' as const,
    progressLabel: 'received',
  },
  EXPECTED_OUT: {
    label: 'Expected out',
    icon: CalendarClock,
    color: 'text-violet-600 dark:text-violet-400',
    bg: 'bg-violet-500/10',
    progressTone: 'warning' as const,
    progressLabel: 'paid',
  },
};

export function LedgerDetailModal({
  entry,
  onClose,
  onRecord,
  onEdit,
  onRemove,
}: {
  entry: LedgerEntry | null;
  onClose: () => void;
  onRecord: () => void;
  onEdit: () => void;
  onRemove: () => void;
}) {
  const { money } = useMoney(entry?.currency);

  if (!entry) return null;

  const config = kindConfig[entry.kind];
  const KindIcon = config.icon;
  const totalAmount = Number(entry.totalAmount);
  const remaining = Number(entry.remaining);

  function recordLabel() {
    if (entry!.kind === 'EXPECTED_IN') return 'Mark received';
    if (entry!.kind === 'EXPECTED_OUT') return 'Mark paid';
    if (entry!.kind === 'LENT') return 'Record repayment';
    return 'Record payment';
  }

  return (
    <Modal open={!!entry} onClose={onClose} title="Tab Details">
      <div className="space-y-5">
        {/* Hero */}
        <div className="rounded-2xl border border-border bg-surface-muted/30 p-5">
          <div className="flex items-start gap-4">
            <span className={cn('flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl', config.bg, config.color)}>
              <KindIcon className="h-6 w-6" />
            </span>
            <div className="flex-1">
              <p className="text-lg font-bold">{entry.counterparty}</p>
              {entry.title && <p className="text-sm text-muted">{entry.title}</p>}
              <span className={cn('mt-1 inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold', config.bg, config.color)}>
                {config.label}
              </span>
            </div>
            <div className="text-right">
              <p className="text-2xl font-bold tabular-nums">{money(remaining)}</p>
              <p className="text-xs text-muted">of {money(totalAmount)}</p>
            </div>
          </div>

          <div className="mt-4">
            <ProgressBar value={entry.pct} tone={config.progressTone} />
            <div className="mt-1.5 flex justify-between text-xs text-muted">
              <span>{entry.pct}% {config.progressLabel}</span>
              {entry.dueDate && (
                <span className={cn(entry.isOverdue && 'font-medium text-warning')}>
                  {entry.isOverdue && <AlertTriangle className="inline h-3 w-3 mr-0.5" />}
                  {entry.isOverdue ? 'Overdue · ' : 'Due '}{formatDate(entry.dueDate)}
                </span>
              )}
            </div>
          </div>
        </div>

        {/* Details */}
        <div className="rounded-xl border border-border divide-y divide-border overflow-hidden">
          <div className="flex items-center gap-3 px-4 py-3">
            <Coins className="h-4 w-4 shrink-0 text-muted" />
            <div className="flex-1">
              <p className="text-xs text-muted">Amount</p>
              <p className="text-sm font-medium">{money(totalAmount)} {entry.currency}</p>
            </div>
          </div>
          {entry.dueDate && (
            <div className="flex items-center gap-3 px-4 py-3">
              <CalendarDays className="h-4 w-4 shrink-0 text-muted" />
              <div className="flex-1">
                <p className="text-xs text-muted">Due date</p>
                <p className={cn('text-sm font-medium', entry.isOverdue && 'text-warning')}>
                  {formatDate(entry.dueDate)}
                  {entry.isOverdue && <span className="ml-1.5 text-xs">(overdue)</span>}
                </p>
              </div>
            </div>
          )}
          {entry.settledAt && (
            <div className="flex items-center gap-3 px-4 py-3">
              <CalendarCheck className="h-4 w-4 shrink-0 text-muted" />
              <div className="flex-1">
                <p className="text-xs text-muted">Settled on</p>
                <p className="text-sm font-medium">{formatDate(entry.settledAt)}</p>
              </div>
            </div>
          )}
          {entry.note && (
            <div className="flex items-start gap-3 px-4 py-3">
              <FileText className="h-4 w-4 shrink-0 text-muted mt-0.5" />
              <div className="flex-1">
                <p className="text-xs text-muted">Note</p>
                <p className="text-sm font-medium">{entry.note}</p>
              </div>
            </div>
          )}
        </div>

        {/* Payment history */}
        {entry.payments.length > 0 && (
          <div>
            <p className="text-sm font-semibold mb-3">Payment history</p>
            <ul className="space-y-2">
              {entry.payments.map((p) => (
                <li key={p.id} className="flex items-center justify-between rounded-xl border border-border px-4 py-3">
                  <div className="flex items-center gap-3">
                    <CheckCircle2 className="h-4 w-4 text-emerald-500 shrink-0" />
                    <div>
                      <p className="text-sm font-medium tabular-nums">{money(p.amount)}</p>
                      {p.note && <p className="text-xs text-muted">{p.note}</p>}
                    </div>
                  </div>
                  <p className="text-xs text-muted">{formatDate(p.date)}</p>
                </li>
              ))}
            </ul>
          </div>
        )}

        {/* Actions */}
        {entry.status === 'OPEN' && (
          <div className="flex flex-wrap gap-2">
            <Button
              className="flex-1"
              onClick={() => { onClose(); onRecord(); }}
            >
              {recordLabel()}
            </Button>
            <Button
              variant="outline"
              onClick={() => { onClose(); onEdit(); }}
            >
              Edit
            </Button>
            <Button
              variant="outline"
              className="text-danger hover:bg-danger/10"
              onClick={() => { onClose(); onRemove(); }}
            >
              Delete
            </Button>
          </div>
        )}
      </div>
    </Modal>
  );
}
