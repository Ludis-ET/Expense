'use client';

import { useEffect, useMemo, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import {
  ArrowDownLeft,
  ArrowUpRight,
  CalendarClock,
  HandCoins,
  Plus,
  Sparkles,
  Users,
} from 'lucide-react';
import { PageHeader, Skeleton, EmptyState } from '@/components/ui/misc';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select, Textarea, DateInput } from '@/components/ui/input';
import { TabEntryCard, PersonTabCard } from '@/components/finance/tab-widget';
import { api, ApiError } from '@/lib/api';
import { useMoney } from '@/lib/amount-visibility';
import { useConfirm } from '@/components/ui/confirm-dialog';
import { CurrencyBadge, currencyScopeHint } from '@/components/finance/currency-badge';
import { useCurrencyView } from '@/lib/currency-view-context';
import { cn } from '@/lib/utils';
import type { Account, Category, LedgerEntry, LedgerKind, LedgerPersonGroup, LedgerSummary } from '@/lib/types';

type TabFilter = 'all' | LedgerKind;
type ViewMode = 'entries' | 'people';

const filters: { id: TabFilter; label: string; icon: typeof HandCoins }[] = [
  { id: 'all', label: 'All open', icon: HandCoins },
  { id: 'LENT', label: 'They owe me', icon: ArrowDownLeft },
  { id: 'BORROWED', label: 'I owe', icon: ArrowUpRight },
  { id: 'EXPECTED_IN', label: 'Incoming', icon: Sparkles },
  { id: 'EXPECTED_OUT', label: 'Outgoing', icon: CalendarClock },
];

