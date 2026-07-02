'use client';

import { useState } from 'react';
import Link from 'next/link';
import useSWR from 'swr';
import { toast } from 'sonner';
import { FolderKanban, Plus, Users, Flag, Wallet } from 'lucide-react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Modal } from '@/components/ui/modal';
import { Field, Input, Select, Textarea } from '@/components/ui/input';
import { StatusBadge } from '@/components/ui/badge';
import { EmptyState, PageHeader, Skeleton } from '@/components/ui/misc';
import { api, ApiError } from '@/lib/api';
import { relativeTime } from '@/lib/format';
import type { Project, ProjectStatus } from '@/lib/types';

interface ProjectList {
  items: Project[];
  total: number;
}

const STATUSES: ProjectStatus[] = ['PLANNING', 'ACTIVE', 'ON_HOLD', 'COMPLETED', 'CANCELLED'];

export default function ProjectsPage() {
  const [filter, setFilter] = useState<ProjectStatus | ''>('');
  const [modalOpen, setModalOpen] = useState(false);
  const key = `/projects${filter ? `?status=${filter}` : ''}`;
  const { data, isLoading, mutate } = useSWR<ProjectList>(key);

  return (
    <div>
      <PageHeader
        title="Projects"
        description="Track research projects from planning through completion."
        action={
          <Button onClick={() => setModalOpen(true)}>
            <Plus className="h-4 w-4" /> New project
          </Button>
        }
      />

      {/* Filter chips */}
      <div className="mb-5 flex flex-wrap gap-2">
        <Chip active={filter === ''} onClick={() => setFilter('')}>
          All
        </Chip>
        {STATUSES.map((s) => (
          <Chip key={s} active={filter === s} onClick={() => setFilter(s)}>
            {s.replace(/_/g, ' ').toLowerCase().replace(/^\w/, (c) => c.toUpperCase())}
          </Chip>
        ))}
      </div>

      {isLoading ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-40" />
          ))}
        </div>
      ) : !data?.items.length ? (
        <EmptyState
          icon={<FolderKanban className="h-6 w-6" />}
          title="No projects yet"
          description="Create your first research project to start tracking teams, budgets and milestones."
          action={
            <Button onClick={() => setModalOpen(true)}>
              <Plus className="h-4 w-4" /> New project
            </Button>
          }
        />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {data.items.map((p) => (
            <Link key={p.id} href={`/projects/${p.id}`}>
              <Card className="h-full p-5 transition-all hover:-translate-y-0.5 hover:shadow-lg">
                <div className="flex items-start justify-between gap-2">
                  <h3 className="font-semibold leading-snug">{p.title}</h3>
                  <StatusBadge.Project status={p.status} />
                </div>
                <p className="mt-2 line-clamp-2 min-h-10 text-sm text-muted">{p.summary || 'No summary provided.'}</p>
                <div className="mt-4 flex items-center gap-4 border-t border-border pt-3 text-xs text-muted">
                  <span className="inline-flex items-center gap-1">
                    <Users className="h-3.5 w-3.5" /> {p._count?.team ?? 0}
                  </span>
                  <span className="inline-flex items-center gap-1">
                    <Flag className="h-3.5 w-3.5" /> {p._count?.milestones ?? 0}
                  </span>
                  <span className="inline-flex items-center gap-1">
                    <Wallet className="h-3.5 w-3.5" /> {p._count?.budgetItems ?? 0}
                  </span>
                  <span className="ml-auto">{relativeTime(p.updatedAt)}</span>
                </div>
              </Card>
            </Link>
          ))}
        </div>
      )}

      <CreateProjectModal open={modalOpen} onClose={() => setModalOpen(false)} onCreated={() => mutate()} />
    </div>
  );
}

function Chip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={`rounded-full border px-3.5 py-1.5 text-sm font-medium transition-colors ${
        active ? 'border-primary bg-primary/10 text-primary' : 'border-border text-muted hover:bg-surface-muted'
      }`}
    >
      {children}
    </button>
  );
}

function CreateProjectModal({
  open,
  onClose,
  onCreated,
}: {
  open: boolean;
  onClose: () => void;
  onCreated: () => void;
}) {
  const [form, setForm] = useState({ title: '', summary: '', status: 'PLANNING', currency: 'ETB' });
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      await api.post('/projects', form);
      toast.success('Project created');
      onCreated();
      onClose();
      setForm({ title: '', summary: '', status: 'PLANNING', currency: 'ETB' });
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to create project');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="New project" description="Set up a project and you'll be added as PI.">
      <form onSubmit={submit} className="space-y-4">
        <Field label="Title">
          <Input
            required
            value={form.title}
            onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))}
            placeholder="Drought-resistant Teff Varieties"
          />
        </Field>
        <Field label="Summary">
          <Textarea
            value={form.summary}
            onChange={(e) => setForm((f) => ({ ...f, summary: e.target.value }))}
            placeholder="Short description of the research goals…"
          />
        </Field>
        <div className="grid grid-cols-2 gap-4">
          <Field label="Status">
            <Select value={form.status} onChange={(e) => setForm((f) => ({ ...f, status: e.target.value }))}>
              {STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, ' ').toLowerCase().replace(/^\w/, (c) => c.toUpperCase())}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Currency">
            <Select value={form.currency} onChange={(e) => setForm((f) => ({ ...f, currency: e.target.value }))}>
              {['ETB', 'USD', 'EUR', 'GBP'].map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </Select>
          </Field>
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={loading}>
            Create project
          </Button>
        </div>
      </form>
    </Modal>
  );
}
