'use client';

import { useEffect, useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { ArrowDown, ArrowUp, Check, ExternalLink, X } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Spinner } from '@/components/ui/misc';
import { api, ApiError } from '@/lib/api';
import { cn } from '@/lib/utils';

type ProviderId = 'anthropic' | 'openai' | 'google';

interface CatalogEntry {
  id: ProviderId;
  label: string;
  defaultModel: string;
  keysUrl: string;
}
interface SettingsResponse {
  catalog: CatalogEntry[];
  providers: { id: ProviderId; label: string; model: string; enabled: boolean; hasKey: boolean }[];
}
interface Row {
  id: ProviderId;
  label: string;
  model: string;
  enabled: boolean;
  hasKey: boolean;
  apiKey: string;
  clear: boolean;
}

export function AiProviders() {
  const { data, mutate } = useSWR<SettingsResponse>('/ai/settings');
  const [rows, setRows] = useState<Row[]>([]);
  const [saving, setSaving] = useState(false);
  const [testing, setTesting] = useState<ProviderId | null>(null);

  useEffect(() => {
    if (data) {
      setRows(data.providers.map((p) => ({ ...p, apiKey: '', clear: false })));
    }
  }, [data]);

  const catalogById = new Map((data?.catalog ?? []).map((c) => [c.id, c]));

  function patch(id: ProviderId, change: Partial<Row>) {
    setRows((rs) => rs.map((r) => (r.id === id ? { ...r, ...change } : r)));
  }
  function move(index: number, dir: -1 | 1) {
    setRows((rs) => {
      const next = [...rs];
      const j = index + dir;
      if (j < 0 || j >= next.length) return rs;
      [next[index], next[j]] = [next[j], next[index]];
      return next;
    });
  }

  function buildPayload() {
    return {
      providers: rows.map((r) => ({
        id: r.id,
        model: r.model,
        enabled: r.enabled,
        ...(r.clear ? { apiKey: '' } : r.apiKey ? { apiKey: r.apiKey } : {}),
      })),
    };
  }

  async function save() {
    setSaving(true);
    try {
      await api.put('/ai/settings', buildPayload());
      toast.success('AI settings saved');
      await mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to save');
    } finally {
      setSaving(false);
    }
  }

  async function test(id: ProviderId) {
    setTesting(id);
    try {
      // Persist current edits first so the test uses what the user sees.
      await api.put('/ai/settings', buildPayload());
      await mutate();
      const res = await api.post<{ ok: boolean; error?: string }>('/ai/settings/test', { id });
      if (res.ok) toast.success(`${id} responded successfully`);
      else toast.error(`${id}: ${res.error ?? 'no response'}`);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Test failed');
    } finally {
      setTesting(null);
    }
  }

  if (!data) {
    return (
      <Card>
        <CardContent className="flex justify-center py-10">
          <Spinner />
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>AI providers</CardTitle>
          <CardDescription>
            Add keys for one or more providers. They&apos;re tried top-to-bottom — if the first fails, the next is used.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {rows.map((r, i) => {
          const cat = catalogById.get(r.id);
          return (
            <div
              key={r.id}
              className={cn('rounded-xl border border-border p-4', r.enabled ? 'bg-surface' : 'bg-surface-muted/40')}
            >
              <div className="flex items-center gap-3">
                <div className="flex flex-col">
                  <button
                    onClick={() => move(i, -1)}
                    disabled={i === 0}
                    className="text-muted hover:text-foreground disabled:opacity-30"
                    aria-label="Move up"
                  >
                    <ArrowUp className="h-3.5 w-3.5" />
                  </button>
                  <button
                    onClick={() => move(i, 1)}
                    disabled={i === rows.length - 1}
                    className="text-muted hover:text-foreground disabled:opacity-30"
                    aria-label="Move down"
                  >
                    <ArrowDown className="h-3.5 w-3.5" />
                  </button>
                </div>
                <span className="flex h-6 w-6 items-center justify-center rounded-full bg-primary/10 text-xs font-semibold text-primary">
                  {i + 1}
                </span>
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{r.label}</span>
                    {r.hasKey && (
                      <span className="flex items-center gap-1 text-xs text-emerald-500">
                        <Check className="h-3 w-3" /> key saved
                      </span>
                    )}
                  </div>
                  {cat && (
                    <a
                      href={cat.keysUrl}
                      target="_blank"
                      rel="noreferrer"
                      className="inline-flex items-center gap-1 text-xs text-muted hover:text-primary"
                    >
                      Get an API key <ExternalLink className="h-3 w-3" />
                    </a>
                  )}
                </div>
                <label className="flex cursor-pointer items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={r.enabled}
                    onChange={(e) => patch(r.id, { enabled: e.target.checked })}
                    className="h-4 w-4 accent-[var(--primary)]"
                  />
                  Enabled
                </label>
              </div>

              <div className="mt-3 grid gap-2 sm:grid-cols-[1fr_1fr_auto]">
                <Input
                  value={r.model}
                  onChange={(e) => patch(r.id, { model: e.target.value })}
                  placeholder={cat?.defaultModel}
                  aria-label="Model"
                />
                <Input
                  type="password"
                  value={r.apiKey}
                  onChange={(e) => patch(r.id, { apiKey: e.target.value, clear: false })}
                  placeholder={r.hasKey ? '•••••••• (saved)' : 'Paste API key'}
                  aria-label="API key"
                />
                <div className="flex gap-2">
                  <Button variant="outline" size="md" onClick={() => test(r.id)} loading={testing === r.id} type="button">
                    Test
                  </Button>
                  {r.hasKey && (
                    <Button
                      variant="ghost"
                      size="icon"
                      type="button"
                      onClick={() => patch(r.id, { clear: true, apiKey: '', hasKey: false })}
                      aria-label="Remove key"
                    >
                      <X className="h-4 w-4 text-danger" />
                    </Button>
                  )}
                </div>
              </div>
            </div>
          );
        })}

        <div className="flex justify-end pt-1">
          <Button onClick={save} loading={saving}>
            Save AI settings
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
