'use client';

import { Suspense, useState } from 'react';
import Link from 'next/link';
import { usePathname, useSearchParams } from 'next/navigation';
import useSWR from 'swr';
import { PiggyBank, Plus, Sparkles, Wallet } from 'lucide-react';
import { Button } from '@/components/ui/button';
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
  const [showClosed, setShowClosed] = useState(false);

  const items = data?.items ?? [];
  const unplanned = items.find((b) => b.isUnplanned);
  const active = items.filter((b) => !b.isUnplanned && b.state === 'ACTIVE');
  const closed = items.filter((b) => !b.isUnplanned && b.state === 'CLOSED');
  const totals = data?.totals;

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

      {totals && active.length > 0 && (
        <div className="relative overflow-hidden rounded-2xl border border-border bg-gradient-to-br from-indigo-50 via-sky-50 to-emerald-50 p-5 dark:from-indigo-950/40 dark:via-sky-950/30 dark:to-emerald-950/30 sm:p-6">
          <div className="pointer-events-none absolute -right-8 -top-8 h-32 w-32 rounded-full bg-primary/10 blur-3xl" />
          <p className="flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-muted">
            <Wallet className="h-3.5 w-3.5" /> Set aside in plans · {activeCurrency}
          </p>
          <div className="mt-3 grid grid-cols-2 gap-4 sm:grid-cols-4">
            <div>
              <p className="text-2xl font-bold tabular-nums text-primary">
                {money(totals.locked)}
              </p>
              <p className="text-xs text-muted">locked right now</p>
            </div>
            <div>
              <p className="text-2xl font-bold tabular-nums">{money(totals.funded)}</p>
              <p className="text-xs text-muted">filled this cycle</p>
            </div>
            <div>
              <p className="text-2xl font-bold tabular-nums">{money(totals.spent)}</p>
              <p className="text-xs text-muted">spent from plans</p>
            </div>
            <div>
              <p className="text-2xl font-bold tabular-nums">{money(totals.unplannedSpent)}</p>
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
          {unplanned && <BudgetPlanCard key={unplanned.id} plan={unplanned} />}
          {active.map((plan) => (
            <BudgetPlanCard key={plan.id} plan={plan} />
          ))}
        </div>
      )}

      {!isLoading && active.length === 0 && (
        <EmptyState
          icon={<PiggyBank className="h-5 w-5" />}
          title="No budget plans yet"
          description="Everything you spend lands in Unplanned until you make a plan. Name one, say how much you intend to spend, then move money into it from an account."
          action={<Button onClick={() => setFormOpen(true)}>Create your first plan</Button>}
        />
      )}

      {closed.length > 0 && (
        <div>
          <button
            type="button"
            onClick={() => setShowClosed((v) => !v)}
            className="mb-3 text-sm font-medium text-muted hover:text-foreground"
          >
            {showClosed ? 'Hide' : 'Show'} closed plans ({closed.length})
          </button>
          {showClosed && (
            <div className="grid gap-4 sm:grid-cols-2">
              {closed.map((plan) => (
                <BudgetPlanCard key={plan.id} plan={plan} />
              ))}
            </div>
          )}
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
