"use client";

import { useEffect, useMemo, useState } from "react";
import useSWR, { useSWRConfig } from "swr";
import { toast } from "sonner";
import {
  Sparkles,
  Plus,
  Trash2,
  ExternalLink,
  Star,
  PiggyBank,
  Target,
  ShoppingBag,
  Check,
} from "lucide-react";
import {
  PageHeader,
  Skeleton,
  EmptyState,
  ProgressBar,
} from "@/components/ui/misc";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Field, Input, Select, Textarea } from "@/components/ui/input";
import {
  CurrencyBadge,
  currencyScopeHint,
} from "@/components/finance/currency-badge";
import { api, ApiError } from "@/lib/api";
import { useMoney } from "@/lib/amount-visibility";
import { useCurrencyView } from "@/lib/currency-view-context";
import { useConfirm } from "@/components/ui/confirm-dialog";
import { cn } from "@/lib/utils";
import type {
  Account,
  Category,
  SavingsGoal,
  WishlistItem,
  WishlistResponse,
  WishlistStatus,
} from "@/lib/types";

const EMOJIS = [
  "✨",
  "🎧",
  "👟",
  "📱",
  "✈️",
  "📚",
  "🎮",
  "☕",
  "🎸",
  "🏠",
  "🚲",
  "📷",
];
const PRIORITY_LABEL = ["", "Must have", "Soon", "Nice", "Someday", "Dream"];

