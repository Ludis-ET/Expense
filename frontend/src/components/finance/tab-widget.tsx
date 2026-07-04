'use client';

import Link from 'next/link';
import { AlertTriangle, ArrowDownLeft, ArrowUpRight, HandCoins, Sparkles } from 'lucide-react';
import { ProgressBar } from '@/components/ui/misc';
import { formatMoney, formatDate } from '@/lib/format';
import type { LedgerEntry, LedgerSummary } from '@/lib/types';
import { cn } from '@/lib/utils';

const kindMeta = {
  LENT: { label: 'They owe you', tone: 'text-emerald-600 dark:text-emerald-400', bg: 'bg-emerald-500/10', icon: ArrowDownLeft },
  BORROWED: { label: 'You owe', tone: 'text-amber-600 dark:text-amber-400', bg: 'bg-amber-500/10', icon: ArrowUpRight },
  EXPECTED_IN: { label: 'Incoming', tone: 'text-sky-600 dark:text-sky-400', bg: 'bg-sky-500/10', icon: Sparkles },
} as const;

export function TabWidget({
  tab,
  money,
}: {
  tab: LedgerSummary;
  money: (v: number | string) => string;
}) {
  if (tab.openCount === 0) {
    return (
      <div className="card flex flex-col items-center p-6 text-center">
        <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
          <HandCoins className="h-6 w-6" />
        </span>
        <p className="mt-3 font-semibold">Money Tab</p>
        <p className="mt-1 max-w-xs text-sm text-muted">
          Track loans, debts, and one-off payments you&apos;re still waiting on.
        </p>
        <Link href="/tab" className="mt-4 text-sm font-medium text-primary hover:underline">
          Open Tab →
        </Link>
      </div>
    );
  }

  return (
    <div className="card p-5">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <HandCoins className="h-4 w-4 text-primary" />
          <p className="font-semibold">Money Tab</p>
        </div>
        <Link href="/tab" className="text-xs font-medium text-primary hover:underline">
          View all
        </Link>
      </div>

      <div className="mt-4 grid grid-cols-3 gap-2 text-center">
        <div className="rounded-xl bg-emerald-500/8 px-2 py-2">
          <p className="text-[10px] font-medium uppercase tracking-wide text-muted">Owed to you</p>
          <p className="mt-0.5 text-sm font-bold tabular-nums text-emerald-600 dark:text-emerald-400">{money(tab.receivable)}</p>
        </div>
        <div className="rounded-xl bg-sky-500/8 px-2 py-2">
          <p className="text-[10px] font-medium uppercase tracking-wide text-muted">Incoming</p>
          <p className="mt-0.5 text-sm font-bold tabular-nums text-sky-600 dark:text-sky-400">{money(tab.expectedIn)}</p>
        </div>
        <div className="rounded-xl bg-amber-500/8 px-2 py-2">
          <p className="text-[10px] font-medium uppercase tracking-wide text-muted">You owe</p>
          <p className="mt-0.5 text-sm font-bold tabular-nums text-amber-600 dark:text-amber-400">{money(tab.payable)}</p>
        </div>
      </div>

      {tab.overdueCount > 0 && (
        <p className="mt-3 flex items-center gap-1.5 text-xs text-warning">
          <AlertTriangle className="h-3.5 w-3.5" />
          {tab.overdueCount} overdue · net position {money(tab.netPosition)}
        </p>
      )}

      <ul className="mt-4 space-y-2">
        {tab.highlights.slice(0, 3).map((e) => (
          <MiniRow key={e.id} entry={e} money={money} />
        ))}
      </ul>
    </div>
  );
}

function MiniRow({ entry, money }: { entry: LedgerEntry; money: (v: number | string) => string }) {
  const meta = kindMeta[entry.kind];
  const Icon = meta.icon;
  return (
    <li className="flex items-center gap-2 rounded-lg bg-surface-muted/50 px-3 py-2">
      <span className={cn('flex h-7 w-7 shrink-0 items-center justify-center rounded-lg', meta.bg, meta.tone)}>
        <Icon className="h-3.5 w-3.5" />
      </span>
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium">{entry.counterparty}</p>
        <p className="text-[10px] text-muted">{meta.label}{entry.dueDate ? ` · ${formatDate(entry.dueDate)}` : ''}</p>
      </div>
      <span className="shrink-0 text-sm font-semibold tabular-nums">{money(entry.remaining)}</span>
    </li>
  );
}

export function TabEntryCard({
  entry,
  money,
  onRecord,
  onEdit,
  onRemove,
}: {
  entry: LedgerEntry;
  money: (v: number | string) => string;
  onRecord: () => void;
  onEdit: () => void;
  onRemove: () => void;
}) {
  const meta = kindMeta[entry.kind];
  const Icon = meta.icon;
  const label = entry.title?.trim() || entry.counterparty;

  return (
    <div className={cn('card overflow-hidden', entry.isOverdue && 'ring-1 ring-warning/40')}>
      <div className="p-5">
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-start gap-3">
            <span className={cn('flex h-11 w-11 shrink-0 items-center justify-center rounded-xl', meta.bg, meta.tone)}>
              <Icon className="h-5 w-5" />
            </span>
            <div>
              <p className="font-semibold">{entry.counterparty}</p>
              {entry.title && <p className="text-sm text-muted">{entry.title}</p>}
              <p className={cn('mt-1 text-xs font-medium', meta.tone)}>{meta.label}</p>
            </div>
          </div>
          <div className="text-right">
            <p className="text-lg font-bold tabular-nums">{money(entry.remaining)}</p>
            <p className="text-xs text-muted">of {money(entry.totalAmount)}</p>
          </div>
        </div>

        <div className="mt-4">
          <ProgressBar
            value={entry.pct}
            tone={entry.kind === 'BORROWED' ? 'warning' : entry.kind === 'EXPECTED_IN' ? 'primary' : 'success'}
          />
          <div className="mt-1 flex justify-between text-xs text-muted">
            <span>{entry.pct}% {entry.kind === 'EXPECTED_IN' ? 'received' : 'settled'}</span>
            {entry.dueDate && (
              <span className={entry.isOverdue ? 'font-medium text-warning' : ''}>
                {entry.isOverdue ? 'Overdue · ' : 'Due '}{formatDate(entry.dueDate)}
              </span>
            )}
          </div>
        </div>

        {entry.note && <p className="mt-3 text-sm text-muted">{entry.note}</p>}

        {entry.status === 'OPEN' && (
          <div className="mt-4 flex flex-wrap gap-2">
            <button
              type="button"
              onClick={onRecord}
              className="rounded-lg bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:opacity-90"
            >
              {entry.kind === 'EXPECTED_IN' ? 'Mark received' : entry.kind === 'LENT' ? 'Record repayment' : 'Record payment'}
            </button>
            <button type="button" onClick={onEdit} className="rounded-lg border border-border px-3 py-1.5 text-xs font-medium text-muted hover:bg-surface-muted">
              Edit
            </button>
            <button type="button" onClick={onRemove} className="rounded-lg px-3 py-1.5 text-xs font-medium text-muted hover:text-danger">
              Delete
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
