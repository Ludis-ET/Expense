'use client';

import { useState } from 'react';
import useSWR, { mutate as globalMutate } from 'swr';
import { toast } from 'sonner';
import {
  ArrowDownLeft,
  ArrowLeftRight,
  ArrowUpRight,
  Lock,
  RotateCcw,
  Scale,
  Undo2,
  Unlock,
} from 'lucide-react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { InfoHint } from '@/components/ui/info-hint';
import { api, ApiError } from '@/lib/api';
import { cn } from '@/lib/utils';
import { useAmountVisibility } from '@/lib/amount-visibility';
import type { Movement, MovementsResponse, MovementType, UndoResponse } from '@/lib/types';

/**
 * Every kind of movement gets its own mark, because the list mixes things that
 * are genuinely different: money leaving, money arriving, money merely being
 * set aside. Colour separates the three so the row reads before it is read.
 */
const MARK: Record<
  MovementType,
  { Icon: typeof ArrowUpRight; tone: string; ring: string }
> = {
  expense: { Icon: ArrowUpRight, tone: 'text-rose-600 dark:text-rose-400', ring: 'bg-rose-500/10' },
  income: { Icon: ArrowDownLeft, tone: 'text-emerald-600 dark:text-emerald-400', ring: 'bg-emerald-500/10' },
  transfer: { Icon: ArrowLeftRight, tone: 'text-sky-600 dark:text-sky-400', ring: 'bg-sky-500/10' },
  fund: { Icon: Lock, tone: 'text-primary', ring: 'bg-primary/10' },
  release: { Icon: Unlock, tone: 'text-primary', ring: 'bg-primary/10' },
  move: { Icon: ArrowLeftRight, tone: 'text-violet-600 dark:text-violet-400', ring: 'bg-violet-500/10' },
  adjust: { Icon: Scale, tone: 'text-amber-600 dark:text-amber-400', ring: 'bg-amber-500/10' },
};

function timeAgo(iso: string): string {
  const minutes = Math.round((Date.now() - new Date(iso).getTime()) / 60_000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

/** Keys worth refreshing once a movement is taken back. */
function shouldRevalidate(key: unknown): boolean {
  if (typeof key !== 'string') return false;
  return (
    key.startsWith('/transactions') ||
    key.startsWith('/dashboard') ||
    key.startsWith('/accounts') ||
    key.startsWith('/budgets') ||
    key.startsWith('/analytics') ||
    key.startsWith('/money')
  );
}

function MovementRow({
  movement,
  onUndone,
}: {
  movement: Movement;
  onUndone: () => void;
}) {
  const [working, setWorking] = useState(false);
  const { hidden } = useAmountVisibility();
  const { Icon, tone, ring } = MARK[movement.type];
  const negative = Number(movement.amount) < 0;

  async function undo() {
    setWorking(true);
    try {
      const res = await api.post<UndoResponse>(
        `/money/movements/${encodeURIComponent(movement.id)}/undo`,
      );
      toast.success(res.message);
      onUndone();
      void globalMutate(shouldRevalidate);
    } catch (err) {
      // A refusal here is the invariant proof doing its job, and its wording
      // already says what to do instead.
      toast.error(err instanceof ApiError ? err.message : 'Could not undo that');
    } finally {
      setWorking(false);
    }
  }

  return (
    <li className="flex items-center gap-3 py-2.5">
      <span className={cn('grid h-9 w-9 shrink-0 place-items-center rounded-full', ring)}>
        <Icon className={cn('h-4 w-4', tone)} />
      </span>

      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-medium text-foreground">{movement.title}</p>
        <p className="truncate text-xs text-muted">
          {movement.subtitle ? `${movement.subtitle} · ` : ''}
          {timeAgo(movement.recordedAt)}
        </p>
      </div>

      <span
        className={cn(
          'shrink-0 text-sm font-semibold tabular-nums',
          negative ? 'text-foreground' : 'text-emerald-600 dark:text-emerald-400',
        )}
      >
        {hidden ? '•••' : `${negative ? '' : '+'}${Number(movement.amount).toFixed(2)}`}
      </span>

      {movement.undoable ? (
        <Button
          type="button"
          size="sm"
          variant="ghost"
          loading={working}
          onClick={undo}
          className="shrink-0 gap-1.5 text-xs"
        >
          <Undo2 className="h-3.5 w-3.5" />
          Undo
        </Button>
      ) : (
        <span
          title={movement.blockedReason ?? undefined}
          className="shrink-0 px-2 text-xs text-muted/60"
        >
          —
        </span>
      )}
    </li>
  );
}

/**
 * The recent-movements list, with a one-tap take-back.
 *
 * Undo removes the movement rather than posting a mirror-image entry: a mistake
 * should leave no trace, the way crossing a line out of a paper ledger does. The
 * server re-proves the books afterwards, so an undo that would leave money
 * unaccounted for is refused with the reason rather than half-applied.
 */
export function RecentMovements({ limit = 8 }: { limit?: number }) {
  const { data, isLoading, mutate } = useSWR<MovementsResponse>(`/money/movements?limit=${limit}`);
  const items = data?.items ?? [];

  return (
    <Card className="p-4 sm:p-5">
      <div className="mb-1 flex items-center justify-between gap-2">
        <h2 className="flex items-center gap-2 text-sm font-semibold">
          <RotateCcw className="h-4 w-4 text-primary" />
          Just happened
          <InfoHint>
            Everything that moved money recently - spending, income, transfers, and money set aside
            in plans. Undo takes a movement back completely rather than recording it twice; it is
            available for {data?.undoWindowHours ?? 48} hours, and refused if taking it back would
            leave your wallets and plans disagreeing.
          </InfoHint>
        </h2>
      </div>

      {isLoading ? (
        <div className="space-y-2 py-2">
          {[0, 1, 2].map((i) => (
            <div key={i} className="h-11 animate-pulse rounded-lg bg-surface-muted" />
          ))}
        </div>
      ) : items.length === 0 ? (
        <p className="py-6 text-center text-sm text-muted">
          Nothing has moved yet. Your most recent changes will show up here, ready to undo.
        </p>
      ) : (
        <ul className="divide-y divide-border">
          {items.map((m) => (
            <MovementRow key={m.id} movement={m} onUndone={() => void mutate()} />
          ))}
        </ul>
      )}
    </Card>
  );
}
