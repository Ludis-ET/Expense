'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import useSWR from 'swr';
import { toast } from 'sonner';
import {
  Check,
  ExternalLink,
  Link2Off,
  Pencil,
  PiggyBank,
  Repeat,
  Sparkles,
  Star,
  Trash2,
  Wallet,
  Zap,
} from 'lucide-react';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { Field, Input, Select, Textarea, DateInput } from '@/components/ui/input';
import { ColorPicker } from '@/components/finance/pickers';
import { WishEmojiPicker, DEFAULT_WISH_EMOJI } from '@/components/finance/wish-emoji';
import { api, ApiError } from '@/lib/api';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type {
  BudgetKind,
  Category,
  RecurrenceUnit,
  WishlistItem,
  WishlistStatus,
} from '@/lib/types';

export const PRIORITY_LABEL = ['', 'Must have', 'Soon', 'Nice', 'Someday', 'Dream'];

export const STATUS_META: Record<
  WishlistStatus,
  { label: string; chip: string }
> = {
  WANTING: { label: 'Wanting', chip: 'bg-sky-500/12 text-sky-600 dark:text-sky-400' },
  PLANNED: { label: 'Planned', chip: 'bg-violet-500/12 text-violet-600 dark:text-violet-400' },
  BOUGHT: { label: 'Bought', chip: 'bg-emerald-500/12 text-emerald-600 dark:text-emerald-400' },
  DROPPED: { label: 'Dropped', chip: 'bg-surface-muted text-muted' },
};

/** Create or edit a want: emoji, name, priority, link, note. Nothing else. */
export function WishForm({
  open,
  editing,
  onClose,
  onSaved,
}: {
  open: boolean;
  editing: WishlistItem | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState('');
  const [priority, setPriority] = useState('3');
  const [emoji, setEmoji] = useState(DEFAULT_WISH_EMOJI);
  const [note, setNote] = useState('');
  const [link, setLink] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setName(editing?.name ?? '');
    setPriority(String(editing?.priority ?? 3));
    setEmoji(editing?.emoji ?? DEFAULT_WISH_EMOJI);
    setNote(editing?.note ?? '');
    setLink(editing?.link ?? '');
  }, [open, editing]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    const payload = {
      name,
      priority: Number(priority),
      emoji,
      note: note || null,
      link: link || null,
    };
    try {
      if (editing) await api.put(`/wishlist/${editing.id}`, payload);
      else await api.post('/wishlist', payload);
      toast.success(editing ? 'Updated' : 'Added to your wishlist');
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={editing ? 'Edit want' : 'New want'}
      description="Park it here so it stops living only in your head. Money comes later."
    >
      <form onSubmit={submit} className="space-y-4">
        <div className="flex items-center gap-3">
          <span className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-surface-muted text-3xl">
            {emoji}
          </span>
          <div className="min-w-0 flex-1">
            <Field label="What do you want?">
              <Input
                required
                autoFocus
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Noise-cancelling headphones"
              />
            </Field>
          </div>
        </div>

        <Field label="Emoji">
          <WishEmojiPicker value={emoji} onChange={setEmoji} />
        </Field>

        <Field label="Priority">
          <Select value={priority} onChange={(e) => setPriority(e.target.value)}>
            {[1, 2, 3, 4, 5].map((p) => (
              <option key={p} value={p}>
                {PRIORITY_LABEL[p]}
              </option>
            ))}
          </Select>
        </Field>

        <Field label="Link" hint="optional">
          <Input
            type="url"
            value={link}
            onChange={(e) => setLink(e.target.value)}
            placeholder="https://…"
          />
        </Field>

        <Field label="Note">
          <Textarea
            rows={2}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Why you want it…"
          />
        </Field>

        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            {editing ? 'Save' : 'Add want'}
          </Button>
        </div>
      </form>
    </Modal>
  );
}

const UNITS: { value: RecurrenceUnit; one: string; many: string }[] = [
  { value: 'HOUR', one: 'hour', many: 'hours' },
  { value: 'DAY', one: 'day', many: 'days' },
  { value: 'WEEK', one: 'week', many: 'weeks' },
  { value: 'MONTH', one: 'month', many: 'months' },
  { value: 'QUARTER', one: 'quarter', many: 'quarters' },
  { value: 'YEAR', one: 'year', many: 'years' },
];

/**
 * Turn a want into a budget plan. This is the only place a want ever meets a
 * number: everything a plan needs that the want does not already know.
 */
