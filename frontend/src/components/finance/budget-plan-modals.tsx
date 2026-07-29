'use client';

import { useEffect, useMemo, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { ArrowDownLeft, ArrowUpRight, Repeat, Zap } from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select, Textarea, DateInput } from '@/components/ui/input';
import { IconPicker, ColorPicker } from '@/components/finance/pickers';
import { api, ApiError } from '@/lib/api';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type {
  Account,
  BudgetDetail,
  BudgetKind,
  BudgetRow,
  Category,
  RecurrenceUnit,
} from '@/lib/types';

const UNITS: { value: RecurrenceUnit; one: string; many: string }[] = [
  { value: 'HOUR', one: 'hour', many: 'hours' },
  { value: 'DAY', one: 'day', many: 'days' },
  { value: 'WEEK', one: 'week', many: 'weeks' },
  { value: 'MONTH', one: 'month', many: 'months' },
  { value: 'QUARTER', one: 'quarter', many: 'quarters' },
  { value: 'YEAR', one: 'year', many: 'years' },
];

/** One-tap cadences that cover most real plans; anything else is hand-dialled. */
const PRESETS: { label: string; unit: RecurrenceUnit; interval: number }[] = [
  { label: 'Daily', unit: 'DAY', interval: 1 },
  { label: 'Weekly', unit: 'WEEK', interval: 1 },
  { label: 'Fortnightly', unit: 'WEEK', interval: 2 },
  { label: 'Monthly', unit: 'MONTH', interval: 1 },
  { label: 'Quarterly', unit: 'QUARTER', interval: 1 },
  { label: 'Yearly', unit: 'YEAR', interval: 1 },
];

const unitMeta = (u: RecurrenceUnit) => UNITS.find((o) => o.value === u) ?? UNITS[3]!;

/** "month" / "6 hours" - what one cycle is measured in. */
function nounFor(unit: RecurrenceUnit, interval: number): string {
  const m = unitMeta(unit);
  return interval === 1 ? m.one : `${interval} ${m.many}`;
}

/** "monthly" / "every 6 hours" - how the cadence reads in a sentence. */
function cadenceLabel(unit: RecurrenceUnit, interval: number): string {
  if (interval !== 1) return `every ${interval} ${unitMeta(unit).many}`;
  return (
    {
      HOUR: 'hourly',
      DAY: 'daily',
      WEEK: 'weekly',
      MONTH: 'monthly',
      QUARTER: 'quarterly',
      YEAR: 'yearly',
    } as const
  )[unit];
}

