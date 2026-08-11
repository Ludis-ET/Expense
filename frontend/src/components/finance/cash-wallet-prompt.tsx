"use client";

import { useEffect, useState } from "react";
import useSWR from "swr";
import { toast } from "sonner";
import { Banknote, Plus, Wallet } from "lucide-react";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { Field, Input } from "@/components/ui/input";
import { api, ApiError } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { cn } from "@/lib/utils";
import type { Account } from "@/lib/types";

const SKIP_KEY = "santim.cashWalletPrompt.skip";

/**
 * After sign-in, ask which wallet holds physical cash   ATM withdrawals are
 * booked as transfers into it. Users can pick an existing wallet or create one.
 */
export function CashWalletPrompt() {
  const { user, loading, refreshUser } = useAuth();
  const { data, mutate } = useSWR<{ items: Account[] }>(
    user ? "/accounts" : null,
  );
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [mode, setMode] = useState<"pick" | "create">("pick");
  const [newName, setNewName] = useState("Cash");
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const accounts = (data?.items ?? []).filter((a) => !a.archived);

  useEffect(() => {
    if (loading || !user) {
      setOpen(false);
      return;
    }
    if (user.cashAccountId) {
      setOpen(false);
      return;
    }
    try {
      if (sessionStorage.getItem(SKIP_KEY) === user.id) {
        setOpen(false);
        return;
      }
    } catch {
      /* ignore */
    }
    setOpen(true);
  }, [loading, user]);

  useEffect(() => {
    if (!open) return;
    if (accounts.length === 0) {
      setMode("create");
      return;
    }
    // Prefer an existing CASH-typed wallet as the default pick.
    const cashTyped = accounts.find((a) => a.type === "CASH");
    setSelectedId((prev) => prev ?? cashTyped?.id ?? accounts[0]?.id ?? null);
    setMode("pick");
  }, [open, accounts]);

  function skip() {
    if (user) {
      try {
        sessionStorage.setItem(SKIP_KEY, user.id);
      } catch {
        /* ignore */
      }
    }
    setOpen(false);
  }

  async function assign(accountId: string) {
    setBusy(true);
    try {
      await api.put("/users/me", { cashAccountId: accountId });
      await refreshUser();
      toast.success("Cash wallet saved");
      setOpen(false);
    } catch (err) {
      toast.error(
        err instanceof ApiError ? err.message : "Could not save cash wallet",
      );
    } finally {
      setBusy(false);
    }
  }

  async function createAndAssign() {
    const name = newName.trim() || "Cash";
    setBusy(true);
    try {
      const created = await api.post<Account>("/accounts", {
        name,
        type: "CASH",
        currency: user?.currency ?? "ETB",
        icon: "banknote",
        color: "#22c55e",
      });
      await mutate();
      await assign(created.id);
    } catch (err) {
      toast.error(
        err instanceof ApiError ? err.message : "Could not create wallet",
      );
      setBusy(false);
    }
  }

  if (!user || user.cashAccountId) return null;

  return (
    <Modal
      open={open}
      onClose={skip}
      title="Which wallet is your cash?"
      description="ATM withdrawals move into this wallet instead of counting as spending. You can change it later in Settings."
    >
      <div className="space-y-4">
        <div className="flex gap-2 rounded-xl border border-border bg-surface-muted/40 p-1">
          <button
            type="button"
            onClick={() => setMode("pick")}
            className={cn(
              "flex flex-1 items-center justify-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
              mode === "pick"
                ? "bg-surface text-foreground shadow-sm"
                : "text-muted hover:text-foreground",
            )}
          >
            <Wallet className="h-4 w-4" />
            Use existing
          </button>
          <button
            type="button"
            onClick={() => setMode("create")}
            className={cn(
              "flex flex-1 items-center justify-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
              mode === "create"
                ? "bg-surface text-foreground shadow-sm"
                : "text-muted hover:text-foreground",
            )}
          >
            <Plus className="h-4 w-4" />
            Create new
          </button>
        </div>

        {mode === "pick" ? (
          accounts.length === 0 ? (
            <p className="rounded-xl border border-dashed border-border px-4 py-6 text-center text-sm text-muted">
              No wallets yet. Create a cash wallet to continue.
            </p>
          ) : (
            <ul className="max-h-56 space-y-1.5 overflow-y-auto">
              {accounts.map((a) => {
                const selected = selectedId === a.id;
                return (
                  <li key={a.id}>
                    <button
                      type="button"
                      onClick={() => setSelectedId(a.id)}
                      className={cn(
                        "flex w-full items-center gap-3 rounded-xl border px-3 py-2.5 text-left transition-colors",
                        selected
                          ? "border-primary bg-primary/5"
                          : "border-border hover:bg-surface-muted",
                      )}
                    >
                      <span
                        className={cn(
                          "flex h-9 w-9 items-center justify-center rounded-xl",
                          selected
                            ? "bg-primary/15 text-primary"
                            : "bg-surface-muted text-muted",
                        )}
                      >
                        <Banknote className="h-4 w-4" />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm font-semibold">
                          {a.name}
                        </span>
                        <span className="block text-xs text-muted">
                          {a.type.replaceAll("_", " ").toLowerCase()}
                          {a.type === "CASH" ? " · good default" : ""}
                        </span>
                      </span>
                      <span
                        className={cn(
                          "h-4 w-4 rounded-full border-2",
                          selected
                            ? "border-primary bg-primary"
                            : "border-border",
                        )}
                      />
                    </button>
                  </li>
                );
              })}
            </ul>
          )
        ) : (
          <Field label="Wallet name">
            <Input
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              placeholder="Cash"
              autoFocus
            />
          </Field>
        )}

        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Button type="button" variant="ghost" onClick={skip} disabled={busy}>
            Not now
          </Button>
          {mode === "pick" ? (
            <Button
              type="button"
              loading={busy}
              disabled={!selectedId || accounts.length === 0}
              onClick={() => selectedId && void assign(selectedId)}
            >
              Use this wallet
            </Button>
          ) : (
            <Button
              type="button"
              loading={busy}
              onClick={() => void createAndAssign()}
            >
              Create &amp; use
            </Button>
          )}
        </div>
      </div>
    </Modal>
  );
}
