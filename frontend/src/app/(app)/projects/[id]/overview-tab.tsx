'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Field, Input, Select, Textarea } from '@/components/ui/input';
import { api, ApiError } from '@/lib/api';
import { formatDate } from '@/lib/format';
import type { ProjectDetail, ProjectStatus } from '@/lib/types';

const STATUSES: ProjectStatus[] = ['PLANNING', 'ACTIVE', 'ON_HOLD', 'COMPLETED', 'CANCELLED'];
const toInput = (d?: string | null) => (d ? new Date(d).toISOString().slice(0, 10) : '');

export function OverviewTab({ project, onChange }: { project: ProjectDetail; onChange: () => void }) {
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState({
    summary: project.summary ?? '',
    status: project.status,
    startDate: toInput(project.startDate),
    endDate: toInput(project.endDate),
  });
  const [loading, setLoading] = useState(false);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      await api.put(`/projects/${project.id}`, {
        summary: form.summary,
        status: form.status,
        startDate: form.startDate ? new Date(form.startDate).toISOString() : undefined,
        endDate: form.endDate ? new Date(form.endDate).toISOString() : undefined,
      });
      toast.success('Project updated');
      setEditing(false);
      onChange();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to update');
    } finally {
      setLoading(false);
    }
  }

  if (editing) {
    return (
      <Card>
        <CardContent>
          <form onSubmit={save} className="space-y-4">
            <Field label="Summary">
              <Textarea value={form.summary} onChange={(e) => setForm((f) => ({ ...f, summary: e.target.value }))} />
            </Field>
            <div className="grid gap-4 sm:grid-cols-3">
              <Field label="Status">
                <Select
                  value={form.status}
                  onChange={(e) => setForm((f) => ({ ...f, status: e.target.value as ProjectStatus }))}
                >
                  {STATUSES.map((s) => (
                    <option key={s} value={s}>
                      {s.replace(/_/g, ' ')}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="Start date">
                <Input
                  type="date"
                  value={form.startDate}
                  onChange={(e) => setForm((f) => ({ ...f, startDate: e.target.value }))}
                />
              </Field>
              <Field label="End date">
                <Input
                  type="date"
                  value={form.endDate}
                  onChange={(e) => setForm((f) => ({ ...f, endDate: e.target.value }))}
                />
              </Field>
            </div>
            <div className="flex justify-end gap-2">
              <Button type="button" variant="outline" onClick={() => setEditing(false)}>
                Cancel
              </Button>
              <Button type="submit" loading={loading}>
                Save changes
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardContent className="space-y-5">
        <div className="flex items-start justify-between">
          <h3 className="font-semibold">Summary</h3>
          <Button variant="outline" size="sm" onClick={() => setEditing(true)}>
            Edit
          </Button>
        </div>
        <p className="text-sm leading-relaxed text-muted">{project.summary || 'No summary provided yet.'}</p>
        <div className="grid grid-cols-2 gap-4 border-t border-border pt-4 sm:grid-cols-4">
          <Meta label="Currency" value={project.currency} />
          <Meta label="Start" value={formatDate(project.startDate)} />
          <Meta label="End" value={formatDate(project.endDate)} />
          <Meta label="Team size" value={String(project.team.length)} />
        </div>
      </CardContent>
    </Card>
  );
}

function Meta({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-xs text-muted">{label}</div>
      <div className="mt-0.5 text-sm font-medium">{value}</div>
    </div>
  );
}
