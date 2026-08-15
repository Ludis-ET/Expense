'use client';

import { useEffect, useMemo, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { ArrowRight, Sparkles, TriangleAlert, Wallet } from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select, Textarea, DateInput } from '@/components/ui/input';
import { financeIcon } from './icons';
import { api, ApiError } from '@/lib/api';
import { useOffline } from '@/lib/offline/offline-context';
import { newId } from '@/lib/offline/outbox';
import { cn } from '@/lib/utils';
import { todayInputValue } from '@/lib/date-range';
import type {
  Account,
  BudgetSourcesResponse,
  Category,
  SpendCover,
  Transaction,
  TxKind,
} from '@/lib/types';

/**
 * The "pay from" dropdown mixes plain accounts with budget plans that still
 * hold money. A plan value is prefixed so the two namespaces can't collide.
 */
const PLAN_PREFIX = 'plan:';

/**
 * "No plan" has one id everywhere now. The server turns it into a transaction
 * with no plan at all - the single representation of unplanned spending, rather
 * than an envelope that could not be funded and carried a negative balance.
 */
const UNPLANNED_ID = 'unplanned';

/** Prefixes for the cover picker, which mixes plans and wallets. */
const COVER_PLAN = 'cover-plan:';
const COVER_ACCOUNT = 'cover-account:';

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
  const { data: accountsData, isLoading: accountsLoading } = useSWR<{ items: Account[] }>(open ? '/accounts' : null);
  const { data: categoriesData } = useSWR<{ items: Category[] }>(open ? '/categories' : null);
  const { data: plansData, isLoading: plansLoading } = useSWR<BudgetSourcesResponse>(open ? '/budgets/sources' : null);
  const { saveTransaction, updateTransaction } = useOffline();

  const [kind, setKind] = useState<Exclude<TxKind, 'TRANSFER'>>('EXPENSE');
  const [amount, setAmount] = useState('');
  /**
   * For an expense this is always `plan:<id>` - Unplanned included, so the
   * question is always "which plan", never "plan or account". For income it is
   * a plain account id, since plans only ever pay out.
   */
  const [source, setSource] = useState('');
  /** Which account the money really leaves. Free choice, for any plan. */
  const [drawFromId, setDrawFromId] = useState('');
  /**
   * Which funder's reservation to free. Only asked for when a plan holds money
   * in more than one wallet - with a single one there is nothing to choose.
   */
  const [releaseFromId, setReleaseFromId] = useState('');
  /** Where the shortfall comes from when the plan cannot cover this on its own. */
  const [cover, setCover] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [date, setDate] = useState(todayInputValue());
  const [payee, setPayee] = useState('');
  const [note, setNote] = useState('');
  const [tags, setTags] = useState('');
  const [saving, setSaving] = useState(false);
  const [suggesting, setSuggesting] = useState(false);

  const accounts = useMemo(
    () => accountsData?.items.filter((a) => !a.archived) ?? [],
    [accountsData?.items],
  );
  const plans = useMemo(
    () => (kind === 'EXPENSE' ? (plansData?.items ?? []) : []),
    [kind, plansData?.items],
  );
  const categories = (categoriesData?.items ?? []).filter((c) => !c.archived && c.kind === kind);

  const selectedPlan = source.startsWith(PLAN_PREFIX)
    ? plans.find((p) => p.id === source.slice(PLAN_PREFIX.length))
    : undefined;
  const isUnplanned = selectedPlan?.isUnplanned ?? false;

  const isPlanSource = source.startsWith(PLAN_PREFIX);
  const accountId = isPlanSource ? drawFromId : source;
  const drawAccount = accounts.find((a) => a.id === drawFromId);

  // Where the reservation is held. One wallet means nothing to choose.
  const planSources = useMemo(
    () => (selectedPlan && !isUnplanned ? selectedPlan.sources.filter((s) => s.account) : []),
    [selectedPlan, isUnplanned],
  );
  const multiSource = planSources.length > 1;
  const releaseSource = planSources.find((s) => s.account!.id === releaseFromId) ?? planSources[0];

  /**
   * How far past the plan this spend goes.
   *
   * Refusing an overspend outright reads as strict but teaches nothing - people
   * just record it as unplanned instead, which quietly ruins both numbers.
   * Naming where the money came from is the part worth knowing.
   */
  const planBalance =
    selectedPlan && !isUnplanned && selectedPlan.balance !== null
      ? Number(selectedPlan.balance)
      : null;
  const wanted = Number(amount) || 0;
  const shortfall = planBalance !== null && wanted > planBalance ? wanted - planBalance : 0;

  const coverPlans = useMemo(
    () =>
      plans.filter(
        (p) =>
          !p.isUnplanned &&
          p.id !== selectedPlan?.id &&
          p.balance !== null &&
          Number(p.balance) >= shortfall &&
          p.currency === selectedPlan?.currency,
      ),
    [plans, selectedPlan, shortfall],
  );
  const coverAccounts = useMemo(
    () =>
      accounts.filter(
        (a) => Number(a.balance) >= shortfall && a.currency === selectedPlan?.currency,
      ),
    [accounts, selectedPlan, shortfall],
  );

  // Seed the form when opening (either blank or from the editing target).
  useEffect(() => {
    if (!open) return;
    if (editing) {
      setKind(editing.kind === 'INCOME' ? 'INCOME' : 'EXPENSE');
      setAmount(String(Number(editing.amount)));
      setSource(
        editing.kind === 'INCOME'
          ? editing.accountId
          : `${PLAN_PREFIX}${editing.budgetId ?? UNPLANNED_ID}`,
      );
      setDrawFromId(editing.accountId);
      setReleaseFromId(editing.budgetSourceAccountId ?? '');
      setCategoryId(editing.categoryId ?? '');
      setDate(editing.date.slice(0, 10));
      setPayee(editing.payee ?? '');
      setNote(editing.note ?? '');
      setTags(editing.tags.join(', '));
    } else {
      setKind('EXPENSE');
      setAmount('');
      setCategoryId('');
      setDate(todayInputValue());
      setPayee('');
      setNote('');
      setTags('');
    }
    setCover('');
  }, [open, editing]);

  // An expense starts on Unplanned: the honest default, and the one that lets
  // you pick a wallet and move on.
  useEffect(() => {
    if (!open || kind !== 'EXPENSE') return;
    if (!source.startsWith(PLAN_PREFIX)) setSource(`${PLAN_PREFIX}${UNPLANNED_ID}`);
  }, [open, kind, source]);

  // Income has no plan to go through, so it names an account directly.
  useEffect(() => {
    if (kind !== 'INCOME' || accounts.length === 0) return;
    if (!accounts.some((a) => a.id === source)) {
      setSource((accounts.find((a) => a.isDefault) ?? accounts[0]!).id);
    }
  }, [kind, source, accounts]);

  // Keep the draw-from wallet valid. A funded plan starts on the wallet holding
  // its biggest share, because paying from where the money is set aside is the
  // ordinary case - it is just no longer the only one.
  useEffect(() => {
    if (!isPlanSource || accounts.length === 0) return;
    if (accounts.some((a) => a.id === drawFromId)) return;
    const funder = planSources[0]?.account?.id;
    const fallback = accounts.find((a) => a.isDefault) ?? accounts[0]!;
    setDrawFromId(funder && accounts.some((a) => a.id === funder) ? funder : fallback.id);
  }, [isPlanSource, accounts, drawFromId, planSources]);

  // Default the reservation source to the largest share.
  useEffect(() => {
    if (planSources.length === 0) {
      if (releaseFromId) setReleaseFromId('');
      return;
    }
    if (!planSources.some((s) => s.account!.id === releaseFromId)) {
      setReleaseFromId(planSources[0]!.account!.id);
    }
  }, [planSources, releaseFromId]);

  // A cover only makes sense while there is a shortfall to cover.
  useEffect(() => {
    if (shortfall <= 0 && cover) setCover('');
  }, [shortfall, cover]);

  /** Picking a plan that has a category pre-selects it, as promised. */
  function pickSource(value: string) {
    setSource(value);
    setCover('');
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

  function coverPayload(): SpendCover | undefined {
    if (shortfall <= 0 || !cover) return undefined;
    if (cover.startsWith(COVER_PLAN)) {
      return { from: 'BUDGET', budgetId: cover.slice(COVER_PLAN.length) };
    }
    return { from: 'ACCOUNT', accountId: cover.slice(COVER_ACCOUNT.length) };
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!source) return toast.error(kind === 'EXPENSE' ? 'Pick a plan' : 'Pick an account');
    if (!categoryId) return toast.error('Pick a category');
    if (isPlanSource && !drawFromId) return toast.error('Pick which wallet this comes out of');
    if (shortfall > 0 && !cover) {
      return toast.error(`Say where the extra ${shortfall.toFixed(2)} comes from.`);
    }
    // Paying from a wallet that holds no reservation for this plan spends its
    // own free money, so it must genuinely have it.
    if (
      drawAccount &&
      releaseSource?.account?.id !== drawAccount.id &&
      wanted > Number(drawAccount.balance)
    ) {
      return toast.error(
        `"${drawAccount.name}" only has ${Number(drawAccount.balance).toFixed(2)} ${drawAccount.currency} free.`,
      );
    }

    setSaving(true);
    const tagList = tags.split(',').map((t) => t.trim()).filter(Boolean);
    const planId = isPlanSource ? source.slice(PLAN_PREFIX.length) : null;
    const payload = {
      kind,
      amount: wanted,
      // A plan spend sends three things: the plan it draws down, the wallet the
      // cash leaves, and - when the plan holds money in several - which
      // reservation to free.
      ...(isPlanSource
        ? {
            budgetId: planId,
            accountId: drawFromId,
            ...(releaseSource ? { budgetSourceAccountId: releaseSource.account!.id } : {}),
            ...(coverPayload() ? { cover: coverPayload() } : {}),
          }
        : { accountId }),
      categoryId,
      date,
      payee: payee || undefined,
      note: note || undefined,
      tags: tagList,
    };

    // A local preview so the change appears instantly, even offline.
    const previewAccountId = accountId || editing?.accountId || '';
    const account = accounts.find((a) => a.id === previewAccountId);
    const category = categories.find((c) => c.id === categoryId);
    const realPlan = selectedPlan && !isUnplanned ? selectedPlan : null;
    const optimistic: Transaction = {
      id: editing ? editing.id : newId(),
      kind,
      amount: wanted.toFixed(2),
      currency: account?.currency ?? realPlan?.currency ?? 'ETB',
      date: `${date}T12:00:00.000Z`,
      accountId: previewAccountId,
      account: account ? { id: account.id, name: account.name, type: account.type } : undefined,
      categoryId,
      category: category ? { id: category.id, name: category.name, icon: category.icon, color: category.color } : null,
      budgetId: realPlan?.id ?? null,
      budget: realPlan
        ? {
            id: realPlan.id,
            name: realPlan.name,
            icon: realPlan.icon,
            color: realPlan.color,
            currency: realPlan.currency,
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

  const fronted =
    drawAccount && releaseSource?.account && drawAccount.id !== releaseSource.account.id;

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

        {kind === 'EXPENSE' ? (
          <Field
            label="Pay from"
            hint="every expense belongs to a plan; pick Unplanned if you did not set money aside"
          >
            <Select
              value={source}
              onChange={(e) => pickSource(e.target.value)}
              loading={open && plansLoading}
            >
              {plans.some((p) => !p.isUnplanned) && (
                <optgroup label="Budget plans">
                  {plans
                    .filter((p) => !p.isUnplanned)
                    .map((p) => (
                      <option key={p.id} value={`${PLAN_PREFIX}${p.id}`}>
                        {p.name} - {Number(p.balance ?? 0).toFixed(2)} {p.currency} left
                      </option>
                    ))}
                </optgroup>
              )}
              <optgroup label="Not set aside">
                <option value={`${PLAN_PREFIX}${UNPLANNED_ID}`}>Unplanned</option>
              </optgroup>
            </Select>
          </Field>
        ) : (
          <Field label="Deposit to">
            <Select
              value={source}
              onChange={(e) => setSource(e.target.value)}
              loading={open && accountsLoading}
            >
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name} - {Number(a.balance).toFixed(2)} {a.currency} available
                </option>
              ))}
            </Select>
          </Field>
        )}

        {isPlanSource && (
          <Field
            label="Take it out of"
            hint={
              isUnplanned
                ? 'Unplanned has no pot of its own. The money comes straight out of the wallet you pick, from whatever is left after your other plans.'
                : 'Any wallet, not just the one holding the plan’s money - you might set aside in one bank and pay with another.'
            }
          >
            <Select
              value={drawFromId}
              onChange={(e) => setDrawFromId(e.target.value)}
              loading={open && accountsLoading}
            >
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name} - {Number(a.balance).toFixed(2)} {a.currency} available
                </option>
              ))}
            </Select>
          </Field>
        )}

        {/* Whose reservation comes off. Only a question with several wallets. */}
        {multiSource && (
          <Field
            label="Free the money held in"
            hint="This plan holds money in more than one wallet. The cash leaves the wallet above; this is the reservation that gets released."
          >
            <Select value={releaseFromId} onChange={(e) => setReleaseFromId(e.target.value)}>
              {planSources.map((s) => (
                <option key={s.account!.id} value={s.account!.id}>
                  {s.account!.name} - {Number(s.available).toFixed(2)} {selectedPlan!.currency} held
                </option>
              ))}
            </Select>
          </Field>
        )}

        {/* The plan is short. Cover it rather than refusing outright. */}
        {shortfall > 0 && selectedPlan && (
          <div className="space-y-2 rounded-xl border border-amber-500/40 bg-amber-500/5 p-3">
            <p className="flex items-start gap-2 text-xs text-foreground">
              <TriangleAlert className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-600 dark:text-amber-400" />
              <span>
                <strong>{selectedPlan.name}</strong> holds{' '}
                {Number(selectedPlan.balance ?? 0).toFixed(2)} {selectedPlan.currency} - this is{' '}
                <strong>{shortfall.toFixed(2)}</strong> more. Where should the extra come from?
              </span>
            </p>
            <Select value={cover} onChange={(e) => setCover(e.target.value)}>
              <option value="">Choose where to cover it from…</option>
              {coverPlans.length > 0 && (
                <optgroup label="Move it from another plan">
                  {coverPlans.map((p) => (
                    <option key={p.id} value={`${COVER_PLAN}${p.id}`}>
                      {p.name} - {Number(p.balance ?? 0).toFixed(2)} {p.currency} held
                    </option>
                  ))}
                </optgroup>
              )}
              {coverAccounts.length > 0 && (
                <optgroup label="Use money that is not in any plan">
                  {coverAccounts.map((a) => (
                    <option key={a.id} value={`${COVER_ACCOUNT}${a.id}`}>
                      {a.name} - {Number(a.balance).toFixed(2)} {a.currency} free
                    </option>
                  ))}
                </optgroup>
              )}
            </Select>
            {cover && (
              <p className="text-[11px] leading-relaxed text-muted">
                {selectedPlan.name} will be raised to {(wanted).toFixed(2)} {selectedPlan.currency} to
                match. You will see the raise in the plan&apos;s history, and undoing this expense
                undoes it too.
              </p>
            )}
            {coverPlans.length === 0 && coverAccounts.length === 0 && (
              <p className="text-[11px] leading-relaxed text-muted">
                Nothing has {shortfall.toFixed(2)} {selectedPlan.currency} spare right now. Give money
                back from another plan first, or record this as Unplanned.
              </p>
            )}
          </div>
        )}

        {selectedPlan && !isUnplanned && shortfall <= 0 && (
          <p className="-mt-2 flex items-start gap-2 rounded-xl bg-primary/5 px-3 py-2 text-xs text-muted">
            <Wallet className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" />
            <span>
              Comes out of the money already set aside in{' '}
              <strong className="text-foreground">{selectedPlan.name}</strong>
              {releaseSource?.account && !multiSource && (
                <> · freeing the {Number(releaseSource.available).toFixed(2)} held in{' '}
                  {releaseSource.account.name}</>
              )}
              .
            </span>
          </p>
        )}

        {/*
          The wallet paying is not the wallet holding the plan's money. That is
          allowed, and it really does move spending power between them - so say
          so plainly rather than letting the balances shift unexplained.
        */}
        {fronted && (
          <p className="-mt-2 flex items-start gap-2 rounded-xl border border-border bg-surface-muted px-3 py-2 text-xs text-muted">
            <ArrowRight className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary" />
            <span>
              <strong className="text-foreground">{drawAccount!.name}</strong> is covering this for
              money held in <strong className="text-foreground">{releaseSource!.account!.name}</strong>
              . {drawAccount!.name} goes down by {wanted.toFixed(2)}, and the same amount frees up in{' '}
              {releaseSource!.account!.name}.
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
