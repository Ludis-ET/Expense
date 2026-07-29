'use client';

import { useEffect, useMemo, useState } from 'react';
import useSWR from 'swr';
import { ArrowDownWideNarrow, Filter, Search, X } from 'lucide-react';
import { Input, Select, DateRangeField } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Skeleton, EmptyState } from '@/components/ui/misc';
import { TransactionList } from '@/components/finance/transaction-list';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type {
  Account,
  BudgetCycleSnapshot,
  BudgetDetail,
  Category,
  Transaction,
  TransactionPage,
} from '@/lib/types';

const PAGE_SIZE = 20;

const SORTS = [
  { value: 'date_desc', label: 'Newest first' },
  { value: 'date_asc', label: 'Oldest first' },
  { value: 'amount_desc', label: 'Largest first' },
  { value: 'amount_asc', label: 'Smallest first' },
] as const;

type Sort = (typeof SORTS)[number]['value'];

/**
 * Every expense filed under a plan, searchable and filterable. Fetched
 * separately from the plan summary because Unplanned alone can hold years of
 * rows - the server paginates and filters, we never load them all.
 */
export function BudgetTransactions({
  plan,
  onView,
}: {
  plan: BudgetDetail;
  onView?: (tx: Transaction) => void;
}) {
  const { money } = useMoney();
  const { data: categoriesData } = useSWR<{ items: Category[] }>('/categories?kind=EXPENSE');
  const { data: accountsData } = useSWR<{ items: Account[] }>('/accounts');

  const [q, setQ] = useState('');
  const [debouncedQ, setDebouncedQ] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [accountId, setAccountId] = useState('');
  const [cycle, setCycle] = useState<string>('all');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [sort, setSort] = useState<Sort>('date_desc');
  const [page, setPage] = useState(1);
  const [showFilters, setShowFilters] = useState(false);

  // Typing shouldn't fire a request per keystroke.
  useEffect(() => {
    const t = setTimeout(() => setDebouncedQ(q.trim()), 300);
    return () => clearTimeout(t);
  }, [q]);

  const activeFilters =
    (debouncedQ ? 1 : 0) +
    (categoryId ? 1 : 0) +
    (accountId ? 1 : 0) +
    (cycle !== 'all' ? 1 : 0) +
    (from ? 1 : 0) +
    (to ? 1 : 0);

  // Any filter change puts you back on page 1.
  useEffect(() => {
    setPage(1);
  }, [debouncedQ, categoryId, accountId, cycle, from, to, sort]);

  const key = useMemo(() => {
    const p = new URLSearchParams({
      budgetId: plan.id,
      page: String(page),
      pageSize: String(PAGE_SIZE),
      sort,
    });
    if (debouncedQ) p.set('q', debouncedQ);
    if (categoryId) p.set('categoryId', categoryId);
    if (accountId) p.set('accountId', accountId);
    if (cycle !== 'all') p.set('budgetCycle', cycle);
    if (from) p.set('from', from);
    if (to) p.set('to', to);
    return `/transactions?${p.toString()}`;
  }, [plan.id, page, sort, debouncedQ, categoryId, accountId, cycle, from, to]);

  const { data, isLoading } = useSWR<TransactionPage>(key);

  const categories = (categoriesData?.items ?? []).filter((c) => !c.archived);
  const accounts = (accountsData?.items ?? []).filter((a) => !a.archived);
  const items = data?.items ?? [];
  const total = data?.total ?? 0;
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const pageTotal = items.reduce((s, tx) => s + Number(tx.amount), 0);

  const cycles: BudgetCycleSnapshot[] = plan.cycles;

  function reset() {
    setQ('');
    setCategoryId('');
    setAccountId('');
    setCycle('all');
    setFrom('');
    setTo('');
    setSort('date_desc');
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-sm font-semibold">Transactions</h2>
          <p className="text-xs text-muted">
            {isLoading
              ? 'Loading…'
              : total === 0
                ? 'Nothing here yet'
                : `${total} expense${total === 1 ? '' : 's'}${
                    activeFilters > 0 ? ' matching your filters' : ''
                  }`}
          </p>
        </div>

        <div className="flex flex-1 flex-wrap items-center justify-end gap-2">
          <div className="relative min-w-40 flex-1 sm:max-w-64">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
            <Input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Search payee or note…"
              className="pl-9"
              aria-label="Search transactions"
            />
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
        </div>
      </div>

      {showFilters && (
        <div className="grid gap-3 rounded-xl border border-border bg-surface-muted/40 p-3 sm:grid-cols-2 lg:grid-cols-3">
          <label className="text-xs font-medium text-muted">
            Category
            <Select
              className="mt-1"
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
            >
              <option value="">All categories</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </label>

          <label className="text-xs font-medium text-muted">
            Account
            <Select
              className="mt-1"
              value={accountId}
              onChange={(e) => setAccountId(e.target.value)}
            >
              <option value="">All accounts</option>
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </Select>
          </label>

          {cycles.length > 0 && (
            <label className="text-xs font-medium text-muted">
              {plan.periodNoun ? `${plan.periodNoun}` : 'Cycle'}
              <Select className="mt-1" value={cycle} onChange={(e) => setCycle(e.target.value)}>
                <option value="all">All time</option>
                <option value={String(plan.cycleIndex)}>Current</option>
                {cycles.map((c) => (
                  <option key={c.index} value={String(c.index)}>
                    {c.label}
                  </option>
                ))}
              </Select>
            </label>
          )}

          <div className="text-xs font-medium text-muted sm:col-span-2">
            Date range
            <DateRangeField
              className="mt-1"
              from={from}
              to={to}
              onFrom={setFrom}
              onTo={setTo}
              maxToday
            />
          </div>

          <label className="text-xs font-medium text-muted">
            <span className="inline-flex items-center gap-1">
              <ArrowDownWideNarrow className="h-3 w-3" /> Sort
            </span>
            <Select className="mt-1" value={sort} onChange={(e) => setSort(e.target.value as Sort)}>
              {SORTS.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </Select>
          </label>

          {activeFilters > 0 && (
            <button
              type="button"
              onClick={reset}
              className="inline-flex items-center justify-center gap-1 self-end rounded-lg border border-border px-3 py-2 text-xs font-medium text-muted hover:bg-surface-muted"
            >
              <X className="h-3 w-3" /> Clear filters
            </button>
          )}
        </div>
      )}

      {isLoading ? (
        <div className="space-y-2">
          {Array.from({ length: 5 }).map((_, i) => (
            <Skeleton key={i} className="h-14" />
          ))}
        </div>
      ) : items.length === 0 ? (
        <EmptyState
          icon={<Search className="h-5 w-5" />}
          title={activeFilters > 0 ? 'Nothing matches' : 'No spending yet'}
          description={
            activeFilters > 0
              ? 'Try widening the date range or clearing a filter.'
              : 'Expenses charged to this plan will show up here.'
          }
          action={
            activeFilters > 0 ? (
              <Button variant="outline" onClick={reset}>
                Clear filters
              </Button>
            ) : undefined
          }
        />
      ) : (
        <>
          <TransactionList items={items} onView={onView} />

          <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border pt-3 text-xs text-muted">
            <span>
              Showing {items.length} of {total} ·{' '}
              <strong className="text-foreground tabular-nums">{money(pageTotal)}</strong> on this
              page
            </span>
            {pages > 1 && (
              <div className="flex items-center gap-1">
                <button
                  type="button"
                  disabled={page <= 1}
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                  className={cn(
                    'rounded-lg border border-border px-3 py-1.5 font-medium',
                    page <= 1 ? 'opacity-40' : 'hover:bg-surface-muted',
                  )}
                >
                  Previous
                </button>
                <span className="px-2 tabular-nums">
                  {page} / {pages}
                </span>
                <button
                  type="button"
                  disabled={page >= pages}
                  onClick={() => setPage((p) => Math.min(pages, p + 1))}
                  className={cn(
                    'rounded-lg border border-border px-3 py-1.5 font-medium',
                    page >= pages ? 'opacity-40' : 'hover:bg-surface-muted',
                  )}
                >
                  Next
                </button>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
