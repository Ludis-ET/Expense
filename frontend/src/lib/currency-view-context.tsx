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

const STORAGE_KEY = 'santim-active-currency';

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
  activeCurrency: string;
  breakdown: CurrencyBreakdown[];
  convertedTotal: ConvertedTotal | null;
  setFromDashboard: (currencies: string[], breakdown: CurrencyBreakdown[], converted?: ConvertedTotal | null) => void;
  mergeCurrencies: (list: string[]) => void;
  setActiveCurrency: (currency: string) => void;
  hasMultiple: boolean;
  activeBreakdown: CurrencyBreakdown | null;
}

const CurrencyViewContext = createContext<CurrencyViewContextValue | null>(null);

export function CurrencyViewProvider({ children, defaultCurrency = 'ETB' }: { children: ReactNode; defaultCurrency?: string }) {
  const [currencies, setCurrencies] = useState<string[]>([defaultCurrency]);
  const [breakdown, setBreakdown] = useState<CurrencyBreakdown[]>([]);
  const [convertedTotal, setConvertedTotal] = useState<ConvertedTotal | null>(null);
  const [activeCurrency, setActiveCurrencyState] = useState(defaultCurrency);

  useEffect(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) setActiveCurrencyState(saved.toUpperCase());
    } catch {
      /* ignore */
    }
  }, []);

  const persistCurrency = useCallback((currency: string) => {
    try {
      localStorage.setItem(STORAGE_KEY, currency);
    } catch {
      /* ignore */
    }
  }, []);

  const setFromDashboard = useCallback(
    (list: string[], items: CurrencyBreakdown[], converted?: ConvertedTotal | null) => {
      const next = list.length > 0 ? list : [defaultCurrency];
      setCurrencies(next);
      setBreakdown(items);
      setConvertedTotal(converted ?? null);
      setActiveCurrencyState((prev) => {
        if (next.includes(prev)) return prev;
        if (next.includes(defaultCurrency)) return defaultCurrency;
        return next[0]!;
      });
    },
    [defaultCurrency],
  );

  const mergeCurrencies = useCallback(
    (list: string[]) => {
      if (list.length === 0) return;
      setCurrencies((prev) => {
        const merged = [...new Set([...prev, ...list.map((c) => c.toUpperCase())])].sort();
        return merged.length > 0 ? merged : [defaultCurrency];
      });
    },
    [defaultCurrency],
  );

  const setActiveCurrency = useCallback(
    (currency: string) => {
      const c = currency.toUpperCase();
      setCurrencies((prev) => (prev.includes(c) ? prev : [...prev, c].sort()));
      setActiveCurrencyState(c);
      persistCurrency(c);
    },
    [persistCurrency],
  );

  const activeBreakdown = breakdown.find((b) => b.currency === activeCurrency) ?? null;

  const value = useMemo(
    (): CurrencyViewContextValue => ({
      currencies,
      activeCurrency,
      breakdown,
      convertedTotal,
      setFromDashboard,
      mergeCurrencies,
      setActiveCurrency,
      hasMultiple: currencies.length > 1,
      activeBreakdown,
    }),
    [
      currencies,
      activeCurrency,
      breakdown,
      convertedTotal,
      setFromDashboard,
      mergeCurrencies,
      setActiveCurrency,
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

/** Safe read when provider may be absent (auth pages). */
export function useOptionalActiveCurrency(fallback = 'ETB') {
  const ctx = useContext(CurrencyViewContext);
  return ctx?.activeCurrency ?? fallback;
}
