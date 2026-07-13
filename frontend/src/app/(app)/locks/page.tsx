"use client";

import { useEffect, useState } from "react";
import useSWR from "swr";
import { toast } from "sonner";
import {
  Lock,
  Shield,
  Target,
  Vault,
  Plus,
  Trash2,
  Unlock,
} from "lucide-react";
import { PageHeader, Skeleton, EmptyState } from "@/components/ui/misc";
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
  SavingsGoal,
  SpendLock,
  SpendLockKind,
  SpendLocksResponse,
} from "@/lib/types";

const KIND_META: Record<
  SpendLockKind,
  { label: string; blurb: string; icon: typeof Lock }
> = {
  FLOOR: {
    label: "Safety floor",
    blurb:
      "You cannot spend below this balance. Multiple floors → highest wins.",
    icon: Shield,
  },
  GOAL: {
    label: "Goal vault",
    blurb: "Money reserved for a savings goal   stacked with other vaults.",
    icon: Target,
  },
  RESERVE: {
    label: "Named reserve",
    blurb: "A labeled pot you refuse to touch (rent, emergency…).",
    icon: Vault,
  },
};

export default function LocksPage() {
  const confirm = useConfirm();
  const { activeCurrency } = useCurrencyView();
  const { money } = useMoney();
  const { data, mutate, isLoading } = useSWR<SpendLocksResponse>(
    `/spend-locks?currency=${encodeURIComponent(activeCurrency)}`,
  );
  const { data: goalsData } = useSWR<{ items: SavingsGoal[] }>("/goals");
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState<SpendLock | null>(null);

  const overview =
    data?.overview.find((o) => o.currency === activeCurrency) ??
    data?.overview[0];
  const items = data?.items ?? [];
  const spendablePct =
    overview && Number(overview.balance) > 0
      ? Math.round(
          (Number(overview.spendable) / Number(overview.balance)) * 100,
        )
      : 100;

  async function remove(lock: SpendLock) {
    const ok = await confirm({
      title: "Remove lock?",
      description: `"${lock.name}" will unlock ${money(lock.amount)}.`,
      confirmLabel: "Remove",
      tone: "danger",
    });
    if (!ok) return;
    try {
      await api.del(`/spend-locks/${lock.id}`);
      toast.success("Lock removed");
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed");
    }
  }

  async function toggle(lock: SpendLock) {
    try {
      await api.put(`/spend-locks/${lock.id}`, { active: !lock.active });
      toast.success(lock.active ? "Lock paused" : "Lock armed");
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed");
    }
  }

  return (
    <div className="animate-in space-y-6">
      <PageHeader
        title="Spend locks"
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
            <Plus className="h-4 w-4" /> New lock
          </Button>
        }
      />

      {isLoading || !overview ? (
        <Skeleton className="h-40 rounded-2xl" />
      ) : (
        <div className="relative overflow-hidden rounded-2xl border border-border bg-gradient-to-br from-slate-900 via-slate-800 to-emerald-950 p-5 text-white shadow-lg sm:p-6">
          <div className="pointer-events-none absolute -right-10 -top-10 h-40 w-40 rounded-full bg-emerald-400/20 blur-3xl" />
          <div className="relative flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <p className="flex items-center gap-2 text-xs font-semibold uppercase tracking-widest text-emerald-200/80">
                <Lock className="h-3.5 w-3.5" /> Unlocked to spend
              </p>
              <p className="mt-2 text-3xl font-bold tabular-nums sm:text-4xl">
                {money(overview.spendable)}
              </p>
              <p className="mt-1 text-sm text-white/70">
                of {money(overview.balance)} · {overview.lockCount} active lock
                {overview.lockCount === 1 ? "" : "s"}
              </p>
            </div>
            <div className="grid grid-cols-2 gap-3 text-sm sm:text-right">
              <div>
                <p className="text-white/50">Floor</p>
                <p className="font-semibold tabular-nums">
                  {money(overview.floorAmount)}
                </p>
              </div>
              <div>
                <p className="text-white/50">Reserved</p>
                <p className="font-semibold tabular-nums">
                  {money(overview.reservedAmount)}
                </p>
              </div>
            </div>
          </div>
          <div className="relative mt-4">
            <div className="h-2 overflow-hidden rounded-full bg-white/15">
              <div
                className="h-full rounded-full bg-emerald-400 transition-all"
                style={{ width: `${spendablePct}%` }}
              />
            </div>
            <p className="mt-2 text-xs text-white/60">
              {spendablePct}% of balance is free to spend
            </p>
          </div>
          {overview.hint && (
            <p className="relative mt-3 rounded-xl bg-amber-400/15 px-3 py-2 text-xs text-amber-100">
              {overview.hint}
            </p>
          )}
        </div>
      )}

      {isLoading ? (
        <div className="space-y-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton key={i} className="h-24" />
          ))}
        </div>
      ) : items.length === 0 ? (
        <EmptyState
          icon={<Lock className="h-5 w-5" />}
          title="No locks yet"
          description="Set a safety floor, vault money for a goal, or name a reserve you won't touch."
          action={
            <Button onClick={() => setOpen(true)}>Create first lock</Button>
          }
        />
      ) : (
        <ul className="space-y-3">
          {items.map((lock) => {
            const meta = KIND_META[lock.kind];
            const Icon = meta.icon;
            return (
              <li
                key={lock.id}
                className={cn(
                  "card flex flex-col gap-3 p-4 sm:flex-row sm:items-center",
                  !lock.active && "opacity-60",
                )}
              >
                <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
                  <Icon className="h-5 w-5" />
                </span>
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="font-semibold">{lock.name}</p>
                    <span className="rounded-full bg-surface-muted px-2 py-0.5 text-[10px] font-medium uppercase text-muted">
                      {meta.label}
                    </span>
                    {!lock.active && (
                      <span className="rounded-full bg-amber-500/10 px-2 py-0.5 text-[10px] font-medium text-amber-600">
                        paused
                      </span>
                    )}
                  </div>
                  <p className="mt-0.5 text-xs text-muted">
                    {lock.goal ? `→ ${lock.goal.name}` : meta.blurb}
                  </p>
                </div>
                <p className="text-lg font-bold tabular-nums">
                  {money(lock.amount)}
                </p>
                <div className="flex gap-1">
                  <button
                    type="button"
                    onClick={() => toggle(lock)}
                    className="flex h-10 w-10 items-center justify-center rounded-lg text-muted hover:bg-surface-muted"
                    aria-label={lock.active ? "Pause lock" : "Arm lock"}
                  >
                    {lock.active ? (
                      <Unlock className="h-4 w-4" />
                    ) : (
                      <Lock className="h-4 w-4" />
                    )}
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      setEditing(lock);
                      setOpen(true);
                    }}
                    className="rounded-lg px-3 py-2 text-xs font-medium text-muted hover:bg-surface-muted"
                  >
                    Edit
                  </button>
                  <button
                    type="button"
                    onClick={() => remove(lock)}
                    className="flex h-10 w-10 items-center justify-center rounded-lg text-muted hover:bg-surface-muted hover:text-danger"
                    aria-label="Delete"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>
              </li>
            );
          })}
        </ul>
      )}

      <LockForm
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
    </div>
  );
}

