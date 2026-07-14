"use client";

import { useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { toast } from "sonner";
import { FileText, MessageCircle, Sparkles, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Spinner } from "@/components/ui/misc";
import { AskWidget } from "@/components/ai/ask-widget";
import { Markdown } from "@/components/markdown";
import { currentMonth } from "@/components/finance/month-navigator";
import { api, ApiError } from "@/lib/api";
import { formatMonth } from "@/lib/format";
import { cn } from "@/lib/utils";

export const OPEN_ASSISTANT_EVENT = "santim:open-assistant";

export function openAssistant(tab?: "ask" | "review") {
  if (typeof window === "undefined") return;
  window.dispatchEvent(
    new CustomEvent(OPEN_ASSISTANT_EVENT, { detail: { tab } }),
  );
}

export function AssistantFab() {
  const params = useSearchParams();
  const [open, setOpen] = useState(false);
  const [tab, setTab] = useState<"ask" | "review">("ask");
  const [month, setMonth] = useState(currentMonth());
  const [review, setReview] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (params.get("assistant")) setOpen(true);
  }, [params]);

  useEffect(() => {
    const onOpen = (e: Event) => {
      const detail = (e as CustomEvent<{ tab?: "ask" | "review" }>).detail;
      if (detail?.tab) setTab(detail.tab);
      setOpen(true);
    };
    window.addEventListener(OPEN_ASSISTANT_EVENT, onOpen);
    return () => window.removeEventListener(OPEN_ASSISTANT_EVENT, onOpen);
  }, []);

  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [open]);

  async function generateReview() {
    setLoading(true);
    setReview(null);
    try {
      const res = await api.post<{ markdown: string }>("/ai/review", { month });
      setReview(res.markdown);
    } catch (err) {
      toast.error(
        err instanceof ApiError ? err.message : "Failed to generate review",
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      {/* Desktop only   mobile uses top bar / bottom nav so tabs stay clear */}
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="fixed bottom-6 right-6 z-40 hidden h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-primary to-accent text-white shadow-lg shadow-primary/25 transition-transform hover:scale-[1.03] active:scale-95 lg:flex"
        aria-label="Open AI assistant"
      >
        <Sparkles className="h-6 w-6" />
      </button>

      {open && (
        <div className="fixed inset-0 z-[70] flex items-end justify-center sm:items-center sm:p-4">
          <button
            type="button"
            className="absolute inset-0 bg-black/50 backdrop-blur-sm"
            aria-label="Close assistant"
            onClick={() => setOpen(false)}
          />
          <div
            className={cn(
              "relative z-10 flex w-full flex-col overflow-hidden border-border bg-surface shadow-2xl animate-in",
              "max-h-[min(92dvh,920px)] rounded-t-3xl border-t sm:max-h-[90vh] sm:max-w-lg sm:rounded-2xl sm:border",
            )}
            role="dialog"
            aria-modal="true"
            aria-label="Money assistant"
          >
            <div className="flex justify-center pt-2 sm:hidden" aria-hidden>
              <span className="h-1 w-10 rounded-full bg-border" />
            </div>

            <div className="flex items-center justify-between px-5 pb-3 pt-2 sm:border-b sm:border-border sm:py-4">
              <div className="flex items-center gap-2.5">
                <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary/10 text-primary">
                  <Sparkles className="h-4.5 w-4.5" />
                </span>
                <div>
                  <p className="font-semibold leading-tight">Money assistant</p>
                  <p className="text-[11px] text-muted">
                    Ask about your finances
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setOpen(false)}
                className="rounded-xl p-2 text-muted transition-colors hover:bg-surface-muted hover:text-foreground"
                aria-label="Close"
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="mx-4 mb-3 flex rounded-xl border border-border bg-surface-muted/50 p-1 sm:mx-5">
              {(["ask", "review"] as const).map((t) => (
                <button
                  key={t}
                  type="button"
                  onClick={() => setTab(t)}
                  className={cn(
                    "flex flex-1 items-center justify-center gap-2 rounded-lg py-2 text-sm font-medium transition-all",
                    tab === t
                      ? "bg-surface text-foreground shadow-sm"
                      : "text-muted hover:text-foreground",
                  )}
                >
                  {t === "ask" ? (
                    <MessageCircle className="h-4 w-4" />
                  ) : (
                    <FileText className="h-4 w-4" />
                  )}
                  {t === "ask" ? "Ask" : "Review"}
                </button>
              ))}
            </div>

            <div className="flex-1 overflow-y-auto px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))]">
              {tab === "ask" ? (
                <AskWidget compact />
              ) : (
                <div className="space-y-4 pb-2">
                  <div className="flex flex-wrap items-end gap-3">
                    <div>
                      <label className="mb-1.5 block text-sm font-medium">
                        Month
                      </label>
                      <Input
                        type="month"
                        value={month}
                        max={currentMonth()}
                        onChange={(e) => setMonth(e.target.value)}
                        className="w-44"
                      />
                    </div>
                    <Button
                      onClick={generateReview}
                      loading={loading}
                      size="sm"
                    >
                      Generate for {formatMonth(month)}
                    </Button>
                  </div>
                  {loading && (
                    <div className="flex items-center gap-2 py-6 text-sm text-muted">
                      <Spinner /> Writing your review…
                    </div>
                  )}
                  {review && (
                    <div className="rounded-xl border border-border bg-surface-muted/30 p-4">
                      <Markdown content={review} />
                    </div>
                  )}
                  <p className="text-xs text-muted">
                    <Link
                      href="/settings"
                      className="text-primary hover:underline"
                    >
                      Configure AI keys
                    </Link>{" "}
                    in Settings.
                  </p>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
