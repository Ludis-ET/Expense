"use client";

import { Coins } from "lucide-react";
import { Select } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import { useCurrencyView } from "@/lib/currency-view-context";

interface CurrencySelectorProps {
  className?: string;
  /** Compact styling for the top bar */
  variant?: "header" | "inline";
}

/** Global currency picker   lives in the app header. */
export function CurrencySelector({
  className,
  variant = "header",
}: CurrencySelectorProps) {
  const { activeCurrency, currencies, setActiveCurrency, hasMultiple } =
    useCurrencyView();

  if (!hasMultiple) {
    return (
      <span
        className={cn(
          "inline-flex items-center gap-1.5 rounded-xl border border-border bg-surface-muted/60 px-3 py-2 text-sm font-semibold tabular-nums",
          className,
        )}
        title="Active currency"
      >
        <Coins className="h-4 w-4 text-primary" aria-hidden />
        {activeCurrency}
      </span>
    );
  }

  return (
    <div
      className={cn(
        "inline-flex items-center gap-1.5 rounded-xl border border-border bg-surface-muted/60 transition-colors hover:bg-surface-muted",
        variant === "header" ? "px-2 py-1" : "px-2.5 py-1.5",
        className,
      )}
    >
      <Coins className="h-4 w-4 shrink-0 text-primary" aria-hidden />
      <Select
        variant="ghost"
        value={activeCurrency}
        onChange={(e) => setActiveCurrency(e.target.value)}
        aria-label="Select currency view"
        className="w-auto min-w-[3.5rem]"
        options={currencies.map((c) => ({ value: c, label: c }))}
      />
    </div>
  );
}
