'use client';

import { useEffect, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { ArrowLeftRight, Plus, Trash2 } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select } from '@/components/ui/input';
import { PageHeader, Skeleton, EmptyState } from '@/components/ui/misc';
import { TransferModal } from '@/components/finance/transfer-modal';
import { IconPicker, ColorPicker } from '@/components/finance/pickers';
import { financeIcon } from '@/components/finance/icons';
import { api, ApiError } from '@/lib/api';
import { formatMoney } from '@/lib/format';
import { useAuth } from '@/lib/auth';
import type { Account, AccountType } from '@/lib/types';

const TYPES: AccountType[] = ['CASH', 'BANK', 'MOBILE_MONEY', 'CARD', 'OTHER'];
const typeLabel = (t: AccountType) => t.replace('_', ' ').toLowerCase().replace(/^\w/, (c) => c.toUpperCase());

export default function AccountsPage() {
  const { user } = useAuth();
  const currency = user?.currency ?? 'ETB';
  const { data, mutate } = useSWR<{ items: Account[] }>('/accounts');
  const [formOpen, setFormOpen] = useState(false);
  const [transferOpen, setTransferOpen] = useState(false);
  const [editing, setEditing] = useState<Account | null>(null);

  const money = (v: number | string) => formatMoney(v, currency);
  const accounts = data?.items ?? [];
  const total = accounts.filter((a) => !a.archived).reduce((s, a) => s + Number(a.balance), 0);

  async function remove(account: Account) {
    if (!confirm(`Delete "${account.name}"?`)) return;
    try {
      await api.del(`/accounts/${account.id}`);
      toast.success('Account deleted');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to delete');
    }
  }

  return (
    <div>
      <PageHeader
        title="Accounts"
        description="Cash, bank and mobile-money wallets."
        action={
          <div className="flex gap-2">
            <Button variant="outline" size="sm" disabled={accounts.length < 2} onClick={() => setTransferOpen(true)}>
              <ArrowLeftRight className="h-4 w-4" /> Transfer
            </Button>
            <Button size="sm" onClick={() => { setEditing(null); setFormOpen(true); }}>
              <Plus className="h-4 w-4" /> Add
            </Button>
          </div>
        }
      />

      {!data ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-32" />)}
        </div>
      ) : accounts.length === 0 ? (
        <EmptyState title="No accounts" description="Add your first wallet to start tracking." />
      ) : (
        <>
          <Card className="mb-4">
            <CardContent className="flex items-center justify-between p-5">
              <span className="text-sm text-muted">Total balance across accounts</span>
              <span className="text-2xl font-bold tabular-nums">{money(total)}</span>
            </CardContent>
          </Card>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {accounts.map((a) => {
              const Icon = financeIcon(a.icon);
              const color = a.color ?? '#64748b';
              return (
                <Card key={a.id} className={a.archived ? 'opacity-60' : undefined}>
                  <CardContent className="p-5">
                    <div className="flex items-start justify-between">
                      <span
                        className="flex h-10 w-10 items-center justify-center rounded-lg"
                        style={{ backgroundColor: `${color}22`, color }}
                      >
                        <Icon className="h-5 w-5" />
                      </span>
                      <div className="flex gap-1">
                        <button
                          onClick={() => { setEditing(a); setFormOpen(true); }}
                          className="rounded-md px-2 py-1 text-xs text-muted hover:bg-surface-muted"
                        >
                          Edit
                        </button>
                        <button
                          onClick={() => remove(a)}
                          className="rounded-md p-1 text-muted hover:bg-surface-muted hover:text-danger"
                          aria-label="Delete"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </button>
                      </div>
                    </div>
                    <p className="mt-3 flex items-center gap-2 font-medium">
                      {a.name}
                      {a.isDefault && <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] text-primary">default</span>}
                      {a.archived && <span className="rounded-full bg-surface-muted px-2 py-0.5 text-[10px] text-muted">archived</span>}
                    </p>
                    <p className="text-xs text-muted">{typeLabel(a.type)} · {a.currency}</p>
                    <p className="mt-2 text-xl font-bold tabular-nums">{money(a.balance)}</p>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        </>
      )}

      <AccountForm
        open={formOpen}
        editing={editing}
        defaultCurrency={currency}
        onClose={() => setFormOpen(false)}
        onSaved={() => void mutate()}
      />
      <TransferModal open={transferOpen} onClose={() => setTransferOpen(false)} onSaved={() => void mutate()} />
    </div>
  );
}

function AccountForm({
  open,
  editing,
  defaultCurrency,
  onClose,
  onSaved,
}: {
  open: boolean;
  editing: Account | null;
  defaultCurrency: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState('');
  const [type, setType] = useState<AccountType>('CASH');
  const [currency, setCurrency] = useState(defaultCurrency);
  const [openingBalance, setOpeningBalance] = useState('0');
  const [icon, setIcon] = useState('wallet');
  const [color, setColor] = useState('#3b82f6');
  const [archived, setArchived] = useState(false);
  const [saving, setSaving] = useState(false);

  // Seed the fields from the editing target (or blank) each time the modal opens.
  useEffect(() => {
    if (!open) return;
    setName(editing?.name ?? '');
    setType(editing?.type ?? 'CASH');
    setCurrency(editing?.currency ?? defaultCurrency);
    setOpeningBalance(editing ? String(Number(editing.openingBalance)) : '0');
    setIcon(editing?.icon ?? 'wallet');
    setColor(editing?.color ?? '#3b82f6');
    setArchived(editing?.archived ?? false);
  }, [open, editing, defaultCurrency]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    const payload = { name, type, currency, openingBalance: Number(openingBalance), icon, color, archived };
    try {
      if (editing) await api.put(`/accounts/${editing.id}`, payload);
      else await api.post('/accounts', payload);
      toast.success(editing ? 'Account updated' : 'Account added');
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title={editing ? 'Edit account' : 'Add account'}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="Name">
          <Input required value={name} onChange={(e) => setName(e.target.value)} placeholder="CBE" />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="Type">
            <Select value={type} onChange={(e) => setType(e.target.value as AccountType)}>
              {TYPES.map((t) => <option key={t} value={t}>{typeLabel(t)}</option>)}
            </Select>
          </Field>
          <Field label="Currency">
            <Input value={currency} onChange={(e) => setCurrency(e.target.value.toUpperCase())} maxLength={3} />
          </Field>
        </div>
        <Field label="Opening balance">
          <Input type="number" step="0.01" value={openingBalance} onChange={(e) => setOpeningBalance(e.target.value)} />
        </Field>
        <Field label="Icon">
          <IconPicker value={icon} onChange={setIcon} />
        </Field>
        <Field label="Color">
          <ColorPicker value={color} onChange={setColor} />
        </Field>
        {editing && (
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={archived} onChange={(e) => setArchived(e.target.checked)} className="h-4 w-4 accent-[var(--primary)]" />
            Archived
          </label>
        )}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={saving}>{editing ? 'Save' : 'Add account'}</Button>
        </div>
      </form>
    </Modal>
  );
}
