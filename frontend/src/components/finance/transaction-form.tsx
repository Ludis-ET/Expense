'use client';

import { useEffect, useMemo, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Sparkles, Wallet } from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select, Textarea, DateInput } from '@/components/ui/input';
import { financeIcon } from './icons';
import { api, ApiError } from '@/lib/api';
import { useOffline } from '@/lib/offline/offline-context';
import { newId } from '@/lib/offline/outbox';
import { cn } from '@/lib/utils';
import type {
  Account,
  BudgetSourcesResponse,
  Category,
  Transaction,
  TxKind,
} from '@/lib/types';

/**
 * The "pay from" dropdown mixes plain accounts with budget plans that still
 * hold money. A plan value is prefixed so the two namespaces can't collide.
 */
const PLAN_PREFIX = 'plan:';

interface TransactionFormProps {
  open: boolean;
  onClose: () => void;
  onSaved: () => void;
  /** When set, the form edits this transaction instead of creating one. */
  editing?: Transaction | null;
}

const KINDS: { value: Exclude<TxKind, 'TRANSFER'>; label: string }[] = [
  { value: 'EXPENSE', label: 'Expense' },
  { value: 'INCOME', label: 'Income' },
];

export function TransactionForm({ open, onClose, onSaved, editing }: TransactionFormProps) {
  const { data: accountsData } = useSWR<{ items: Account[] }>(open ? '/accounts' : null);
  const { data: categoriesData } = useSWR<{ items: Category[] }>(open ? '/categories' : null);
  const { data: plansData } = useSWR<BudgetSourcesResponse>(open ? '/budgets/sources' : null);
  const { saveTransaction, updateTransaction } = useOffline();

  const [kind, setKind] = useState<Exclude<TxKind, 'TRANSFER'>>('EXPENSE');
  const [amount, setAmount] = useState('');
  /** Either an account id, or `plan:<budgetId>`. */
  const [source, setSource] = useState('');
  /** Only used when the chosen source is the pot-less Unplanned plan. */
  const [drawFromId, setDrawFromId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [payee, setPayee] = useState('');
  const [note, setNote] = useState('');
  const [tags, setTags] = useState('');
  const [saving, setSaving] = useState(false);
  const [suggesting, setSuggesting] = useState(false);

  const accounts = useMemo(
    () => accountsData?.items.filter((a) => !a.archived) ?? [],
    [accountsData?.items],
  );
  // Plans are a spend source for expenses only, and only while they hold money.
  const plans = useMemo(
    () => (kind === 'EXPENSE' ? (plansData?.items ?? []) : []),
    [kind, plansData?.items],
  );
  const categories = (categoriesData?.items ?? []).filter((c) => !c.archived && c.kind === kind);

  const selectedPlan = source.startsWith(PLAN_PREFIX)
    ? plans.find((p) => p.id === source.slice(PLAN_PREFIX.length))
    : undefined;
  const isUnplanned = selectedPlan?.isUnplanned ?? false;

  // A funded plan charges the account that filled it; Unplanned draws on
  // whichever account the user points at.
  const accountId = !selectedPlan ? source : isUnplanned ? drawFromId : undefined;
  const drawAccount = accounts.find((a) => a.id === drawFromId);

  // Seed the form when opening (either blank or from the editing target).
  useEffect(() => {
    if (!open) return;
    if (editing) {
      setKind(editing.kind === 'INCOME' ? 'INCOME' : 'EXPENSE');
      setAmount(String(Number(editing.amount)));
      setSource(editing.budgetId ? `${PLAN_PREFIX}${editing.budgetId}` : editing.accountId);
      setDrawFromId(editing.accountId);
      setCategoryId(editing.categoryId ?? '');
      setDate(editing.date.slice(0, 10));
      setPayee(editing.payee ?? '');
      setNote(editing.note ?? '');
      setTags(editing.tags.join(', '));
    } else {
      setKind('EXPENSE');
      setAmount('');
      setCategoryId('');
      setDate(new Date().toISOString().slice(0, 10));
      setPayee('');
      setNote('');
      setTags('');
    }
  }, [open, editing]);

  // Default the source to the user's default account once accounts load.
  useEffect(() => {
    if (open && !editing && !source && accounts.length > 0) {
      setSource((accounts.find((a) => a.isDefault) ?? accounts[0]!).id);
    }
  }, [open, editing, source, accounts]);

  // Keep the Unplanned draw-from account valid and defaulted.
  useEffect(() => {
    if (!isUnplanned || accounts.length === 0) return;
    if (!accounts.some((a) => a.id === drawFromId)) {
      setDrawFromId((accounts.find((a) => a.isDefault) ?? accounts[0]!).id);
    }
  }, [isUnplanned, accounts, drawFromId]);

  // Switching to income drops any plan selection - plans only pay expenses.
  useEffect(() => {
    if (kind === 'INCOME' && source.startsWith(PLAN_PREFIX)) {
      setSource((accounts.find((a) => a.isDefault) ?? accounts[0])?.id ?? '');
    }
  }, [kind, source, accounts]);

  /** Picking a plan that has a category pre-selects it, as promised. */
  function pickSource(value: string) {
    setSource(value);
    if (value.startsWith(PLAN_PREFIX)) {
      const plan = plans.find((p) => p.id === value.slice(PLAN_PREFIX.length));
      if (plan?.categoryId) setCategoryId(plan.categoryId);
    }
  }

  async function suggestCategory() {
    const description = [payee, note].filter(Boolean).join(' ');
    if (!description) {
      toast.info('Add a payee or note first, then I can suggest a category.');
      return;
    }
    setSuggesting(true);
    try {
      const res = await api.post<{ categoryId: string | null; kind: string | null; payee: string | null }>(
        '/ai/categorize',
        { description, amount: amount ? Number(amount) : undefined, payee: payee || undefined },
      );
      if (res.kind === 'INCOME' || res.kind === 'EXPENSE') setKind(res.kind);
      if (res.categoryId) {
        setCategoryId(res.categoryId);
        if (res.payee && !payee) setPayee(res.payee);
        toast.success('Category suggested');
      } else {
        toast.info('Couldn’t confidently match a category.');
      }
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Suggestion failed - is an AI provider configured?');
    } finally {
      setSuggesting(false);
    }
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!source) return toast.error('Pick an account or plan');
    if (!categoryId) return toast.error('Pick a category');
    if (isUnplanned && !drawFromId) return toast.error('Pick which account this comes out of');
    if (selectedPlan && !isUnplanned && Number(amount) > Number(selectedPlan.balance)) {
      return toast.error(
        `"${selectedPlan.name}" only has ${Number(selectedPlan.balance).toFixed(2)} ${selectedPlan.currency} left.`,
      );
    }
    if (isUnplanned && drawAccount && Number(amount) > Number(drawAccount.balance)) {
      return toast.error(
        `"${drawAccount.name}" only has ${Number(drawAccount.balance).toFixed(2)} ${drawAccount.currency} available.`,
      );
    }
    setSaving(true);
    const tagList = tags.split(',').map((t) => t.trim()).filter(Boolean);
    const payload = {
      kind,
      amount: Number(amount),
      // Unplanned sends both: the plan it is filed under, and the account it
      // actually comes out of.
      ...(selectedPlan
        ? { budgetId: selectedPlan.id, ...(isUnplanned ? { accountId: drawFromId } : {}) }
        : { accountId }),
      categoryId,
      date,
      payee: payee || undefined,
      note: note || undefined,
      tags: tagList,
    };

    // A local preview so the change appears instantly, even offline. For a plan
    // spend the backend decides the account, so mirror its largest source.
    const previewAccountId =
      accountId ?? selectedPlan?.sources[0]?.account?.id ?? editing?.accountId ?? '';
    const account = accounts.find((a) => a.id === previewAccountId);
    const category = categories.find((c) => c.id === categoryId);
    const optimistic: Transaction = {
      id: editing ? editing.id : newId(),
      kind,
      amount: Number(amount).toFixed(2),
      currency: selectedPlan?.currency ?? account?.currency ?? 'ETB',
      date: `${date}T12:00:00.000Z`,
      accountId: previewAccountId,
      account: account ? { id: account.id, name: account.name, type: account.type } : undefined,
      categoryId,
      category: category ? { id: category.id, name: category.name, icon: category.icon, color: category.color } : null,
      budgetId: selectedPlan?.id ?? null,
      budget: selectedPlan
        ? {
            id: selectedPlan.id,
            name: selectedPlan.name,
            icon: selectedPlan.icon,
            color: selectedPlan.color,
            currency: selectedPlan.currency,
          }
        : null,
      payee: payee || null,
      note: note || null,
      tags: tagList,
    };

    try {
      const { queued } = editing
        ? await updateTransaction(editing.id, payload, optimistic)
        : await saveTransaction(payload, optimistic);
      toast.success(
        queued
          ? 'Saved offline - will sync when you reconnect'
          : editing
            ? 'Transaction updated'
            : 'Transaction added',
      );
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title={editing ? 'Edit transaction' : 'Add transaction'}>
      <form onSubmit={submit} className="space-y-4">
        {!editing && (
          <div className="grid grid-cols-2 gap-2">
            {KINDS.map((k) => (
              <button
                key={k.value}
                type="button"
                onClick={() => {
                  setKind(k.value);
                  setCategoryId('');
                }}
                className={cn(
                  'rounded-lg border px-4 py-2 text-sm font-medium transition-colors',
                  kind === k.value
                    ? k.value === 'INCOME'
                      ? 'border-emerald-500 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
                      : 'border-primary bg-primary/10 text-primary'
                    : 'border-border text-muted hover:bg-surface-muted',
                )}
              >
                {k.label}
              </button>
            ))}
          </div>
        )}

        <div className="grid grid-cols-2 gap-3">
          <Field label="Amount">
            <Input
              type="number"
              inputMode="decimal"
              step="0.01"
              min="0"
              required
              autoFocus
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
            />
          </Field>
          <Field label="Date">
            <DateInput
              required
              maxToday
              value={date}
              onChange={(e) => setDate(e.target.value)}
            />
          </Field>
        </div>

        <Field
          label="Pay from"
          hint={plans.length > 0 ? 'accounts or a funded budget plan' : undefined}
        >
          <Select value={source} onChange={(e) => pickSource(e.target.value)}>
            <optgroup label="Accounts">
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name} - {Number(a.balance).toFixed(2)} {a.currency} available
                </option>
              ))}
            </optgroup>
            {plans.some((p) => !p.isUnplanned) && (
              <optgroup label="Budget plans">
                {plans
                  .filter((p) => !p.isUnplanned)
                  .map((p) => (
                    <option key={p.id} value={`${PLAN_PREFIX}${p.id}`}>
                      {p.name} - {Number(p.balance).toFixed(2)} {p.currency} left
                    </option>
                  ))}
              </optgroup>
            )}
            {plans
              .filter((p) => p.isUnplanned)
              .map((p) => (
                <optgroup key={p.id} label="Not set aside">
                  <option value={`${PLAN_PREFIX}${p.id}`}>{p.name}</option>
                </optgroup>
              ))}
          </Select>
        </Field>

        {isUnplanned && (
          <Field label="Take it out of" hint="Unplanned has no pot of its own">
            <Select value={drawFromId} onChange={(e) => setDrawFromId(e.target.value)}>
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name} - {Number(a.balance).toFixed(2)} {a.currency} available
                </option>
              ))}
            </Select>
          </Field>
        )}

        {selectedPlan && !isUnplanned && (
          <p className="-mt-2 flex items-start gap-2 rounded-xl bg-primary/5 px-3 py-2 text-xs text-muted">
            <Wallet className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" />
            <span>
              Comes out of the money already set aside in{' '}
              <strong className="text-foreground">{selectedPlan.name}</strong>
              {selectedPlan.sources[0]?.account && (
                <> · charged to {selectedPlan.sources[0].account.name}</>
              )}
              . It can&apos;t go below zero.
            </span>
          </p>
        )}

        {isUnplanned && (
          <p className="-mt-2 flex items-start gap-2 rounded-xl bg-surface-muted/60 px-3 py-2 text-xs text-muted">
            <Wallet className="mt-0.5 h-3.5 w-3.5 shrink-0" />
            <span>
              Money you did not set aside in advance. It comes straight out of the account
              you picked, from whatever is left after your other plans.
            </span>
          </p>
        )}

        <div>
          <div className="mb-1.5 flex items-center justify-between">
            <label className="text-sm font-medium">Category</label>
            <button
              type="button"
              onClick={suggestCategory}
              disabled={suggesting}
              className="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline disabled:opacity-50"
            >
              <Sparkles className="h-3 w-3" /> {suggesting ? 'Thinking…' : 'Suggest'}
            </button>
          </div>
          <div className="grid max-h-40 grid-cols-2 gap-1.5 overflow-y-auto rounded-lg border border-border p-2 sm:grid-cols-3">
            {categories.map((c) => {
              const Icon = financeIcon(c.icon);
              return (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => setCategoryId(c.id)}
                  className={cn(
                    'flex items-center gap-1.5 rounded-md px-2 py-1.5 text-left text-xs font-medium transition-colors',
                    categoryId === c.id ? 'text-primary-foreground' : 'text-foreground hover:bg-surface-muted',
                  )}
                  style={categoryId === c.id ? { backgroundColor: c.color } : undefined}
                >
                  <Icon className="h-3.5 w-3.5 shrink-0" style={categoryId === c.id ? undefined : { color: c.color }} />
                  <span className="truncate">{c.name}</span>
                </button>
              );
            })}
          </div>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <Field label="Payee">
            <Input value={payee} onChange={(e) => setPayee(e.target.value)} placeholder="Shoa Supermarket" />
          </Field>
          <Field label="Tags" hint="comma-separated">
            <Input value={tags} onChange={(e) => setTags(e.target.value)} placeholder="groceries, weekly" />
          </Field>
        </div>

        <Field label="Note">
          <Textarea value={note} onChange={(e) => setNote(e.target.value)} rows={2} placeholder="Optional details…" />
        </Field>

        <div className="flex justify-end gap-2 pt-1">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            {editing ? 'Save changes' : 'Add transaction'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
