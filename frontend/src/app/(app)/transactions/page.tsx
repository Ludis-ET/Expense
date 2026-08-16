'use client';

import { Suspense, useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Download, Plus, Search, ArrowLeftRight } from 'lucide-react';
import { PageHeader, Skeleton, EmptyState } from '@/components/ui/misc';
import { Button } from '@/components/ui/button';
import { Input, Select } from '@/components/ui/input';
import { TransactionList } from '@/components/finance/transaction-list';
import { TransactionForm } from '@/components/finance/transaction-form';
import { TransactionDetailModal } from '@/components/finance/transaction-detail-modal';
import { TransferModal } from '@/components/finance/transfer-modal';
import { RecurringPanel } from '@/components/finance/recurring-panel';
import { ExportImportModal } from '@/components/finance/export-import-modal';
import { MonthNavigator, currentMonth } from '@/components/finance/month-navigator';
import { DailyPace } from '@/components/finance/daily-pace';
import { ApiError } from '@/lib/api';
import { useOffline } from '@/lib/offline/offline-context';
import { useConfirm } from '@/components/ui/confirm-dialog';
import { CurrencyBadge, currencyScopeHint } from '@/components/finance/currency-badge';
import { useCurrencyView } from '@/lib/currency-view-context';
import { cn } from '@/lib/utils';
import type { Account, BudgetRow, Category, Transaction, TransactionPage, TxKind } from '@/lib/types';

/** Spending with no plan behind it. One id, understood the same way everywhere. */
const UNPLANNED_ID = 'unplanned';

function monthBounds(month: string) {
  const [y, m] = month.split('-').map(Number);
  const from = new Date(Date.UTC(y!, (m ?? 1) - 1, 1)).toISOString().slice(0, 10);
  const to = new Date(Date.UTC(y!, m ?? 1, 0)).toISOString().slice(0, 10);
  return { from, to };
}