function LockForm({
  open,
  editing,
  goals,
  currency,
  onClose,
  onSaved,
}: {
  open: boolean;
  editing: SpendLock | null;
  goals: SavingsGoal[];
  currency: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [kind, setKind] = useState<SpendLockKind>("FLOOR");
  const [name, setName] = useState("");
  const [amount, setAmount] = useState("");
  const [goalId, setGoalId] = useState("");
  const [note, setNote] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    setKind(editing?.kind ?? "FLOOR");
    setName(editing?.name ?? "");
    setAmount(editing ? String(Number(editing.amount)) : "");
    setGoalId(editing?.goalId ?? "");
    setNote(editing?.note ?? "");
  }, [open, editing]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    try {
      if (editing) {
        await api.put(`/spend-locks/${editing.id}`, {
          name,
          amount: Number(amount),
          note: note || null,
          goalId:
            kind === "GOAL" || editing.kind === "GOAL" ? goalId || null : null,
        });
        toast.success("Lock updated");
      } else {
        await api.post("/spend-locks", {
          kind,
          name: name || KIND_META[kind].label,
          amount: Number(amount),
          currency,
          note: note || undefined,
          goalId: kind === "GOAL" ? goalId || undefined : undefined,
        });
        toast.success("Lock armed");
      }
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed");
    } finally {
      setSaving(false);
    }
  }

  const formKind = editing?.kind ?? kind;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={editing ? "Edit lock" : "New spend lock"}
      description="Locks stack per currency. Floors use the highest value."
    >
      <form onSubmit={submit} className="space-y-4">
        {!editing && (
          <div className="grid gap-2">
            {(Object.keys(KIND_META) as SpendLockKind[]).map((k) => {
              const meta = KIND_META[k];
              const Icon = meta.icon;
              return (
                <button
                  key={k}
                  type="button"
                  onClick={() => setKind(k)}
                  className={cn(
                    "flex min-h-12 items-start gap-3 rounded-xl border p-3 text-left transition-colors",
                    kind === k
                      ? "border-primary bg-primary/5"
                      : "border-border hover:bg-surface-muted",
                  )}
                >
                  <Icon className="mt-0.5 h-5 w-5 shrink-0 text-primary" />
                  <span>
                    <span className="block text-sm font-semibold">
                      {meta.label}
                    </span>
                    <span className="text-xs text-muted">{meta.blurb}</span>
                  </span>
                </button>
              );
            })}
          </div>
        )}
        <Field label="Name">
          <Input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={KIND_META[formKind].label}
          />
        </Field>
        <Field label={`Amount (${currency})`}>
          <Input
            type="number"
            step="0.01"
            min="0"
            required
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
        </Field>
        {formKind === "GOAL" && (
          <Field label="Savings goal">
            <Select
              required={!editing}
              value={goalId}
              onChange={(e) => setGoalId(e.target.value)}
            >
              <option value="">Pick a goal…</option>
              {goals.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </Select>
          </Field>
        )}
        <Field label="Note">
          <Textarea
            rows={2}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Why this money stays locked…"
          />
        </Field>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            {editing ? "Save" : "Arm lock"}
          </Button>
        </div>
      </form>
    </Modal>
  );
}
