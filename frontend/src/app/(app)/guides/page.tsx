"use client";

import { useEffect, useMemo, useState } from "react";
import useSWR from "swr";
import Link from "next/link";
import {
  BookOpen,
  Lightbulb,
  ArrowRight,
  ChevronLeft,
  ChevronRight,
  Clock,
  Check,
  AlertTriangle,
  Sparkles,
} from "lucide-react";
import { PageHeader, Skeleton } from "@/components/ui/misc";
import { Modal } from "@/components/ui/modal";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import type {
  Guide,
  GuideCategory,
  GuidesOverview,
  GuideSuggestion,
} from "@/lib/types";

const CATEGORY_META: Record<
  GuideCategory,
  { label: string; tint: string }
> = {
  "getting-started": {
    label: "Getting started",
    tint: "from-sky-500/15 to-sky-500/5 text-sky-600 dark:text-sky-400",
  },
  saving: {
    label: "Saving",
    tint: "from-emerald-500/15 to-emerald-500/5 text-emerald-600 dark:text-emerald-400",
  },
  spending: {
    label: "Spending",
    tint: "from-amber-500/15 to-amber-500/5 text-amber-600 dark:text-amber-400",
  },
  debt: {
    label: "Debt",
    tint: "from-violet-500/15 to-violet-500/5 text-violet-600 dark:text-violet-400",
  },
};

const TONE_META = {
  tip: { icon: Lightbulb, cls: "text-primary", bg: "bg-primary/10" },
  success: {
    icon: Check,
    cls: "text-emerald-600 dark:text-emerald-400",
    bg: "bg-emerald-500/12",
  },
  warning: {
    icon: AlertTriangle,
    cls: "text-amber-600 dark:text-amber-400",
    bg: "bg-amber-500/12",
  },
} as const;

export default function GuidesPage() {
  const { data, isLoading } = useSWR<GuidesOverview>("/guides");
  const [filter, setFilter] = useState<"all" | GuideCategory>("all");
  const [reading, setReading] = useState<Guide | null>(null);

  const guides = useMemo(() => data?.guides ?? [], [data?.guides]);
  const suggestions = data?.suggestions ?? [];

  const filtered = useMemo(
    () => (filter === "all" ? guides : guides.filter((g) => g.category === filter)),
    [guides, filter],
  );

  const openGuide = (id?: string) => {
    if (!id) return;
    const g = guides.find((x) => x.id === id);
    if (g) setReading(g);
  };

  return (
    <div className="animate-in space-y-6">
      <PageHeader
        title="Guides"
        description="Money stories, saving strategies, and how to get the most from Santim."
      />

      {isLoading ? (
        <div className="space-y-3">
          <Skeleton className="h-28 rounded-2xl" />
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {Array.from({ length: 6 }).map((_, i) => (
              <Skeleton key={i} className="h-44" />
            ))}
          </div>
        </div>
      ) : (
        <>
          {suggestions.length > 0 && (
            <section className="space-y-3">
              <h2 className="flex items-center gap-2 text-sm font-semibold uppercase tracking-widest text-muted">
                <Sparkles className="h-4 w-4 text-primary" /> For you
              </h2>
              <div className="grid gap-3 sm:grid-cols-2">
                {suggestions.map((s) => (
                  <SuggestionCard
                    key={s.id}
                    suggestion={s}
                    onRead={() => openGuide(s.guideId)}
                  />
                ))}
              </div>
            </section>
          )}

          <section className="space-y-4">
            <div className="flex gap-1 overflow-x-auto rounded-xl border border-border p-1">
              {(["all", ...Object.keys(CATEGORY_META)] as const).map((c) => (
                <button
                  key={c}
                  type="button"
                  onClick={() => setFilter(c as "all" | GuideCategory)}
                  className={cn(
                    "min-h-9 shrink-0 rounded-lg px-3 py-1.5 text-xs font-medium capitalize",
                    filter === c
                      ? "bg-primary text-primary-foreground"
                      : "text-muted hover:text-foreground",
                  )}
                >
                  {c === "all" ? "All guides" : CATEGORY_META[c as GuideCategory].label}
                </button>
              ))}
            </div>

            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {filtered.map((g) => (
                <GuideCard key={g.id} guide={g} onOpen={() => setReading(g)} />
              ))}
            </div>
          </section>
        </>
      )}

      <GuideReader guide={reading} onClose={() => setReading(null)} />
    </div>
  );
}

