'use client';

import { useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Check, ChevronDown, Plus, Receipt, X } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Modal } from '@/components/ui/modal';
import { Field, Input, Select, Textarea } from '@/components/ui/input';
import { StatusBadge } from '@/components/ui/badge';
import { ProgressBar, EmptyState, Skeleton } from '@/components/ui/misc';
import { api, ApiError } from '@/lib/api';
import { formatMoney, formatDate } from '@/lib/format';
import { cn } from '@/lib/utils';
import type { BudgetSummary, BudgetSummaryItem } from '@/lib/types';

const CATEGORIES = ['equipment', 'travel', 'personnel', 'indirect', 'materials', 'other'];

export function BudgetTab({ projectId, currency }: { projectId: string; currency: string }) {
  const { data, isLoading, mutate } = useSWR<BudgetSummary>(`/projects/${projectId}/budget`);
  const [itemModal, setItemModal] = useState(false);
  const [expenseFor, setExpenseFor] = useState<BudgetSummaryItem | null>(null);

  if (isLoading) return <Skeleton className="h-64 w-full" />;

  const totalSpent =
    data?.items.reduce((sum, i) => sum + Number(i.spent), 0) ?? 0;
  const totalPlanned = Number(data?.totalPlanned ?? 0);
  const utilization = totalPlanned > 0 ? Math.round((totalSpent / totalPlanned) * 100) : 0;

  return (
    <div className="space-y-5">
      {/* Summary header */}
      <Card>
        <CardContent>
          <div className="flex flex-wrap items-end justify-between gap-4">
            <div className="grid grid-cols-3 gap-6">
              <div>
                <div className="text-xs text-muted">Planned</div>
                <div className="mt-1 text-xl font-bold">{formatMoney(totalPlanned, currency)}</div>
              </div>
              <div>
                <div className="text-xs text-muted">Spent (approved)</div>
                <div className="mt-1 text-xl font-bold text-emerald-500">{formatMoney(totalSpent, currency)}</div>
              </div>
              <div>
                <div className="text-xs text-muted">Remaining</div>
                <div className="mt-1 text-xl font-bold">{formatMoney(totalPlanned - totalSpent, currency)}</div>
              </div>
            </div>
            <Button size="sm" onClick={() => setItemModal(true)}>
              <Plus className="h-4 w-4" /> Budget line
            </Button>
          </div>
          <div className="mt-4">
            <ProgressBar value={utilization} tone={utilization > 90 ? 'danger' : utilization > 70 ? 'warning' : 'success'} />
            <p className="mt-1.5 text-xs text-muted">{utilization}% of planned budget used</p>
          </div>
        </CardContent>
      </Card>

      {!data?.items.length ? (
        <EmptyState
          icon={<Receipt className="h-6 w-6" />}
          title="No budget lines yet"
          description="Add a budget category to start tracking planned vs. actual spend."
          action={
            <Button onClick={() => setItemModal(true)}>
              <Plus className="h-4 w-4" /> Budget line
            </Button>
          }
        />
      ) : (
        <div className="space-y-3">
          {data.items.map((item) => (
            <BudgetLine key={item.id} item={item} onExpense={() => setExpenseFor(item)} onChange={mutate} />
          ))}
        </div>
      )}

      <AddBudgetItemModal
        open={itemModal}
        onClose={() => setItemModal(false)}
        projectId={projectId}
        currency={currency}
        onAdded={mutate}
      />
      <AddExpenseModal item={expenseFor} onClose={() => setExpenseFor(null)} onAdded={mutate} />
    </div>
  );
}

