'use client';

import { ArrowLeftRight, Tag, CreditCard, CalendarDays, FileText, Repeat, User, ArrowUpRight, ArrowDownLeft } from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { financeIcon } from './icons';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type { Transaction } from '@/lib/types';

const kindConfig = {
  INCOME: {
    label: 'Income',
    color: 'text-emerald-600 dark:text-emerald-400',
    bg: 'bg-emerald-500/10',
    icon: ArrowDownLeft,
  },
  EXPENSE: {
    label: 'Expense',
    color: 'text-red-600 dark:text-red-400',
    bg: 'bg-red-500/10',
    icon: ArrowUpRight,
  },
  TRANSFER: {
    label: 'Transfer',
    color: 'text-muted',
    bg: 'bg-surface-muted',
    icon: ArrowLeftRight,
  },
};

function DetailRow({ icon: Icon, label, value, valueClass }: {
  icon: React.ComponentType<{ className?: string }>;
  label: string;
  value: React.ReactNode;
  valueClass?: string;
}) {
  return (
    <div className="flex min-h-14 items-center gap-3 border-b border-border px-4 py-3 last:border-0">
      <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-surface-muted text-muted self-start">
        <Icon className="h-4 w-4" />
      </span>
      <div className="min-w-0 flex-1 py-0.5">
        <p className="mb-0.5 text-xs leading-none text-muted">{label}</p>
        <p className={cn('text-sm font-medium leading-snug', valueClass)}>{value}</p>
      </div>
    </div>
  );
}