function SuggestionCard({
  suggestion,
  onRead,
}: {
  suggestion: GuideSuggestion;
  onRead: () => void;
}) {
  const tone = TONE_META[suggestion.tone];
  const Icon = tone.icon;
  return (
    <div className="card flex flex-col gap-3 p-4">
      <div className="flex items-start gap-3">
        <span
          className={cn(
            "flex h-9 w-9 shrink-0 items-center justify-center rounded-xl",
            tone.bg,
            tone.cls,
          )}
        >
          <Icon className="h-4.5 w-4.5" />
        </span>
        <div className="min-w-0">
          <p className="font-semibold leading-snug">{suggestion.title}</p>
          <p className="mt-1 text-sm text-muted">{suggestion.body}</p>
        </div>
      </div>
      <div className="mt-auto flex flex-wrap gap-2">
        {suggestion.href && suggestion.cta && (
          <Link href={suggestion.href}>
            <Button size="sm" className="min-h-9">
              {suggestion.cta} <ArrowRight className="h-3.5 w-3.5" />
            </Button>
          </Link>
        )}
        {suggestion.guideId && (
          <Button size="sm" variant="outline" className="min-h-9" onClick={onRead}>
            <BookOpen className="h-3.5 w-3.5" /> Read guide
          </Button>
        )}
      </div>
    </div>
  );
}

function GuideCard({ guide, onOpen }: { guide: Guide; onOpen: () => void }) {
  const meta = CATEGORY_META[guide.category];
  return (
    <button
      type="button"
      onClick={onOpen}
      className="card group flex flex-col p-0 text-left transition-all hover:-translate-y-0.5 hover:shadow-md"
    >
      <div
        className={cn(
          "flex items-center justify-between rounded-t-2xl bg-gradient-to-br p-4",
          meta.tint,
        )}
      >
        <span className="text-4xl">{guide.emoji}</span>
        <span className="rounded-full bg-surface/70 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide">
          {meta.label}
        </span>
      </div>
      <div className="flex flex-1 flex-col p-4">
        <h3 className="font-semibold leading-snug">{guide.title}</h3>
        <p className="mt-1 flex-1 text-sm text-muted">{guide.tagline}</p>
        <div className="mt-3 flex items-center justify-between text-xs text-muted">
          <span className="inline-flex items-center gap-1">
            <Clock className="h-3 w-3" /> {guide.readMins} min read
          </span>
          <span className="inline-flex items-center gap-1 font-medium text-primary">
            Read <ArrowRight className="h-3 w-3 transition-transform group-hover:translate-x-0.5" />
          </span>
        </div>
      </div>
    </button>
  );
}

function GuideReader({
  guide,
  onClose,
}: {
  guide: Guide | null;
  onClose: () => void;
}) {
  const [step, setStep] = useState(0);

  // Reset to the first section whenever a different guide opens.
  useEffect(() => {
    setStep(0);
  }, [guide?.id]);

  if (!guide) {
    return (
      <Modal open={false} onClose={onClose} title="">
        {null}
      </Modal>
    );
  }

  const total = guide.sections.length;
  const activeStep = Math.min(step, total - 1);
  const current = guide.sections[activeStep]!;

  return (
    <Modal
      open={!!guide}
      onClose={onClose}
      title={`${guide.emoji}  ${guide.title}`}
      description={guide.tagline}
    >
      <div className="space-y-4">
        <div className="flex gap-1.5">
          {guide.sections.map((_, i) => (
            <span
              key={i}
              className={cn(
                "h-1 flex-1 rounded-full transition-colors",
                i <= activeStep ? "bg-primary" : "bg-surface-muted",
              )}
            />
          ))}
        </div>

        <div className="min-h-[8rem]">
          <h3 className="font-semibold">{current.heading}</h3>
          <p className="mt-2 text-sm leading-relaxed text-muted">{current.body}</p>
        </div>

        <div className="flex items-center justify-between gap-2">
          <span className="text-xs text-muted">
            {activeStep + 1} / {total}
          </span>
          <div className="flex gap-2">
            <Button
              size="sm"
              variant="outline"
              disabled={activeStep === 0}
              onClick={() => setStep((s) => Math.max(0, s - 1))}
            >
              <ChevronLeft className="h-4 w-4" /> Back
            </Button>
            {activeStep < total - 1 ? (
              <Button size="sm" onClick={() => setStep((s) => Math.min(total - 1, s + 1))}>
                Next <ChevronRight className="h-4 w-4" />
              </Button>
            ) : guide.href ? (
              <Link href={guide.href} onClick={onClose}>
                <Button size="sm">
                  Try it now <ArrowRight className="h-4 w-4" />
                </Button>
              </Link>
            ) : (
              <Button size="sm" onClick={onClose}>
                Done <Check className="h-4 w-4" />
              </Button>
            )}
          </div>
        </div>
      </div>
    </Modal>
  );
}