/** Create or edit a plan. Category is optional and only pre-selects on spend. */
export function BudgetPlanForm({
  open,
  editing,
  currency,
  onClose,
  onSaved,
}: {
  open: boolean;
  editing: BudgetRow | null;
  currency: string;
  onClose: () => void;
  onSaved: (plan: BudgetRow) => void;
}) {
  const { data: categoriesData } = useSWR<{ items: Category[] }>(
    open ? '/categories?kind=EXPENSE' : null,
  );

  const [name, setName] = useState('');
  const [kind, setKind] = useState<BudgetKind>('ONE_TIME');
  const [unit, setUnit] = useState<RecurrenceUnit>('MONTH');
  const [interval, setInterval] = useState('1');
  const [startsAt, setStartsAt] = useState('');
  const [plannedAmount, setPlannedAmount] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [icon, setIcon] = useState('wallet');
  const [color, setColor] = useState('#6366f1');
  const [note, setNote] = useState('');
  const [threshold, setThreshold] = useState('80');
  const [endDate, setEndDate] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setName(editing?.name ?? '');
    setKind(editing?.kind === 'RECURRING' ? 'RECURRING' : 'ONE_TIME');
    setUnit(editing?.recurrenceUnit ?? 'MONTH');
    setInterval(String(editing?.recurrenceInterval ?? 1));
    setStartsAt(
      editing?.startsAt ? editing.startsAt.slice(0, 10) : new Date().toISOString().slice(0, 10),
    );
    setPlannedAmount(editing ? String(Number(editing.plannedAmount)) : '');
    setCategoryId(editing?.categoryId ?? '');
    setIcon(editing?.icon ?? 'wallet');
    setColor(editing?.color ?? '#6366f1');
    setNote(editing?.note ?? '');
    setThreshold(String(editing?.alertThreshold ?? 80));
    setEndDate(editing?.endDate ? editing.endDate.slice(0, 10) : '');
  }, [open, editing]);

  const categories = (categoriesData?.items ?? []).filter((c) => !c.archived);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    const payload = {
      name,
      kind,
      recurrenceUnit: kind === 'RECURRING' ? unit : null,
      recurrenceInterval: Number(interval) || 1,
      startsAt: startsAt || undefined,
      plannedAmount: Number(plannedAmount),
      categoryId: categoryId || null,
      icon,
      color,
      note: note || null,
      alertThreshold: Number(threshold),
      endDate: endDate || null,
    };
    try {
      const saved = editing
        ? await api.put<BudgetRow>(`/budgets/${editing.id}`, payload)
        : await api.post<BudgetRow>('/budgets', { ...payload, currency });
      toast.success(editing ? 'Plan updated' : 'Plan created - now put money in it');
      onSaved(saved);
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={editing ? 'Edit plan' : 'New budget plan'}
      description="A plan starts empty. You fill it from your accounts, then spend only from it."
    >
      <form onSubmit={submit} className="space-y-4">
        <Field label="Plan name">
          <Input
            required
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Weekend food, New laptop, School fees…"
          />
        </Field>

        <div className="grid grid-cols-2 gap-2">
          {(
            [
              { value: 'ONE_TIME' as const, label: 'One-time', icon: Zap, blurb: 'Runs until the money is gone' },
              { value: 'RECURRING' as const, label: 'Recurring', icon: Repeat, blurb: 'Renews and carries leftovers' },
            ]
          ).map((k) => {
            const Icon = k.icon;
            return (
              <button
                key={k.value}
                type="button"
                onClick={() => setKind(k.value)}
                className={cn(
                  'flex flex-col gap-1 rounded-xl border p-3 text-left transition-colors',
                  kind === k.value
                    ? 'border-primary bg-primary/5'
                    : 'border-border hover:bg-surface-muted',
                )}
              >
                <span className="flex items-center gap-1.5 text-sm font-semibold">
                  <Icon className="h-4 w-4 text-primary" /> {k.label}
                </span>
                <span className="text-xs text-muted">{k.blurb}</span>
              </button>
            );
          })}
        </div>

        {kind === 'RECURRING' && (
          <div className="space-y-3 rounded-xl border border-border p-3">
            <div className="flex flex-wrap gap-1.5">
              {PRESETS.map((preset) => {
                const active = unit === preset.unit && Number(interval) === preset.interval;
                return (
                  <button
                    key={preset.label}
                    type="button"
                    onClick={() => {
                      setUnit(preset.unit);
                      setInterval(String(preset.interval));
                    }}
                    className={cn(
                      'rounded-lg px-2.5 py-1.5 text-xs font-medium transition-colors',
                      active
                        ? 'bg-primary text-primary-foreground'
                        : 'bg-surface-muted text-muted hover:text-foreground',
                    )}
                  >
                    {preset.label}
                  </button>
                );
              })}
            </div>

            <div className="flex items-end gap-2">
              <span className="pb-2.5 text-sm text-muted">Every</span>
              <div className="w-20">
                <Input
                  type="number"
                  min="1"
                  max="365"
                  value={interval}
                  onChange={(e) => setInterval(e.target.value)}
                  aria-label="Repeat interval"
                />
              </div>
              <div className="flex-1">
                <Select
                  value={unit}
                  onChange={(e) => setUnit(e.target.value as RecurrenceUnit)}
                  aria-label="Repeat unit"
                >
                  {UNITS.map((o) => (
                    <option key={o.value} value={o.value}>
                      {Number(interval) === 1 ? o.one : o.many}
                    </option>
                  ))}
                </Select>
              </div>
            </div>

            <p className="text-xs text-muted">
              Resets{' '}
              <strong className="text-foreground">
                {cadenceLabel(unit, Math.max(1, Number(interval) || 1))}
              </strong>
              , carrying anything left over into the next{' '}
              {nounFor(unit, Math.max(1, Number(interval) || 1))}.
            </p>
          </div>
        )}

        <div className="grid grid-cols-2 gap-3">
          <Field
            label={
              kind === 'RECURRING'
                ? `Plan to spend per ${nounFor(unit, Math.max(1, Number(interval) || 1))} (${currency})`
                : `Plan to spend (${currency})`
            }
            hint="Also the most you can put in"
          >
            <Input
              type="number"
              step="0.01"
              min="0"
              required
              value={plannedAmount}
              onChange={(e) => setPlannedAmount(e.target.value)}
              placeholder="0.00"
            />
          </Field>
          <Field
            label="Starts on"
            hint={kind === 'RECURRING' ? 'first cycle begins here' : 'spendable from this date'}
          >
            <DateInput
              value={startsAt}
              max={endDate || undefined}
              onChange={(e) => {
                const next = e.target.value;
                setStartsAt(next);
                if (next && endDate && next > endDate) setEndDate(next);
              }}
            />
          </Field>
        </div>

        <Field label="Category" hint="optional - pre-selected when you spend from this plan">
          <Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
            <option value="">No category</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </Select>
        </Field>

        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="Icon">
            <IconPicker value={icon} onChange={setIcon} />
          </Field>
          <Field label="Colour">
            <ColorPicker value={color} onChange={setColor} />
          </Field>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <Field label="Warn me at" hint="% of the filled pot spent">
            <Input
              type="number"
              min="1"
              max="100"
              value={threshold}
              onChange={(e) => setThreshold(e.target.value)}
            />
          </Field>
          {kind === 'RECURRING' && (
            <Field label="Stop after" hint="optional">
              <DateInput
                value={endDate}
                min={startsAt || undefined}
                clearable
                onClear={() => setEndDate('')}
                onChange={(e) => setEndDate(e.target.value)}
              />
            </Field>
          )}
        </div>

        <Field label="Note">
          <Textarea
            rows={2}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="What this plan is for…"
          />
        </Field>

        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            {editing ? 'Save plan' : 'Create plan'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}

/** Move money from an account into a plan's pot (or give it back). */
export function FundPlanModal({
  plan,
  mode,
  onClose,
  onSaved,
}: {
  plan: BudgetDetail | BudgetRow | null;
  mode: 'fund' | 'release';
  onClose: () => void;
  onSaved: (plan: BudgetDetail) => void;
}) {
  const { money } = useMoney();
  const { data: accountsData } = useSWR<{ items: Account[] }>(plan ? '/accounts' : null);
  const [accountId, setAccountId] = useState('');
  const [amount, setAmount] = useState('');
  const [note, setNote] = useState('');
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [saving, setSaving] = useState(false);

  const releasing = mode === 'release';

  // Filling draws on any account in the plan's currency; giving back can only
  // return money to an account that actually put some in.
  const options = useMemo(() => {
    if (!plan) return [];
    if (releasing) {
      const sources = 'sources' in plan ? plan.sources : [];
      return sources
        .filter((s) => s.account && Number(s.available) > 0)
        .map((s) => ({
          id: s.account!.id,
          name: s.account!.name,
          available: s.available,
        }));
    }
    return (accountsData?.items ?? [])
      .filter((a) => !a.archived && a.currency === plan.currency)
      .map((a) => ({ id: a.id, name: a.name, available: a.balance }));
  }, [plan, releasing, accountsData?.items]);

  const cap = releasing
    ? Number(plan?.balance ?? 0)
    : Math.min(
        Number(plan && 'fillable' in plan ? plan.fillable : 0),
        Number(options.find((o) => o.id === accountId)?.available ?? 0),
      );

  useEffect(() => {
    if (!plan) return;
    setAmount('');
    setNote('');
    setDate(new Date().toISOString().slice(0, 10));
  }, [plan, mode]);

  useEffect(() => {
    if (plan && !options.some((o) => o.id === accountId)) {
      setAccountId(options[0]?.id ?? '');
    }
  }, [plan, options, accountId]);

  if (!plan) return null;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!plan) return;
    if (!accountId) return toast.error('Pick an account');
    setSaving(true);
    try {
      const updated = await api.post<BudgetDetail>(
        `/budgets/${plan.id}/${releasing ? 'release' : 'fund'}`,
        { accountId, amount: Number(amount), date, note: note || null },
      );
      toast.success(releasing ? 'Money returned to the account' : 'Money set aside in the plan');
      onSaved(updated);
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={!!plan}
      onClose={onClose}
      title={releasing ? `Give back from "${plan.name}"` : `Put money in "${plan.name}"`}
      description={
        releasing
          ? 'Returns money to the account it came from and frees it to spend elsewhere.'
          : 'The cash stays in your account but stops counting as available until you spend it here.'
      }
    >
      <form onSubmit={submit} className="space-y-4">
        {options.length === 0 ? (
          <p className="rounded-xl bg-surface-muted/60 px-3 py-4 text-sm text-muted">
            {releasing
              ? 'This plan has no money to give back yet.'
              : `No ${plan.currency} account available.`}
          </p>
        ) : (
          <>
            <Field label={releasing ? 'Return to' : 'Take from'}>
              <Select value={accountId} onChange={(e) => setAccountId(e.target.value)}>
                {options.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.name} - {Number(o.available).toFixed(2)} {plan.currency}
                  </option>
                ))}
              </Select>
            </Field>

            <Field label={`Amount (${plan.currency})`}>
              <Input
                type="number"
                step="0.01"
                min="0"
                required
                autoFocus
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder={cap > 0 ? cap.toFixed(2) : '0.00'}
              />
            </Field>

            {cap > 0 && (
              <div className="flex flex-wrap gap-2">
                {[0.25, 0.5, 1].map((f) => (
                  <button
                    key={f}
                    type="button"
                    onClick={() => setAmount(String(Math.round(cap * f * 100) / 100))}
                    className="rounded-lg border border-border px-3 py-1 text-xs font-medium text-muted hover:bg-surface-muted"
                  >
                    {f === 1 ? (releasing ? 'All of it' : 'Fill it up') : `${f * 100}%`}
                  </button>
                ))}
              </div>
            )}

            <div className="grid grid-cols-2 gap-3">
              <Field label="Date">
                <DateInput maxToday value={date} onChange={(e) => setDate(e.target.value)} />
              </Field>
              <Field label="Note" hint="optional">
                <Input
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  placeholder="Payday top-up"
                />
              </Field>
            </div>

            {!releasing && 'fillable' in plan && (
              <p className="rounded-xl bg-surface-muted/60 px-3 py-2 text-xs text-muted">
                This plan accepts up to {money(plan.fillable)} more before it hits its planned{' '}
                {money(plan.plannedAmount)}.
              </p>
            )}
          </>
        )}

        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={saving} disabled={options.length === 0}>
            {releasing ? (
              <>
                <ArrowDownLeft className="h-4 w-4" /> Give back
              </>
            ) : (
              <>
                <ArrowUpRight className="h-4 w-4" /> Set aside
              </>
            )}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
