'use client';

import { useEffect, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Plus, Trash2 } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select } from '@/components/ui/input';
import { PageHeader, ProgressBar, Skeleton, EmptyState } from '@/components/ui/misc';
import { MonthNavigator, currentMonth } from '@/components/finance/month-navigator';
import { CategoryBadge } from '@/components/finance/category-badge';
import { api, ApiError } from '@/lib/api';
import { formatMoney } from '@/lib/format';
import { useAuth } from '@/lib/auth';
import type { BudgetRow, BudgetsResponse, Category } from '@/lib/types';

const tone = (status: BudgetRow['status']) => (status === 'over' ? 'danger' : status === 'warning' ? 'warning' : 'success');

export default function BudgetsPage() {
  const { user } = useAuth();
  const currency = user?.currency ?? 'ETB';
  const [month, setMonth] = useState(currentMonth());
  const { data, mutate } = useSWR<BudgetsResponse>(`/budgets?month=${month}`);
  const { data: categoriesData } = useSWR<{ items: Category[] }>('/categories?kind=EXPENSE');
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState<BudgetRow | null>(null);

  const money = (v: number | string) => formatMoney(v, currency);
  const budgeted = new Set((data?.items ?? []).map((b) => b.categoryId));
  const unbudgeted = (categoriesData?.items ?? []).filter((c) => !c.archived && !budgeted.has(c.id));

  async function remove(row: BudgetRow) {
    if (!confirm(`Remove the budget for ${row.category.name}?`)) return;
    try {
      await api.del(`/budgets/${row.categoryId}`);
      toast.success('Budget removed');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  return (
    <div>
      <PageHeader
        title="Budgets"
        description="Set monthly limits and get nudged before you overspend."
        action={
          <Button size="sm" onClick={() => { setEditing(null); setModalOpen(true); }} disabled={unbudgeted.length === 0}>
            <Plus className="h-4 w-4" /> Set budget
          </Button>
        }
      />

      <div className="mb-4 flex items-center justify-between">
        <MonthNavigator month={month} onChange={setMonth} />
        {data && (
          <p className="text-sm text-muted">
            <span className="font-semibold text-foreground">{money(data.totals.spent)}</span> of {money(data.totals.budgeted)} used
          </p>
        )}
      </div>

      {!data ? (
        <div className="space-y-3">{Array.from({ length: 4 }).map((_, i) => <Skeleton key={i} className="h-20" />)}</div>
      ) : data.items.length === 0 ? (
        <EmptyState
          title="No budgets yet"
          description="Create a budget for a spending category to track it here."
          action={unbudgeted.length > 0 ? <Button onClick={() => { setEditing(null); setModalOpen(true); }}>Set a budget</Button> : undefined}
        />
      ) : (
        <div className="space-y-3">
          {data.items.map((b) => (
            <Card key={b.id}>
              <CardContent className="p-4">
                <div className="mb-2 flex items-center justify-between">
                  <CategoryBadge category={b.category} className="font-medium" />
                  <div className="flex items-center gap-3">
                    <span className="text-sm tabular-nums text-muted">
                      {money(b.spent)} / {money(b.amount)}
                    </span>
                    <button onClick={() => { setEditing(b); setModalOpen(true); }} className="text-xs text-muted hover:text-foreground">Edit</button>
                    <button onClick={() => remove(b)} className="text-muted hover:text-danger" aria-label="Remove">
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                </div>
                <ProgressBar value={b.pct} tone={tone(b.status)} />
                <div className="mt-1.5 flex items-center justify-between text-xs text-muted">
                  <span>{b.pct}% used</span>
                  <span className={b.status === 'over' ? 'font-medium text-danger' : ''}>
                    {Number(b.remaining) >= 0 ? `${money(b.remaining)} left` : `${money(Math.abs(Number(b.remaining)))} over`}
                  </span>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {unbudgeted.length > 0 && data && data.items.length > 0 && (
        <p className="mt-4 text-sm text-muted">
          {unbudgeted.length} categories have no budget yet.
        </p>
      )}

      <BudgetModal
        open={modalOpen}
        editing={editing}
        unbudgeted={unbudgeted}
        onClose={() => setModalOpen(false)}
        onSaved={() => void mutate()}
      />
    </div>
  );
}

function BudgetModal({
  open,
  editing,
  unbudgeted,
  onClose,
  onSaved,
}: {
  open: boolean;
  editing: BudgetRow | null;
  unbudgeted: Category[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [categoryId, setCategoryId] = useState('');
  const [amount, setAmount] = useState('');
  const [threshold, setThreshold] = useState('80');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setCategoryId(editing?.categoryId ?? unbudgeted[0]?.id ?? '');
    setAmount(editing ? String(Number(editing.amount)) : '');
    setThreshold(String(editing?.alertThreshold ?? 80));
  }, [open, editing, unbudgeted]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    try {
      await api.put(`/budgets/${categoryId}`, { amount: Number(amount), alertThreshold: Number(threshold) });
      toast.success('Budget saved');
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title={editing ? 'Edit budget' : 'Set a budget'}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="Category">
          <Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)} disabled={!!editing}>
            {editing ? (
              <option value={editing.categoryId}>{editing.category.name}</option>
            ) : (
              unbudgeted.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)
            )}
          </Select>
        </Field>
        <Field label="Monthly limit">
          <Input type="number" step="0.01" min="0" required value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
        </Field>
        <Field label="Alert threshold" hint="Get notified when you cross this percentage">
          <Input type="number" min="1" max="100" value={threshold} onChange={(e) => setThreshold(e.target.value)} />
        </Field>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={saving}>Save budget</Button>
        </div>
      </form>
    </Modal>
  );
}
