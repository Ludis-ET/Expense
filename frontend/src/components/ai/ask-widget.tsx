'use client';

import { useState } from 'react';
import Link from 'next/link';
import { CornerDownLeft, Sparkles } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/misc';
import { Donut, type DonutSlice } from '@/components/charts/donut';
import { BarChart } from '@/components/charts/bar';
import { api, ApiError } from '@/lib/api';
import { formatMoney } from '@/lib/format';
import { useAuth } from '@/lib/auth';

interface AskResult {
  answer: string;
  chart?: { type: 'bar' | 'donut'; title: string; data: { label: string; value: number }[] };
  provider: string;
}

const PALETTE = ['#6366f1', '#10b981', '#f59e0b', '#0ea5e9', '#ef4444', '#a78bfa', '#ec4899'];

const SUGGESTIONS = [
  'How much did I spend on transport this month?',
  'What are my top 3 spending categories?',
  'Am I saving more or less than last month?',
  'Where is my money leaking?',
];

export function AskWidget() {
  const { user } = useAuth();
  const currency = user?.currency ?? 'ETB';
  const [question, setQuestion] = useState('');
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<AskResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [needsKey, setNeedsKey] = useState(false);

  async function ask(q: string) {
    if (!q.trim()) return;
    setLoading(true);
    setError(null);
    setResult(null);
    setNeedsKey(false);
    try {
      setResult(await api.post<AskResult>('/ai/ask', { question: q }));
    } catch (err) {
      const message = err instanceof ApiError ? err.message : 'Something went wrong';
      setError(message);
      if (message.toLowerCase().includes('no ai provider')) setNeedsKey(true);
    } finally {
      setLoading(false);
    }
  }

  const slices: DonutSlice[] =
    result?.chart?.data.map((d, i) => ({ label: d.label, value: d.value, color: PALETTE[i % PALETTE.length]! })) ?? [];

  return (
    <Card className="overflow-hidden">
      <div className="flex items-center gap-2 border-b border-border bg-gradient-to-r from-primary/10 to-accent/10 px-5 py-3">
        <Sparkles className="h-4.5 w-4.5 text-primary" />
        <span className="text-sm font-semibold">Ask about your money</span>
        {result && <span className="ml-auto text-xs text-muted">via {result.provider}</span>}
      </div>
      <CardContent className="space-y-4">
        <form
          onSubmit={(e) => {
            e.preventDefault();
            void ask(question);
          }}
          className="flex gap-2"
        >
          <input
            value={question}
            onChange={(e) => setQuestion(e.target.value)}
            placeholder="e.g. How much did I spend on food this month?"
            className="h-10 flex-1 rounded-lg border border-border bg-surface px-3.5 text-sm outline-none focus:ring-2 focus:ring-ring/60"
          />
          <Button type="submit" loading={loading} size="md">
            <CornerDownLeft className="h-4 w-4" /> Ask
          </Button>
        </form>

        {!result && !loading && !error && (
          <div className="flex flex-wrap gap-2">
            {SUGGESTIONS.map((s) => (
              <button
                key={s}
                onClick={() => {
                  setQuestion(s);
                  void ask(s);
                }}
                className="rounded-full border border-border px-3 py-1.5 text-xs text-muted transition-colors hover:bg-surface-muted hover:text-foreground"
              >
                {s}
              </button>
            ))}
          </div>
        )}

        {loading && (
          <div className="flex items-center gap-2 py-4 text-sm text-muted">
            <Spinner className="h-4 w-4" /> Thinking about your finances…
          </div>
        )}

        {error && (
          <div className="rounded-lg bg-danger/10 px-4 py-3 text-sm text-danger">
            {error}
            {needsKey && (
              <>
                {' '}
                <Link href="/settings" className="font-medium underline">
                  Configure an AI provider →
                </Link>
              </>
            )}
          </div>
        )}

        {result && (
          <div className="space-y-4">
            <p className="whitespace-pre-wrap text-sm leading-relaxed">{result.answer}</p>
            {result.chart && slices.length > 0 && (
              <div className="rounded-xl border border-border p-4">
                <p className="mb-3 text-sm font-medium">{result.chart.title}</p>
                {result.chart.type === 'donut' ? (
                  <Donut data={slices} format={(v) => formatMoney(v, currency)} centerLabel="total" />
                ) : (
                  <BarChart data={result.chart.data} />
                )}
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
