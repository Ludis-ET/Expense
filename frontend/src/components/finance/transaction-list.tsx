'use client';

import { ArrowLeftRight, Pencil, Trash2, Loader2, Clock, AlertTriangle } from 'lucide-react';
import { financeIcon } from './icons';
import { formatHiddenNumber } from '@/lib/format';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type { Transaction } from '@/lib/types';

function dayLabel(iso: string): string {
  const d = new Date(iso);
  const today = new Date();
  const yesterday = new Date(Date.now() - 86_400_000);
  const sameDay = (a: Date, b: Date) => a.toDateString() === b.toDateString();
  if (sameDay(d, today)) return 'Today';
  if (sameDay(d, yesterday)) return 'Yesterday';
  return new Intl.DateTimeFormat('en-GB', { weekday: 'short', day: '2-digit', month: 'short' }).format(d);
}

const amountColor: Record<Transaction['kind'], string> = {
  INCOME: 'text-emerald-600 dark:text-emerald-400',
  EXPENSE: 'text-red-600 dark:text-red-400',
  TRANSFER: 'text-muted',
};

/** Small badge shown on transactions still queued in the offline outbox. */
function PendingChip({ status }: { status: NonNullable<Transaction['pending']> }) {
  const map = {
    pending: { icon: Clock, text: 'Queued', cls: 'bg-amber-500/10 text-amber-600 dark:text-amber-400' },
    syncing: { icon: Loader2, text: 'Syncing', cls: 'bg-primary/10 text-primary', spin: true },
    error: { icon: AlertTriangle, text: 'Failed', cls: 'bg-danger/10 text-danger' },
  } as const;
  const { icon: Icon, text, cls } = map[status];
  return (
    <span className={cn('inline-flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[10px] font-medium', cls)}>
      <Icon className={cn('h-2.5 w-2.5', status === 'syncing' && 'animate-spin')} /> {text}
    </span>
  );
}

interface TransactionListProps {
  items: Transaction[];
  compact?: boolean;
  onEdit?: (tx: Transaction) => void;
  onDelete?: (tx: Transaction) => void;
}

/** Day-grouped transaction rows with always-visible mobile actions. */
export function TransactionList({ items, compact, onEdit, onDelete }: TransactionListProps) {
  const { signedMoney, hidden } = useMoney();
  const groups: { day: string; items: Transaction[]; net: number }[] = [];
  for (const tx of items) {
    const day = tx.date.slice(0, 10);
    let group = groups[groups.length - 1];
    if (!group || group.day !== day) {
      group = { day, items: [], net: 0 };
      groups.push(group);
    }
    group.items.push(tx);
    if (tx.kind === 'INCOME') group.net += Number(tx.amount);
    if (tx.kind === 'EXPENSE') group.net -= Number(tx.amount);
  }

  return (
    <div className="space-y-4">
      {groups.map((group) => (
        <div key={group.day}>
          <div className="mb-1 flex items-baseline justify-between px-1">
            <p className="text-xs font-semibold uppercase tracking-wide text-muted">
              {dayLabel(group.items[0]!.date)}
            </p>
            {!compact && (
              <p
                className={cn(
                  'text-xs font-medium tabular-nums',
                  group.net >= 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-muted',
                )}
              >
                {hidden
                  ? formatHiddenNumber()
                  : `${group.net >= 0 ? '+' : '−'}${Math.abs(group.net).toLocaleString()}`}
              </p>
            )}
          </div>
          <ul className="overflow-hidden rounded-xl border border-border bg-surface">
            {group.items.map((tx) => {
              const isTransfer = tx.kind === 'TRANSFER';
              const Icon = isTransfer ? ArrowLeftRight : financeIcon(tx.category?.icon);
              const color = isTransfer ? '#64748b' : (tx.category?.color ?? '#64748b');
              return (
                <li
                  key={tx.id}
                  className={cn(
                    'flex items-center gap-2 border-b border-border px-3 py-3 last:border-b-0 sm:gap-3 sm:px-4',
                    tx.pending && 'bg-primary/[0.03]',
                  )}
                >
                  <span
                    className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg"
                    style={{ backgroundColor: `${color}22`, color }}
                  >
                    <Icon className="h-4.5 w-4.5" />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="flex items-center gap-1.5 truncate text-sm font-medium">
                      <span className="truncate">
                        {isTransfer
                          ? `${tx.account?.name ?? '?'} → ${tx.transferAccount?.name ?? '?'}`
                          : (tx.payee || tx.category?.name || '-')}
                      </span>
                      {tx.pending && <PendingChip status={tx.pending} />}
                    </p>
                    <p className="truncate text-xs text-muted">
                      {isTransfer
                        ? (tx.note ?? 'Transfer')
                        : [tx.category?.name, tx.account?.name, tx.note].filter(Boolean).join(' · ')}
                      {tx.tags.length > 0 && (
                        <span className="ml-1 text-primary">{tx.tags.map((t) => `#${t}`).join(' ')}</span>
                      )}
                    </p>
                  </div>
                  <span className={cn('shrink-0 text-sm font-semibold tabular-nums', amountColor[tx.kind])}>
                    {signedMoney(tx.amount, tx.kind, tx.currency)}
                  </span>
                  {(onEdit || onDelete) && (
                    <span className="flex shrink-0 items-center gap-0.5">
                      {onEdit && !isTransfer && (
                        <button
                          type="button"
                          onClick={() => onEdit(tx)}
                          className="flex h-9 w-9 items-center justify-center rounded-lg text-muted hover:bg-surface-muted hover:text-foreground"
                          aria-label="Edit"
                        >
                          <Pencil className="h-4 w-4" />
                        </button>
                      )}
                      {onDelete && (
                        <button
                          type="button"
                          onClick={() => onDelete(tx)}
                          className="flex h-9 w-9 items-center justify-center rounded-lg text-muted hover:bg-surface-muted hover:text-danger"
                          aria-label="Delete"
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      )}
                    </span>
                  )}
                </li>
              );
            })}
          </ul>
        </div>
      ))}
    </div>
  );
}
