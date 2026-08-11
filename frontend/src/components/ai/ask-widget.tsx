'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { ArrowUp, Eraser, Sparkles } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Spinner } from '@/components/ui/misc';
import { Donut, type DonutSlice } from '@/components/charts/donut';
import { BarChart } from '@/components/charts/bar';
import { api, ApiError } from '@/lib/api';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';

interface ChartPayload {
  type: 'bar' | 'donut';
  title: string;
  data: { label: string; value: number }[];
}

interface ChatMessage {
  id: string;
  role: 'user' | 'assistant' | 'error';
  text: string;
  chart?: ChartPayload;
  provider?: string;
  at: string;
}

const STORAGE_KEY = 'santim_ai_chat_v1';
const MAX_STORED = 60;
const PALETTE = ['#059669', '#0ea5e9', '#f59e0b', '#8b5cf6', '#ec4899', '#14b8a6', '#ef4444'];

const SUGGESTIONS = [
  'How much did I spend on transport this month?',
  'What are my top 3 spending categories?',
  'Am I saving more or less than last month?',
  'Where is my money leaking?',
];

function loadMessages(): ChatMessage[] {
  if (typeof window === 'undefined') return [];
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as ChatMessage[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveMessages(messages: ChatMessage[]) {
  try {
    const slice = messages.slice(-MAX_STORED);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(slice));
  } catch {
    /* ignore quota */
  }
}

export function AskWidget({ compact = false }: { compact?: boolean }) {
  const { money } = useMoney();
  const [question, setQuestion] = useState('');
  const [loading, setLoading] = useState(false);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [hydrated, setHydrated] = useState(false);
  const [needsKey, setNeedsKey] = useState(false);
  const endRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setMessages(loadMessages());
    setHydrated(true);
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    saveMessages(messages);
  }, [messages, hydrated]);

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' });
  }, [messages, loading]);

  async function ask(q: string) {
    const text = q.trim();
    if (!text || loading) return;

    const userMsg: ChatMessage = {
      id: `u-${Date.now()}`,
      role: 'user',
      text,
      at: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, userMsg]);
    setQuestion('');
    setLoading(true);
    setNeedsKey(false);

    try {
      const result = await api.post<{
        answer: string;
        chart?: ChartPayload;
        provider: string;
      }>('/ai/ask', { question: text });
      setMessages((prev) => [
        ...prev,
        {
          id: `a-${Date.now()}`,
          role: 'assistant',
          text: result.answer || 'No answer came back.',
          chart: result.chart,
          provider: result.provider,
          at: new Date().toISOString(),
        },
      ]);
    } catch (err) {
      const message = err instanceof ApiError ? err.message : 'Something went wrong';
      if (message.toLowerCase().includes('no ai provider')) setNeedsKey(true);
      setMessages((prev) => [
        ...prev,
        {
          id: `e-${Date.now()}`,
          role: 'error',
          text: message,
          at: new Date().toISOString(),
        },
      ]);
    } finally {
      setLoading(false);
    }
  }

  function clearChat() {
    setMessages([]);
    try {
      localStorage.removeItem(STORAGE_KEY);
    } catch {
      /* ignore */
    }
  }

  const thread = (
    <div className={cn('flex flex-col', compact ? 'min-h-[320px]' : 'min-h-[420px]')}>
      <div className="mb-3 flex items-center justify-between gap-2">
        <p className="text-xs text-muted">
          {messages.length > 0 ? 'Chat saved in this browser' : 'Ask anything about your money'}
        </p>
        {messages.length > 0 && (
          <button
            type="button"
            onClick={clearChat}
            className="inline-flex items-center gap-1.5 rounded-lg px-2 py-1 text-xs font-medium text-muted transition-colors hover:bg-surface-muted hover:text-foreground"
          >
            <Eraser className="h-3.5 w-3.5" />
            Clear
          </button>
        )}
      </div>

      <div className="flex-1 space-y-3 overflow-y-auto pr-1">
        {messages.length === 0 && !loading && (
          <div className="space-y-3 py-2">
            <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-primary to-accent text-white shadow-lg shadow-primary/25">
              <Sparkles className="h-6 w-6" />
            </div>
            <p className="text-center text-sm font-semibold">Your money, in conversation</p>
            <p className="text-center text-xs text-muted">
              Answers come from your figures. Chats stay on this device.
            </p>
            <div className="flex flex-wrap justify-center gap-2 pt-1">
              {SUGGESTIONS.map((s) => (
                <button
                  key={s}
                  type="button"
                  onClick={() => void ask(s)}
                  className="rounded-full border border-border bg-surface px-3 py-1.5 text-left text-xs text-muted transition-colors hover:border-primary/40 hover:bg-primary/5 hover:text-foreground"
                >
                  {s}
                </button>
              ))}
            </div>
          </div>
        )}

        {messages.map((m) => (
          <MessageBubble key={m.id} message={m} money={money} />
        ))}

        {loading && (
          <div className="flex items-start gap-2">
            <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-primary to-accent text-white">
              <Sparkles className="h-3.5 w-3.5" />
            </span>
            <div className="rounded-2xl rounded-bl-md border border-border bg-surface px-3.5 py-3 text-sm text-muted shadow-sm">
              <span className="inline-flex items-center gap-2">
                <Spinner className="h-3.5 w-3.5" /> Thinking…
              </span>
            </div>
          </div>
        )}
        <div ref={endRef} />
      </div>

      {needsKey && (
        <div className="mt-3 rounded-lg bg-danger/10 px-3 py-2 text-xs text-danger">
          No AI provider configured.{' '}
          <Link href="/settings" className="font-medium underline">
            Add a key →
          </Link>
        </div>
      )}

      <form
        onSubmit={(e) => {
          e.preventDefault();
          void ask(question);
        }}
        className="mt-3 flex gap-2"
      >
        <input
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          placeholder="Ask about your money…"
          className="h-11 flex-1 rounded-xl border border-border bg-surface-muted/60 px-3.5 text-sm outline-none transition-shadow focus:border-primary/40 focus:ring-2 focus:ring-ring/40"
        />
        <Button type="submit" loading={loading} size="md" className="h-11 w-11 shrink-0 rounded-full p-0">
          <ArrowUp className="h-4 w-4" />
        </Button>
      </form>
    </div>
  );

  if (compact) return thread;

  return (
    <Card className="overflow-hidden">
      <div className="flex items-center gap-2 border-b border-border bg-gradient-to-r from-primary/10 to-accent/10 px-5 py-3">
        <Sparkles className="h-4.5 w-4.5 text-primary" />
        <span className="text-sm font-semibold">Ask Santim</span>
      </div>
      <CardContent className="pt-4">{thread}</CardContent>
    </Card>
  );
}

