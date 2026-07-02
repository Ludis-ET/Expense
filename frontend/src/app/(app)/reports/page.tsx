'use client';

import { useState } from 'react';
import Link from 'next/link';
import useSWR from 'swr';
import { toast } from 'sonner';
import { FileText, Printer, Sparkles, Wand2 } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Field, Select, Textarea } from '@/components/ui/input';
import { PageHeader, Spinner } from '@/components/ui/misc';
import { Markdown } from '@/components/markdown';
import { Brand } from '@/components/brand';
import { api, ApiError } from '@/lib/api';
import { useAuth } from '@/lib/auth';
import { formatDate } from '@/lib/format';
import type { Project } from '@/lib/types';

interface ProjectList {
  items: Project[];
}
const REPORT_TYPES = [
  { value: 'progress', label: 'Progress report' },
  { value: 'funder', label: 'Funder report' },
  { value: 'proposal', label: 'Proposal / concept note' },
];

export default function ReportsPage() {
  const { user } = useAuth();
  const { data: projects } = useSWR<ProjectList>('/projects');
  const [projectId, setProjectId] = useState('');
  const [type, setType] = useState('progress');
  const [loading, setLoading] = useState(false);
  const [markdown, setMarkdown] = useState('');
  const [provider, setProvider] = useState('');

  async function generate(e: React.FormEvent) {
    e.preventDefault();
    if (!projectId) {
      toast.error('Pick a project first');
      return;
    }
    setLoading(true);
    setMarkdown('');
    try {
      const res = await api.post<{ markdown: string; provider: string }>('/ai/report', { projectId, type });
      setMarkdown(res.markdown);
      setProvider(res.provider);
    } catch (err) {
      const msg = err instanceof ApiError ? err.message : 'Failed to generate';
      toast.error(msg);
      if (msg.toLowerCase().includes('no ai provider')) {
        toast.message('Configure an AI provider in Settings to use this feature.');
      }
    } finally {
      setLoading(false);
    }
  }

  const projectTitle = projects?.items.find((p) => p.id === projectId)?.title ?? '';

  return (
    <div>
      <PageHeader title="Reports" description="Let AI draft reports and proposals from your real project data." />

      <div className="grid gap-6 lg:grid-cols-[320px_1fr]">
        {/* Controls */}
        <div className="space-y-6 no-print">
          <Card>
            <CardHeader>
              <div>
                <CardTitle>AI report writer</CardTitle>
                <CardDescription>Pick a project and a report type.</CardDescription>
              </div>
            </CardHeader>
            <CardContent>
              <form onSubmit={generate} className="space-y-4">
                <Field label="Project">
                  <Select value={projectId} onChange={(e) => setProjectId(e.target.value)} required>
                    <option value="" disabled>
                      Select a project…
                    </option>
                    {projects?.items.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.title}
                      </option>
                    ))}
                  </Select>
                </Field>
                <Field label="Report type">
                  <Select value={type} onChange={(e) => setType(e.target.value)}>
                    {REPORT_TYPES.map((t) => (
                      <option key={t.value} value={t.value}>
                        {t.label}
                      </option>
                    ))}
                  </Select>
                </Field>
                <Button type="submit" loading={loading} className="w-full">
                  <Sparkles className="h-4 w-4" /> Generate
                </Button>
              </form>
            </CardContent>
          </Card>

          <SmartImport />
        </div>

        {/* Output */}
        <Card className="min-h-[400px]">
          {loading ? (
            <div className="flex h-96 flex-col items-center justify-center gap-3 text-muted">
              <Spinner className="h-6 w-6" />
              <p className="text-sm">Drafting your {REPORT_TYPES.find((t) => t.value === type)?.label.toLowerCase()}…</p>
            </div>
          ) : markdown ? (
            <>
              <div className="flex items-center justify-between border-b border-border px-5 py-3 no-print">
                <span className="text-xs text-muted">Generated via {provider} · review before sharing</span>
                <Button size="sm" variant="outline" onClick={() => window.print()}>
                  <Printer className="h-4 w-4" /> Print / PDF
                </Button>
              </div>
              <div className="print-area p-6">
                <div className="mb-6 flex items-center justify-between border-b border-border pb-4">
                  <Brand />
                  <div className="text-right text-xs text-muted">
                    <div className="font-medium text-foreground">{user?.org?.name ?? 'Workspace'}</div>
                    <div>{formatDate(new Date())}</div>
                  </div>
                </div>
                <h1 className="mb-1 text-xl font-bold">{projectTitle}</h1>
                <Markdown content={markdown} />
              </div>
            </>
          ) : (
            <div className="flex h-96 flex-col items-center justify-center gap-3 text-center text-muted">
              <FileText className="h-10 w-10" />
              <p className="max-w-xs text-sm">
                Select a project and click Generate. The report uses only your real milestones, budget and publications.
              </p>
            </div>
          )}
        </Card>
      </div>
    </div>
  );
}

function SmartImport() {
  const [text, setText] = useState('');
  const [loading, setLoading] = useState(false);
  const [fields, setFields] = useState<Record<string, unknown> | null>(null);

  async function extract() {
    if (text.trim().length < 10) {
      toast.error('Paste a bit more text');
      return;
    }
    setLoading(true);
    setFields(null);
    try {
      const res = await api.post<{ fields: Record<string, unknown> }>('/ai/extract', { text });
      setFields(res.fields);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to extract');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Smart import</CardTitle>
          <CardDescription>Paste a citation, abstract or email — AI extracts the fields.</CardDescription>
        </div>
        <Wand2 className="h-5 w-5 text-muted" />
      </CardHeader>
      <CardContent className="space-y-3">
        <Textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Paste reference text here…"
          className="min-h-28"
        />
        <Button onClick={extract} loading={loading} variant="outline" size="sm" className="w-full">
          Extract fields
        </Button>
        {fields && (
          <dl className="space-y-1.5 rounded-lg bg-surface-muted p-3 text-sm">
            {Object.entries(fields).map(([k, v]) => (
              <div key={k} className="flex gap-2">
                <dt className="w-20 shrink-0 text-xs capitalize text-muted">{k}</dt>
                <dd className="min-w-0 flex-1 break-words">{Array.isArray(v) ? v.join(', ') : String(v ?? '—')}</dd>
              </div>
            ))}
          </dl>
        )}
      </CardContent>
    </Card>
  );
}
