'use client';

import { useEffect, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Sparkles } from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select, Textarea } from '@/components/ui/input';
import { financeIcon } from './icons';
import { api, ApiError } from '@/lib/api';
import { cn } from '@/lib/utils';
import type { Account, Category, Transaction, TxKind } from '@/lib/types';

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

  const [kind, setKind] = useState<Exclude<TxKind, 'TRANSFER'>>('EXPENSE');
  const [amount, setAmount] = useState('');
  const [accountId, setAccountId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10));
  const [payee, setPayee] = useState('');
  const [note, setNote] = useState('');
  const [tags, setTags] = useState('');
  const [saving, setSaving] = useState(false);
  const [suggesting, setSuggesting] = useState(false);

  const accounts = accountsData?.items.filter((a) => !a.archived) ?? [];
  const categories = (categoriesData?.items ?? []).filter((c) => !c.archived && c.kind === kind);

  // Seed the form when opening (either blank or from the editing target).
  useEffect(() => {
    if (!open) return;
    if (editing) {
      setKind(editing.kind === 'INCOME' ? 'INCOME' : 'EXPENSE');
      setAmount(String(Number(editing.amount)));
      setAccountId(editing.accountId);
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

  // Default the account to the user's default once accounts load.
  useEffect(() => {
    if (open && !editing && !accountId && accounts.length > 0) {
      setAccountId((accounts.find((a) => a.isDefault) ?? accounts[0]!).id);
    }
  }, [open, editing, accountId, accounts]);

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
      toast.error(err instanceof ApiError ? err.message : 'Suggestion failed — is an AI provider configured?');
    } finally {
      setSuggesting(false);
    }
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!accountId) return toast.error('Pick an account');
    if (!categoryId) return toast.error('Pick a category');
    setSaving(true);
    const payload = {
      kind,
      amount: Number(amount),
      accountId,
      categoryId,
      date,
      payee: payee || undefined,
      note: note || undefined,
      tags: tags.split(',').map((t) => t.trim()).filter(Boolean),
    };
    try {
      if (editing) await api.put(`/transactions/${editing.id}`, payload);
      else await api.post('/transactions', payload);
      toast.success(editing ? 'Transaction updated' : 'Transaction added');
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
            <Input type="date" required value={date} onChange={(e) => setDate(e.target.value)} />
          </Field>
        </div>

        <Field label="Account">
          <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
            {accounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </Select>
        </Field>

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