export function TransactionDetailModal({
  transaction,
  onClose,
  onEdit,
  onDelete,
}: {
  transaction: Transaction | null;
  onClose: () => void;
  onEdit?: (tx: Transaction) => void;
  onDelete?: (tx: Transaction) => void;
}) {
  const { signedMoney } = useMoney();

  if (!transaction) return null;

  const tx = transaction;
  const config = kindConfig[tx.kind];
  const KindIcon = config.icon;
  const isTransfer = tx.kind === 'TRANSFER';
  const CategoryIcon = isTransfer ? ArrowLeftRight : financeIcon(tx.category?.icon);
  const iconColor = isTransfer ? '#64748b' : (tx.category?.color ?? '#64748b');

  const dateFormatted = new Intl.DateTimeFormat('en-GB', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  }).format(new Date(tx.date));

  return (
    <Modal open={!!transaction} onClose={onClose} title="Transaction Details" className="sm:max-w-2xl">
      <div className="space-y-5">
        <div
          className="overflow-hidden rounded-3xl border border-border bg-linear-to-br from-surface-muted/90 via-surface to-surface-muted/40 p-5 shadow-sm"
          style={{
            backgroundImage: `radial-gradient(circle at top right, ${iconColor}18, transparent 38%), radial-gradient(circle at bottom left, ${iconColor}12, transparent 34%)`,
          }}
        >
          <div className="flex flex-col items-center text-center">
            <span
              className="mb-3 flex h-16 w-16 items-center justify-center rounded-2xl shadow-sm ring-1 ring-border/60"
              style={{ backgroundColor: `${iconColor}22`, color: iconColor }}
            >
              <CategoryIcon className="h-8 w-8" />
            </span>
            <p className={cn('text-3xl font-bold tabular-nums', config.color)}>
              {signedMoney(tx.amount, tx.kind, tx.currency)}
            </p>
            <span className={cn(
              'mt-2 inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold',
              config.bg,
              config.color,
            )}>
              <KindIcon className="h-3 w-3" />
              {config.label}
            </span>
            {tx.pending && (
              <span className="mt-2 rounded-full bg-amber-500/10 px-2 py-0.5 text-[11px] font-medium text-amber-600 dark:text-amber-400">
                ⏳ {tx.pending === 'pending' ? 'Queued (offline)' : tx.pending === 'syncing' ? 'Syncing…' : 'Sync failed'}
              </span>
            )}
          </div>
        </div>

        {tx.budget && (
          <div className="overflow-hidden rounded-2xl border border-border bg-surface">
            <div className="flex items-center gap-3 border-b border-border px-4 py-3">
              <span
                className="flex h-10 w-10 items-center justify-center rounded-xl"
                style={{ backgroundColor: `${tx.budget.color ?? '#6366f1'}22`, color: tx.budget.color ?? '#6366f1' }}
              >
                <ArrowLeftRight className="h-4.5 w-4.5" />
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-xs uppercase tracking-widest text-muted">Parent plan</p>
                <p className="truncate font-semibold">{tx.budget.name}</p>
              </div>
              <div className="text-right">
                <p className="text-sm font-semibold tabular-nums">{tx.budget.currency}</p>
                <p className="text-xs text-muted">
                  {tx.budgetCycle !== null && tx.budgetCycle !== undefined ? `Cycle ${tx.budgetCycle}` : 'Plan spend'}
                </p>
              </div>
            </div>
            <div className="grid gap-3 p-4 sm:grid-cols-3">
              <div className="rounded-xl bg-surface-muted/60 p-3">
                <p className="text-[11px] uppercase tracking-wide text-muted">Plan</p>
                <p className="mt-1 truncate text-sm font-medium">{tx.budget.name}</p>
              </div>
              <div className="rounded-xl bg-surface-muted/60 p-3">
                <p className="text-[11px] uppercase tracking-wide text-muted">Category</p>
                <p className="mt-1 truncate text-sm font-medium">{tx.category?.name ?? 'Uncategorized'}</p>
              </div>
              <div className="rounded-xl bg-surface-muted/60 p-3">
                <p className="text-[11px] uppercase tracking-wide text-muted">Account</p>
                <p className="mt-1 truncate text-sm font-medium">{tx.account?.name ?? 'Unknown'}</p>
              </div>
            </div>
          </div>
        )}

        {/* Detail rows */}
        <div className="rounded-xl border border-border overflow-hidden divide-y divide-border">
          <DetailRow
            icon={CalendarDays}
            label="Date"
            value={dateFormatted}
          />

          {isTransfer ? (
            <DetailRow
              icon={ArrowLeftRight}
              label="Transfer"
              value={`${tx.account?.name ?? '?'} → ${tx.transferAccount?.name ?? '?'}`}
            />
          ) : (
            <>
              {(tx.payee) && (
                <DetailRow
                  icon={User}
                  label="Payee / Merchant"
                  value={tx.payee}
                />
              )}
              {tx.category && (
                <DetailRow
                  icon={financeIcon(tx.category.icon)}
                  label="Category"
                  value={tx.category.name}
                />
              )}
            </>
          )}

          <DetailRow
            icon={CreditCard}
            label="Account"
            value={tx.account?.name ?? 'Unknown'}
          />

          {tx.note && (
            <DetailRow
              icon={FileText}
              label="Note"
              value={tx.note}
            />
          )}

          {tx.tags.length > 0 && (
            <DetailRow
              icon={Tag}
              label="Tags"
              value={
                <span className="flex flex-wrap gap-1 mt-0.5">
                  {tx.tags.map((t) => (
                    <span key={t} className="rounded-full bg-primary/10 px-2 py-0.5 text-[11px] font-medium text-primary">
                      #{t}
                    </span>
                  ))}
                </span>
              }
            />
          )}

          {tx.recurringRuleId && (
            <DetailRow
              icon={Repeat}
              label="Recurring"
              value="Part of a recurring rule"
              valueClass="text-primary"
            />
          )}
        </div>

        <p className="pt-1 text-center font-mono text-[10px] text-muted/50">{tx.id}</p>

        {/* Actions */}
        {!isTransfer && (onEdit || onDelete) && (
          <div className="flex gap-2 pt-4">
            {onEdit && (
              <Button
                type="button"
                variant="outline"
                className="flex-1"
                onClick={() => { onClose(); onEdit(tx); }}
              >
                Edit
              </Button>
            )}
            {onDelete && (
              <Button
                type="button"
                variant="outline"
                className="flex-1 text-danger hover:bg-danger/10"
                onClick={() => { onClose(); onDelete(tx); }}
              >
                Delete
              </Button>
            )}
          </div>
        )}
      </div>
    </Modal>
  );
}
