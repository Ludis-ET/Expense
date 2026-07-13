'use client';

import { useEffect, useMemo, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Play, Plus, Trash2, Target, Sparkles } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Checkbox } from '@/components/ui/checkbox';
import { Field, Input, Select, DateInput } from '@/components/ui/input';
import { Skeleton, EmptyState } from '@/components/ui/misc';
import { CategoryBadge } from '@/components/finance/category-badge';
import { api, ApiError } from '@/lib/api';
import { formatDate } from '@/lib/format';
import { useMoney } from '@/lib/amount-visibility';
import { useCurrencyView } from '@/lib/currency-view-context';
import { useConfirm } from '@/components/ui/confirm-dialog';
import type { Account, Category, Frequency, RecurringRule, SavingsGoal, TxKind, WishlistItem } from '@/lib/types';

type PlanType = 'transaction' | 'goal' | 'wishlist';

const FREQUENCIES: Frequency[] = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'];
const freqLabel = (f: Frequency, interval: number) =>
  interval === 1 ? f.toLowerCase() : `every ${interval} ${f.toLowerCase().replace('ly', 's').replace('daiy', 'days')}`;

export function RecurringPanel() {
  const confirm = useConfirm();
  const { activeCurrency } = useCurrencyView();
  const { money } = useMoney();
  const { data, mutate } = useSWR<{ items: RecurringRule[] }>('/recurring');
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<RecurringRule | null>(null);

  const [togglingId, setTogglingId] = useState<string | null>(null);

  async function toggle(rule: RecurringRule) {
    setTogglingId(rule.id);
    try {
      await api.put(`/recurring/${rule.id}`, { active: !rule.active });
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setTogglingId(null);
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
    const ok = await confirm({
      title: 'Delete recurring rule?',
      description: `Delete "${rule.name}"? Future scheduled posts will stop.`,
      confirmLabel: 'Delete',
      tone: 'danger',
    });
    if (!ok) return;
    try {
      await api.del(`/recurring/${rule.id}`);
      toast.success('Deleted');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  const rules = (data?.items ?? []).filter((r) => r.currency === activeCurrency);

  return (
    <div>
      <div className="mb-4 flex justify-end">
        <Button size="sm" onClick={() => { setEditing(null); setFormOpen(true); }}>
          <Plus className="h-4 w-4" /> New rule
        </Button>
      </div>

      {!data ? (
        <div className="space-y-3">{Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-16" />)}</div>
      ) : rules.length === 0 ? (
        <EmptyState
          title="No recurring rules"
          description={`No recurring rules in ${activeCurrency}. Switch currency in the header or create one.`}
          action={<Button onClick={() => { setEditing(null); setFormOpen(true); }}>Create a rule</Button>}
        />
      ) : (
        <div className="space-y-2">
          {rules.map((r) => (
            <Card key={r.id} className={r.active ? undefined : 'opacity-60'}>
              <CardContent className="flex flex-wrap items-center gap-3 p-4">
                <div className="min-w-40 flex-1">
                  <p className="flex items-center gap-2 font-medium">
                    {r.name}
                    {r.planType === 'goal' ? (
                      <Badge tone="info">auto-save</Badge>
                    ) : r.planType === 'wishlist' ? (
                      <Badge tone="info">wishlist</Badge>
                    ) : (
                      <Badge tone={r.kind === 'INCOME' ? 'success' : 'neutral'}>{r.kind.toLowerCase()}</Badge>
                    )}
                  </p>
                  {r.planType === 'goal' && r.goal ? (
                    <p className="mt-1 flex items-center gap-1 text-xs text-muted">
                      <Target className="h-3 w-3" /> {r.goal.name}
                    </p>
                  ) : r.planType === 'wishlist' && r.wishlistItem ? (
                    <p className="mt-1 flex items-center gap-1 text-xs text-muted">
                      <Sparkles className="h-3 w-3" /> {r.wishlistItem.emoji} {r.wishlistItem.name}
                    </p>
                  ) : (
                    r.category && <CategoryBadge category={r.category} className="mt-1 text-xs text-muted" />
                  )}
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
                  <button onClick={() => runNow(r)} className="rounded-md p-1.5 text-muted hover:bg-surface-muted hover:text-primary" title="Post now" aria-label="Run now">
                    <Play className="h-4 w-4" />
                  </button>
                  <Checkbox
                    checked={r.active}
                    loading={togglingId === r.id}
                    onChange={() => toggle(r)}
                    label="active"
                  />
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

const PLAN_TYPES: { id: PlanType; label: string; hint: string }[] = [
  { id: 'transaction', label: 'Transaction', hint: 'Post income or an expense on a schedule.' },
  { id: 'goal', label: 'Save to goal', hint: 'Auto-contribute to a savings goal each period.' },
  { id: 'wishlist', label: 'Fund a want', hint: 'Set money aside toward a wishlist item.' },
];

function RecurringForm({ open, editing, onClose, onSaved }: { open: boolean; editing: RecurringRule | null; onClose: () => void; onSaved: () => void }) {
  const { activeCurrency } = useCurrencyView();
  const { data: accountsData } = useSWR<{ items: Account[] }>(open ? '/accounts' : null);
  const { data: categoriesData } = useSWR<{ items: Category[] }>(open ? '/categories' : null);
  const { data: goalsData } = useSWR<{ items: SavingsGoal[] }>(open ? '/goals' : null);
  const { data: wishlistData } = useSWR<{ items: WishlistItem[] }>(
    open ? `/wishlist?currency=${encodeURIComponent(activeCurrency)}` : null,
  );
  const [planType, setPlanType] = useState<PlanType>('transaction');
  const [name, setName] = useState('');
  const [kind, setKind] = useState<Exclude<TxKind, 'TRANSFER'>>('EXPENSE');
  const [amount, setAmount] = useState('');
  const [accountId, setAccountId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [goalId, setGoalId] = useState('');
  const [wishlistItemId, setWishlistItemId] = useState('');
  const [frequency, setFrequency] = useState<Frequency>('MONTHLY');
  const [interval, setInterval] = useState('1');
  const [dayOfMonth, setDayOfMonth] = useState('1');
  const [nextRun, setNextRun] = useState(new Date().toISOString().slice(0, 10));
  const [autoPost, setAutoPost] = useState(true);
  const [saving, setSaving] = useState(false);
  const accounts = useMemo(
    () => accountsData?.items.filter((a) => !a.archived) ?? [],
    [accountsData?.items],
  );
  const categories = (categoriesData?.items ?? []).filter((c) => !c.archived && c.kind === kind);
  const goals = (goalsData?.items ?? []).filter((g) => !g.achievedAt);
  const wants = (wishlistData?.items ?? []).filter((w) => w.status === 'WANTING' || w.status === 'SAVING');
  const isSavings = planType !== 'transaction';

  useEffect(() => {
    if (!open) return;
    setPlanType(editing?.planType ?? 'transaction');
    setName(editing?.name ?? '');
    setKind(editing?.kind === 'INCOME' ? 'INCOME' : 'EXPENSE');
    setAmount(editing ? String(Number(editing.amount)) : '');
    setAccountId(editing?.accountId ?? '');
    setCategoryId(editing?.categoryId ?? '');
    setGoalId(editing?.goalId ?? '');
    setWishlistItemId(editing?.wishlistItemId ?? '');
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
    if (planType === 'transaction' && !categoryId) return toast.error('Pick a category');
    if (planType === 'goal' && !goalId) return toast.error('Pick a goal');
    if (planType === 'wishlist' && !wishlistItemId) return toast.error('Pick a wishlist item');
    setSaving(true);
    const base = {
      name,
      amount: Number(amount),
      accountId,
      currency: activeCurrency,
      frequency,
      interval: Number(interval),
      dayOfMonth: frequency === 'MONTHLY' ? Number(dayOfMonth) : undefined,
      nextRun,
      autoPost,
    };
    const payload = isSavings
      ? {
          ...base,
          kind: 'EXPENSE' as const,
          goalId: planType === 'goal' ? goalId : null,
          wishlistItemId: planType === 'wishlist' ? wishlistItemId : null,
          categoryId: null,
        }
      : { ...base, kind, categoryId, goalId: null, wishlistItemId: null };
    try {
      if (editing) await api.put(`/recurring/${editing.id}`, payload);
      else await api.post('/recurring', payload);
      toast.success(editing ? 'Rule updated' : isSavings ? 'Auto-save plan created' : 'Rule created');
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title={editing ? 'Edit rule' : 'New recurring plan'}>
      <form onSubmit={submit} className="space-y-4">
        {!editing && (
          <div className="grid grid-cols-3 gap-2">
            {PLAN_TYPES.map((p) => (
              <button
                key={p.id}
                type="button"
                onClick={() => setPlanType(p.id)}
                className={`rounded-xl border p-2.5 text-left text-xs transition-colors ${
                  planType === p.id ? 'border-primary bg-primary/5' : 'border-border hover:bg-surface-muted'
                }`}
              >
                <span className="block font-semibold">{p.label}</span>
              </button>
            ))}
          </div>
        )}
        {isSavings && (
          <p className="rounded-lg bg-primary/5 px-3 py-2 text-xs text-muted">
            {PLAN_TYPES.find((p) => p.id === planType)!.hint} A linked spend lock will grow automatically, reserving the money.
          </p>
        )}

        <Field label="Name"><Input required value={name} onChange={(e) => setName(e.target.value)} placeholder={isSavings ? 'Weekly saving' : 'Rent'} /></Field>

        <div className="grid grid-cols-2 gap-3">
          {isSavings ? (
            <Field label="Type"><Input value="Auto-save" disabled /></Field>
          ) : (
            <Field label="Type">
              <Select value={kind} onChange={(e) => { setKind(e.target.value as 'INCOME' | 'EXPENSE'); setCategoryId(''); }}>
                <option value="EXPENSE">Expense</option>
                <option value="INCOME">Income</option>
              </Select>
            </Field>
          )}
          <Field label="Amount"><Input type="number" step="0.01" min="0" required value={amount} onChange={(e) => setAmount(e.target.value)} /></Field>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <Field label={isSavings ? 'From account' : 'Account'}><Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>{accounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</Select></Field>
          {planType === 'transaction' && (
            <Field label="Category"><Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}><option value="">Select…</option>{categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</Select></Field>
          )}
          {planType === 'goal' && (
            <Field label="Goal"><Select value={goalId} onChange={(e) => setGoalId(e.target.value)}><option value="">Select…</option>{goals.map((g) => <option key={g.id} value={g.id}>{g.name}</option>)}</Select></Field>
          )}
          {planType === 'wishlist' && (
            <Field label="Wishlist item"><Select value={wishlistItemId} onChange={(e) => setWishlistItemId(e.target.value)}><option value="">Select…</option>{wants.map((w) => <option key={w.id} value={w.id}>{w.emoji} {w.name}</option>)}</Select></Field>
          )}
        </div>

        <div className="grid grid-cols-3 gap-3">
          <Field label="Frequency"><Select value={frequency} onChange={(e) => setFrequency(e.target.value as Frequency)}>{FREQUENCIES.map((f) => <option key={f} value={f}>{f.toLowerCase()}</option>)}</Select></Field>
          <Field label="Every"><Input type="number" min="1" value={interval} onChange={(e) => setInterval(e.target.value)} /></Field>
          {frequency === 'MONTHLY' && <Field label="Day"><Input type="number" min="1" max="31" value={dayOfMonth} onChange={(e) => setDayOfMonth(e.target.value)} /></Field>}
        </div>
        <Field label="Next run"><DateInput required value={nextRun} onChange={(e) => setNextRun(e.target.value)} /></Field>
        <Checkbox checked={autoPost} onChange={setAutoPost} label={isSavings ? 'Save automatically' : 'Post automatically'} />
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={saving}>{editing ? 'Save' : 'Create'}</Button>
        </div>
      </form>
    </Modal>
  );
}