function TransactionsInner() {
  const params = useSearchParams();
  const confirm = useConfirm();
  const tab = params.get('tab') === 'recurring' ? 'recurring' : 'ledger';
  const { activeCurrency } = useCurrencyView();
  const [month, setMonth] = useState(currentMonth());
  const [kind, setKind] = useState<TxKind | ''>('');
  const [categoryId, setCategoryId] = useState('');
  const [budgetId, setBudgetId] = useState(params.get('budgetId') ?? '');
  const [q, setQ] = useState('');
  const [page, setPage] = useState(1);
  const [formOpen, setFormOpen] = useState(false);
  const [transferOpen, setTransferOpen] = useState(false);
  const [exportImportOpen, setExportImportOpen] = useState(false);
  const [editing, setEditing] = useState<Transaction | null>(null);
  const [viewing, setViewing] = useState<Transaction | null>(null);

  // Pre-fill plan filter from URL (when navigating from plan details).
  useEffect(() => {
    const fromUrl = params.get('budgetId');
    if (fromUrl) setBudgetId(fromUrl);
  }, [params]);

  const { data: accountsData } = useSWR<{ items: Account[] }>('/accounts');
  const { data: categoriesData, isLoading: categoriesLoading } = useSWR<{ items: Category[] }>('/categories');
  const { data: budgetsData, isLoading: budgetsLoading } = useSWR<{ items: BudgetRow[] }>(
    tab === 'ledger' ? `/budgets?currency=${activeCurrency}` : null,
  );

  const { from, to } = monthBounds(month);
  const query = useMemo(() => {
    const p = new URLSearchParams({ from, to, page: String(page), pageSize: '25', currency: activeCurrency });
    if (kind) p.set('kind', kind);
    if (categoryId) p.set('categoryId', categoryId);
    if (budgetId) p.set('budgetId', budgetId);
    if (q) p.set('q', q);
    return p.toString();
  }, [from, to, page, kind, categoryId, budgetId, q, activeCurrency]);

  const { data, isLoading, mutate } = useSWR<TransactionPage>(`/transactions?${query}`);
  const { deleteTransaction, pendingCreates, pendingPatches, deletedIds } = useOffline();

  // Fold the offline outbox into what's on screen: queued edits patch matching
  // rows, queued deletes hide them, and queued new items appear on page 1.
  const displayItems = useMemo(() => {
    const base = (data?.items ?? [])
      .filter((t) => !deletedIds.has(t.id))
      .map((t) => pendingPatches.get(t.id) ?? t);
    if (page !== 1) return base;
    const matches = (t: Transaction) => {
      const day = t.date.slice(0, 10);
      if (day < from || day > to) return false;
      if (kind && t.kind !== kind) return false;
      if (categoryId && t.categoryId !== categoryId) return false;
      // "unplanned" is a view, not a plan id: it means no plan at all, which is
      // how the server reads it too.
      if (budgetId === UNPLANNED_ID) {
        if (t.kind !== 'EXPENSE' || t.budgetId) return false;
      } else if (budgetId && t.budgetId !== budgetId) {
        return false;
      }
      if (q && !`${t.payee ?? ''} ${t.note ?? ''}`.toLowerCase().includes(q.toLowerCase())) return false;
      return true;
    };
    const seen = new Set(base.map((t) => t.id));
    const extras = pendingCreates.filter((t) => !seen.has(t.id) && matches(t));
    return [...extras, ...base];
  }, [data?.items, pendingCreates, pendingPatches, deletedIds, page, from, to, kind, categoryId, budgetId, q]);

  // Open the quick-add modal when arriving via ?add=1 (topbar / command palette).
  useEffect(() => {
    if (params.get('add')) {
      setEditing(null);
      setFormOpen(true);
    }
  }, [params]);

  // Keyboard shortcut: "n" opens the add form.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const el = e.target as HTMLElement;
      if (e.key === 'n' && !e.metaKey && !e.ctrlKey && !['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName)) {
        e.preventDefault();
        setEditing(null);
        setFormOpen(true);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  useEffect(() => setPage(1), [month, kind, categoryId, budgetId, q, activeCurrency]);

  async function remove(tx: Transaction) {
    const ok = await confirm({
      title: 'Delete transaction?',
      description: 'This transaction will be removed permanently.',
      confirmLabel: 'Delete',
      tone: 'danger',
    });
    if (!ok) return;
    try {
      const { queued } = await deleteTransaction(tx.id);
      toast.success(queued ? 'Delete queued - will sync when online' : 'Deleted');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to delete');
    }
  }

  const totalPages = data ? Math.max(1, Math.ceil(data.total / data.pageSize)) : 1;

  return (
    <div>
      <PageHeader
        title="Transactions"
        description={tab === 'recurring' ? currencyScopeHint(activeCurrency) : currencyScopeHint(activeCurrency)}
        badge={<CurrencyBadge />}
        action={
          tab === 'ledger' ? (
            <div className="flex flex-wrap items-center gap-2">
              <Button variant="outline" size="sm" onClick={() => setExportImportOpen(true)} className="hidden sm:inline-flex">
                <Download className="h-4 w-4" /> Export / Import
              </Button>
              <Button
                variant="outline"
                size="sm"
                disabled={(accountsData?.items.length ?? 0) < 2}
                onClick={() => setTransferOpen(true)}
              >
                <ArrowLeftRight className="h-4 w-4" />
                <span className="hidden xs:inline sm:inline">Transfer</span>
              </Button>
              <Button size="sm" onClick={() => { setEditing(null); setFormOpen(true); }}>
                <Plus className="h-4 w-4" /> Add
              </Button>
            </div>
          ) : undefined
        }
      />

      <div className="mb-4 flex gap-1 rounded-xl border border-border p-1 w-fit">
        {(['ledger', 'recurring'] as const).map((t) => (
          <a
            key={t}
            href={t === 'ledger' ? '/transactions' : '/transactions?tab=recurring'}
            className={cn(
              'rounded-lg px-4 py-2 text-sm font-medium capitalize transition-colors',
              tab === t ? 'bg-primary text-primary-foreground' : 'text-muted hover:bg-surface-muted',
            )}
          >
            {t === 'ledger' ? 'Ledger' : 'Recurring'}
          </a>
        ))}
      </div>

      {tab === 'recurring' ? (
        <RecurringPanel presetBudgetId={params.get('budgetId') ?? undefined} />
      ) : (
        <>
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <MonthNavigator month={month} onChange={setMonth} />
        <div className="relative flex-1 min-w-40">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search payee or note…" className="pl-9" />
        </div>
        <Select value={kind} onChange={(e) => setKind(e.target.value as TxKind | '')} className="w-auto">
          <option value="">All types</option>
          <option value="EXPENSE">Expense</option>
          <option value="INCOME">Income</option>
          <option value="TRANSFER">Transfer</option>
        </Select>
        <Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)} className="w-auto" loading={categoriesLoading}>
          <option value="">All categories</option>
          {(categoriesData?.items ?? []).filter((c) => !c.archived).map((c) => (
            <option key={c.id} value={c.id}>{c.name}</option>
          ))}
        </Select>
        <Select value={budgetId} onChange={(e) => setBudgetId(e.target.value)} className="w-auto" loading={budgetsLoading}>
          <option value="">All plans</option>
          {(budgetsData?.items ?? []).map((plan) => (
            <option key={plan.id} value={plan.id}>{plan.name}</option>
          ))}
          <option value={UNPLANNED_ID}>Unplanned</option>
        </Select>
        {/* Mobile export button */}
        <Button variant="outline" size="sm" onClick={() => setExportImportOpen(true)} className="sm:hidden">
          <Download className="h-4 w-4" />
        </Button>
      </div>

      <DailyPace month={month} />

      {isLoading && displayItems.length === 0 ? (
        <div className="space-y-3">{Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-14" />)}</div>
      ) : displayItems.length === 0 ? (
        <EmptyState
          title="No transactions"
          description="Nothing matches these filters for this month."
          action={<Button onClick={() => { setEditing(null); setFormOpen(true); }}>Add transaction</Button>}
        />
      ) : (
        <>
          <TransactionList
            items={displayItems}
            onView={(tx) => setViewing(tx)}
            onEdit={(tx) => { setEditing(tx); setFormOpen(true); }}
            onDelete={remove}
          />
          {totalPages > 1 && (
            <div className="mt-6 flex items-center justify-center gap-3 text-sm">
              <Button variant="outline" size="sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
                Previous
              </Button>
              <span className="text-muted">Page {page} of {totalPages}</span>
              <Button variant="outline" size="sm" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>
                Next
              </Button>
            </div>
          )}
        </>
      )}

      <TransactionForm
        open={formOpen}
        editing={editing}
        onClose={() => setFormOpen(false)}
        onSaved={() => void mutate()}
      />
      <TransferModal
        open={transferOpen}
        onClose={() => setTransferOpen(false)}
        onSaved={() => void mutate()}
      />
      <TransactionDetailModal
        transaction={viewing}
        onClose={() => setViewing(null)}
        onEdit={(tx) => { setViewing(null); setEditing(tx); setFormOpen(true); }}
        onDelete={(tx) => { setViewing(null); void remove(tx); }}
      />
      <ExportImportModal
        open={exportImportOpen}
        onClose={() => setExportImportOpen(false)}
      />
        </>
      )}
    </div>
  );
}

export default function TransactionsPage() {
  return (
    <Suspense fallback={<Skeleton className="h-96" />}>
      <TransactionsInner />
    </Suspense>
  );
}