export function PlanWishModal({
  wish,
  onClose,
  onPlanned,
}: {
  wish: WishlistItem | null;
  onClose: () => void;
  onPlanned: (planId: string) => void;
}) {
  const { data: categoriesData } = useSWR<{ items: Category[] }>(
    wish ? '/categories?kind=EXPENSE' : null,
  );

  const [name, setName] = useState('');
  const [plannedAmount, setPlannedAmount] = useState('');
  const [kind, setKind] = useState<Exclude<BudgetKind, 'UNPLANNED'>>('ONE_TIME');
  const [unit, setUnit] = useState<RecurrenceUnit>('MONTH');
  const [interval, setInterval] = useState('1');
  const [categoryId, setCategoryId] = useState('');
  const [color, setColor] = useState('#a855f7');
  const [startsAt, setStartsAt] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!wish) return;
    setName(wish.name);
    setPlannedAmount('');
    setKind('ONE_TIME');
    setUnit('MONTH');
    setInterval('1');
    setCategoryId('');
    setColor('#a855f7');
    setStartsAt(new Date().toISOString().slice(0, 10));
  }, [wish]);

  if (!wish) return null;

  const categories = (categoriesData?.items ?? []).filter((c) => !c.archived);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!wish) return;
    setSaving(true);
    try {
      const res = await api.post<{ plan: { id: string } }>(`/wishlist/${wish.id}/plan`, {
        name,
        plannedAmount: Number(plannedAmount),
        kind,
        recurrenceUnit: kind === 'RECURRING' ? unit : null,
        recurrenceInterval: Number(interval) || 1,
        categoryId: categoryId || null,
        color,
        startsAt: startsAt || undefined,
      });
      toast.success(`"${wish.name}" now has a plan`);
      onPlanned(res.plan.id);
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={!!wish}
      onClose={onClose}
      title={`Plan "${wish.name}"`}
      description="Creates a budget plan you can fill a little at a time. The want stays on your list, linked to it."
    >
      <form onSubmit={submit} className="space-y-4">
        <div className="flex items-center gap-3 rounded-xl bg-surface-muted/60 p-3">
          <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-surface text-2xl">
            {wish.emoji || DEFAULT_WISH_EMOJI}
          </span>
          <p className="text-sm text-muted">
            <strong className="text-foreground">{wish.name}</strong> becomes a plan you fill from
            your accounts. Nothing is moved yet.
          </p>
        </div>

        <Field label="Plan name">
          <Input required value={name} onChange={(e) => setName(e.target.value)} />
        </Field>

        <div className="grid grid-cols-2 gap-2">
          {(
            [
              { value: 'ONE_TIME' as const, label: 'Save up once', icon: Zap, blurb: 'Fill it until you can buy' },
              { value: 'RECURRING' as const, label: 'Every period', icon: Repeat, blurb: 'A budget that renews' },
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
          <div className="flex items-end gap-2 rounded-xl border border-border p-3">
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
        )}

        <div className="grid grid-cols-2 gap-3">
          <Field label="How much" hint="the most the plan will hold">
            <Input
              type="number"
              step="0.01"
              min="0"
              required
              autoFocus
              value={plannedAmount}
              onChange={(e) => setPlannedAmount(e.target.value)}
              placeholder="0.00"
            />
          </Field>
          <Field label="Starts on">
            <DateInput value={startsAt} onChange={(e) => setStartsAt(e.target.value)} />
          </Field>
        </div>

        <Field label="Category" hint="optional, pre-selected when you spend from the plan">
          <Select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
            <option value="">No category</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </Select>
        </Field>

        <Field label="Colour">
          <ColorPicker value={color} onChange={setColor} />
        </Field>

        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            <PiggyBank className="h-4 w-4" /> Create the plan
          </Button>
        </div>
      </form>
    </Modal>
  );
}

