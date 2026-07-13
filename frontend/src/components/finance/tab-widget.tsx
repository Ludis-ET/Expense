'use client';

import Link from 'next/link';
import {
  AlertTriangle,
  ArrowDownLeft,
  ArrowUpRight,
  CalendarClock,
  HandCoins,
  Sparkles,
  TrendingUp,
} from 'lucide-react';
import { ProgressBar } from '@/components/ui/misc';
import { formatDate } from '@/lib/format';
import type { LedgerEntry, LedgerSummary } from '@/lib/types';
import { cn } from '@/lib/utils';

export const kindMeta = {
  LENT: { label: 'They owe you', tone: 'text-emerald-600 dark:text-emerald-400', bg: 'bg-emerald-500/10', icon: ArrowDownLeft },
  BORROWED: { label: 'You owe', tone: 'text-amber-600 dark:text-amber-400', bg: 'bg-amber-500/10', icon: ArrowUpRight },
  EXPECTED_IN: { label: 'Incoming', tone: 'text-sky-600 dark:text-sky-400', bg: 'bg-sky-500/10', icon: Sparkles },
  EXPECTED_OUT: { label: 'Outgoing', tone: 'text-violet-600 dark:text-violet-400', bg: 'bg-violet-500/10', icon: CalendarClock },
} as const;

