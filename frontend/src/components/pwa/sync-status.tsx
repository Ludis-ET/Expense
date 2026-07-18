'use client';

import { useEffect, useState } from 'react';
import {
  AlertTriangle,
  Check,
  CloudOff,
  Loader2,
  RefreshCw,
  RotateCw,
  Trash2,
  UploadCloud,
} from 'lucide-react';
import { useOffline } from '@/lib/offline/offline-context';
import type { OutboxOp } from '@/lib/offline/outbox';
import { cn } from '@/lib/utils';

function opLabel(op: OutboxOp): string {
  const amt = op.optimistic ? Number(op.optimistic.amount).toLocaleString() : '';
  switch (op.kind) {
    case 'create':
      return `${op.optimistic?.kind === 'INCOME' ? 'Income' : 'Expense'} ${amt}`.trim();
    case 'transfer':
      return `Transfer ${amt}`.trim();
    case 'update':
      return `Edit ${amt}`.trim();
    case 'delete':
      return 'Delete transaction';
  }
}

export function SyncStatus() {
  const { online, syncing, justSynced, pendingCount, errorCount, ops, flush, retry, discard } = useOffline();
  const [open, setOpen] = useState(false);

  // Nothing to show: online, idle, empty queue, and no recent flourish.
  const idle = online && !syncing && pendingCount === 0 && errorCount === 0 && !justSynced;

  // Auto-close the panel once everything has drained.
  useEffect(() => {
    if (open && idle) setOpen(false);
  }, [open, idle]);

  if (idle) return null;

  let icon = <UploadCloud className="h-4.5 w-4.5" />;
  let label = 'Pending';
  let toneClass = 'text-muted hover:bg-surface-muted';

  if (!online) {
    icon = <CloudOff className="h-4.5 w-4.5" />;
    label = 'Offline';
    toneClass = 'text-amber-600 dark:text-amber-400 hover:bg-amber-500/10';
  } else if (syncing) {
    icon = <Loader2 className="h-4.5 w-4.5 animate-spin" />;
    label = 'Syncing…';
    toneClass = 'text-primary hover:bg-primary/10';
  } else if (errorCount > 0) {
    icon = <AlertTriangle className="h-4.5 w-4.5" />;
    label = `${errorCount} failed`;
    toneClass = 'text-danger hover:bg-danger/10';
  } else if (justSynced && pendingCount === 0) {
    icon = <Check className="h-4.5 w-4.5" />;
    label = 'Synced';
    toneClass = 'text-emerald-600 dark:text-emerald-400 hover:bg-emerald-500/10';
  }

  const badge = pendingCount > 0 && !syncing;

  return (
    <div className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className={cn(
          'relative flex items-center gap-1.5 rounded-xl px-2 py-2 text-sm font-medium transition-colors',
          toneClass,
          justSynced && pendingCount === 0 && 'animate-in',
        )}
        aria-label={`Sync status: ${label}`}
        title={label}
      >
        <span className={cn('grid place-items-center', justSynced && pendingCount === 0 && 'sync-pop')}>{icon}</span>
        <span className="hidden text-xs md:inline">{label}</span>
        {badge && (
          <span className="absolute -right-0.5 -top-0.5 grid h-4 min-w-4 place-items-center rounded-full bg-primary px-1 text-[10px] font-semibold text-primary-foreground">
            {pendingCount}
          </span>
        )}
        {!online && pendingCount === 0 && (
          <span className="absolute right-1 top-1.5 h-2 w-2 animate-pulse rounded-full bg-amber-500" />
        )}
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute right-0 z-50 mt-2 w-72 overflow-hidden rounded-xl border border-border bg-surface shadow-xl animate-in">
            <div className="flex items-center justify-between border-b border-border px-4 py-3">
              <div>
                <p className="text-sm font-medium">
                  {online ? 'Connected' : 'Working offline'}
                </p>
                <p className="text-xs text-muted">
                  {pendingCount > 0
                    ? `${pendingCount} change${pendingCount > 1 ? 's' : ''} waiting to sync`
                    : errorCount > 0
                      ? `${errorCount} change${errorCount > 1 ? 's' : ''} need attention`
                      : 'Everything is up to date'}
                </p>
              </div>
              <span
                className={cn(
                  'h-2.5 w-2.5 rounded-full',
                  online ? 'bg-emerald-500' : 'bg-amber-500 animate-pulse',
                )}
              />
            </div>

            {ops.length > 0 ? (
              <ul className="max-h-64 overflow-y-auto p-1.5">
                {ops.map((op) => (
                  <li
                    key={op.id}
                    className="flex items-center gap-2 rounded-lg px-2.5 py-2 text-sm"
                  >
                    <span
                      className={cn(
                        'grid h-7 w-7 shrink-0 place-items-center rounded-lg',
                        op.status === 'error'
                          ? 'bg-danger/10 text-danger'
                          : op.status === 'syncing'
                            ? 'bg-primary/10 text-primary'
                            : 'bg-surface-muted text-muted',
                      )}
                    >
                      {op.status === 'syncing' ? (
                        <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      ) : op.status === 'error' ? (
                        <AlertTriangle className="h-3.5 w-3.5" />
                      ) : (
                        <UploadCloud className="h-3.5 w-3.5" />
                      )}
                    </span>
                    <div className="min-w-0 flex-1">
                      <p className="truncate font-medium">{opLabel(op)}</p>
                      {op.status === 'error' && op.error && (
                        <p className="truncate text-xs text-danger">{op.error}</p>
                      )}
                    </div>
                    {op.status === 'error' && (
                      <span className="flex shrink-0 items-center gap-0.5">
                        <button
                          onClick={() => retry(op.id)}
                          className="grid h-7 w-7 place-items-center rounded-lg text-muted hover:bg-surface-muted hover:text-foreground"
                          aria-label="Retry"
                          title="Retry"
                        >
                          <RotateCw className="h-3.5 w-3.5" />
                        </button>
                        <button
                          onClick={() => discard(op.id)}
                          className="grid h-7 w-7 place-items-center rounded-lg text-muted hover:bg-surface-muted hover:text-danger"
                          aria-label="Discard"
                          title="Discard"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </button>
                      </span>
                    )}
                  </li>
                ))}
              </ul>
            ) : (
              <div className="grid place-items-center gap-2 px-4 py-8 text-center">
                <span className="grid h-10 w-10 place-items-center rounded-full bg-emerald-500/10 text-emerald-600 dark:text-emerald-400">
                  <Check className="h-5 w-5" />
                </span>
                <p className="text-sm text-muted">No changes waiting.</p>
              </div>
            )}

            {online && pendingCount > 0 && (
              <div className="border-t border-border p-2">
                <button
                  onClick={() => flush()}
                  disabled={syncing}
                  className="flex w-full items-center justify-center gap-2 rounded-lg bg-primary px-3 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:opacity-60"
                >
                  <RefreshCw className={cn('h-4 w-4', syncing && 'animate-spin')} /> Sync now
                </button>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