export default function WishlistPage() {
  const confirm = useConfirm();
  const { activeCurrency } = useCurrencyView();
  const { money } = useMoney();
  const { mutate: globalMutate } = useSWRConfig();
  const { data, mutate, isLoading } = useSWR<WishlistResponse>(
    `/wishlist?currency=${encodeURIComponent(activeCurrency)}`,
  );
  const { data: goalsData } = useSWR<{ items: SavingsGoal[] }>("/goals");
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<WishlistItem | null>(null);
  const [funding, setFunding] = useState<WishlistItem | null>(null);
  const [promoting, setPromoting] = useState<WishlistItem | null>(null);
  const [buying, setBuying] = useState<WishlistItem | null>(null);
  const [filter, setFilter] = useState<"open" | WishlistStatus | "all">("open");

  // After money moves, refresh anything downstream (dashboard, goals, accounts, locks).
  const refreshLinked = () =>
    globalMutate(
      (key) =>
        typeof key === "string" &&
        (key.startsWith("/dashboard") ||
          key.startsWith("/goals") ||
          key.startsWith("/accounts") ||
          key.startsWith("/spend-locks")),
    );

  const items = (data?.items ?? []).filter((i) => {
    if (filter === "all") return true;
    if (filter === "open")
      return i.status === "WANTING" || i.status === "SAVING";
    return i.status === filter;
  });

  async function remove(item: WishlistItem) {
    const ok = await confirm({
      title: "Drop from wishlist?",
      description: `"${item.name}" will be removed.`,
      confirmLabel: "Remove",
      tone: "danger",
    });
    if (!ok) return;
    try {
      await api.del(`/wishlist/${item.id}`);
      toast.success("Removed");
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed");
    }
  }

  async function startSaving(item: WishlistItem) {
    try {
      await api.put(`/wishlist/${item.id}`, { status: "SAVING" });
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed");
    }
  }

  return (
    <div className="animate-in space-y-6">
      <PageHeader
        title="Wishlist"
        description={currencyScopeHint(activeCurrency)}
        badge={<CurrencyBadge />}
        action={
          <Button
            size="sm"
            className="min-h-10"
            onClick={() => {
              setEditing(null);
              setOpen(true);
            }}
          >
            <Plus className="h-4 w-4" /> Add want
          </Button>
        }
      />

      {data?.stats && (
        <div className="relative overflow-hidden rounded-2xl border border-border bg-gradient-to-br from-amber-50 via-rose-50 to-violet-100 p-5 dark:from-amber-950/40 dark:via-rose-950/30 dark:to-violet-950/40 sm:p-6">
          <div className="pointer-events-none absolute right-4 top-4 text-5xl opacity-30">
            ✨
          </div>
          <p className="text-xs font-semibold uppercase tracking-widest text-muted">
            Dream board · {activeCurrency}
          </p>
          <div className="mt-3 grid grid-cols-2 gap-4 sm:grid-cols-4">
            <div>
              <p className="text-2xl font-bold tabular-nums">
                {money(data.stats.dreamTotal)}
              </p>
              <p className="text-xs text-muted">total wants</p>
            </div>
            <div>
              <p className="text-2xl font-bold tabular-nums text-emerald-600 dark:text-emerald-400">
                {money(data.stats.savedTotal)}
              </p>
              <p className="text-xs text-muted">saved toward</p>
            </div>
            <div>
              <p className="text-2xl font-bold">
                {data.stats.wanting + data.stats.saving}
              </p>
              <p className="text-xs text-muted">active dreams</p>
            </div>
            <div>
              <p className="text-2xl font-bold text-emerald-600 dark:text-emerald-400">
                {data.stats.affordable}
              </p>
              <p className="text-xs text-muted">you can afford now</p>
            </div>
          </div>
        </div>
      )}

      <div className="flex gap-1 overflow-x-auto rounded-xl border border-border p-1">
        {[
          { id: "open" as const, label: "Active" },
          { id: "WANTING" as const, label: "Wanting" },
          { id: "SAVING" as const, label: "Saving" },
          { id: "BOUGHT" as const, label: "Bought" },
          { id: "all" as const, label: "All" },
        ].map((f) => (
          <button
            key={f.id}
            type="button"
            onClick={() => setFilter(f.id)}
            className={cn(
              "min-h-10 shrink-0 rounded-lg px-3 py-1.5 text-xs font-medium",
              filter === f.id
                ? "bg-primary text-primary-foreground"
                : "text-muted hover:text-foreground",
            )}
          >
            {f.label}
          </button>
        ))}
      </div>

      {isLoading ? (
        <div className="grid gap-4 sm:grid-cols-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-44" />
          ))}
        </div>
      ) : items.length === 0 ? (
        <EmptyState
          icon={<Sparkles className="h-5 w-5" />}
          title="Wishlist is empty"
          description="Park the things you want — phones, trips, tools — and track how close you are."
          action={<Button onClick={() => setOpen(true)}>Add first want</Button>}
        />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2">
          {items.map((item) => (
            <article
              key={item.id}
              className={cn(
                "card relative flex flex-col overflow-hidden p-4",
                item.status === "BOUGHT" && "opacity-70",
              )}
            >
              {item.affordable && (
                <span className="absolute right-3 top-3 inline-flex items-center gap-1 rounded-full bg-emerald-500/15 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-emerald-600 dark:text-emerald-400">
                  <Check className="h-3 w-3" /> Can afford
                </span>
              )}
              <div className="flex items-start gap-3">
                <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-surface-muted text-2xl">
                  {item.emoji || "✨"}
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex items-start justify-between gap-2">
                    <h3 className="font-semibold leading-snug">{item.name}</h3>
                    <button
                      type="button"
                      onClick={() => remove(item)}
                      className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-muted hover:bg-surface-muted hover:text-danger"
                      aria-label="Remove"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                  <p className="mt-0.5 flex flex-wrap items-center gap-x-1 gap-y-0.5 text-xs text-muted">
                    <Star className="h-3 w-3 fill-amber-400 text-amber-400" />
                    {PRIORITY_LABEL[item.priority] ?? "Someday"}
                    {item.goal && (
                      <span className="inline-flex items-center gap-0.5">
                        · <Target className="h-3 w-3" /> {item.goal.name}
                      </span>
                    )}
                  </p>
                </div>
              </div>

              <div className="mt-4">
                <div className="mb-1 flex justify-between text-sm">
                  <span className="font-bold tabular-nums">
                    {money(item.estimatedCost)}
                  </span>
                  <span className="text-xs text-muted">{item.pct}% saved</span>
                </div>
                <ProgressBar
                  value={item.pct}
                  tone={item.pct >= 100 ? "success" : "primary"}
                />
                <p className="mt-1 text-xs text-muted">
                  {money(item.savedAmount)} in · {money(item.remaining)} to go
                </p>
              </div>

              <div className="mt-4 flex flex-wrap gap-2">
                {item.status !== "BOUGHT" && (
                  <>
                    <Button
                      size="sm"
                      variant="outline"
                      className="min-h-9"
                      onClick={() => setFunding(item)}
                    >
                      <PiggyBank className="h-3.5 w-3.5" /> Fund
                    </Button>
                    {!item.goalId && (
                      <Button
                        size="sm"
                        variant="outline"
                        className="min-h-9"
                        onClick={() => setPromoting(item)}
                      >
                        <Target className="h-3.5 w-3.5" /> To goal
                      </Button>
                    )}
                    {item.status === "WANTING" && (
                      <Button
                        size="sm"
                        variant="outline"
                        className="min-h-9"
                        onClick={() => startSaving(item)}
                      >
                        Start saving
                      </Button>
                    )}
                    <Button
                      size="sm"
                      className="min-h-9"
                      onClick={() => setBuying(item)}
                    >
                      <ShoppingBag className="h-3.5 w-3.5" /> Buy
                    </Button>
                  </>
                )}
                <Button
                  size="sm"
                  variant="ghost"
                  className="min-h-9"
                  onClick={() => {
                    setEditing(item);
                    setOpen(true);
                  }}
                >
                  Edit
                </Button>
                {item.link && (
                  <a
                    href={item.link}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex min-h-9 items-center gap-1 rounded-lg border border-border px-3 text-xs font-medium text-muted hover:bg-surface-muted"
                  >
                    <ExternalLink className="h-3.5 w-3.5" /> Link
                  </a>
                )}
              </div>
            </article>
          ))}
        </div>
      )}

      <WishForm
        open={open}
        editing={editing}
        goals={goalsData?.items ?? []}
        currency={activeCurrency}
        onClose={() => {
          setOpen(false);
          setEditing(null);
        }}
        onSaved={() => void mutate()}
      />

      <FundModal
        item={funding}
        onClose={() => setFunding(null)}
        onSaved={() => {
          void mutate();
          void refreshLinked();
        }}
      />

      <PromoteModal
        item={promoting}
        onClose={() => setPromoting(null)}
        onSaved={() => {
          void mutate();
          void refreshLinked();
        }}
      />

      <PurchaseModal
        item={buying}
        onClose={() => setBuying(null)}
        onSaved={() => {
          void mutate();
          void refreshLinked();
        }}
      />
    </div>
  );
}