export function TabWidget({
  tab,
  money,
}: {
  tab: LedgerSummary | null | undefined;
  money: (v: number | string) => string;
}) {
  if (!tab || tab.openCount === 0) {
    return (
      <div className="card flex flex-col items-center p-6 text-center">
        <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
          <HandCoins className="h-6 w-6" />
        </span>
        <p className="mt-3 font-semibold">Money Tab</p>
        <p className="mt-1 max-w-xs text-sm text-muted">
          Track loans, debts, and one-off money moving between you and others.
        </p>
        <Link href="/tab" className="mt-4 text-sm font-medium text-primary hover:underline">
          Open Tab →
        </Link>
      </div>
    );
  }

  const forecastNet = Number(tab.forecast?.netIfOnTime ?? 0);

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

      {tab.forecast && (
        <div className="mt-3 flex items-center gap-2 rounded-xl bg-primary/8 px-3 py-2.5 text-sm">
          <TrendingUp className="h-4 w-4 shrink-0 text-primary" />
          <p className="leading-snug">
            If due tabs settle this month:{' '}
            <span className={cn('font-bold tabular-nums', forecastNet >= 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-amber-600 dark:text-amber-400')}>
              {forecastNet >= 0 ? '+' : ''}{money(forecastNet)}
            </span>
          </p>
        </div>
      )}

      <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
        <MiniStat label="Owed to you" value={money(tab.receivable)} tone="emerald" />
        <MiniStat label="Incoming" value={money(tab.expectedIn)} tone="sky" />
        <MiniStat label="You owe" value={money(tab.payable)} tone="amber" />
        <MiniStat label="Outgoing" value={money(tab.expectedOut)} tone="violet" />
      </div>

      {tab.overdueCount > 0 && (
        <p className="mt-3 flex items-center gap-1.5 text-xs text-warning">
          <AlertTriangle className="h-3.5 w-3.5" />
          {tab.overdueCount} overdue · net {money(tab.netPosition)}
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

function MiniStat({ label, value, tone }: { label: string; value: string; tone: 'emerald' | 'sky' | 'amber' | 'violet' }) {
  const toneClass = {
    emerald: 'text-emerald-600 dark:text-emerald-400',
    sky: 'text-sky-600 dark:text-sky-400',
    amber: 'text-amber-600 dark:text-amber-400',
    violet: 'text-violet-600 dark:text-violet-400',
  }[tone];
  return (
    <div className="rounded-xl bg-surface-muted/50 px-2 py-2 text-center">
      <p className="text-[10px] font-medium uppercase tracking-wide text-muted">{label}</p>
      <p className={cn('mt-0.5 text-sm font-bold tabular-nums', toneClass)}>{value}</p>
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

function recordLabel(kind: LedgerEntry['kind']) {
  if (kind === 'EXPECTED_IN') return 'Mark received';
  if (kind === 'EXPECTED_OUT') return 'Mark paid';
  if (kind === 'LENT') return 'Record repayment';
  return 'Record payment';
}

function progressTone(kind: LedgerEntry['kind']) {
  if (kind === 'BORROWED' || kind === 'EXPECTED_OUT') return 'warning' as const;
  if (kind === 'EXPECTED_IN') return 'primary' as const;
  return 'success' as const;
}

function progressLabel(kind: LedgerEntry['kind']) {
  if (kind === 'EXPECTED_IN') return 'received';
  if (kind === 'EXPECTED_OUT') return 'paid';
  return 'settled';
}

export function TabEntryCard({
  entry,
  money,
  onRecord,
  onEdit,
  onRemove,
  compact,
}: {
  entry: LedgerEntry;
  money: (v: number | string) => string;
  onRecord: () => void;
  onEdit: () => void;
  onRemove: () => void;
  compact?: boolean;
}) {
  const meta = kindMeta[entry.kind];
  const Icon = meta.icon;

  return (
    <div className={cn('card overflow-hidden', entry.isOverdue && 'ring-1 ring-warning/40')}>
      <div className={cn('p-5', compact && 'p-4')}>
        <div className="flex items-start justify-between gap-3">
          <div className="flex items-start gap-3">
            <span className={cn('flex h-11 w-11 shrink-0 items-center justify-center rounded-xl', meta.bg, meta.tone)}>
              <Icon className="h-5 w-5" />
            </span>
            <div>
              {!compact && <p className="font-semibold">{entry.counterparty}</p>}
              {entry.title && <p className={cn('text-sm text-muted', compact && 'font-medium text-foreground')}>{entry.title}</p>}
              {!compact && entry.title && <p className="text-xs text-muted">{entry.counterparty}</p>}
              {compact && !entry.title && <p className="font-medium">{entry.counterparty}</p>}
              <p className={cn('mt-1 text-xs font-medium', meta.tone)}>{meta.label}</p>
            </div>
          </div>
          <div className="text-right">
            <p className="text-lg font-bold tabular-nums">{money(entry.remaining)}</p>
            <p className="text-xs text-muted">of {money(entry.totalAmount)}</p>
          </div>
        </div>

        <div className="mt-4">
          <ProgressBar value={entry.pct} tone={progressTone(entry.kind)} />
          <div className="mt-1 flex justify-between text-xs text-muted">
            <span>{entry.pct}% {progressLabel(entry.kind)}</span>
            {entry.dueDate && (
              <span className={entry.isOverdue ? 'font-medium text-warning' : ''}>
                {entry.isOverdue ? 'Overdue · ' : 'Due '}{formatDate(entry.dueDate)}
              </span>
            )}
          </div>
        </div>

        {entry.note && !compact && <p className="mt-3 text-sm text-muted">{entry.note}</p>}

        {entry.status === 'OPEN' && !compact && (
          <div className="mt-4 flex flex-wrap gap-2">
            <button
              type="button"
              onClick={onRecord}
              className="rounded-lg bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:opacity-90"
            >
              {recordLabel(entry.kind)}
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

export function PersonTabCard({
  group,
  money,
  onRecord,
  onEdit,
}: {
  group: import('@/lib/types').LedgerPersonGroup;
  money: (v: number | string) => string;
  onRecord: (entry: LedgerEntry) => void;
  onEdit: (entry: LedgerEntry) => void;
  onRemove?: (entry: LedgerEntry) => void;
}) {
  const net = Number(group.netRemaining);
  return (
    <div className="card overflow-hidden">
      <div className="border-b border-border bg-surface-muted/40 px-5 py-4">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <span className="flex h-11 w-11 items-center justify-center rounded-full bg-primary/10 text-sm font-bold text-primary">
              {group.counterparty.slice(0, 2).toUpperCase()}
            </span>
            <div>
              <p className="font-semibold">{group.counterparty}</p>
              <p className="text-xs text-muted">{group.openCount} open tab{group.openCount === 1 ? '' : 's'}</p>
            </div>
          </div>
          <div className="text-right">
            <p className={cn('text-lg font-bold tabular-nums', net >= 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-amber-600 dark:text-amber-400')}>
              {net >= 0 ? '+' : ''}{money(net)}
            </p>
            <p className="text-[10px] text-muted">{net >= 0 ? 'net in your favour' : 'net you owe'}</p>
          </div>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-2 text-xs sm:grid-cols-4">
          <span className="text-muted">Owed: <strong className="text-emerald-600 dark:text-emerald-400">{money(group.receivable)}</strong></span>
          <span className="text-muted">Incoming: <strong className="text-sky-600 dark:text-sky-400">{money(group.expectedIn)}</strong></span>
          <span className="text-muted">You owe: <strong className="text-amber-600 dark:text-amber-400">{money(group.payable)}</strong></span>
          <span className="text-muted">Outgoing: <strong className="text-violet-600 dark:text-violet-400">{money(group.expectedOut)}</strong></span>
        </div>
      </div>
      <ul className="divide-y divide-border">
        {group.entries.map((entry) => {
          const meta = kindMeta[entry.kind];
          const Icon = meta.icon;
          return (
            <li key={entry.id} className="flex flex-wrap items-center gap-3 px-5 py-3">
              <span className={cn('flex h-8 w-8 shrink-0 items-center justify-center rounded-lg', meta.bg, meta.tone)}>
                <Icon className="h-4 w-4" />
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium">{entry.title || meta.label}</p>
                <p className="text-xs text-muted">
                  {entry.title ? meta.label : ''}{entry.dueDate ? ` · ${formatDate(entry.dueDate)}` : ''}
                  {entry.isOverdue ? ' · overdue' : ''}
                </p>
              </div>
              <span className="text-sm font-semibold tabular-nums">{money(entry.remaining)}</span>
              <div className="flex gap-1">
                <button type="button" onClick={() => onRecord(entry)} className="rounded-md bg-primary/10 px-2 py-1 text-[10px] font-medium text-primary">
                  {recordLabel(entry.kind)}
                </button>
                <button type="button" onClick={() => onEdit(entry)} className="rounded-md px-2 py-1 text-[10px] text-muted hover:bg-surface-muted">Edit</button>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
