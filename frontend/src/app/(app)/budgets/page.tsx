'use client';

import { Suspense, useState, useMemo } from 'react';
import Link from 'next/link';
import { usePathname, useSearchParams } from 'next/navigation';
import useSWR from 'swr';
import { ArrowDownUp, PiggyBank, Plus, Sparkles, Wallet, Search, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Select } from '@/components/ui/input';
import { PageHeader, Skeleton, EmptyState } from '@/components/ui/misc';
import { CurrencyBadge, currencyScopeHint } from '@/components/finance/currency-badge';
import { BudgetPlanCard } from '@/components/finance/budget-plan-card';
import { BudgetPlanForm } from '@/components/finance/budget-plan-modals';
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
        description={currencyScopeHint(activeCurrency)}
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
  const [sort, setSort] = useState<'priority' | 'name' | 'spent' | 'planned' | 'remaining' | 'progress'>('priority');

  const items = useMemo(() => data?.items ?? [], [data?.items]);
  const unplanned = items.find((b) => b.isUnplanned);
  const hasActive = items.some((b) => !b.isUnplanned && b.state === 'ACTIVE');

  const filtered = useMemo(() => {
    return items
      .filter((b) => {
        if (b.isUnplanned) return false;
        if (status === 'open' && b.state !== 'ACTIVE') return false;
        if (status === 'closed' && b.state !== 'CLOSED') return false;
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
  }, [items, status, q, sort]);

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
    };
  }, [filtered, data?.totals]);

  return (
    <div className="animate-in space-y-5">
      <div className="flex items-center justify-between gap-3">
        <p className="text-sm text-muted">
          Envelopes you fill from your accounts, then spend only from.
        </p>
        <Button size="sm" className="min-h-10 shrink-0" onClick={() => setFormOpen(true)}>
          <Plus className="h-4 w-4" /> New plan
        </Button>
      </div>

      {hasActive && (
        <div className="space-y-3">
          {/* Search bar */}
          <div className="relative">
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

          {/* Status pills + Sort row */}
          <div className="flex flex-wrap items-center gap-2">
            {/* Status toggle group */}
            <div className="flex items-center gap-1 rounded-xl border border-border bg-surface-muted/40 p-1">
              {(['open', 'closed', 'all'] as const).map((s) => (
                <button
                  key={s}
                  type="button"
                  onClick={() => setStatus(s)}
                  className={cn(
                    'rounded-lg px-3 py-1.5 text-xs font-semibold capitalize transition-all',
                    status === s
                      ? s === 'closed'
                        ? 'bg-slate-500 text-white shadow-sm'
                        : s === 'all'
                          ? 'bg-foreground text-background shadow-sm'
                          : 'bg-primary text-primary-foreground shadow-sm'
                      : 'text-muted hover:text-foreground',
                  )}
                >
                  {s === 'open' ? 'Active' : s === 'closed' ? 'Closed' : 'All'}
                </button>
              ))}
            </div>

            {/* Sort selector */}
            <div className="flex h-9 items-center gap-1 rounded-xl border border-border bg-surface-muted/40 pl-2.5 pr-1 transition-colors focus-within:border-primary/40">
              <ArrowDownUp className="h-3.5 w-3.5 shrink-0 text-muted" />
              <Select
                value={sort}
                onChange={(e) => setSort(e.target.value as 'priority' | 'name' | 'spent' | 'planned' | 'remaining' | 'progress')}
                variant="ghost"
                size="sm"
                aria-label="Sort plans"
                className="w-auto"
              >
                <option value="priority">Active first</option>
                <option value="name">Name (A-Z)</option>
                <option value="spent">Most spent</option>
                <option value="planned">Highest planned</option>
                <option value="remaining">Most remaining</option>
                <option value="progress">Progress</option>
              </Select>
            </div>

            {/* Active filter chip */}
            {(q || status !== 'open') && (
              <button
                type="button"
                onClick={() => { setQ(''); setStatus('open'); setSort('priority'); }}
                className="inline-flex items-center gap-1.5 rounded-full border border-primary/30 bg-primary/8 px-3 py-1.5 text-xs font-medium text-primary transition-colors hover:bg-primary/15"
              >
                <X className="h-3 w-3" />
                Reset filters
              </button>
            )}

            {/* Match count badge */}
            {!isLoading && (
              <span className="ml-auto text-xs text-muted">
                {filtered.length} {filtered.length === 1 ? 'plan' : 'plans'}
              </span>
            )}
          </div>
        </div>
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
          {unplanned && status !== 'closed' && <BudgetPlanCard key={unplanned.id} plan={unplanned} />}
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
