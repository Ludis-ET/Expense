'use client';

import { useEffect, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Play, Plus, Trash2 } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Field, Input, Select } from '@/components/ui/input';
import { PageHeader, Skeleton, EmptyState } from '@/components/ui/misc';
import { CategoryBadge } from '@/components/finance/category-badge';
import { api, ApiError } from '@/lib/api';
import { formatMoney, formatDate } from '@/lib/format';
import { useAuth } from '@/lib/auth';
import type { Account, Category, Frequency, RecurringRule, TxKind } from '@/lib/types';

const FREQUENCIES: Frequency[] = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'];
const freqLabel = (f: Frequency, interval: number) =>
  interval === 1 ? f.toLowerCase() : `every ${interval} ${f.toLowerCase().replace('ly', 's').replace('daiy', 'days')}`;

export default function RecurringPage() {
  const { user } = useAuth();
  const currency = user?.currency ?? 'ETB';
  const { data, mutate } = useSWR<{ items: RecurringRule[] }>('/recurring');
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<RecurringRule | null>(null);

  const money = (v: number | string) => formatMoney(v, currency);

  async function toggle(rule: RecurringRule) {
    try {
      await api.put(`/recurring/${rule.id}`, { active: !rule.active });
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  async function runNow(rule: RecurringRule) {
    try {
      await api.post(`/recurring/${rule.id}/run-now`);
      toast.success(`Posted "${rule.name}"`);
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  async function remove(rule: RecurringRule) {
    if (!confirm(`Delete "${rule.name}"?`)) return;
    try {
      await api.del(`/recurring/${rule.id}`);
      toast.success('Deleted');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  return (
    <div>
      <PageHeader
        title="Recurring"
        description="Salary, rent, subscriptions — posted automatically or as reminders."
        action={
          <Button size="sm" onClick={() => { setEditing(null); setFormOpen(true); }}>
            <Plus className="h-4 w-4" /> New rule
          </Button>
        }
      />

      {!data ? (
        <div className="space-y-3">{Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-16" />)}</div>
      ) : data.items.length === 0 ? (
        <EmptyState
          title="No recurring rules"
          description="Automate income and bills that repeat on a schedule."
          action={<Button onClick={() => { setEditing(null); setFormOpen(true); }}>Create a rule</Button>}
        />
      ) : (
        <div className="space-y-2">
          {data.items.map((r) => (
            <Card key={r.id} className={r.active ? undefined : 'opacity-60'}>
              <CardContent className="flex flex-wrap items-center gap-3 p-4">
                <div className="min-w-40 flex-1">
                  <p className="flex items-center gap-2 font-medium">
                    {r.name}
                    <Badge tone={r.kind === 'INCOME' ? 'success' : 'neutral'}>{r.kind.toLowerCase()}</Badge>
                  </p>
                  {r.category && <CategoryBadge category={r.category} className="mt-1 text-xs text-muted" />}
                </div>
                <div className="text-sm">
                  <p className="font-semibold tabular-nums">{money(r.amount)}</p>
                  <p className="text-xs text-muted">{freqLabel(r.frequency, r.interval)}</p>
                </div>
                <div className="text-sm">
                  <p className="text-xs text-muted">Next run</p>
                  <p>{formatDate(r.nextRun)}</p>
                </div>
                <Badge tone={r.autoPost ? 'info' : 'warning'}>{r.autoPost ? 'auto-post' : 'remind'}</Badge>
                <div className="flex items-center gap-1">
                  <button
                    onClick={() => runNow(r)}
                    className="rounded-md p-1.5 text-muted hover:bg-surface-muted hover:text-primary"
                    title="Post one now"
                    aria-label="Run now"
                  >
                    <Play className="h-4 w-4" />
                  </button>
                  <label className="flex cursor-pointer items-center gap-1.5 text-xs text-muted">
                    <input type="checkbox" checked={r.active} onChange={() => toggle(r)} className="h-4 w-4 accent-[var(--primary)]" />
                    active
                  </label>
                  <button onClick={() => { setEditing(r); setFormOpen(true); }} className="rounded-md px-2 py-1 text-xs text-muted hover:bg-surface-muted">Edit</button>
                  <button onClick={() => remove(r)} className="rounded-md p-1 text-muted hover:bg-surface-muted hover:text-danger" aria-label="Delete">
                    <Trash2 className="h-3.5 w-3.5" />
                  </button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <RecurringForm open={formOpen} editing={editing} onClose={() => setFormOpen(false)} onSaved={() => void mutate()} />
    </div>
  );
}

function RecurringForm({ open, editing, onClose, onSaved }: { open: boolean; editing: RecurringRule | null; onClose: () => void; onSaved: () => void }) {
  const { data: accountsData } = useSWR<{ items: Account[] }>(open ? '/accounts' : null);
  const { data: categoriesData } = useSWR<{ items: Category[] }>(open ? '/categories' : null);

  const [name, setName] = useState('');
  const [kind, setKind] = useState<Exclude<TxKind, 'TRANSFER'>>('EXPENSE');
  const [amount, setAmount] = useState('');
  const [accountId, setAccountId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [frequency, setFrequency] = useState<Frequency>('MONTHLY');
  const [interval, setInterval] = useState('1');
  const [dayOfMonth, setDayOfMonth] = useState('1');
  const [nextRun, setNextRun] = useState(new Date().toISOString().slice(0, 10));
  const [autoPost, setAutoPost] = useState(true);
  const [saving, setSaving] = useState(false);

  const accounts = accountsData?.items.filter((a) => !a.archived) ?? [];
  const categories = (categoriesData?.items ?? []).filter((c) => !c.archived && c.kind === kind);

  useEffect(() => {
    if (!open) return;
    setName(editing?.name ?? '');
    setKind(editing?.kind === 'INCOME' ? 'INCOME' : 'EXPENSE');
    setAmount(editing ? String(Number(editing.amount)) : '');
    setAccountId(editing?.accountId ?? '');
    setCategoryId(editing?.categoryId ?? '');
    setFrequency(editing?.frequency ?? 'MONTHLY');
    setInterval(String(editing?.interval ?? 1));
    setDayOfMonth(String(editing?.dayOfMonth ?? 1));
    setNextRun(editing?.nextRun ? editing.nextRun.slice(0, 10) : new Date().toISOString().slice(0, 10));
    setAutoPost(editing?.autoPost ?? true);
  }, [open, editing]);

  useEffect(() => {
    if (open && !accountId && accounts.length > 0) setAccountId((accounts.find((a) => a.isDefault) ?? accounts[0]!).id);
  }, [open, accountId, accounts]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!categoryId) return toast.error('Pick a category');
    setSaving(true);
    const payload = {
      name,
      kind,
      amount: Number(amount),
      accountId,
      categoryId,
      frequency,
      interval: Number(interval),
      dayOfMonth: frequency === 'MONTHLY' ? Number(dayOfMonth) : undefined,
      nextRun,
      autoPost,
    };
    try {
      if (editing) await api.put(`/recurring/${editing.id}`, payload);
      else await api.post('/recurring', payload);
      toast.success(editing ? 'Rule updated' : 'Rule created');
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title={editing ? 'Edit rule' : 'New recurring rule'}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="Name"><Input required value={name} onChange={(e) => setName(e.target.value)} placeholder="Rent" /></Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="Type">
            <Select value={kind} onChange={(e) => { setKind(e.target.value as 'INCOME' | 'EXPENSE'); setCategoryId(''); }}>
              <option value="EXPENSE">Expense</option>
              <option value="INCOME">Income</option>
            </Select>
          </Field>
          <Field label="Amount"><Input type="number" step="0.01" min="0" required value={amount} onChange={(e) => setAmount(e.target.value)} /></Field>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <Field label="Account">
            <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
              {accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </Select>
          </Field>
          <Field label="Category">
            <Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
              <option value="">Select…</option>
              {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </Select>
          </Field>
        </div>
        <div className="grid grid-cols-3 gap-3">
          <Field label="Frequency">
            <Select value={frequency} onChange={(e) => setFrequency(e.target.value as Frequency)}>
              {FREQUENCIES.map((f) => <option key={f} value={f}>{f.toLowerCase()}</option>)}
            </Select>
          </Field>
          <Field label="Every">
            <Input type="number" min="1" value={interval} onChange={(e) => setInterval(e.target.value)} />
          </Field>
          {frequency === 'MONTHLY' && (
            <Field label="Day">
              <Input type="number" min="1" max="31" value={dayOfMonth} onChange={(e) => setDayOfMonth(e.target.value)} />
            </Field>
          )}
        </div>
        <Field label="Next run"><Input type="date" required value={nextRun} onChange={(e) => setNextRun(e.target.value)} /></Field>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={autoPost} onChange={(e) => setAutoPost(e.target.checked)} className="h-4 w-4 accent-[var(--primary)]" />
          Post automatically (uncheck to only get a reminder)
        </label>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={saving}>{editing ? 'Save' : 'Create rule'}</Button>
        </div>
      </form>
    </Modal>
  );
}
