'use client';

import Link from 'next/link';
import { CircleEllipsis, Sparkles, Wallet } from 'lucide-react';
import { InfoHint } from '@/components/ui/info-hint';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type { UnplannedSummary } from '@/lib/types';

/**
 * Ready to assign.
 *
 * The number envelope budgeting is actually built around, and the one Santim
 * never showed: money you have that is not in any plan yet. It sits at the top
 * of the page because it is the only figure here that asks you to do something.
 */
export function ReadyToAssign({
  amount,
  currency,
  onAssign,
}: {
  amount: string;
  currency: string;
  onAssign?: () => void;
}) {
  const { money } = useMoney(currency);
  const value = Number(amount);
  const nothingLeft = value <= 0;

  return (
    <div
      className={cn(
        'relative overflow-hidden rounded-2xl border p-5 sm:p-6',
        nothingLeft
          ? 'border-border bg-surface'
          : 'border-emerald-500/30 bg-gradient-to-br from-emerald-50 via-teal-50 to-sky-50 dark:from-emerald-950/40 dark:via-teal-950/30 dark:to-sky-950/30',
      )}
    >
      {!nothingLeft && (
        <div className="pointer-events-none absolute -right-10 -top-10 h-36 w-36 rounded-full bg-emerald-400/20 blur-3xl" />
      )}

      <div className="relative flex flex-wrap items-end justify-between gap-4">
        <div className="min-w-0">
          <p className="flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-muted">
            <Wallet className="h-3.5 w-3.5" />
            Ready to assign · {currency}
            <InfoHint>
              Money sitting in your wallets that no plan has claimed. Giving every birr a job is the
              whole idea behind envelopes - when this reaches zero, everything you have is spoken
              for, and you always know what a purchase is really costing you.
            </InfoHint>
          </p>
          <p
            className={cn(
              'mt-2 text-3xl font-bold tabular-nums sm:text-4xl',
              nothingLeft ? 'text-foreground' : 'text-emerald-600 dark:text-emerald-400',
            )}
          >
            {money(amount)}
          </p>
          <p className="mt-1 text-xs text-muted">
            {nothingLeft
              ? 'Every birr you have is already in a plan. That is the goal.'
              : 'Not in any plan yet. Put it to work.'}
          </p>
        </div>

        {!nothingLeft && onAssign && (
          <button
            type="button"
            onClick={onAssign}
            className="inline-flex min-h-10 items-center gap-1.5 rounded-xl bg-emerald-600 px-4 text-sm font-semibold text-white shadow-sm transition-[filter] hover:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-600"
          >
            <Sparkles className="h-4 w-4" />
            Assign it
          </button>
        )}
      </div>
    </div>
  );
}

/**
 * The catch-all card.
 *
 * Deliberately shaped unlike a plan, because it is not one: no pot, no progress
 * bar, nothing to fill. It reports what you spent without setting money aside,
 * which is a fact about the past rather than a container for the future.
 */
export function UnplannedCard({ summary }: { summary: UnplannedSummary }) {
  const { money } = useMoney(summary.currency);
  const spent = Number(summary.spentAmount);

  return (
    <Link
      href="/transactions?budgetId=unplanned"
      className="group flex flex-col rounded-2xl border border-dashed border-border bg-surface p-5 transition-colors hover:border-slate-400 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary dark:hover:border-slate-500"
    >
      <div className="flex items-start gap-3">
        <span
          className="grid h-10 w-10 shrink-0 place-items-center rounded-xl"
          style={{ backgroundColor: `${summary.color}1a` }}
        >
          <CircleEllipsis className="h-5 w-5" style={{ color: summary.color }} />
        </span>
        <div className="min-w-0 flex-1">
          <h3 className="flex items-center gap-1.5 truncate text-sm font-semibold">
            {summary.name}
            <InfoHint>
              Not a plan and not a pot - just everything you spent this month without setting money
              aside first. Nothing is reserved here, so it can never run out; it simply spends
              whatever the wallet you pick has free.
            </InfoHint>
          </h3>
          <p className="text-xs text-muted">no money set aside</p>
        </div>
      </div>

      <div className="mt-4 flex items-end justify-between gap-3">
        <div>
          <p className="text-2xl font-bold tabular-nums">{money(summary.spentAmount)}</p>
          <p className="text-xs text-muted">
            this month{summary.txCount > 0 ? ` · ${summary.txCount} ${summary.txCount === 1 ? 'entry' : 'entries'}` : ''}
          </p>
        </div>
        {spent > 0 && (
          <span className="text-xs text-muted opacity-0 transition-opacity group-hover:opacity-100">
            See them →
          </span>
        )}
      </div>
    </Link>
  );
}
