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
import { formatHiddenMoney, formatMoney, formatSignedMoney, type MoneyFormatOpts } from '@/lib/format';
import { useAuth } from '@/lib/auth';

const STORAGE_KEY = 'santim-hide-amounts';

interface AmountVisibilityContextValue {
  hidden: boolean;
  toggle: () => void;
  setHidden: (hidden: boolean) => void;
}

const AmountVisibilityContext = createContext<AmountVisibilityContextValue | null>(null);

export function AmountVisibilityProvider({ children }: { children: ReactNode }) {
  const [hidden, setHiddenState] = useState(false);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    try {
      setHiddenState(localStorage.getItem(STORAGE_KEY) === '1');
    } catch {
      /* ignore */
    }
    setReady(true);
  }, []);

  const setHidden = useCallback((value: boolean) => {
    setHiddenState(value);
    try {
      localStorage.setItem(STORAGE_KEY, value ? '1' : '0');
    } catch {
      /* ignore */
    }
  }, []);

  const toggle = useCallback(() => {
    setHiddenState((prev) => {
      const next = !prev;
      try {
        localStorage.setItem(STORAGE_KEY, next ? '1' : '0');
      } catch {
        /* ignore */
      }
      return next;
    });
  }, []);

  const value = useMemo(
    () => ({ hidden: ready ? hidden : false, toggle, setHidden }),
    [hidden, toggle, setHidden, ready],
  );

  return <AmountVisibilityContext.Provider value={value}>{children}</AmountVisibilityContext.Provider>;
}

export function useAmountVisibility() {
  const ctx = useContext(AmountVisibilityContext);
  if (!ctx) throw new Error('useAmountVisibility must be used within AmountVisibilityProvider');
  return ctx;
}

export function useMoney(currency?: string) {
  const { user } = useAuth();
  const { hidden } = useAmountVisibility();
  const curr = currency ?? user?.currency ?? 'ETB';

  const money = useCallback(
    (v: number | string, opts?: MoneyFormatOpts) =>
      hidden ? formatHiddenMoney(curr) : formatMoney(v, curr, opts),
    [hidden, curr],
  );

  const signedMoney = useCallback(
    (amount: number | string, kind: 'INCOME' | 'EXPENSE' | 'TRANSFER', c?: string) => {
      const currencyCode = c ?? curr;
      if (hidden) {
        const masked = formatHiddenMoney(currencyCode);
        if (kind === 'INCOME') return `+${masked}`;
        if (kind === 'EXPENSE') return `−${masked}`;
        return masked;
      }
      return formatSignedMoney(amount, kind, currencyCode);
    },
    [hidden, curr],
  );

  return { money, signedMoney, hidden };
}