/** Everything about one want, and every action you can take on it. */
export function WishDetailModal({
  wish,
  onClose,
  onEdit,
  onPlan,
  onChanged,
  onDelete,
}: {
  wish: WishlistItem | null;
  onClose: () => void;
  onEdit: (w: WishlistItem) => void;
  onPlan: (w: WishlistItem) => void;
  onChanged: () => void;
  onDelete: (w: WishlistItem) => void;
}) {
  const { money } = useMoney();
  const [busy, setBusy] = useState(false);

  if (!wish) return null;
  const meta = STATUS_META[wish.status];

  async function act(path: string, msg: string) {
    if (!wish) return;
    setBusy(true);
    try {
      await api.post(`/wishlist/${wish.id}/${path}`, {});
      toast.success(msg);
      onChanged();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setBusy(false);
    }
  }

  async function setStatus(status: WishlistStatus, msg: string) {
    if (!wish) return;
    setBusy(true);
    try {
      await api.put(`/wishlist/${wish.id}`, { status });
      toast.success(msg);
      onChanged();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open={!!wish} onClose={onClose} title="Want">
      <div className="space-y-5">
        <div className="flex items-start gap-4">
          <span className="flex h-16 w-16 shrink-0 items-center justify-center rounded-2xl bg-surface-muted text-4xl">
            {wish.emoji || DEFAULT_WISH_EMOJI}
          </span>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <h3 className="text-lg font-bold leading-snug">{wish.name}</h3>
              <span
                className={cn(
                  'rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide',
                  meta.chip,
                )}
              >
                {meta.label}
              </span>
            </div>
            <p className="mt-1 flex flex-wrap items-center gap-1 text-xs text-muted">
              <Star className="h-3 w-3 fill-amber-400 text-amber-400" />
              {PRIORITY_LABEL[wish.priority] ?? 'Someday'}
              <span>· added {new Date(wish.createdAt).toLocaleDateString()}</span>
            </p>
          </div>
        </div>

        {wish.note && (
          <p className="whitespace-pre-wrap rounded-xl bg-surface-muted/50 px-3 py-2.5 text-sm text-muted">
            {wish.note}
          </p>
        )}

        {wish.link && (
          <a
            href={wish.link}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:underline"
          >
            <ExternalLink className="h-3.5 w-3.5" /> Open link
          </a>
        )}

        {/* The plan, if this want has one. */}
        {wish.plan ? (
          <div className="rounded-xl border border-border p-3">
            <p className="mb-2 text-xs font-semibold uppercase tracking-widest text-muted">
              Saving through
            </p>
            <Link
              href={`/budgets/${wish.plan.id}`}
              onClick={onClose}
              className="flex items-center gap-3 rounded-lg p-1 transition-colors hover:bg-surface-muted"
            >
              <span
                className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl"
                style={{
                  backgroundColor: `${wish.plan.color ?? '#a855f7'}1f`,
                  color: wish.plan.color ?? '#a855f7',
                }}
              >
                <Wallet className="h-5 w-5" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-semibold">{wish.plan.name}</span>
                <span className="block text-xs text-muted">
                  plan of {money(wish.plan.plannedAmount)}
                  {wish.plan.state === 'CLOSED' && ' · closed'}
                </span>
              </span>
              <span className="shrink-0 text-xs font-medium text-primary">Open</span>
            </Link>
            <button
              type="button"
              disabled={busy}
              onClick={() => act('unlink-plan', 'Plan unlinked')}
              className="mt-2 inline-flex items-center gap-1 text-xs text-muted hover:text-danger"
            >
              <Link2Off className="h-3 w-3" /> Unlink this plan
            </button>
          </div>
        ) : (
          wish.status !== 'BOUGHT' && (
            <div className="rounded-xl border border-dashed border-border p-4 text-center">
              <Sparkles className="mx-auto h-5 w-5 text-muted" />
              <p className="mt-2 text-sm font-medium">No plan yet</p>
              <p className="mt-0.5 text-xs text-muted">
                Turn it into a budget plan and start filling it whenever money comes in.
              </p>
              <Button size="sm" className="mt-3" onClick={() => onPlan(wish)}>
                <PiggyBank className="h-4 w-4" /> Plan this wish
              </Button>
            </div>
          )
        )}

        <div className="flex flex-wrap justify-end gap-2 border-t border-border pt-4">
          <Button variant="ghost" onClick={() => onDelete(wish)} aria-label="Delete want">
            <Trash2 className="h-4 w-4" />
          </Button>
          <Button variant="outline" onClick={() => onEdit(wish)}>
            <Pencil className="h-4 w-4" /> Edit
          </Button>
          {wish.status === 'DROPPED' ? (
            <Button variant="outline" loading={busy} onClick={() => setStatus('WANTING', 'Back on the list')}>
              Restore
            </Button>
          ) : (
            <Button variant="outline" loading={busy} onClick={() => setStatus('DROPPED', 'Dropped')}>
              Drop
            </Button>
          )}
          {wish.status !== 'BOUGHT' && (
            <Button loading={busy} onClick={() => act('bought', `You got "${wish.name}"`)}>
              <Check className="h-4 w-4" /> Mark bought
            </Button>
          )}
        </div>
      </div>
    </Modal>
  );
}
