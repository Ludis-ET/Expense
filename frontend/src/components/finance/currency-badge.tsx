"use client";

import { Coins } from "lucide-react";
import { cn } from "@/lib/utils";
import { useCurrencyView } from "@/lib/currency-view-context";

/** Shows the active currency on feature pages (selection is in the header). */
export function CurrencyBadge({
  className,
  showIcon = true,
}: {
  className?: string;
  showIcon?: boolean;
}) {
  const { activeCurrency } = useCurrencyView();

  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-primary",
        className,
      )}
      title={`Showing amounts in ${activeCurrency}`}
    >
      {showIcon && <Coins className="h-3 w-3" aria-hidden />}
      {activeCurrency}
    </span>
  );
}

/** Short hint for page descriptions. */
export function currencyScopeHint(currency: string) {
  return `Amounts shown in ${currency} only   switch currency in the header.`;
}
