'use client';

import Link from 'next/link';
import { Sparkles, Check, Star } from 'lucide-react';
import type { WishlistDigest } from '@/lib/types';

const PRIORITY_LABEL = ['', 'Must have', 'Soon', 'Nice', 'Someday', 'Dream'];

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
        <Link href="/budgets?tab=wishlist" className="mt-4 text-sm font-medium text-primary hover:underline">
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
        <Link href="/budgets?tab=wishlist" className="text-xs font-medium text-primary hover:underline">
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