export default function TabPage() {
  const confirm = useConfirm();
  const { activeCurrency } = useCurrencyView();
  const { money } = useMoney();
  const [filter, setFilter] = useState<TabFilter>('all');
  const [view, setView] = useState<ViewMode>('entries');
  const [formOpen, setFormOpen] = useState(false);
  const [paying, setPaying] = useState<LedgerEntry | null>(null);
  const [editing, setEditing] = useState<LedgerEntry | null>(null);

  const query = filter === 'all'
    ? `/ledger?status=open&currency=${encodeURIComponent(activeCurrency)}`
    : `/ledger?status=open&kind=${filter}&currency=${encodeURIComponent(activeCurrency)}`;
  const { data: list, mutate: mutateList } = useSWR<{ items: LedgerEntry[] }>(view === 'entries' ? query : null);
  const { data: people, mutate: mutatePeople } = useSWR<{ items: LedgerPersonGroup[] }>(
    view === 'people' ? `/ledger/people?currency=${encodeURIComponent(activeCurrency)}` : null,
  );
  const { data: summary, mutate: mutateSummary } = useSWR<LedgerSummary>(
    `/ledger/summary?currency=${encodeURIComponent(activeCurrency)}`,
  );

  const refresh = () => {
    void mutateList();
    void mutatePeople();
    void mutateSummary();
  };

  async function removeEntry(entry: LedgerEntry) {
    const ok = await confirm({
      title: 'Remove tab entry?',
      description: `Remove the tab with ${entry.counterparty}? This cannot be undone.`,
      confirmLabel: 'Remove',
      tone: 'danger',
    });
    if (!ok) return;
    try {
      await api.del(`/ledger/${entry.id}`);
      toast.success('Removed');
      refresh();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  const settledHint = useMemo(
    () => (view === 'entries' && list?.items.length === 0 ? 'Nothing open - you\'re all square.' : undefined),
    [list, view],
  );

  const forecastNet = summary?.forecast ? Number(summary.forecast.netIfOnTime) : 0;

  return (
    <div className="animate-in space-y-6">
      <PageHeader
        title="Money Tab"
        description={currencyScopeHint(activeCurrency)}
        badge={<CurrencyBadge />}
        action={
          <Button size="sm" className="min-h-10" onClick={() => { setEditing(null); setFormOpen(true); }}>
            <Plus className="h-4 w-4" /> New entry
          </Button>
        }
      />

      {!summary ? (
        <Skeleton className="h-28 rounded-2xl" />
      ) : (
        <>
          {summary.forecast && (
            <div className="card flex flex-col gap-2 border-primary/20 bg-primary/5 px-4 py-4 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between sm:px-5">
              <div>
                <p className="text-xs font-medium uppercase tracking-wide text-muted">Cash-flow forecast · {summary.forecast.month}</p>
                <p className="mt-1 text-sm text-muted">If everything due this month settles on time · {activeCurrency}</p>
              </div>
              <p className={cn('text-2xl font-bold tabular-nums', forecastNet >= 0 ? 'text-emerald-600 dark:text-emerald-400' : 'text-amber-600 dark:text-amber-400')}>
                {forecastNet >= 0 ? '+' : ''}{money(forecastNet)}
              </p>
            </div>
          )}
          <div className="grid grid-cols-2 gap-2 sm:gap-3 lg:grid-cols-5">
            <StatTile label="Net position" value={money(summary.netPosition)} hint={`${activeCurrency} open tabs`} />
            <StatTile label="Owed to you" value={money(summary.receivable)} tone="emerald" />
            <StatTile label="Incoming" value={money(summary.expectedIn)} tone="sky" />
            <StatTile label="You owe" value={money(summary.payable)} tone="amber" />
            <StatTile label="Outgoing" value={money(summary.expectedOut)} tone="violet" className="col-span-2 lg:col-span-1" />
          </div>
        </>
      )}

      <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center">
        <div className="flex w-full gap-1 overflow-x-auto rounded-xl border border-border p-1 sm:w-auto">
          {(['entries', 'people'] as ViewMode[]).map((v) => (
            <button
              key={v}
              type="button"
              onClick={() => setView(v)}
              className={cn(
                'flex min-h-10 flex-1 items-center justify-center gap-1.5 rounded-lg px-3.5 py-1.5 text-xs font-medium capitalize sm:flex-none',
                view === v ? 'bg-primary text-primary-foreground' : 'text-muted hover:text-foreground',
              )}
            >
              {v === 'people' && <Users className="h-3.5 w-3.5" />}
              {v === 'entries' ? 'By entry' : 'By person'}
            </button>
          ))}
        </div>
        {view === 'entries' && (
          <div className="flex gap-1 overflow-x-auto rounded-xl border border-border p-1 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
            {filters.map((f) => (
              <button
                key={f.id}
                type="button"
                onClick={() => setFilter(f.id)}
                className={cn(
                  'flex min-h-10 shrink-0 items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition-all',
                  filter === f.id ? 'bg-surface-muted text-foreground shadow-sm' : 'text-muted hover:text-foreground',
                )}
              >
                <f.icon className="h-3.5 w-3.5" />
                {f.label}
              </button>
            ))}
          </div>
        )}
      </div>

      {view === 'people' ? (
        !people ? (
          <div className="grid gap-4">{Array.from({ length: 2 }).map((_, i) => <Skeleton key={i} className="h-44" />)}</div>
        ) : people.items.length === 0 ? (
          <EmptyState icon={<Users className="h-5 w-5" />} title="No open tabs with anyone" action={<Button onClick={() => setFormOpen(true)}>Add entry</Button>} />
        ) : (
          <div className="grid gap-4">
            {people.items.map((group) => (
              <PersonTabCard
                key={group.counterparty}
                group={group}
                money={money}
                onRecord={setPaying}
                onEdit={(e) => { setEditing(e); setFormOpen(true); }}
                onRemove={removeEntry}
              />
            ))}
          </div>
        )
      ) : !list ? (
        <div className="grid gap-4 sm:grid-cols-2">{Array.from({ length: 2 }).map((_, i) => <Skeleton key={i} className="h-44" />)}</div>
      ) : list.items.length === 0 ? (
        <EmptyState
          icon={<HandCoins className="h-5 w-5" />}
          title="Tab is clear"
          description={settledHint ?? 'Track money between you and other people.'}
          action={<Button onClick={() => setFormOpen(true)}>Add first entry</Button>}
        />
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {list.items.map((entry) => (
            <TabEntryCard
              key={entry.id}
              entry={entry}
              money={money}
              onRecord={() => setPaying(entry)}
              onEdit={() => { setEditing(entry); setFormOpen(true); }}
              onRemove={() => removeEntry(entry)}
            />
          ))}
        </div>
      )}

      <EntryForm
        open={formOpen}
        editing={editing}
        onClose={() => { setFormOpen(false); setEditing(null); }}
        onSaved={refresh}
      />
      <PaymentModal entry={paying} onClose={() => setPaying(null)} onSaved={refresh} />
    </div>
  );
}

function StatTile({
  label,
  value,
  hint,
  tone,
  className,
}: {
  label: string;
  value: string;
  hint?: string;
  tone?: 'emerald' | 'sky' | 'amber' | 'violet';
  className?: string;
}) {
  const toneClass =
    tone === 'emerald'
      ? 'text-emerald-600 dark:text-emerald-400'
      : tone === 'sky'
        ? 'text-sky-600 dark:text-sky-400'
        : tone === 'amber'
          ? 'text-amber-600 dark:text-amber-400'
          : tone === 'violet'
            ? 'text-violet-600 dark:text-violet-400'
            : '';
  return (
    <div className={cn('card p-3 sm:p-4', className)}>
      <p className="text-xs font-medium text-muted">{label}</p>
      <p className={cn('mt-1 text-lg font-bold tabular-nums sm:text-xl', toneClass)}>{value}</p>
      {hint && <p className="mt-0.5 text-[10px] text-muted">{hint}</p>}
    </div>
  );
}

function EntryForm({
  open,
  editing,
  onClose,
  onSaved,
}: {
  open: boolean;
  editing: LedgerEntry | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { activeCurrency } = useCurrencyView();
  const [kind, setKind] = useState<LedgerKind>('LENT');
  const [counterparty, setCounterparty] = useState('');
  const [title, setTitle] = useState('');
  const [totalAmount, setTotalAmount] = useState('');
  const [dueDate, setDueDate] = useState('');
  const [note, setNote] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [recordMovement, setRecordMovement] = useState(false);
  const [sourceAccountId, setSourceAccountId] = useState('');
  const [saving, setSaving] = useState(false);

  const { data: accounts } = useSWR<{ items: Account[] }>('/accounts');
  const { data: incomeCats } = useSWR<{ items: Category[] }>('/categories?kind=INCOME');
  const { data: expenseCats } = useSWR<{ items: Category[] }>('/categories?kind=EXPENSE');

  const currencyAccounts = (accounts?.items ?? []).filter(
    (a) => !a.archived && a.currency === activeCurrency,
  );

  useEffect(() => {
    if (!open) return;
    if (editing) {
      setKind(editing.kind);
      setCounterparty(editing.counterparty);
      setTitle(editing.title ?? '');
      setTotalAmount(String(Number(editing.totalAmount)));
      setDueDate(editing.dueDate ? editing.dueDate.slice(0, 10) : '');
      setNote(editing.note ?? '');
      setCategoryId(editing.category?.id ?? '');
      setRecordMovement(false);
      setSourceAccountId('');
    } else {
      setKind('LENT');
      setCounterparty('');
      setTitle('');
      setTotalAmount('');
      setDueDate('');
      setNote('');
      setCategoryId('');
      setRecordMovement(false);
      setSourceAccountId('');
    }
  }, [open, editing]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    const payload = {
      counterparty,
      title: title || undefined,
      totalAmount: Number(totalAmount),
      currency: activeCurrency,
      dueDate: dueDate || undefined,
      note: note || undefined,
      categoryId:
        kind === 'EXPECTED_IN' || kind === 'EXPECTED_OUT' ? categoryId || undefined : undefined,
      ...(editing
        ? {}
        : {
            kind,
            recordMovement,
            sourceAccountId: recordMovement ? sourceAccountId : undefined,
          }),
    };
    try {
      if (editing) await api.put(`/ledger/${editing.id}`, payload);
      else await api.post('/ledger', payload);
      toast.success(editing ? 'Updated' : 'Added to your tab');
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setSaving(false);
    }
  }

  const kindHelp =
    kind === 'LENT'
      ? 'Money you gave someone - they still owe you.'
      : kind === 'BORROWED'
        ? 'Money you borrowed - you still need to pay back.'
        : kind === 'EXPECTED_IN'
          ? 'Payment you expect once - not on a recurring schedule.'
          : 'One-off bill you know is coming (school fee, repair quote…) - not recurring.';

  return (
    <Modal open={open} onClose={onClose} title={editing ? 'Edit tab entry' : 'New tab entry'} description={kindHelp}>
      <form onSubmit={submit} className="space-y-4">
        {!editing && (
          <Field label="Type">
            <Select value={kind} onChange={(e) => setKind(e.target.value as LedgerKind)}>
              <option value="LENT">I lent money (they owe me)</option>
              <option value="BORROWED">I borrowed (I owe them)</option>
              <option value="EXPECTED_IN">Incoming payment (one-off)</option>
              <option value="EXPECTED_OUT">Outgoing bill (one-off)</option>
            </Select>
          </Field>
        )}
        <Field label="Person or source">
          <Input required value={counterparty} onChange={(e) => setCounterparty(e.target.value)} placeholder="Abe, Client Co., Mom…" />
        </Field>
        <Field label="Label (optional)">
          <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Phone loan, Invoice #4…" />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="Amount">
            <Input type="number" step="0.01" min="0" required value={totalAmount} onChange={(e) => setTotalAmount(e.target.value)} />
          </Field>
          <Field label="Expected by">
            <DateInput value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          </Field>
        </div>
        {(kind === 'EXPECTED_IN' || kind === 'EXPECTED_OUT') && (
          <Field label={kind === 'EXPECTED_IN' ? 'Income category' : 'Expense category'}>
            <Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
              <option value="">Pick when {kind === 'EXPECTED_IN' ? 'received' : 'paid'}…</option>
              {(kind === 'EXPECTED_IN' ? incomeCats : expenseCats)?.items.filter((c) => !c.archived).map((c) => (
                <option key={c.id} value={c.id}>{c.name}</option>
              ))}
            </Select>
          </Field>
        )}
        {!editing && kind !== 'EXPECTED_IN' && kind !== 'EXPECTED_OUT' && (
          <>
            <label className="flex items-start gap-2 text-sm">
              <input
                type="checkbox"
                className="mt-1"
                checked={recordMovement}
                onChange={(e) => setRecordMovement(e.target.checked)}
              />
              <span>
                <span className="font-medium">Also record in my accounts</span>
                <span className="block text-xs text-muted">
                  {kind === 'LENT' ? 'Logs cash leaving your wallet now.' : 'Logs cash you received when borrowing.'}
                </span>
              </span>
            </label>
            {recordMovement && (
              <Field label="Account">
                <Select required value={sourceAccountId} onChange={(e) => setSourceAccountId(e.target.value)}>
                  <option value="">Select account…</option>
                  {currencyAccounts.map((a) => (
                    <option key={a.id} value={a.id}>{a.name}</option>
                  ))}
                </Select>
              </Field>
            )}
          </>
        )}
        <Field label="Note">
          <Textarea rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Context you'll forget in 2 weeks…" />
        </Field>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={saving}>{editing ? 'Save' : 'Add to tab'}</Button>
        </div>
      </form>
    </Modal>
  );
}

function PaymentModal({
  entry,
  onClose,
  onSaved,
}: {
  entry: LedgerEntry | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [amount, setAmount] = useState('');
  const [date, setDate] = useState('');
  const [note, setNote] = useState('');
  const [accountId, setAccountId] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [recordTransaction, setRecordTransaction] = useState(true);
  const [saving, setSaving] = useState(false);

  const { data: accounts } = useSWR<{ items: Account[] }>('/accounts');
  const isExpense = entry?.kind === 'BORROWED' || entry?.kind === 'EXPECTED_OUT';
  const incomeCats = useSWR<{ items: Category[] }>(!isExpense && entry ? '/categories?kind=INCOME' : null);
  const expenseCats = useSWR<{ items: Category[] }>(isExpense && entry ? '/categories?kind=EXPENSE' : null);
  const categories = isExpense ? expenseCats.data : incomeCats.data;

  useEffect(() => {
    if (!entry) return;
    setAmount(String(Number(entry.remaining)));
    setDate(new Date().toISOString().slice(0, 10));
    setNote('');
    setAccountId('');
    setCategoryId(entry.category?.id ?? '');
    setRecordTransaction(true);
  }, [entry]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!entry) return;
    setSaving(true);
    try {
      await api.post(`/ledger/${entry.id}/payments`, {
        amount: Number(amount),
        date: date || undefined,
        note: note || undefined,
        accountId: recordTransaction ? accountId || undefined : undefined,
        categoryId: categoryId || undefined,
        recordTransaction,
      });
      toast.success(
        entry.kind === 'EXPECTED_IN'
          ? 'Marked as received'
          : entry.kind === 'EXPECTED_OUT'
            ? 'Marked as paid'
            : 'Payment recorded',
      );
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setSaving(false);
    }
  }

  const title =
    entry?.kind === 'EXPECTED_IN'
      ? `Received from ${entry.counterparty}`
      : entry?.kind === 'EXPECTED_OUT'
        ? `Pay ${entry.counterparty}`
        : entry?.kind === 'LENT'
          ? `Repayment from ${entry?.counterparty}`
          : `Pay ${entry?.counterparty}`;

  return (
    <Modal open={!!entry} onClose={onClose} title={title ?? ''}>
      <form onSubmit={submit} className="space-y-4">
        <Field label="Amount">
          <Input type="number" step="0.01" min="0" required value={amount} onChange={(e) => setAmount(e.target.value)} />
        </Field>
        <Field label="Date">
          <DateInput value={date} onChange={(e) => setDate(e.target.value)} />
        </Field>
        <label className="flex items-start gap-2 text-sm">
          <input type="checkbox" className="mt-1" checked={recordTransaction} onChange={(e) => setRecordTransaction(e.target.checked)} />
          <span>
            <span className="font-medium">Update my account balance</span>
            <span className="block text-xs text-muted">Creates a matching transaction in your ledger.</span>
          </span>
        </label>
        {recordTransaction && (
          <>
            <Field label="Account">
              <Select required value={accountId} onChange={(e) => setAccountId(e.target.value)}>
                <option value="">Select account…</option>
                {(accounts?.items ?? []).filter((a) => !a.archived).map((a) => (
                  <option key={a.id} value={a.id}>{a.name}</option>
                ))}
              </Select>
            </Field>
            <Field label="Category">
              <Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
                <option value="">Auto-pick</option>
                {(categories?.items ?? []).filter((c) => !c.archived).map((c) => (
                  <option key={c.id} value={c.id}>{c.name}</option>
                ))}
              </Select>
            </Field>
          </>
        )}
        <Field label="Note">
          <Input value={note} onChange={(e) => setNote(e.target.value)} />
        </Field>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={saving}>Save</Button>
        </div>
      </form>
    </Modal>
  );
}
