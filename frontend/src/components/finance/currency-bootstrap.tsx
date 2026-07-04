'use client';

import { useEffect } from 'react';
import useSWR from 'swr';
import { useCurrencyView } from '@/lib/currency-view-context';
import type { Account } from '@/lib/types';

/** Loads account currencies into the global header selector. */
export function CurrencyBootstrap() {
  const { mergeCurrencies } = useCurrencyView();
  const { data } = useSWR<{ items: Account[] }>('/accounts');

  useEffect(() => {
    if (!data?.items) return;
    mergeCurrencies(data.items.filter((a) => !a.archived).map((a) => a.currency));
  }, [data, mergeCurrencies]);

  return null;
}