function FundModal({
  item,
  onClose,
  onSaved,
}: {
  item: WishlistItem | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { money } = useMoney();
  const [amount, setAmount] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (item) setAmount("");
  }, [item]);

  if (!item) return null;
  const remaining = Number(item.remaining);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!item) return;
    setSaving(true);
    try {
      await api.post(`/wishlist/${item.id}/fund`, { amount: Number(amount) });
      toast.success(
        item.goalId ? "Funded — goal updated too" : "Saved toward it",
      );
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={!!item}
      onClose={onClose}
      title={`Fund "${item.name}"`}
      description={
        item.goalId
          ? "Adds to this want and its linked savings goal."
          : `${money(item.remaining)} left to reach ${money(item.estimatedCost)}.`
      }
    >
      <form onSubmit={submit} className="space-y-4">
        <Field label={`Amount to set aside (${item.currency})`}>
          <Input
            type="number"
            step="0.01"
            min="0"
            required
            autoFocus
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder={remaining > 0 ? String(remaining) : "0"}
          />
        </Field>
        {remaining > 0 && (
          <div className="flex flex-wrap gap-2">
            {[0.25, 0.5, 1].map((f) => (
              <button
                key={f}
                type="button"
                onClick={() => setAmount(String(Math.round(remaining * f * 100) / 100))}
                className="rounded-lg border border-border px-3 py-1 text-xs font-medium text-muted hover:bg-surface-muted"
              >
                {f === 1 ? "Fund the rest" : `${f * 100}%`}
              </button>
            ))}
          </div>
        )}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            Set aside
          </Button>
        </div>
      </form>
    </Modal>
  );
}

