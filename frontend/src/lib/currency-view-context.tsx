'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';

export interface CurrencyBreakdown {
  currency: string;
  totalBalance: string;
  accountCount: number;
  month: {
    month: string;
    income: string;
    expense: string;
    net: string;
    incomeDeltaPct: number | null;
    expenseDeltaPct: number | null;
    avgDailySpend: string;
    currency?: string;
  };
}

export interface ConvertedTotal {
  amount: string;
  baseCurrency: string;
  complete: boolean;
  missingRates: string[];
}

interface CurrencyViewContextValue {
  currencies: string[];
  activeIndex: number;
  activeCurrency: string;
  breakdown: CurrencyBreakdown[];
  convertedTotal: ConvertedTotal | null;
  setFromDashboard: (currencies: string[], breakdown: CurrencyBreakdown[], converted?: ConvertedTotal | null) => void;
  mergeCurrencies: (list: string[]) => void;
  setActiveCurrency: (currency: string) => void;
  nextCurrency: () => void;
  prevCurrency: () => void;
  hasMultiple: boolean;
  activeBreakdown: CurrencyBreakdown | null;
}

const CurrencyViewContext = createContext<CurrencyViewContextValue | null>(null);

export function CurrencyViewProvider({ children, defaultCurrency = 'ETB' }: { children: ReactNode; defaultCurrency?: string }) {
  const [currencies, setCurrencies] = useState<string[]>([defaultCurrency]);
  const [breakdown, setBreakdown] = useState<CurrencyBreakdown[]>([]);
  const [convertedTotal, setConvertedTotal] = useState<ConvertedTotal | null>(null);
  const [activeIndex, setActiveIndex] = useState(0);

  const activeCurrency = currencies[activeIndex] ?? defaultCurrency;

  const setFromDashboard = useCallback(
    (list: string[], items: CurrencyBreakdown[], converted?: ConvertedTotal | null) => {
      const next = list.length > 0 ? list : [defaultCurrency];
      setCurrencies(next);
      setBreakdown(items);
      setConvertedTotal(converted ?? null);
      setActiveIndex((i) => Math.min(i, next.length - 1));
    },
    [defaultCurrency],
  );

  const mergeCurrencies = useCallback(
    (list: string[]) => {
      if (list.length === 0) return;
      setCurrencies((prev) => {
        const merged = [...new Set([...prev, ...list.map((c) => c.toUpperCase())])];
        return merged.length > 0 ? merged : [defaultCurrency];
      });
    },
    [defaultCurrency],
  );

  const setActiveCurrency = useCallback(
    (currency: string) => {
      const idx = currencies.indexOf(currency.toUpperCase());
      if (idx >= 0) setActiveIndex(idx);
    },
    [currencies],
  );

  const nextCurrency = useCallback(() => {
    setActiveIndex((i) => (currencies.length <= 1 ? i : (i + 1) % currencies.length));
  }, [currencies.length]);

  const prevCurrency = useCallback(() => {
    setActiveIndex((i) => (currencies.length <= 1 ? i : (i - 1 + currencies.length) % currencies.length));
  }, [currencies.length]);

  useEffect(() => {
    if (activeIndex >= currencies.length) setActiveIndex(0);
  }, [activeIndex, currencies.length]);

  const activeBreakdown = breakdown.find((b) => b.currency === activeCurrency) ?? breakdown[activeIndex] ?? null;

  const value = useMemo(
    (): CurrencyViewContextValue => ({
      currencies,
      activeIndex,
      activeCurrency,
      breakdown,
      convertedTotal,
      setFromDashboard,
      mergeCurrencies,
      setActiveCurrency,
      nextCurrency,
      prevCurrency,
      hasMultiple: currencies.length > 1,
      activeBreakdown,
    }),
    [
      currencies,
      activeIndex,
      activeCurrency,
      breakdown,
      convertedTotal,
      setFromDashboard,
      mergeCurrencies,
      setActiveCurrency,
      nextCurrency,
      prevCurrency,
      activeBreakdown,
    ],
  );

  return <CurrencyViewContext.Provider value={value}>{children}</CurrencyViewContext.Provider>;
}

export function useCurrencyView() {
  const ctx = useContext(CurrencyViewContext);
  if (!ctx) throw new Error('useCurrencyView must be used within CurrencyViewProvider');
  return ctx;
}
