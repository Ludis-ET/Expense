'use client';

import { use, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import useSWR, { useSWRConfig } from 'swr';
import { toast } from 'sonner';
import {
  ArrowDownLeft,
  ArrowLeft,
  ArrowUpRight,
  Archive,
  ArchiveRestore,
  CalendarClock,
  ChevronDown,
  CircleEllipsis,
  History,
  Pencil,
  Repeat,
  ShoppingBag,
  Trash2,
  Wallet,
} from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { EmptyState, PageLoader } from '@/components/ui/misc';
import { CategoryBadge } from '@/components/finance/category-badge';
import { financeIcon } from '@/components/finance/icons';
import { HEALTH_META } from '@/components/finance/budget-plan-card';
import { BudgetPlanForm, FundPlanModal } from '@/components/finance/budget-plan-modals';
import { BudgetTransactions } from '@/components/finance/budget-transactions';
import { TransactionDetailModal } from '@/components/finance/transaction-detail-modal';
import { TransactionForm } from '@/components/finance/transaction-form';
import { TransactionList } from '@/components/finance/transaction-list';
import { CalendarDate } from '@/components/calendar-date';
import { api, ApiError } from '@/lib/api';
import { useMoney } from '@/lib/amount-visibility';
import { useConfirm } from '@/components/ui/confirm-dialog';
import { cn } from '@/lib/utils';
import type {
  BudgetAllocation,
  BudgetCycleSnapshot,
  BudgetDetail,
  BudgetTimelineEntry,
  BudgetTransaction,
  Transaction,
} from '@/lib/types';

export default function BudgetDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const router = useRouter();
  const confirm = useConfirm();
  const { money } = useMoney();
  const { mutate: globalMutate } = useSWRConfig();
  const { data: plan, mutate, isLoading, error } = useSWR<BudgetDetail>(`/budgets/${id}`);

  const [editOpen, setEditOpen] = useState(false);
  const [moveMode, setMoveMode] = useState<'fund' | 'release' | null>(null);
  const [viewing, setViewing] = useState<Transaction | null>(null);
  const [editingTx, setEditingTx] = useState<Transaction | null>(null);
  const [busy, setBusy] = useState(false);

  /** Money moved: accounts, dashboard and the plan list are all stale now. */
  const refreshLinked = () =>
    globalMutate(
      (key) =>
        typeof key === 'string' &&
        (key.startsWith('/dashboard') ||
          key.startsWith('/accounts') ||
          key.startsWith('/budgets') ||
          key.startsWith('/transactions')),
    );

  if (error) {
    return (
      <EmptyState
        icon={<Wallet className="h-5 w-5" />}
        title="Plan not found"
        description="It may have been deleted."
        action={
          <Link href="/budgets">
            <Button variant="outline">Back to budgets</Button>
          </Link>
        }
      />
    );
  }

  if (isLoading || !plan) return <PageLoader rows={4} />;

  const unplanned = plan.isUnplanned;
  const closed = plan.state === 'CLOSED';

  async function act(path: string, successMsg: string) {
    setBusy(true);
    try {
      await api.post(`/budgets/${id}/${path}`, {});
      toast.success(successMsg);
      void mutate();
      void refreshLinked();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setBusy(false);
    }
  }

  async function removeTx(tx: Transaction) {
    const ok = await confirm({
      title: 'Delete this transaction?',
      description: `${tx.payee ?? tx.note ?? 'This expense'} will be removed and the money returned to the plan.`,
      confirmLabel: 'Delete',
      tone: 'danger',
    });
    if (!ok) return;
    try {
      await api.del(`/transactions/${tx.id}`);
      toast.success('Transaction deleted');
      setViewing(null);
      void mutate();
      void refreshLinked();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  async function removePlan() {
    const ok = await confirm({
      title: 'Delete this plan?',
      description:
        'Expenses already recorded against it stay in your transactions as ordinary expenses.',
      confirmLabel: 'Delete',
      tone: 'danger',
    });
    if (!ok) return;
    try {
      await api.del(`/budgets/${id}`);
      toast.success('Plan deleted');
      void refreshLinked();
      router.push('/budgets');
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  return (
    <div className="animate-in space-y-6">
      <Link
        href="/budgets"
        className="inline-flex items-center gap-1.5 text-sm font-medium text-muted hover:text-foreground"
      >
        <ArrowLeft className="h-4 w-4" /> Budgets
      </Link>

      {unplanned ? (
        <UnplannedHero plan={plan} />
      ) : (
        <PlanHero
          plan={plan}
          busy={busy}
          onFund={() => setMoveMode('fund')}
          onRelease={() => setMoveMode('release')}
          onEdit={() => setEditOpen(true)}
          onClose={() => act('close', 'Plan closed')}
          onReopen={() => act('reopen', 'Plan reopened')}
          onDelete={removePlan}
        />
      )}

      {closed && (
        <div className="rounded-xl border border-border bg-surface-muted/50 px-4 py-3 text-sm text-muted">
          This plan is closed - it no longer appears when you add a transaction. Its history is kept
          below, and you can reopen it any time.
        </div>
      )}

      {!unplanned && !plan.started && (
        <div className="flex items-start gap-2 rounded-xl border border-indigo-500/25 bg-indigo-500/5 px-4 py-3 text-sm text-muted">
          <CalendarClock className="mt-0.5 h-4 w-4 shrink-0 text-indigo-500" />
          <span>
            This plan starts on{' '}
            <strong className="text-foreground">
              {new Date(plan.startsAt).toLocaleDateString()}
            </strong>
            . You can fill it now, but nothing can be spent from it until then.
          </span>
        </div>
      )}

      {/* ---- Stat strip ---------------------------------------------- */}
      {unplanned ? (
        <div className="grid gap-3 sm:grid-cols-3">
          <StatTile label="Spent unplanned" value={money(plan.spentAmount)} />
          <StatTile label="All time" value={money(plan.lifetime.spent)} sub={`${plan.lifetime.txCount} transactions`} />
          <StatTile
            label="Since"
            value={
              plan.lifetime.firstTxAt
                ? new Date(plan.lifetime.firstTxAt).toLocaleDateString()
                : 'None yet'
            }
            sub="first unplanned expense"
          />
        </div>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <StatTile label="Planned" value={money(plan.plannedAmount)} />
          <StatTile
            label="Filled this cycle"
            value={money(plan.fundedAmount)}
            sub={Number(plan.carriedIn) > 0 ? `incl. ${money(plan.carriedIn)} carried over` : undefined}
          />
          <StatTile
            label="Spent this cycle"
            value={money(plan.spentAmount)}
            sub={`${plan.pctSpentOfFunded}% of what's in`}
          />
          <StatTile
            label="Lifetime"
            value={money(plan.lifetime.spent)}
            sub={`across ${plan.lifetime.cycleCount} cycle${plan.lifetime.cycleCount === 1 ? '' : 's'}`}
          />
        </div>
      )}

      {/* ---- Where the money is held ---------------------------------- */}
      {/* Unplanned never holds anything, so it never shows this. */}
      {!unplanned && plan.sources.length > 0 && (
        <Card>
          <CardContent className="p-4 sm:p-5">
            <h2 className="mb-3 text-sm font-semibold">Money held per account</h2>
            <ul className="space-y-2">
              {plan.sources.map((s) => (
                <li
                  key={s.account?.id ?? 'unknown'}
                  className="flex items-center justify-between gap-3 rounded-xl bg-surface-muted/50 px-3 py-2.5"
                >
                  <span className="flex min-w-0 items-center gap-2 text-sm">
                    <Wallet className="h-4 w-4 shrink-0 text-muted" />
                    <span className="truncate font-medium">{s.account?.name ?? 'Account'}</span>
                  </span>
                  <span className="shrink-0 text-sm font-semibold tabular-nums">
                    {money(s.available)}
                  </span>
                </li>
              ))}
            </ul>
            <p className="mt-3 text-xs text-muted">
              This money is still physically in these accounts - it just doesn&apos;t count as
              available until you spend it here or give it back.
            </p>
          </CardContent>
        </Card>
      )}

      {/* ---- Transactions (searchable, filterable, paginated) --------- */}
      <Card>
        <CardContent className="p-4 sm:p-5">
          <BudgetTransactions plan={plan} onView={(tx) => setViewing(tx)} />
        </CardContent>
      </Card>

      {/* ---- Recent movements ----------------------------------------- */}
      {!unplanned && (
        <Card>
          <CardContent className="p-4 sm:p-5">
            <div className="mb-4 flex items-center justify-between gap-2">
              <h2 className="text-sm font-semibold">Recent movements</h2>
              {plan.timelineTruncated && (
                <span className="text-xs text-muted">latest {plan.timeline.length}</span>
              )}
            </div>
            {plan.timeline.length === 0 ? (
              <EmptyState
                icon={<Wallet className="h-5 w-5" />}
                title="Nothing yet"
                description="Put money in from an account to get this plan going."
              />
            ) : (
              <Timeline entries={plan.timeline} currentCycle={plan.cycleIndex} />
            )}
          </CardContent>
        </Card>
      )}

      {/* ---- Past cycles ----------------------------------------------- */}
      {plan.cycles.length > 0 && (
        <div className="space-y-3">
          <h2 className="flex items-center gap-2 text-sm font-semibold">
            <History className="h-4 w-4 text-muted" /> Past {plan.periodNoun ?? 'cycle'}s
          </h2>
          {plan.cycles.map((c) => (
            <CycleSnapshot key={c.index} cycle={c} planId={plan.id} onView={setViewing} />
          ))}
        </div>
      )}

      <BudgetPlanForm
        open={editOpen}
        editing={plan}
        currency={plan.currency}
        onClose={() => setEditOpen(false)}
        onSaved={() => {
          void mutate();
          void refreshLinked();
        }}
      />

      <FundPlanModal
        plan={moveMode ? plan : null}
        mode={moveMode ?? 'fund'}
        onClose={() => setMoveMode(null)}
        onSaved={(updated) => {
          void mutate(updated, { revalidate: false });
          void refreshLinked();
        }}
      />

      <TransactionDetailModal
        transaction={viewing}
        onClose={() => setViewing(null)}
        onEdit={(tx) => {
          setViewing(null);
          setEditingTx(tx);
        }}
        onDelete={removeTx}
      />

      <TransactionForm
        open={!!editingTx}
        editing={editingTx}
        onClose={() => setEditingTx(null)}
        onSaved={() => {
          void mutate();
          void refreshLinked();
        }}
      />
    </div>
  );
}

/** The headline for an ordinary funded plan: what's left, and how it got there. */
function PlanHero({
  plan,
  busy,
  onFund,
  onRelease,
  onEdit,
  onClose,
  onReopen,
  onDelete,
}: {
  plan: BudgetDetail;
  busy: boolean;
  onFund: () => void;
  onRelease: () => void;
  onEdit: () => void;
  onClose: () => void;
  onReopen: () => void;
  onDelete: () => void;
}) {
  const { money } = useMoney();
  const Icon = financeIcon(plan.icon ?? 'wallet');
  const meta = HEALTH_META[plan.health];
  const closed = plan.state === 'CLOSED';
  const planned = Math.max(Number(plan.plannedAmount), 0.01);
  const spentPct = Math.min(100, (Number(plan.spentAmount) / planned) * 100);
  const balancePct = Math.min(100 - spentPct, (Number(plan.balance) / planned) * 100);

  return (
    <div
      className="relative overflow-hidden rounded-2xl border border-border p-5 sm:p-6"
      style={{ background: `linear-gradient(135deg, ${plan.color ?? '#6366f1'}1a, transparent 65%)` }}
    >
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="flex min-w-0 items-start gap-3">
          <span
            className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl"
            style={{
              backgroundColor: `${plan.color ?? '#6366f1'}26`,
              color: plan.color ?? '#6366f1',
            }}
          >
            <Icon className="h-7 w-7" />
          </span>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="truncate text-2xl font-bold tracking-tight">{plan.name}</h1>
              <span
                className={cn(
                  'rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide',
                  meta.chip,
                )}
              >
                {meta.label}
              </span>
            </div>
            <p className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm text-muted">
              {plan.kind === 'RECURRING' ? (
                <span className="inline-flex items-center gap-1">
                  <Repeat className="h-3.5 w-3.5" /> resets {plan.recurrenceLabel}
                </span>
              ) : (
                <span>one-time plan</span>
              )}
              {plan.category && (
                <>
                  <span>·</span>
                  <CategoryBadge category={plan.category} />
                </>
              )}
              {plan.cycleLabel && <span>· {plan.cycleLabel}</span>}
            </p>
            {plan.note && <p className="mt-2 max-w-prose text-sm text-muted">{plan.note}</p>}
          </div>
        </div>

        <div className="flex flex-wrap gap-2">
          {!closed && (
            <Button size="sm" onClick={onFund}>
              <ArrowUpRight className="h-4 w-4" /> Put money in
            </Button>
          )}
          {Number(plan.balance) > 0 && (
            <Button size="sm" variant="outline" onClick={onRelease}>
              <ArrowDownLeft className="h-4 w-4" /> Give back
            </Button>
          )}
          <Button size="sm" variant="outline" onClick={onEdit}>
            <Pencil className="h-4 w-4" /> Edit
          </Button>
          {closed ? (
            <Button size="sm" variant="outline" loading={busy} onClick={onReopen}>
              <ArchiveRestore className="h-4 w-4" /> Reopen
            </Button>
          ) : (
            <Button size="sm" variant="outline" loading={busy} onClick={onClose}>
              <Archive className="h-4 w-4" /> Close
            </Button>
          )}
          <Button size="sm" variant="ghost" onClick={onDelete} aria-label="Delete plan">
            <Trash2 className="h-4 w-4" />
          </Button>
        </div>
      </div>

      <div className="mt-6">
        <p className="text-xs font-semibold uppercase tracking-widest text-muted">
          Left in this plan
        </p>
        <p className="mt-1 text-4xl font-bold tabular-nums">{money(plan.balance)}</p>

        <div className="mt-4 flex h-2.5 w-full overflow-hidden rounded-full bg-surface-muted">
          <div
            className="h-full bg-foreground/25 transition-all duration-700"
            style={{ width: `${spentPct}%` }}
          />
          <div
            className={cn('h-full transition-all duration-700', meta.bar)}
            style={{ width: `${Math.max(0, balancePct)}%` }}
          />
        </div>
        <p className="mt-2 text-sm text-muted">
          You planned to spend <strong className="text-foreground">{money(plan.plannedAmount)}</strong>,
          filled <strong className="text-foreground">{money(plan.fundedAmount)}</strong> from your
          accounts, and have spent{' '}
          <strong className="text-foreground">{money(plan.spentAmount)}</strong> of it
          {Number(plan.fillable) > 0 && !closed && <> · {money(plan.fillable)} can still go in</>}.
        </p>
      </div>
    </div>
  );
}

/** The catch-all has no pot, so its headline is what leaked out through it. */
function UnplannedHero({ plan }: { plan: BudgetDetail }) {
  const { money } = useMoney();

  return (
    <div className="relative overflow-hidden rounded-2xl border border-dashed border-border bg-surface-muted/30 p-5 sm:p-6">
      <div className="flex min-w-0 items-start gap-3">
        <span className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-surface-muted text-muted">
          <CircleEllipsis className="h-7 w-7" />
        </span>
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="truncate text-2xl font-bold tracking-tight">{plan.name}</h1>
            <span className="rounded-full bg-surface-muted px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-muted">
              Built in
            </span>
          </div>
          <p className="mt-1 max-w-prose text-sm text-muted">
            Everything you spend without setting money aside first lands here. It has no pot of its
            own - each expense comes straight out of the account you choose, from whatever is left
            after your other plans.
          </p>
        </div>
      </div>

      <div className="mt-6">
        <p className="text-xs font-semibold uppercase tracking-widest text-muted">
          Spent unplanned
        </p>
        <p className="mt-1 text-4xl font-bold tabular-nums">{money(plan.spentAmount)}</p>
        <p className="mt-2 text-sm text-muted">
          {plan.lifetime.txCount} transaction{plan.lifetime.txCount === 1 ? '' : 's'} all told,
          worth <strong className="text-foreground">{money(plan.lifetime.spent)}</strong>. Turning a
          recurring one of these into a real plan is how the number comes down.
        </p>
      </div>
    </div>
  );
}

function StatTile({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="rounded-2xl border border-border bg-surface p-4">
      <p className="text-xs font-medium uppercase tracking-wide text-muted">{label}</p>
      <p className="mt-1 text-xl font-bold tabular-nums">{value}</p>
      {sub && <p className="mt-0.5 text-xs text-muted">{sub}</p>}
    </div>
  );
}

/** Fills, give-backs and spends on one vertical thread, newest first. */
function Timeline({
  entries,
  currentCycle,
}: {
  entries: BudgetTimelineEntry[];
  currentCycle: number;
}) {
  const { money } = useMoney();

  return (
    <ol className="relative space-y-0 border-l border-border pl-6">
      {entries.map((e, i) => {
        const isSpend = e.type === 'spend';
        const isRelease = e.type === 'release';
        const tone = isSpend
          ? 'bg-rose-500/15 text-rose-600 dark:text-rose-400'
          : isRelease
            ? 'bg-amber-500/15 text-amber-600 dark:text-amber-400'
            : 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400';
        const EntryIcon = isSpend ? ShoppingBag : isRelease ? ArrowDownLeft : ArrowUpRight;

        return (
          <li key={`${e.type}-${e.entry.id}-${i}`} className="relative pb-5 last:pb-0">
            <span
              className={cn(
                'absolute left-[-2.1rem] flex h-7 w-7 items-center justify-center rounded-full ring-4 ring-surface',
                tone,
              )}
            >
              <EntryIcon className="h-3.5 w-3.5" />
            </span>

            <div className="flex flex-wrap items-start justify-between gap-2">
              <div className="min-w-0">
                <p className="text-sm font-medium">
                  {isSpend
                    ? ((e.entry as BudgetTransaction).payee ??
                      (e.entry as BudgetTransaction).note ??
                      'Expense')
                    : isRelease
                      ? `Returned to ${(e.entry as BudgetAllocation).account?.name ?? 'account'}`
                      : `Filled from ${(e.entry as BudgetAllocation).account?.name ?? 'account'}`}
                </p>
                <p className="mt-0.5 flex flex-wrap items-center gap-x-1.5 text-xs text-muted">
                  <CalendarDate value={e.at} />
                  {isSpend && (e.entry as BudgetTransaction).category && (
                    <>· {(e.entry as BudgetTransaction).category!.name}</>
                  )}
                  {isSpend && (e.entry as BudgetTransaction).account && (
                    <>· from {(e.entry as BudgetTransaction).account!.name}</>
                  )}
                  {!isSpend && (e.entry as BudgetAllocation).note && (
                    <>· {(e.entry as BudgetAllocation).note}</>
                  )}
                  {e.cycleIndex !== currentCycle && <>· earlier cycle</>}
                </p>
              </div>
              <span
                className={cn(
                  'shrink-0 text-sm font-semibold tabular-nums',
                  isSpend || isRelease
                    ? 'text-rose-600 dark:text-rose-400'
                    : 'text-emerald-600 dark:text-emerald-400',
                )}
              >
                {isSpend || isRelease ? '−' : '+'}
                {money(Math.abs(Number(e.entry.amount)))}
              </span>
            </div>
          </li>
        );
      })}
    </ol>
  );
}

/**
 * A frozen cycle: what was planned, filled, spent, and what rolled forward.
 * Its transactions are fetched only when you open it.
 */
function CycleSnapshot({
  cycle,
  planId,
  onView,
}: {
  cycle: BudgetCycleSnapshot;
  planId: string;
  onView: (tx: Transaction) => void;
}) {
  const { money } = useMoney();
  const [open, setOpen] = useState(false);
  const { data } = useSWR<{ items: Transaction[] }>(
    open && cycle.txCount > 0
      ? `/transactions?budgetId=${planId}&budgetCycle=${cycle.index}&pageSize=100&sort=date_desc`
      : null,
  );
  const planned = Math.max(Number(cycle.plannedAmount), 0.01);
  const spentPct = Math.min(100, (Number(cycle.spentAmount) / planned) * 100);

  return (
    <Card>
      <CardContent className="p-4">
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          className="flex w-full items-start justify-between gap-3 text-left"
          aria-expanded={open}
        >
          <div className="min-w-0">
            <p className="flex items-center gap-1.5 font-semibold">
              <ChevronDown
                className={cn('h-4 w-4 text-muted transition-transform', open && 'rotate-180')}
              />
              {cycle.label}
            </p>
            <p className="mt-0.5 pl-5 text-xs text-muted">
              filled {money(cycle.fundedAmount)} · spent {money(cycle.spentAmount)} · {cycle.txCount}{' '}
              transaction{cycle.txCount === 1 ? '' : 's'}
            </p>
          </div>
          <div className="shrink-0 text-right">
            <p className="text-sm font-semibold tabular-nums">{money(cycle.leftoverAmount)}</p>
            <p className="text-[11px] text-muted">carried forward</p>
          </div>
        </button>

        <div className="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-surface-muted">
          <div className="h-full rounded-full bg-foreground/30" style={{ width: `${spentPct}%` }} />
        </div>

        {open && (
          <div className="mt-4 space-y-3 border-t border-border pt-3">
            <dl className="grid grid-cols-2 gap-3 text-xs sm:grid-cols-4">
              <Stat label="Planned" value={money(cycle.plannedAmount)} />
              <Stat label="Carried in" value={money(cycle.carriedIn)} />
              <Stat label="Filled" value={money(cycle.fundedAmount)} />
              <Stat label="Spent" value={money(cycle.spentAmount)} />
            </dl>

            {cycle.txCount === 0 ? (
              <p className="text-xs text-muted">No spending in this cycle.</p>
            ) : !data ? (
              <p className="text-xs text-muted">Loading transactions…</p>
            ) : (
              <TransactionList items={data.items} compact onView={onView} />
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-muted">{label}</dt>
      <dd className="font-semibold tabular-nums">{value}</dd>
    </div>
  );
}
