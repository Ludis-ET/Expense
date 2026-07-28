'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import useSWR from 'swr';
import { toast } from 'sonner';
import { ArrowLeftRight, Plus, Trash2 } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select } from '@/components/ui/input';
import { PageHeader, Skeleton, EmptyState } from '@/components/ui/misc';
import { CurrencyBadge, currencyScopeHint } from '@/components/finance/currency-badge';
import { TransferModal } from '@/components/finance/transfer-modal';
import { IconPicker, ColorPicker } from '@/components/finance/pickers';
import { financeIcon } from '@/components/finance/icons';
import { api, ApiError } from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { useMoney } from '@/lib/amount-visibility';
import { useCurrencyView } from '@/lib/currency-view-context';
import { useConfirm } from '@/components/ui/confirm-dialog';
import type { Account, AccountType, Transaction } from '@/lib/types';

const TYPES: AccountType[] = ['CASH', 'BANK', 'MOBILE_MONEY', 'CARD', 'OTHER'];
const typeLabel = (t: AccountType) => t.replace('_', ' ').toLowerCase().replace(/^\w/, (c) => c.toUpperCase());

/** Mini SVG sparkline showing last 7 data points */
function Sparkline({ points, color }: { points: number[]; color: string }) {
  if (points.length < 2) return null;
  const min = Math.min(...points);
  const max = Math.max(...points);
  const range = max - min || 1;
  const w = 80;
  const h = 32;
  const pad = 2;
  const coords = points.map((v, i) => ({
    x: pad + (i / (points.length - 1)) * (w - pad * 2),
    y: h - pad - ((v - min) / range) * (h - pad * 2),
  }));
  const d = coords.map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' ');
  const areaD = `${d} L${coords[coords.length - 1]!.x.toFixed(1)},${h} L${coords[0]!.x.toFixed(1)},${h} Z`;

  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} className="overflow-visible">
      <defs>
        <linearGradient id={`grad-${color.replace('#', '')}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.3" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={areaD} fill={`url(#grad-${color.replace('#', '')})`} />
      <path d={d} fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** Fetch last 14 days of transactions for a given account and compute daily running balance */
function useAccountSparkline(accountId: string, openingBalance: string) {
  const today = new Date();
  const from = new Date(today.getTime() - 13 * 86_400_000).toISOString().slice(0, 10);
  const to = today.toISOString().slice(0, 10);

  const { data } = useSWR<{ items: Transaction[] }>(
    `/transactions?accountId=${accountId}&from=${from}&to=${to}&pageSize=200`,
  );

  const points = useMemo(() => {
    if (!data) return [];
    // Build day buckets for last 14 days
    const days: Record<string, number> = {};
    for (let i = 0; i < 14; i++) {
      const d = new Date(today.getTime() - (13 - i) * 86_400_000).toISOString().slice(0, 10);
      days[d] = 0;
    }
    for (const tx of data.items) {
      const day = tx.date.slice(0, 10);
      if (day in days) {
        if (tx.kind === 'INCOME') days[day]! += Number(tx.amount);
        else if (tx.kind === 'EXPENSE') days[day]! -= Number(tx.amount);
      }
    }
    // Running balance from opening
    let balance = Number(openingBalance);
    return Object.values(days).map((delta) => { balance += delta; return balance; });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data, openingBalance]);

  return points;
}

export default function AccountsPage() {
  const router = useRouter();
  const { user } = useAuth();
  const confirm = useConfirm();
  const { activeCurrency } = useCurrencyView();
  const { money } = useMoney();
  const currency = user?.currency ?? 'ETB';
  const { data, mutate } = useSWR<{ items: Account[] }>('/accounts');
  const [formOpen, setFormOpen] = useState(false);
  const [transferOpen, setTransferOpen] = useState(false);
  const [editing, setEditing] = useState<Account | null>(null);

  const accounts = data?.items ?? [];
  const activeAccounts = accounts.filter((a) => !a.archived && a.currency === activeCurrency);

  // `balance` is available money; `realBalance` is what is physically there.
  const totals = useMemo(
    () => ({
      available: activeAccounts.reduce((s, a) => s + Number(a.balance), 0),
      real: activeAccounts.reduce((s, a) => s + Number(a.realBalance), 0),
      locked: activeAccounts.reduce((s, a) => s + Number(a.lockedAmount), 0),
    }),
    [activeAccounts],
  );

  async function remove(account: Account) {
    const ok = await confirm({
      title: 'Delete account?',
      description: `"${account.name}" will be removed permanently.`,
      confirmLabel: 'Delete',
      tone: 'danger',
    });
    if (!ok) return;
    try {
      await api.del(`/accounts/${account.id}`);
      toast.success('Account deleted');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to delete');
    }
  }

  function goToTransactions(accountId: string) {
    router.push(`/transactions?accountId=${accountId}`);
  }

  return (
    <div>
      <PageHeader
        title="Accounts"
        description={currencyScopeHint(activeCurrency)}
        badge={<CurrencyBadge />}
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
          {Array.from({ length: 3 }).map((_, i) => <Skeleton key={i} className="h-40" />)}
        </div>
      ) : accounts.length === 0 ? (
        <EmptyState title="No accounts" description="Add your first wallet to start tracking." />
      ) : (
        <>
          <Card className="mb-4">
            <CardContent className="p-5">
              <span className="text-sm text-muted">Available to spend · {activeCurrency}</span>
              <p className="mt-1 text-2xl font-bold tabular-nums">{money(totals.available)}</p>
              {totals.locked > 0 && (
                <p className="mt-1.5 text-xs text-muted">
                  {money(totals.real)} actually in your accounts ·{' '}
                  <Link href="/budgets" className="font-medium text-primary hover:underline">
                    {money(totals.locked)} set aside in budget plans
                  </Link>
                </p>
              )}
            </CardContent>
          </Card>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {accounts.filter((a) => a.currency === activeCurrency).map((a) => (
              <AccountCard
                key={a.id}
                account={a}
                onEdit={() => { setEditing(a); setFormOpen(true); }}
                onDelete={() => remove(a)}
                onClick={() => goToTransactions(a.id)}
              />
            ))}
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

function AccountCard({
  account,
  onEdit,
  onDelete,
  onClick,
}: {
  account: Account;
  onEdit: () => void;
  onDelete: () => void;
  onClick: () => void;
}) {
  const { money } = useMoney(account.currency);
  const sparkPoints = useAccountSparkline(account.id, account.openingBalance);
  const Icon = financeIcon(account.icon);
  const color = account.color ?? '#64748b';

  return (
    <Card
      className={`${account.archived ? 'opacity-60' : ''} cursor-pointer hover:shadow-lg transition-shadow group`}
      onClick={onClick}
    >
      <CardContent className="p-5">
        <div className="flex items-start justify-between">
          <span
            className="flex h-10 w-10 items-center justify-center rounded-lg"
            style={{ backgroundColor: `${color}22`, color }}
          >
            <Icon className="h-5 w-5" />
          </span>
          <div className="flex gap-1" onClick={(e) => e.stopPropagation()}>
            <button
              onClick={onEdit}
              className="rounded-md px-2 py-1 text-xs text-muted hover:bg-surface-muted"
            >
              Edit
            </button>
            <button
              onClick={onDelete}
              className="rounded-md p-1 text-muted hover:bg-surface-muted hover:text-danger"
              aria-label="Delete"
            >
              <Trash2 className="h-3.5 w-3.5" />
            </button>
          </div>
        </div>
        <p className="mt-3 flex items-center gap-2 font-medium">
          {account.name}
          {account.isDefault && <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] text-primary">default</span>}
          {account.archived && <span className="rounded-full bg-surface-muted px-2 py-0.5 text-[10px] text-muted">archived</span>}
        </p>
        <p className="text-xs text-muted">{typeLabel(account.type)} · {account.currency}</p>
        <p className="mt-2 text-xl font-bold tabular-nums">{money(account.balance)}</p>
        {Number(account.lockedAmount) > 0 ? (
          <p className="mt-0.5 text-[11px] text-muted">
            available · {money(account.realBalance)} real, {money(account.lockedAmount)} in plans
          </p>
        ) : (
          <p className="mt-0.5 text-[11px] text-muted">available</p>
        )}

        {/* Mini sparkline */}
        {sparkPoints.length >= 2 && (
          <div className="mt-3 flex items-end justify-between gap-2">
            <p className="text-[10px] text-muted">14-day trend</p>
            <Sparkline points={sparkPoints} color={color} />
          </div>
        )}
        {sparkPoints.length >= 2 && (
          <p className="mt-1 text-right text-[10px] text-primary opacity-0 group-hover:opacity-100 transition-opacity">
            View transactions →
          </p>
        )}
      </CardContent>
    </Card>
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
