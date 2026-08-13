'use client';

import { Suspense, useState, useMemo } from 'react';
import Link from 'next/link';
import { usePathname, useSearchParams } from 'next/navigation';
import useSWR from 'swr';
import { ArrowDownUp, Filter, PiggyBank, Plus, Sparkles, Wallet, Search, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Select } from '@/components/ui/input';
import { PageHeader, Skeleton, EmptyState } from '@/components/ui/misc';
import { CurrencyBadge, currencyScopeHint } from '@/components/finance/currency-badge';
import { BudgetPlanCard } from '@/components/finance/budget-plan-card';
import { BudgetPlanForm } from '@/components/finance/budget-plan-modals';
import { ReadyToAssign, UnplannedCard } from '@/components/finance/assign-and-unplanned';
import { WishlistPanel } from '@/components/finance/wishlist-panel';
import { useMoney } from '@/lib/amount-visibility';
import { useCurrencyView } from '@/lib/currency-view-context';
import { cn } from '@/lib/utils';
import type { BudgetsResponse } from '@/lib/types';

const TABS = [
  { id: 'plans', label: 'Plans', icon: PiggyBank },
  { id: 'wishlist', label: 'Wishlist', icon: Sparkles },
] as const;

type TabId = (typeof TABS)[number]['id'];

export default function BudgetsPage() {
  return (
    <Suspense fallback={<Skeleton className="h-96" />}>
      <BudgetsInner />
    </Suspense>
  );
}

function BudgetsInner() {
  const params = useSearchParams();
  const pathname = usePathname();
  const { activeCurrency } = useCurrencyView();
  const raw = params.get('tab');
  const tab: TabId = TABS.some((t) => t.id === raw) ? (raw as TabId) : 'plans';

  return (
    <div>
      <PageHeader
        title="Budgets"
        description={
          <>
            <span className="block text-foreground">
              {tab === 'plans'
                ? 'Envelopes you fill from your accounts, then spend only from.'
                : 'Things you want, with no money attached. Plan one when you are ready to act on it.'}
            </span>
            <span className="mt-2 block">{currencyScopeHint(activeCurrency)}</span>
          </>
        }
        badge={<CurrencyBadge />}
      />

      <div
        role="tablist"
        className="mb-5 flex w-full gap-1 overflow-x-auto rounded-xl border border-border p-1 sm:w-fit"
      >
        {TABS.map((t) => {
          const Icon = t.icon;
          const active = tab === t.id;
          return (
            <Link
              key={t.id}
              role="tab"
              aria-selected={active}
              href={t.id === 'plans' ? pathname : `${pathname}?tab=${t.id}`}
              scroll={false}
              className={cn(
                'inline-flex min-h-10 shrink-0 items-center gap-1.5 rounded-lg px-4 py-2 text-sm font-medium transition-colors',
                active
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted hover:bg-surface-muted hover:text-foreground',
              )}
            >
              <Icon className="h-4 w-4" />
              {t.label}
            </Link>
          );
        })}
      </div>

      {tab === 'plans' && <PlansPanel />}
      {tab === 'wishlist' && <WishlistPanel />}
    </div>
  );
}

