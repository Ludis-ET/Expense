'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import useSWR, { useSWRConfig } from 'swr';
import { toast } from 'sonner';
import {
  Check,
  ExternalLink,
  PiggyBank,
  Plus,
  Search,
  Sparkles,
  Star,
  Wallet,
  X,
} from 'lucide-react';
import { Skeleton, EmptyState } from '@/components/ui/misc';
import { Button } from '@/components/ui/button';
import { Input, Select } from '@/components/ui/input';
import { DEFAULT_WISH_EMOJI } from '@/components/finance/wish-emoji';
import {
  PRIORITY_LABEL,
  PlanWishModal,
  STATUS_META,
  WishDetailModal,
  WishForm,
} from '@/components/finance/wish-modals';
import { api, ApiError } from '@/lib/api';
import { useConfirm } from '@/components/ui/confirm-dialog';
import { cn } from '@/lib/utils';
import type { WishlistItem, WishlistResponse, WishlistStatus } from '@/lib/types';

const SORTS = [
  { value: 'priority', label: 'Priority' },
  { value: 'newest', label: 'Newest' },
  { value: 'oldest', label: 'Oldest' },
  { value: 'name', label: 'A to Z' },
] as const;

type Sort = (typeof SORTS)[number]['value'];
type Tab = 'all' | WishlistStatus;

