'use client';

import Link from 'next/link';
import { PiggyBank, Sparkles, Star } from 'lucide-react';
import type { WishlistDigest } from '@/lib/types';

const PRIORITY_LABEL = ['', 'Must have', 'Soon', 'Nice', 'Someday', 'Dream'];

/** The wants nearest the top of the pile, and how many have a plan behind them. */
export function WishlistWidget({ wishlist }: { wishlist: WishlistDigest | null | undefined }) {
  if (!wishlist || wishlist.activeCount === 0) {
    return (
      <div className="card flex flex-col items-center p-6 text-center">
        <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
          <Sparkles className="h-6 w-6" />
        </span>
        <p className="mt-3 font-semibold">Wishlist</p>
        <p className="mt-1 max-w-xs text-sm text-muted">
          Park the things you want, then plan them when you are ready.
        </p>
        <Link
          href="/budgets?tab=wishlist"
          className="mt-4 text-sm font-medium text-primary hover:underline"
        >
          Add a want
        </Link>
      </div>
    );
  }

  const unplanned = wishlist.activeCount - wishlist.plannedCount;

  return (
    <div className="card p-5">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Sparkles className="h-4 w-4 text-primary" />
          <p className="font-semibold">Wishlist</p>
        </div>
        <Link
          href="/budgets?tab=wishlist"
          className="text-xs font-medium text-primary hover:underline"
        >
          View all
        </Link>
      </div>

      {wishlist.plannedCount > 0 ? (
        <div className="mt-3 flex items-center gap-2 rounded-xl bg-violet-500/10 px-3 py-2.5 text-sm text-violet-700 dark:text-violet-300">
          <PiggyBank className="h-4 w-4 shrink-0" />
          <p className="leading-snug">
            <span className="font-bold">
              {wishlist.plannedCount} want{wishlist.plannedCount === 1 ? '' : 's'}
            </span>{' '}
            {wishlist.plannedCount === 1 ? 'has' : 'have'} a plan behind{' '}
            {wishlist.plannedCount === 1 ? 'it' : 'them'}.
          </p>
        </div>
      ) : (
        <p className="mt-3 rounded-xl bg-surface-muted/60 px-3 py-2.5 text-sm text-muted">
          {unplanned} want{unplanned === 1 ? '' : 's'} with no plan yet. Planning one turns it into
          a budget you can fill.
        </p>
      )}

      <ul className="mt-4 space-y-2">
        {wishlist.top.map((item) => (
          <li
            key={item.id}
            className="flex items-center gap-3 rounded-lg bg-surface-muted/50 px-3 py-2"
          >
            <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-surface text-base">
              {item.emoji || '✨'}
            </span>
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-medium">{item.name}</p>
              <p className="flex items-center gap-1 text-[10px] text-muted">
                <Star className="h-2.5 w-2.5 fill-amber-400 text-amber-400" />
                {PRIORITY_LABEL[item.priority] ?? 'Someday'}
              </p>
            </div>
            {item.plan ? (
              <Link
                href={`/budgets/${item.plan.id}`}
                className="shrink-0 rounded-full bg-violet-500/15 px-2 py-0.5 text-[10px] font-semibold uppercase text-violet-600 hover:bg-violet-500/25 dark:text-violet-400"
              >
                Planned
              </Link>
            ) : (
              <span className="shrink-0 text-[10px] font-medium uppercase text-muted">
                No plan
              </span>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
