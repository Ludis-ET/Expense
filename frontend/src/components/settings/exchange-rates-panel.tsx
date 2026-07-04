'use client';

import { useEffect, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Plus, Trash2 } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Field, Input, Select } from '@/components/ui/input';
import { api, ApiError } from '@/lib/api';

const CURRENCIES = ['ETB', 'USD', 'EUR', 'GBP', 'KES', 'AED'];

interface RateRow {
  id: string;
  fromCurrency: string;
  toCurrency: string;
  rate: string;
}

interface RatesResp {
  baseCurrency: string;
  currencies: string[];
  rates: RateRow[];
}

export function ExchangeRatesPanel() {
  const { data, mutate } = useSWR<RatesResp>('/exchange-rates');
  const [from, setFrom] = useState('USD');
  const [to, setTo] = useState('ETB');
  const [rate, setRate] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (data?.baseCurrency) setTo(data.baseCurrency);
  }, [data?.baseCurrency]);

  async function save() {
    const n = Number(rate);
    if (!Number.isFinite(n) || n <= 0) return toast.error('Enter a valid rate');
    setSaving(true);
    try {
      await api.put('/exchange-rates', { rates: [{ fromCurrency: from, toCurrency: to, rate: n }] });
      toast.success('Exchange rate saved');
      setRate('');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  async function remove(id: string) {
    try {
      await api.del(`/exchange-rates/${id}`);
      toast.success('Rate removed');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Exchange rates</CardTitle>
        <CardDescription>
          Santim never mixes currencies without a rate you set. Use these to convert totals in your default currency ({data?.baseCurrency ?? 'ETB'}).
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid gap-3 sm:grid-cols-[1fr_1fr_1fr_auto] sm:items-end">
          <Field label="From">
            <Select value={from} onChange={(e) => setFrom(e.target.value)}>
              {CURRENCIES.map((c) => (
                <option key={c} value={c}>{c}</option>
              ))}
            </Select>
          </Field>
          <Field label="To">
            <Select value={to} onChange={(e) => setTo(e.target.value)}>
              {CURRENCIES.map((c) => (
                <option key={c} value={c}>{c}</option>
              ))}
            </Select>
          </Field>
          <Field label="Rate (1 unit = ?)">
            <Input value={rate} onChange={(e) => setRate(e.target.value)} placeholder="e.g. 56.5" inputMode="decimal" />
          </Field>
          <Button onClick={() => void save()} loading={saving} className="sm:mb-0">
            <Plus className="h-4 w-4" /> Add
          </Button>
        </div>

        {!data ? (
          <p className="text-sm text-muted">Loading rates…</p>
        ) : data.rates.length === 0 ? (
          <p className="rounded-xl border border-dashed border-border px-4 py-6 text-center text-sm text-muted">
            No rates yet. Add one above (e.g. 1 USD = 56.5 ETB).
          </p>
        ) : (
          <ul className="divide-y divide-border rounded-xl border border-border">
            {data.rates.map((r) => (
              <li key={r.id} className="flex items-center justify-between gap-3 px-4 py-3 text-sm">
                <span>
                  1 <strong>{r.fromCurrency}</strong> = {Number(r.rate).toLocaleString()} <strong>{r.toCurrency}</strong>
                </span>
                <button
                  type="button"
                  onClick={() => void remove(r.id)}
                  className="rounded-lg p-1.5 text-muted hover:bg-surface-muted hover:text-danger"
                  aria-label={`Delete ${r.fromCurrency} to ${r.toCurrency} rate`}
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              </li>
            ))}
          </ul>
        )}

        {data && data.currencies.length > 1 && (
          <p className="text-xs text-muted">
            Your wallets use: {data.currencies.join(', ')}. Each is tracked separately on the dashboard.
          </p>
        )}
      </CardContent>
    </Card>
  );
}