export function WishlistPanel() {
  const confirm = useConfirm();
  const { mutate: globalMutate } = useSWRConfig();

  const [tab, setTab] = useState<Tab>('WANTING');
  const [q, setQ] = useState('');
  const [debouncedQ, setDebouncedQ] = useState('');
  const [priority, setPriority] = useState('');
  const [sort, setSort] = useState<Sort>('priority');

  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<WishlistItem | null>(null);
  const [viewing, setViewing] = useState<WishlistItem | null>(null);
  const [planning, setPlanning] = useState<WishlistItem | null>(null);

  // Typing shouldn't fire a request per keystroke.
  useEffect(() => {
    const t = setTimeout(() => setDebouncedQ(q.trim()), 300);
    return () => clearTimeout(t);
  }, [q]);

  const key = useMemo(() => {
    const p = new URLSearchParams({ sort });
    if (tab !== 'all') p.set('status', tab);
    if (priority) p.set('priority', priority);
    if (debouncedQ) p.set('q', debouncedQ);
    return `/wishlist?${p.toString()}`;
  }, [tab, priority, debouncedQ, sort]);

  const { data, mutate, isLoading } = useSWR<WishlistResponse>(key);

  /** Planning a want creates a budget, which moves every balance downstream. */
  const refreshLinked = () =>
    globalMutate(
      (k) =>
        typeof k === 'string' &&
        (k.startsWith('/dashboard') || k.startsWith('/accounts') || k.startsWith('/budgets')),
    );

  const items = data?.items ?? [];
  const stats = data?.stats;
  const activeFilters = (debouncedQ ? 1 : 0) + (priority ? 1 : 0);

  const TABS: { id: Tab; label: string; count?: number }[] = [
    { id: 'WANTING', label: 'Wanting', count: stats?.wanting },
    { id: 'PLANNED', label: 'Planned', count: stats?.planned },
    { id: 'BOUGHT', label: 'Bought', count: stats?.bought },
    { id: 'DROPPED', label: 'Dropped', count: stats?.dropped },
    { id: 'all', label: 'All', count: stats?.total },
  ];

  function clearFilters() {
    setQ('');
    setPriority('');
  }

  async function remove(item: WishlistItem) {
    const ok = await confirm({
      title: 'Remove this want?',
      description: item.plan
        ? `"${item.name}" will be removed. Its plan "${item.plan.name}" stays, along with any money in it.`
        : `"${item.name}" will be removed from your wishlist.`,
      confirmLabel: 'Remove',
      tone: 'danger',
    });
    if (!ok) return;
    try {
      await api.del(`/wishlist/${item.id}`);
      toast.success('Removed');
      setViewing(null);
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  return (
    <div className="animate-in space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted">
          Things you want, with no money attached. Plan one when you are ready to act on it.
        </p>
        <Button
          size="sm"
          className="min-h-10 shrink-0"
          onClick={() => {
            setEditing(null);
            setFormOpen(true);
          }}
        >
          <Plus className="h-4 w-4" /> Add want
        </Button>
      </div>

      {/* ---- Status tabs --------------------------------------------- */}
      <div className="flex gap-1 overflow-x-auto rounded-xl border border-border p-1">
        {TABS.map((t) => (
          <button
            key={t.id}
            type="button"
            onClick={() => setTab(t.id)}
            className={cn(
              'inline-flex min-h-9 shrink-0 items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition-colors',
              tab === t.id
                ? 'bg-primary text-primary-foreground'
                : 'text-muted hover:bg-surface-muted hover:text-foreground',
            )}
          >
            {t.label}
            {t.count !== undefined && t.count > 0 && (
              <span
                className={cn(
                  'rounded-full px-1.5 text-[10px] font-bold',
                  tab === t.id ? 'bg-background/25' : 'bg-surface-muted',
                )}
              >
                {t.count}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* ---- Search, priority, sort ---------------------------------- */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative min-w-40 flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <Input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search wants…"
            className="pl-9"
            aria-label="Search wants"
          />
        </div>
        <div className="w-36">
          <Select
            value={priority}
            onChange={(e) => setPriority(e.target.value)}
            aria-label="Filter by priority"
          >
            <option value="">Any priority</option>
            {[1, 2, 3, 4, 5].map((p) => (
              <option key={p} value={String(p)}>
                {PRIORITY_LABEL[p]}
              </option>
            ))}
          </Select>
        </div>
        <div className="w-36">
          <Select
            value={sort}
            onChange={(e) => setSort(e.target.value as Sort)}
            aria-label="Sort wants"
          >
            {SORTS.map((s) => (
              <option key={s.value} value={s.value}>
                {s.label}
              </option>
            ))}
          </Select>
        </div>
        {activeFilters > 0 && (
          <button
            type="button"
            onClick={clearFilters}
            className="inline-flex min-h-10 items-center gap-1 rounded-xl border border-border px-3 text-xs font-medium text-muted hover:bg-surface-muted"
          >
            <X className="h-3 w-3" /> Clear
          </button>
        )}
      </div>

      {/* ---- Grid ------------------------------------------------------ */}
      {isLoading ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-36" />
          ))}
        </div>
      ) : items.length === 0 ? (
        <EmptyState
          icon={<Sparkles className="h-5 w-5" />}
          title={activeFilters > 0 ? 'Nothing matches' : 'Nothing here yet'}
          description={
            activeFilters > 0
              ? 'Try a different search or priority.'
              : 'Park the things you want - phones, trips, tools - and plan them when you are ready.'
          }
          action={
            activeFilters > 0 ? (
              <Button variant="outline" onClick={clearFilters}>
                Clear filters
              </Button>
            ) : (
              <Button onClick={() => setFormOpen(true)}>Add your first want</Button>
            )
          }
        />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {items.map((item) => (
            <WishCard
              key={item.id}
              item={item}
              onOpen={() => setViewing(item)}
              onPlan={() => setPlanning(item)}
            />
          ))}
        </div>
      )}

      <WishForm
        open={formOpen}
        editing={editing}
        onClose={() => {
          setFormOpen(false);
          setEditing(null);
        }}
        onSaved={() => void mutate()}
      />

      <WishDetailModal
        wish={viewing}
        onClose={() => setViewing(null)}
        onEdit={(w) => {
          setViewing(null);
          setEditing(w);
          setFormOpen(true);
        }}
        onPlan={(w) => {
          setViewing(null);
          setPlanning(w);
        }}
        onChanged={() => void mutate()}
        onDelete={remove}
      />

      <PlanWishModal
        wish={planning}
        onClose={() => setPlanning(null)}
        onPlanned={() => {
          void mutate();
          void refreshLinked();
        }}
      />
    </div>
  );
}

/** One want: a face, a name, how badly you want it, and where it stands. */
function WishCard({
  item,
  onOpen,
  onPlan,
}: {
  item: WishlistItem;
  onOpen: () => void;
  onPlan: () => void;
}) {
  const meta = STATUS_META[item.status];
  const dimmed = item.status === 'BOUGHT' || item.status === 'DROPPED';

  return (
    <article
      onClick={onOpen}
      className={cn(
        'card group flex cursor-pointer flex-col gap-3 p-4 transition-all hover:-translate-y-0.5 hover:shadow-md',
        dimmed && 'opacity-70',
      )}
    >
      <div className="flex items-start gap-3">
        <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-surface-muted text-2xl transition-transform group-hover:scale-110">
          {item.emoji || DEFAULT_WISH_EMOJI}
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <h3 className="truncate font-semibold leading-snug">{item.name}</h3>
            <span
              className={cn(
                'shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide',
                meta.chip,
              )}
            >
              {meta.label}
            </span>
          </div>
          <p className="mt-0.5 flex items-center gap-1 text-xs text-muted">
            <Star className="h-3 w-3 fill-amber-400 text-amber-400" />
            {PRIORITY_LABEL[item.priority] ?? 'Someday'}
          </p>
        </div>
      </div>

      {item.note && <p className="line-clamp-2 text-xs text-muted">{item.note}</p>}

      <div
        className="mt-auto flex flex-wrap items-center gap-2"
        onClick={(e) => e.stopPropagation()}
      >
        {item.plan ? (
          <Link
            href={`/budgets/${item.plan.id}`}
            className="inline-flex min-h-8 items-center gap-1.5 rounded-lg bg-primary/10 px-2.5 text-xs font-medium text-primary hover:bg-primary/15"
          >
            <Wallet className="h-3.5 w-3.5" />
            <span className="max-w-32 truncate">{item.plan.name}</span>
          </Link>
        ) : item.status === 'BOUGHT' ? (
          <span className="inline-flex items-center gap-1 text-xs font-medium text-emerald-600 dark:text-emerald-400">
            <Check className="h-3.5 w-3.5" /> Owned
          </span>
        ) : (
          <Button size="sm" variant="outline" className="min-h-8" onClick={onPlan}>
            <PiggyBank className="h-3.5 w-3.5" /> Plan this
          </Button>
        )}

        {item.link && (
          <a
            href={item.link}
            target="_blank"
            rel="noreferrer"
            className="inline-flex min-h-8 items-center gap-1 rounded-lg border border-border px-2.5 text-xs font-medium text-muted hover:bg-surface-muted"
          >
            <ExternalLink className="h-3.5 w-3.5" /> Link
          </a>
        )}
      </div>
    </article>
  );
}