function PromoteModal({
  item,
  onClose,
  onSaved,
}: {
  item: WishlistItem | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [deadline, setDeadline] = useState("");
  const [createLock, setCreateLock] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (item) {
      setDeadline("");
      setCreateLock(true);
    }
  }, [item]);

  if (!item) return null;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!item) return;
    setSaving(true);
    try {
      await api.post(`/wishlist/${item.id}/promote`, {
        createLock,
        deadline: deadline || undefined,
      });
      toast.success("Promoted to a savings goal");
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={!!item}
      onClose={onClose}
      title={`Make "${item.name}" a goal`}
      description="Creates a savings goal, carries over what you've saved, and can reserve the money so you don't spend it by accident."
    >
      <form onSubmit={submit} className="space-y-4">
        <Field label="Target date (optional)">
          <Input
            type="date"
            value={deadline}
            onChange={(e) => setDeadline(e.target.value)}
          />
        </Field>
        <label className="flex cursor-pointer items-start gap-3 rounded-xl border border-border p-3">
          <input
            type="checkbox"
            checked={createLock}
            onChange={(e) => setCreateLock(e.target.checked)}
            className="mt-0.5 h-4 w-4 accent-primary"
          />
          <span className="text-sm">
            <span className="font-medium">Reserve the money</span>
            <span className="block text-xs text-muted">
              Adds a spend lock so this amount is protected from everyday spending.
            </span>
          </span>
        </label>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            Create goal
          </Button>
        </div>
      </form>
    </Modal>
  );
}

function PurchaseModal({
  item,
  onClose,
  onSaved,
}: {
  item: WishlistItem | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const { data: accountsData } = useSWR<{ items: Account[] }>(
    item ? "/accounts" : null,
  );
  const { data: categoriesData } = useSWR<{ items: Category[] }>(
    item ? "/categories" : null,
  );
  const [accountId, setAccountId] = useState("");
  const [categoryId, setCategoryId] = useState("");
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [saving, setSaving] = useState(false);

  const accounts = useMemo(
    () =>
      (accountsData?.items ?? []).filter(
        (a) => !a.archived && (!item || a.currency === item.currency),
      ),
    [accountsData, item],
  );
  const categories = useMemo(
    () =>
      (categoriesData?.items ?? []).filter(
        (c) => c.kind === "EXPENSE" && !c.archived,
      ),
    [categoriesData],
  );

  useEffect(() => {
    if (!item) return;
    setAmount(String(Number(item.estimatedCost)));
    setDate(new Date().toISOString().slice(0, 10));
    setAccountId("");
    setCategoryId("");
  }, [item]);

  useEffect(() => {
    if (accounts.length && !accountId)
      setAccountId(accounts.find((a) => a.isDefault)?.id ?? accounts[0].id);
  }, [accounts, accountId]);

  if (!item) return null;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!item) return;
    if (!accountId || !categoryId) {
      toast.error("Pick an account and category");
      return;
    }
    setSaving(true);
    try {
      await api.post(`/wishlist/${item.id}/purchase`, {
        accountId,
        categoryId,
        amount: Number(amount),
        date,
      });
      toast.success("Recorded the purchase 🛍️");
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={!!item}
      onClose={onClose}
      title={`Buy "${item.name}"`}
      description="Logs a real expense against an account and marks the want bought. Any reserve for it is released."
    >
      {accounts.length === 0 ? (
        <p className="rounded-lg bg-surface-muted p-3 text-sm text-muted">
          No {item.currency} account found. Add one first.
        </p>
      ) : (
        <form onSubmit={submit} className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <Field label={`Amount (${item.currency})`}>
              <Input
                type="number"
                step="0.01"
                min="0"
                required
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
              />
            </Field>
            <Field label="Date">
              <Input
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
              />
            </Field>
          </div>
          <Field label="Pay from">
            <Select
              value={accountId}
              onChange={(e) => setAccountId(e.target.value)}
            >
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Category">
            <Select
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
            >
              <option value="">Choose…</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </Select>
          </Field>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" loading={saving}>
              Record purchase
            </Button>
          </div>
        </form>
      )}
    </Modal>
  );
}

