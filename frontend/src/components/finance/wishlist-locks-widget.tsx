'use client';

import Link from 'next/link';
import { Lock, Sparkles, Check, Star } from 'lucide-react';
import type { SpendLockOverview, WishlistDigest } from '@/lib/types';
import { cn } from '@/lib/utils';

const PRIORITY_LABEL = ['', 'Must have', 'Soon', 'Nice', 'Someday', 'Dream'];

/** Unlocked-to-spend summary, mirroring the Spend Locks page hero in miniature. */
export function SpendableWidget({
  spendable,
  money,
}: {
  spendable: SpendLockOverview | null | undefined;
  money: (v: number | string) => string;
}) {
  if (!spendable) return null;

  if (spendable.lockCount === 0) {
    return (
      <div className="card flex flex-col items-center p-6 text-center">
        <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
          <Lock className="h-6 w-6" />
        </span>
        <p className="mt-3 font-semibold">Spend locks</p>
        <p className="mt-1 max-w-xs text-sm text-muted">
          Ring-fence a safety floor or vault money for a goal so you never overspend.
        </p>
        <Link href="/locks" className="mt-4 text-sm font-medium text-primary hover:underline">
          Set a lock →
        </Link>
      </div>
    );
  }

  const balance = Number(spendable.balance);
  const pct = balance > 0 ? Math.round((Number(spendable.spendable) / balance) * 100) : 100;

  return (
    <div className="card p-5">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Lock className="h-4 w-4 text-primary" />
          <p className="font-semibold">Safe to spend</p>
        </div>
        <Link href="/locks" className="text-xs font-medium text-primary hover:underline">
          Manage
        </Link>
      </div>

      <p className="mt-3 text-3xl font-bold tabular-nums text-emerald-600 dark:text-emerald-400">
        {money(spendable.spendable)}
      </p>
      <p className="mt-0.5 text-xs text-muted">
        of {money(spendable.balance)} · {spendable.lockCount} active lock
        {spendable.lockCount === 1 ? '' : 's'}
      </p>

      <div className="mt-3 h-2 overflow-hidden rounded-full bg-surface-muted">
        <div
          className={cn('h-full rounded-full transition-all', spendable.conflict ? 'bg-amber-500' : 'bg-emerald-500')}
          style={{ width: `${Math.max(2, pct)}%` }}
        />
      </div>

      <div className="mt-3 grid grid-cols-2 gap-2 text-xs">
        <span className="text-muted">
          Floor: <strong className="tabular-nums text-foreground">{money(spendable.floorAmount)}</strong>
        </span>
        <span className="text-muted">
          Reserved: <strong className="tabular-nums text-foreground">{money(spendable.reservedAmount)}</strong>
        </span>
      </div>

      {spendable.hint && (
        <p className="mt-3 rounded-lg bg-amber-500/10 px-3 py-2 text-xs text-amber-600 dark:text-amber-400">
          {spendable.hint}
        </p>
      )}
    </div>
  );
}

/** "Closest wants" digest with an affordable-now signal. */
export function WishlistWidget({
  wishlist,
  money,
}: {
  wishlist: WishlistDigest | null | undefined;
  money: (v: number | string) => string;
}) {
  if (!wishlist || wishlist.activeCount === 0) {
    return (
      <div className="card flex flex-col items-center p-6 text-center">
        <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
          <Sparkles className="h-6 w-6" />
        </span>
        <p className="mt-3 font-semibold">Wishlist</p>
        <p className="mt-1 max-w-xs text-sm text-muted">
          Park the things you want and watch them get closer as you save.
        </p>
        <Link href="/wishlist" className="mt-4 text-sm font-medium text-primary hover:underline">
          Add a want →
        </Link>
      </div>
    );
  }

  return (
    <div className="card p-5">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Sparkles className="h-4 w-4 text-primary" />
          <p className="font-semibold">Wishlist</p>
        </div>
        <Link href="/wishlist" className="text-xs font-medium text-primary hover:underline">
          View all
        </Link>
      </div>

      {wishlist.affordableCount > 0 && (
        <div className="mt-3 flex items-center gap-2 rounded-xl bg-emerald-500/10 px-3 py-2.5 text-sm text-emerald-700 dark:text-emerald-300">
          <Check className="h-4 w-4 shrink-0" />
          <p className="leading-snug">
            You can afford{' '}
            <span className="font-bold">
              {wishlist.affordableCount} want{wishlist.affordableCount === 1 ? '' : 's'}
            </span>{' '}
            right now.
          </p>
        </div>
      )}

      <ul className="mt-4 space-y-2">
        {wishlist.top.map((item) => (
          <li key={item.id} className="flex items-center gap-3 rounded-lg bg-surface-muted/50 px-3 py-2">
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-surface text-base">
              {item.emoji || '✨'}
            </span>
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">{item.name}</p>
              <p className="flex items-center gap-1 text-[10px] text-muted">
                <Star className="h-2.5 w-2.5 fill-amber-400 text-amber-400" />
                {PRIORITY_LABEL[item.priority] ?? 'Someday'} · {item.pct}% saved
              </p>
            </div>
            {item.affordable ? (
              <span className="shrink-0 rounded-full bg-emerald-500/15 px-2 py-0.5 text-[10px] font-semibold uppercase text-emerald-600 dark:text-emerald-400">
                Ready
              </span>
            ) : (
              <span className="shrink-0 text-xs font-semibold tabular-nums text-muted">
                {money(item.remaining)}
              </span>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
