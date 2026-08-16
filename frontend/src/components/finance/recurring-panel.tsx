'use client';
import { todayInputValue } from '@/lib/date-range';

import { useEffect, useMemo, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Play, Plus, Trash2 } from 'lucide-react';
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
import type {
  Account,
  BudgetRow,
  BudgetSourcesResponse,
  BudgetsResponse,
  Category,
  Frequency,
  RecurringRule,
  TxKind,
} from '@/lib/types';

const FREQUENCIES: Frequency[] = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'];
const freqLabel = (f: Frequency, interval: number) =>
  interval === 1 ? f.toLowerCase() : `every ${interval} ${f.toLowerCase().replace('ly', 's').replace('daiy', 'days')}`;

export function RecurringPanel({ presetBudgetId }: { presetBudgetId?: string } = {}) {
  const confirm = useConfirm();
  const { activeCurrency } = useCurrencyView();
  const { money } = useMoney();
  const { data, mutate } = useSWR<{ items: RecurringRule[] }>('/recurring');
  const [formOpen, setFormOpen] = useState(Boolean(presetBudgetId));
  const [editing, setEditing] = useState<RecurringRule | null>(null);
  const [preset, setPreset] = useState<string | undefined>(presetBudgetId);

  useEffect(() => {
    if (!presetBudgetId) return;
    setPreset(presetBudgetId);
    setEditing(null);
    setFormOpen(true);
  }, [presetBudgetId]);

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
        <Button
          size="sm"
          onClick={() => {
            setEditing(null);
            setPreset(undefined);
            setFormOpen(true);
          }}
        >
          <Plus className="h-4 w-4" /> New rule
        </Button>
      </div>

      {!data ? (
        <div className="space-y-3">{Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-16" />)}</div>
      ) : rules.length === 0 ? (
        <EmptyState
          title="No recurring rules"
          description={`No recurring rules in ${activeCurrency}. Switch currency in the header or create one.`}
          action={
            <Button
              onClick={() => {
                setEditing(null);
                setPreset(undefined);
                setFormOpen(true);
              }}
            >
              Create a rule
            </Button>
          }
        />
      ) : (
        <div className="space-y-2">
          {rules.map((r) => (
            <Card key={r.id} className={r.active ? undefined : 'opacity-60'}>
              <CardContent className="flex flex-wrap items-center gap-3 p-4">
                <div className="min-w-40 flex-1">
                  <p className="flex flex-wrap items-center gap-2 font-medium">
                    {r.name}
                    <Badge tone={r.kind === 'INCOME' ? 'success' : 'neutral'}>{r.kind.toLowerCase()}</Badge>
                    {r.kind === 'EXPENSE' &&
                      (r.budget ? (
                        <Badge tone="info">{r.budget.name}</Badge>
                      ) : (
                        <Badge tone="warning">Needs a plan</Badge>
                      ))}
                  </p>
                  {r.category && (
                    <CategoryBadge category={r.category} className="mt-1 text-xs text-muted" />
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
                  <button
                    onClick={() => {
                      setEditing(r);
                      setPreset(undefined);
                      setFormOpen(true);
                    }}
                    className="rounded-md px-2 py-1 text-xs text-muted hover:bg-surface-muted"
                  >
                    Edit
                  </button>
                  <button onClick={() => remove(r)} className="rounded-md p-1 text-muted hover:bg-surface-muted hover:text-danger" aria-label="Delete">
                    <Trash2 className="h-3.5 w-3.5" />
                  </button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      <RecurringForm
        open={formOpen}
        editing={editing}
        presetBudgetId={preset}
        onClose={() => {
          setFormOpen(false);
          setPreset(undefined);
        }}
        onSaved={() => void mutate()}
      />
    </div>
  );
}

function RecurringForm({
  open,
  editing,
  presetBudgetId,
  onClose,
  onSaved,
}: {
  open: boolean;
  editing: RecurringRule | null;
  presetBudgetId?: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { activeCurrency } = useCurrencyView();
  const { money } = useMoney();
  const { data: accountsData, isLoading: accountsLoading } = useSWR<{ items: Account[] }>(open ? '/accounts' : null);
  const { data: categoriesData, isLoading: categoriesLoading } = useSWR<{ items: Category[] }>(open ? '/categories' : null);
  const { data: budgetsData, isLoading: budgetsLoading } = useSWR<BudgetsResponse>(open ? '/budgets' : null);
  const { data: sourcesData } = useSWR<BudgetSourcesResponse>(open ? '/budgets/sources' : null);

  const [name, setName] = useState('');
  const [kind, setKind] = useState<Exclude<TxKind, 'TRANSFER'>>('EXPENSE');
  const [amount, setAmount] = useState('');
  const [accountId, setAccountId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [budgetId, setBudgetId] = useState('');
  const [frequency, setFrequency] = useState<Frequency>('MONTHLY');
  const [interval, setInterval] = useState('1');
  const [dayOfMonth, setDayOfMonth] = useState('1');
  const [nextRun, setNextRun] = useState(todayInputValue());
  const [autoPost, setAutoPost] = useState(true);
  const [saving, setSaving] = useState(false);
  const [defaultsApplied, setDefaultsApplied] = useState(false);

  const accounts = useMemo(
    () => accountsData?.items.filter((a) => !a.archived && a.currency === activeCurrency) ?? [],
    [accountsData?.items, activeCurrency],
  );
  const categories = (categoriesData?.items ?? []).filter((c) => !c.archived && c.kind === kind);

  const spendablePlans = useMemo(() => {
    return (budgetsData?.items ?? []).filter(
      (b) =>
        !b.isUnplanned &&
        b.state === 'ACTIVE' &&
        b.type !== 'SAVING' &&
        b.currency === activeCurrency,
    );
  }, [budgetsData?.items, activeCurrency]);

  const selectedPlan = spendablePlans.find((b) => b.id === budgetId);
  const amountNum = Number(amount) || 0;
  const potShort =
    kind === 'EXPENSE' &&
    selectedPlan != null &&
    amountNum > Number(selectedPlan.balance);

  function applyPlan(plan: BudgetRow | undefined) {
    if (!plan) {
      setBudgetId('');
      return;
    }
    setBudgetId(plan.id);
    if (plan.categoryId) setCategoryId(plan.categoryId);
    const sources = sourcesData?.items.find((s) => s.id === plan.id)?.sources ?? [];
    const withAccount = sources.filter((s) => s.account);
    if (withAccount.length > 0) {
      const sorted = [...withAccount].sort(
        (a, b) => Number(b.available ?? 0) - Number(a.available ?? 0),
      );
      const funderId = sorted[0]?.account?.id;
      if (funderId && accounts.some((a) => a.id === funderId)) {
        setAccountId(funderId);
      }
    }
  }

  useEffect(() => {
    if (!open) return;
    setName(editing?.name ?? '');
    setKind(editing?.kind === 'INCOME' ? 'INCOME' : 'EXPENSE');
    setAmount(editing ? String(Number(editing.amount)) : '');
    setAccountId(editing?.accountId ?? '');
    setCategoryId(editing?.categoryId ?? '');
    setBudgetId(editing?.budgetId ?? presetBudgetId ?? '');
    setFrequency(editing?.frequency ?? 'MONTHLY');
    setInterval(String(editing?.interval ?? 1));
    setDayOfMonth(String(editing?.dayOfMonth ?? 1));
    setNextRun(editing?.nextRun ? editing.nextRun.slice(0, 10) : todayInputValue());
    setAutoPost(editing?.autoPost ?? true);
    // Editing already has category/account; only auto-apply for new rules with a plan.
    setDefaultsApplied(Boolean(editing));
  }, [open, editing, presetBudgetId]);

  useEffect(() => {
    if (!open || editing || kind !== 'EXPENSE' || !budgetId || defaultsApplied) return;
    if (spendablePlans.length === 0 || !sourcesData || accounts.length === 0) return;
    const plan = spendablePlans.find((b) => b.id === budgetId);
    if (!plan) return;
    // Apply category + preferred funder once when opening with a plan selected.
    if (plan.categoryId) setCategoryId(plan.categoryId);
    const sources = sourcesData.items.find((s) => s.id === plan.id)?.sources ?? [];
    const withAccount = sources.filter((s) => s.account);
    if (withAccount.length > 0) {
      const sorted = [...withAccount].sort(
        (a, b) => Number(b.available ?? 0) - Number(a.available ?? 0),
      );
      const funderId = sorted[0]?.account?.id;
      if (funderId && accounts.some((a) => a.id === funderId)) {
        setAccountId(funderId);
      }
    }
    setDefaultsApplied(true);
  }, [
    open,
    editing,
    kind,
    budgetId,
    defaultsApplied,
    spendablePlans,
    sourcesData,
    accounts,
  ]);

  useEffect(() => {
    if (open && !accountId && accounts.length > 0) {
      setAccountId((accounts.find((a) => a.isDefault) ?? accounts[0]!).id);
    }
  }, [open, accountId, accounts]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!categoryId) return toast.error('Pick a category');
    if (kind === 'EXPENSE' && !budgetId) {
      return toast.error('A recurring expense must spend from a plan');
    }
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
      budgetId: kind === 'EXPENSE' ? budgetId : null,
    };
    const payload = { ...base, kind, categoryId };
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
    <Modal open={open} onClose={onClose} title={editing ? 'Edit rule' : 'New recurring plan'}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="Name">
          <Input required value={name} onChange={(e) => setName(e.target.value)} placeholder="Rent" />
        </Field>

        <div className="grid grid-cols-2 gap-3">
          <Field label="Type">
            <Select
              value={kind}
              onChange={(e) => {
                const next = e.target.value as 'INCOME' | 'EXPENSE';
                setKind(next);
                setCategoryId('');
                if (next === 'INCOME') setBudgetId('');
              }}
            >
              <option value="EXPENSE">Expense</option>
              <option value="INCOME">Income</option>
            </Select>
          </Field>
          <Field label="Amount">
            <Input type="number" step="0.01" min="0" required value={amount} onChange={(e) => setAmount(e.target.value)} />
          </Field>
        </div>

        {kind === 'EXPENSE' && (
          <Field
            label="Pay from plan"
            hint="Every recurring spend draws from an active spending plan — one-time or recurring envelopes both work."
          >
            <Select
              required
              value={budgetId}
              onChange={(e) => {
                const plan = spendablePlans.find((b) => b.id === e.target.value);
                applyPlan(plan);
              }}
              loading={budgetsLoading}
            >
              <option value="">
                {spendablePlans.length === 0 ? 'Create a spending plan first' : 'Pick a plan…'}
              </option>
              {spendablePlans.map((b) => (
                <option key={b.id} value={b.id}>
                  {b.name} · {money(b.balance)} left
                </option>
              ))}
            </Select>
            {potShort && (
              <p className="mt-1.5 text-xs text-warning">
                This plan has less than the rule amount right now. Fund it before the due date or the run will be held.
              </p>
            )}
          </Field>
        )}

        <div className="grid grid-cols-2 gap-3">
          <Field label={kind === 'EXPENSE' ? 'Take it out of' : 'Account'}>
            <Select value={accountId} onChange={(e) => setAccountId(e.target.value)} loading={open && accountsLoading}>
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Category">
            <Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)} loading={categoriesLoading}>
              <option value="">Select…</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>
        </div>

        <div className="grid grid-cols-3 gap-3">
          <Field label="Frequency">
            <Select value={frequency} onChange={(e) => setFrequency(e.target.value as Frequency)}>
              {FREQUENCIES.map((f) => (
                <option key={f} value={f}>
                  {f.toLowerCase()}
                </option>
              ))}
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
        <Field label="Next run">
          <DateInput required value={nextRun} onChange={(e) => setNextRun(e.target.value)} />
        </Field>
        <Checkbox checked={autoPost} onChange={setAutoPost} label="Post automatically" />
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            {editing ? 'Save' : 'Create'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