function WishForm({
  open,
  editing,
  goals,
  currency,
  onClose,
  onSaved,
}: {
  open: boolean;
  editing: WishlistItem | null;
  goals: SavingsGoal[];
  currency: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [name, setName] = useState("");
  const [estimatedCost, setEstimatedCost] = useState("");
  const [savedAmount, setSavedAmount] = useState("0");
  const [priority, setPriority] = useState("3");
  const [emoji, setEmoji] = useState("✨");
  const [note, setNote] = useState("");
  const [link, setLink] = useState("");
  const [goalId, setGoalId] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setName(editing?.name ?? "");
    setEstimatedCost(editing ? String(Number(editing.estimatedCost)) : "");
    setSavedAmount(editing ? String(Number(editing.savedAmount)) : "0");
    setPriority(String(editing?.priority ?? 3));
    setEmoji(editing?.emoji ?? "✨");
    setNote(editing?.note ?? "");
    setLink(editing?.link ?? "");
    setGoalId(editing?.goalId ?? "");
  }, [open, editing]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    const payload = {
      name,
      estimatedCost: Number(estimatedCost),
      currency,
      priority: Number(priority),
      emoji,
      note: note || undefined,
      link: link || undefined,
      goalId: goalId || undefined,
      savedAmount: Number(savedAmount) || 0,
      status: Number(savedAmount) > 0 ? ("SAVING" as const) : undefined,
    };
    try {
      if (editing) await api.put(`/wishlist/${editing.id}`, payload);
      else await api.post("/wishlist", payload);
      toast.success(editing ? "Updated" : "Added to wishlist");
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={editing ? "Edit want" : "New want"}
      description="Park it here so it stops living only in your head."
    >
      <form onSubmit={submit} className="space-y-4">
        <Field label="Emoji">
          <div className="flex flex-wrap gap-1.5">
            {EMOJIS.map((e) => (
              <button
                key={e}
                type="button"
                onClick={() => setEmoji(e)}
                className={cn(
                  "flex h-10 w-10 items-center justify-center rounded-xl text-lg transition-colors",
                  emoji === e
                    ? "bg-primary/15 ring-2 ring-primary"
                    : "bg-surface-muted hover:bg-surface-muted/80",
                )}
              >
                {e}
              </button>
            ))}
          </div>
        </Field>
        <Field label="What do you want?">
          <Input
            required
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Noise-cancelling headphones"
          />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label={`Cost (${currency})`}>
            <Input
              type="number"
              step="0.01"
              min="0"
              required
              value={estimatedCost}
              onChange={(e) => setEstimatedCost(e.target.value)}
            />
          </Field>
          <Field label="Already saved">
            <Input
              type="number"
              step="0.01"
              min="0"
              value={savedAmount}
              onChange={(e) => setSavedAmount(e.target.value)}
            />
          </Field>
        </div>
        <Field label="Priority">
          <Select
            value={priority}
            onChange={(e) => setPriority(e.target.value)}
          >
            {[1, 2, 3, 4, 5].map((p) => (
              <option key={p} value={p}>
                {PRIORITY_LABEL[p]}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Link to goal (optional)">
          <Select value={goalId} onChange={(e) => setGoalId(e.target.value)}>
            <option value="">None</option>
            {goals.map((g) => (
              <option key={g.id} value={g.id}>
                {g.name}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Link (optional)">
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
            {editing ? "Save" : "Add want"}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
