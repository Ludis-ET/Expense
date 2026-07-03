'use client';

import { useEffect, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { toast } from 'sonner';
import { FileText, MessageCircle, Sparkles, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Spinner } from '@/components/ui/misc';
import { AskWidget } from '@/components/ai/ask-widget';
import { Markdown } from '@/components/markdown';
import { currentMonth } from '@/components/finance/month-navigator';
import { api, ApiError } from '@/lib/api';
import { formatMonth } from '@/lib/format';
import { cn } from '@/lib/utils';

export function AssistantFab() {
  const params = useSearchParams();
  const [open, setOpen] = useState(false);
  const [tab, setTab] = useState<'ask' | 'review'>('ask');
  const [month, setMonth] = useState(currentMonth());
  const [review, setReview] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (params.get('assistant')) setOpen(true);
  }, [params]);

  async function generateReview() {
    setLoading(true);
    setReview(null);
    try {
      const res = await api.post<{ markdown: string }>('/ai/review', { month });
      setReview(res.markdown);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to generate review');
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="fixed bottom-6 right-6 z-50 flex h-14 w-14 items-center justify-center rounded-full bg-gradient-to-br from-primary to-accent text-white shadow-lg shadow-primary/30 transition-transform hover:scale-105"
        aria-label="Open AI assistant"
      >
        <Sparkles className="h-6 w-6" />
      </button>

      {open && (
        <div className="fixed inset-0 z-[70] flex items-end justify-end p-4 sm:items-center sm:justify-center">
          <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" onClick={() => setOpen(false)} />
          <div className="relative z-10 flex max-h-[90vh] w-full max-w-lg flex-col overflow-hidden rounded-2xl border border-border bg-surface shadow-2xl animate-in">
            <div className="flex items-center justify-between border-b border-border px-5 py-4">
              <div className="flex items-center gap-2">
                <Sparkles className="h-5 w-5 text-primary" />
                <span className="font-semibold">Money assistant</span>
              </div>
              <button onClick={() => setOpen(false)} className="rounded-lg p-1.5 text-muted hover:bg-surface-muted" aria-label="Close">
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="flex border-b border-border">
              {(['ask', 'review'] as const).map((t) => (
                <button
                  key={t}
                  onClick={() => setTab(t)}
                  className={cn(
                    'flex flex-1 items-center justify-center gap-2 py-3 text-sm font-medium transition-colors',
                    tab === t ? 'border-b-2 border-primary text-primary' : 'text-muted hover:text-foreground',
                  )}
                >
                  {t === 'ask' ? <MessageCircle className="h-4 w-4" /> : <FileText className="h-4 w-4" />}
                  {t === 'ask' ? 'Ask' : 'Monthly review'}
                </button>
              ))}
            </div>

            <div className="flex-1 overflow-y-auto p-5">
              {tab === 'ask' ? (
                <AskWidget compact />
              ) : (
                <div className="space-y-4">
                  <div className="flex flex-wrap items-end gap-3">
                    <div>
                      <label className="mb-1.5 block text-sm font-medium">Month</label>
                      <Input type="month" value={month} max={currentMonth()} onChange={(e) => setMonth(e.target.value)} className="w-44" />
                    </div>
                    <Button onClick={generateReview} loading={loading} size="sm">
                      Generate for {formatMonth(month)}
                    </Button>
                  </div>
                  {loading && (
                    <div className="flex items-center gap-2 py-6 text-sm text-muted">
                      <Spinner /> Writing your review…
                    </div>
                  )}
                  {review && (
                    <div className="rounded-xl border border-border bg-surface-muted/30 p-4">
                      <Markdown content={review} />
                    </div>
                  )}
                  <p className="text-xs text-muted">
                    <Link href="/settings" className="text-primary hover:underline">Configure AI keys</Link> in Settings.
                  </p>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