function BudgetLine({
  item,
  onExpense,
  onChange,
}: {
  item: BudgetSummaryItem;
  onExpense: () => void;
  onChange: () => void;
}) {
  const [open, setOpen] = useState(false);
  const planned = Number(item.plannedAmount);
  const spent = Number(item.spent);
  const pct = planned > 0 ? Math.round((spent / planned) * 100) : 0;

  async function decide(expenseId: string, decision: 'APPROVED' | 'REJECTED') {
    try {
      await api.post(`/expenses/${expenseId}/decision`, { decision });
      toast.success(`Expense ${decision.toLowerCase()}`);
      onChange();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  return (
    <Card>
      <button onClick={() => setOpen((o) => !o)} className="flex w-full items-center gap-4 p-4 text-left">
        <ChevronDown className={cn('h-4 w-4 shrink-0 text-muted transition-transform', open && 'rotate-180')} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center justify-between gap-2">
            <span className="font-medium capitalize">{item.category}</span>
            <span className="text-sm tabular-nums text-muted">
              {formatMoney(spent, item.currency)} / {formatMoney(planned, item.currency)}
            </span>
          </div>
          <div className="mt-2">
            <ProgressBar value={pct} tone={pct > 100 ? 'danger' : pct > 80 ? 'warning' : 'primary'} />
          </div>
        </div>
      </button>

      {open && (
        <div className="border-t border-border px-4 py-3">
          <div className="mb-2 flex items-center justify-between">
            <span className="text-xs font-medium text-muted">
              Expenses ({item.expenses.length}) · {formatMoney(item.pending, item.currency)} pending
            </span>
            <Button size="sm" variant="outline" onClick={onExpense}>
              <Plus className="h-3.5 w-3.5" /> Add expense
            </Button>
          </div>
          {!item.expenses.length ? (
            <p className="py-3 text-center text-sm text-muted">No expenses logged.</p>
          ) : (
            <div className="divide-y divide-border">
              {item.expenses.map((e) => (
                <div key={e.id} className="flex items-center gap-3 py-2.5">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm">{e.description || 'Expense'}</p>
                    <p className="text-xs text-muted">
                      {e.user?.name ?? 'Someone'} · {formatDate(e.date)}
                    </p>
                  </div>
                  <span className="text-sm font-medium tabular-nums">{formatMoney(e.amount, e.currency)}</span>
                  <StatusBadge.Expense status={e.status} />
                  {e.status === 'PENDING' && (
                    <div className="flex gap-1">
                      <button
                        onClick={() => decide(e.id, 'APPROVED')}
                        className="rounded-md p-1.5 text-emerald-500 transition-colors hover:bg-emerald-500/10"
                        aria-label="Approve"
                      >
                        <Check className="h-4 w-4" />
                      </button>
                      <button
                        onClick={() => decide(e.id, 'REJECTED')}
                        className="rounded-md p-1.5 text-danger transition-colors hover:bg-danger/10"
                        aria-label="Reject"
                      >
                        <X className="h-4 w-4" />
                      </button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </Card>
  );
}

function AddBudgetItemModal({
  open,
  onClose,
  projectId,
  currency,
  onAdded,
}: {
  open: boolean;
  onClose: () => void;
  projectId: string;
  currency: string;
  onAdded: () => void;
}) {
  const [form, setForm] = useState({ category: 'equipment', plannedAmount: '', notes: '' });
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      await api.post(`/projects/${projectId}/budget`, {
        category: form.category,
        plannedAmount: Number(form.plannedAmount),
        currency,
        notes: form.notes || undefined,
      });
      toast.success('Budget line added');
      onAdded();
      onClose();
      setForm({ category: 'equipment', plannedAmount: '', notes: '' });
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to add');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="Add budget line">
      <form onSubmit={submit} className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <Field label="Category">
            <Select value={form.category} onChange={(e) => setForm((f) => ({ ...f, category: e.target.value }))}>
              {CATEGORIES.map((c) => (
                <option key={c} value={c} className="capitalize">
                  {c}
                </option>
              ))}
            </Select>
          </Field>
          <Field label={`Planned amount (${currency})`}>
            <Input
              type="number"
              min="0"
              step="0.01"
              required
              value={form.plannedAmount}
              onChange={(e) => setForm((f) => ({ ...f, plannedAmount: e.target.value }))}
            />
          </Field>
        </div>
        <Field label="Notes">
          <Textarea value={form.notes} onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
        </Field>
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={loading}>
            Add line
          </Button>
        </div>
      </form>
    </Modal>
  );
}

function AddExpenseModal({
  item,
  onClose,
  onAdded,
}: {
  item: BudgetSummaryItem | null;
  onClose: () => void;
  onAdded: () => void;
}) {
  const [form, setForm] = useState({ amount: '', description: '' });
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!item) return;
    setLoading(true);
    try {
      await api.post(`/budget/${item.id}/expenses`, {
        amount: Number(form.amount),
        currency: item.currency,
        description: form.description || undefined,
      });
      toast.success('Expense submitted for approval');
      onAdded();
      onClose();
      setForm({ amount: '', description: '' });
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to submit');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Modal
      open={!!item}
      onClose={onClose}
      title="Log an expense"
      description={item ? `Against "${item.category}" · submitted as pending` : ''}
    >
      <form onSubmit={submit} className="space-y-4">
        <Field label={`Amount (${item?.currency ?? ''})`}>
          <Input
            type="number"
            min="0"
            step="0.01"
            required
            value={form.amount}
            onChange={(e) => setForm((f) => ({ ...f, amount: e.target.value }))}
          />
        </Field>
        <Field label="Description">
          <Input
            value={form.description}
            onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))}
            placeholder="e.g. Soil moisture sensors"
          />
        </Field>
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={loading}>
            Submit expense
          </Button>
        </div>
      </form>
    </Modal>
  );
}