function PlansPanel() {
  const { activeCurrency } = useCurrencyView();
  const { money } = useMoney();
  const { data, mutate, isLoading } = useSWR<BudgetsResponse>(
    `/budgets?currency=${encodeURIComponent(activeCurrency)}`,
  );
  const [formOpen, setFormOpen] = useState(false);
  const [q, setQ] = useState('');
  const [status, setStatus] = useState<'open' | 'closed' | 'all'>('open');
  const [kind, setKind] = useState<'all' | 'ONE_TIME' | 'RECURRING'>('all');
  const [sort, setSort] = useState<'priority' | 'name' | 'spent' | 'planned' | 'remaining' | 'progress'>('priority');
  const [showFilters, setShowFilters] = useState(false);

  // Sort is a preference, not a filter, so it stays out of the badge count.
  const activeFilters = (q ? 1 : 0) + (status !== 'open' ? 1 : 0) + (kind !== 'all' ? 1 : 0);

  const items = useMemo(() => data?.items ?? [], [data?.items]);
  /**
   * Unplanned is no longer a plan row - it is a view over spending with no plan
   * behind it. The server sends it as its own summary, which is why it is not
   * filtered out of `items` here any more: it was never in there.
   */
  const unplanned = data?.unplanned;
  const hasActive = items.some((b) => b.state === 'ACTIVE');

  const filtered = useMemo(() => {
    return items
      .filter((b) => {
        if (status === 'open' && b.state !== 'ACTIVE') return false;
        if (status === 'closed' && b.state !== 'CLOSED') return false;
        if (kind !== 'all' && b.kind !== kind) return false;
        if (q && !b.name.toLowerCase().includes(q.toLowerCase())) return false;
        return true;
      })
      .sort((a, b) => {
        if (sort === 'priority') {
          if (a.started !== b.started) return a.started ? -1 : 1;
          return a.name.localeCompare(b.name);
        }
        if (sort === 'name') return a.name.localeCompare(b.name);
        if (sort === 'spent') return Number(b.spentAmount) - Number(a.spentAmount);
        if (sort === 'planned') return Number(b.plannedAmount) - Number(a.plannedAmount);
        if (sort === 'remaining') return Number(b.balance) - Number(a.balance);
        if (sort === 'progress') return b.pctSpentOfFunded - a.pctSpentOfFunded;
        return 0;
      });
  }, [items, status, kind, q, sort]);

  const cardTotals = useMemo(() => {
    if (!data?.totals) return null;
    let locked = 0;
    let funded = 0;
    let spent = 0;
    for (const b of filtered) {
      locked += Number(b.balance);
      funded += Number(b.fundedAmount);
      spent += Number(b.spentAmount);
    }
    return {
      locked: locked.toString(),
      funded: funded.toString(),
      spent: spent.toString(),
      unplannedSpent: data.totals.unplannedSpent,
      readyToAssign: data.totals.readyToAssign,
    };
  }, [filtered, data?.totals]);

  return (
    <div className="animate-in space-y-5">
      <div className="flex items-center justify-end gap-3">
        <Button size="sm" className="min-h-10 shrink-0" onClick={() => setFormOpen(true)}>
          <Plus className="h-4 w-4" /> New plan
        </Button>
      </div>

      {hasActive && (
        <div className="space-y-3">
          {/* Search + one button; everything else lives behind it. */}
          <div className="flex items-center gap-2">
            <div className="relative min-w-0 flex-1">
              <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
              <input
                type="search"
                placeholder="Search plans…"
                value={q}
                onChange={(e) => setQ(e.target.value)}
                className="h-10 w-full rounded-xl border border-border bg-background pl-9 pr-9 text-sm transition-colors placeholder:text-muted focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20"
              />
              {q && (
                <button
                  type="button"
                  onClick={() => setQ('')}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-muted transition-colors hover:text-foreground"
                  aria-label="Clear search"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              )}
            </div>

            <Button
              type="button"
              variant={showFilters || activeFilters > 0 ? 'primary' : 'outline'}
              size="sm"
              className="min-h-10 shrink-0"
              onClick={() => setShowFilters((v) => !v)}
            >
              <Filter className="h-4 w-4" />
              Filters
              {activeFilters > 0 && (
                <span className="ml-0.5 rounded-full bg-background/25 px-1.5 text-[10px] font-bold">
                  {activeFilters}
                </span>
              )}
            </Button>

            {!isLoading && (
              <span className="shrink-0 text-xs text-muted">
                {filtered.length} {filtered.length === 1 ? 'plan' : 'plans'}
              </span>
            )}
          </div>

          {showFilters && (
            <div className="grid gap-3 rounded-xl border border-border bg-surface-muted/40 p-3 sm:grid-cols-3">
              <label className="text-xs font-medium text-muted">
                Status
                <Select
                  className="mt-1"
                  size="sm"
                  value={status}
                  onChange={(e) => setStatus(e.target.value as 'open' | 'closed' | 'all')}
                >
                  <option value="open">Active</option>
                  <option value="closed">Closed</option>
                  <option value="all">All</option>
                </Select>
              </label>

              <label className="text-xs font-medium text-muted">
                Type
                <Select
                  className="mt-1"
                  size="sm"
                  value={kind}
                  onChange={(e) => setKind(e.target.value as 'all' | 'ONE_TIME' | 'RECURRING')}
                >
                  <option value="all">All types</option>
                  <option value="ONE_TIME">One-time</option>
                  <option value="RECURRING">Recurring</option>
                </Select>
              </label>

              <label className="text-xs font-medium text-muted">
                <span className="inline-flex items-center gap-1">
                  <ArrowDownUp className="h-3 w-3" /> Sort
                </span>
                <Select
                  className="mt-1"
                  size="sm"
                  value={sort}
                  onChange={(e) => setSort(e.target.value as 'priority' | 'name' | 'spent' | 'planned' | 'remaining' | 'progress')}
                >
                  <option value="priority">Active first</option>
                  <option value="name">Name (A-Z)</option>
                  <option value="spent">Most spent</option>
                  <option value="planned">Highest planned</option>
                  <option value="remaining">Most remaining</option>
                  <option value="progress">Progress</option>
                </Select>
              </label>

              {activeFilters > 0 && (
                <button
                  type="button"
                  onClick={() => { setQ(''); setStatus('open'); setKind('all'); setSort('priority'); }}
                  className="inline-flex items-center justify-center gap-1 self-end rounded-lg border border-border px-3 py-2 text-xs font-medium text-muted hover:bg-surface-muted"
                >
                  <X className="h-3 w-3" /> Clear filters
                </button>
              )}
            </div>
          )}
        </div>
      )}

      {cardTotals && (
        <ReadyToAssign
          amount={cardTotals.readyToAssign}
          currency={data?.totals.currency ?? activeCurrency}
          onAssign={() => setFormOpen(true)}
        />
      )}

      {cardTotals && hasActive && (
        <div className="relative overflow-hidden rounded-2xl border border-border bg-gradient-to-br from-indigo-50 via-sky-50 to-emerald-50 p-5 dark:from-indigo-950/40 dark:via-sky-950/30 dark:to-emerald-950/30 sm:p-6">
          <div className="pointer-events-none absolute -right-8 -top-8 h-32 w-32 rounded-full bg-primary/10 blur-3xl" />
          <p className="flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-muted">
            <Wallet className="h-3.5 w-3.5" /> Set aside in plans · {activeCurrency}
          </p>
          <div className="mt-3 grid grid-cols-2 gap-4 sm:grid-cols-4">
            <div>
              <p className="text-2xl font-bold tabular-nums text-primary">
                {money(cardTotals.locked)}
              </p>
              <p className="text-xs text-muted">locked right now</p>
            </div>
            <div>
              <p className="text-2xl font-bold tabular-nums">{money(cardTotals.funded)}</p>
              <p className="text-xs text-muted">filled this cycle</p>
            </div>
            <div>
              <p className="text-2xl font-bold tabular-nums">{money(cardTotals.spent)}</p>
              <p className="text-xs text-muted">spent from plans</p>
            </div>
            <div>
              <p className="text-2xl font-bold tabular-nums">{money(cardTotals.unplannedSpent)}</p>
              <p className="text-xs text-muted">spent unplanned</p>
            </div>
          </div>
        </div>
      )}

      {isLoading ? (
        <div className="grid gap-4 sm:grid-cols-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-44" />
          ))}
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          {/* The catch-all is always first, and always there. */}
          {unplanned && status !== 'closed' && <UnplannedCard key="unplanned" summary={unplanned} />}
          {filtered.map((plan) => (
            <BudgetPlanCard key={plan.id} plan={plan} />
          ))}
        </div>
      )}

      {!isLoading && filtered.length === 0 && !hasActive && (
        <EmptyState
          icon={<PiggyBank className="h-5 w-5" />}
          title="No budget plans yet"
          description="Everything you spend lands in Unplanned until you make a plan. Name one, say how much you intend to spend, then move money into it from an account."
          action={<Button onClick={() => setFormOpen(true)}>Create your first plan</Button>}
        />
      )}

      {!isLoading && filtered.length === 0 && hasActive && (
        <div className="flex h-32 items-center justify-center rounded-2xl border border-dashed border-border text-sm text-muted">
          No plans match your filters.
        </div>
      )}

      <BudgetPlanForm
        open={formOpen}
        editing={null}
        currency={activeCurrency}
        onClose={() => setFormOpen(false)}
        onSaved={() => void mutate()}
      />
    </div>
  );
}