function MessageBubble({
  message,
  money,
}: {
  message: ChatMessage;
  money: (v: string | number) => string;
}) {
  const isUser = message.role === 'user';
  const isError = message.role === 'error';
  const slices: DonutSlice[] =
    message.chart?.data.map((d, i) => ({
      label: d.label,
      value: d.value,
      color: PALETTE[i % PALETTE.length]!,
    })) ?? [];

  return (
    <div className={cn('flex items-end gap-2', isUser && 'justify-end')}>
      {!isUser && (
        <span className="mb-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-primary to-accent text-white">
          <Sparkles className="h-3.5 w-3.5" />
        </span>
      )}
      <div
        className={cn(
          'max-w-[88%] rounded-2xl px-3.5 py-2.5 text-sm leading-relaxed shadow-sm',
          isUser && 'rounded-br-md bg-gradient-to-br from-primary to-accent text-white',
          isError && 'rounded-bl-md border border-danger/20 bg-danger/10 text-danger',
          !isUser && !isError && 'rounded-bl-md border border-border bg-surface text-foreground',
        )}
      >
        <p className="whitespace-pre-wrap">{message.text}</p>
        {message.chart && slices.length > 0 && (
          <div className="mt-3 rounded-xl border border-border/70 bg-background/40 p-3">
            <p className="mb-2 text-xs font-semibold opacity-80">{message.chart.title}</p>
            {message.chart.type === 'donut' ? (
              <Donut data={slices} format={money} centerLabel="total" />
            ) : (
              <BarChart data={message.chart.data} format={money} />
            )}
          </div>
        )}
        {message.provider && (
          <p className="mt-1.5 text-[10px] opacity-70">via {message.provider}</p>
        )}
      </div>
    </div>
  );
}
