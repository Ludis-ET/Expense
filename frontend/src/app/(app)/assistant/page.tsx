'use client';

import { useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { FileText, Sparkles } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { PageHeader, Spinner } from '@/components/ui/misc';
import { AskWidget } from '@/components/ai/ask-widget';
import { Markdown } from '@/components/markdown';
import { currentMonth } from '@/components/finance/month-navigator';
import { api, ApiError } from '@/lib/api';
import { formatMonth } from '@/lib/format';

export default function AssistantPage() {
  const [month, setMonth] = useState(currentMonth());
  const [review, setReview] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [needsKey, setNeedsKey] = useState(false);

  async function generate() {
    setLoading(true);
    setReview(null);
    setNeedsKey(false);
    try {
      const res = await api.post<{ markdown: string }>('/ai/review', { month });
      setReview(res.markdown);
    } catch (err) {
      const message = err instanceof ApiError ? err.message : 'Failed to generate review';
      toast.error(message);
      if (message.toLowerCase().includes('no ai provider')) setNeedsKey(true);
    } finally {
      setLoading(false);
    }
  }

  return (
    <div>
      <PageHeader
        title="Assistant"
        description="Ask questions and get a personalized monthly money review — powered by your own AI key."
      />

      <div className="space-y-6">
        <AskWidget />

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <FileText className="h-4.5 w-4.5 text-primary" /> Monthly review
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="flex flex-wrap items-end gap-3">
              <div>
                <label className="mb-1.5 block text-sm font-medium">Month</label>
                <Input type="month" value={month} max={currentMonth()} onChange={(e) => setMonth(e.target.value)} className="w-48" />
              </div>
              <Button onClick={generate} loading={loading}>
                <Sparkles className="h-4 w-4" /> Generate review for {formatMonth(month)}
              </Button>
            </div>

            {needsKey && (
              <p className="mt-4 text-sm text-danger">
                No AI provider configured.{' '}
                <Link href="/settings" className="font-medium underline">Add a key in Settings →</Link>
              </p>
            )}

            {loading && (
              <div className="flex items-center gap-2 py-8 text-sm text-muted">
                <Spinner /> Writing your review…
              </div>
            )}

            {review && (
              <div className="mt-5 rounded-xl border border-border bg-surface-muted/30 p-5">
                <Markdown content={review} />
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
