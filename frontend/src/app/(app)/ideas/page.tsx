'use client';

import { useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Lightbulb, Plus, Star, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Modal } from '@/components/ui/modal';
import { Field, Input, Select, Textarea } from '@/components/ui/input';
import { PageHeader, Skeleton, Avatar } from '@/components/ui/misc';
import { api, ApiError } from '@/lib/api';
import { cn } from '@/lib/utils';
import type { Idea, IdeaStatus } from '@/lib/types';

const COLUMNS: { status: IdeaStatus; label: string; accent: string }[] = [
  { status: 'OPEN', label: 'Open', accent: 'bg-sky-500' },
  { status: 'CONVERTED', label: 'Converted', accent: 'bg-emerald-500' },
  { status: 'CLOSED', label: 'Closed', accent: 'bg-slate-400' },
];

export default function IdeasPage() {
  const { data, isLoading, mutate } = useSWR<Idea[]>('/ideas');
  const [modalOpen, setModalOpen] = useState(false);
  const [dragId, setDragId] = useState<string | null>(null);

  async function move(id: string, status: IdeaStatus) {
    // Optimistic update for a snappy board.
    void mutate((prev) => prev?.map((i) => (i.id === id ? { ...i, status } : i)), false);
    try {
      await api.patch(`/ideas/${id}`, { status });
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to move');
      void mutate();
    }
  }

  async function remove(id: string) {
    void mutate((prev) => prev?.filter((i) => i.id !== id), false);
    try {
      await api.del(`/ideas/${id}`);
      toast.success('Idea removed');
    } catch {
      void mutate();
    }
  }

  return (
    <div>
      <PageHeader
        title="Ideas backlog"
        description="Capture and prioritise research ideas — drag between columns to update."
        action={
          <Button onClick={() => setModalOpen(true)}>
            <Plus className="h-4 w-4" /> New idea
          </Button>
        }
      />

      {isLoading ? (
        <div className="grid gap-4 md:grid-cols-3">
          {COLUMNS.map((c) => (
            <Skeleton key={c.status} className="h-64" />
          ))}
        </div>
      ) : (
        <div className="grid gap-4 md:grid-cols-3">
          {COLUMNS.map((col) => {
            const items = data?.filter((i) => i.status === col.status) ?? [];
            return (
              <div
                key={col.status}
                onDragOver={(e) => e.preventDefault()}
                onDrop={() => {
                  if (dragId) move(dragId, col.status);
                  setDragId(null);
                }}
                className="rounded-xl border border-border bg-surface-muted/40 p-3"
              >
                <div className="mb-3 flex items-center gap-2 px-1">
                  <span className={cn('h-2.5 w-2.5 rounded-full', col.accent)} />
                  <h3 className="text-sm font-semibold">{col.label}</h3>
                  <span className="ml-auto rounded-full bg-surface px-2 py-0.5 text-xs text-muted">{items.length}</span>
                </div>
                <div className="space-y-2.5">
                  {items.map((idea) => (
                    <div
                      key={idea.id}
                      draggable
                      onDragStart={() => setDragId(idea.id)}
                      className="group card cursor-grab p-3.5 active:cursor-grabbing"
                    >
                      <div className="flex items-start justify-between gap-2">
                        <p className="text-sm font-medium leading-snug">{idea.title}</p>
                        <button
                          onClick={() => remove(idea.id)}
                          className="text-muted opacity-0 transition-opacity hover:text-danger group-hover:opacity-100"
                          aria-label="Delete idea"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </button>
                      </div>
                      {idea.description && <p className="mt-1 line-clamp-2 text-xs text-muted">{idea.description}</p>}
                      <div className="mt-3 flex items-center justify-between">
                        <div className="flex gap-0.5">
                          {Array.from({ length: 5 }).map((_, i) => (
                            <Star
                              key={i}
                              className={cn(
                                'h-3.5 w-3.5',
                                i < idea.priority ? 'fill-amber-400 text-amber-400' : 'text-border',
                              )}
                            />
                          ))}
                        </div>
                        <Avatar name={idea.user.name} className="h-6 w-6 text-[10px]" />
                      </div>
                      {idea.project && (
                        <div className="mt-2 truncate rounded-md bg-surface-muted px-2 py-1 text-[11px] text-muted">
                          {idea.project.title}
                        </div>
                      )}
                    </div>
                  ))}
                  {!items.length && (
                    <p className="py-6 text-center text-xs text-muted">Drop ideas here</p>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      <AddIdeaModal open={modalOpen} onClose={() => setModalOpen(false)} onAdded={mutate} />
    </div>
  );
}

function AddIdeaModal({ open, onClose, onAdded }: { open: boolean; onClose: () => void; onAdded: () => void }) {
  const [form, setForm] = useState({ title: '', description: '', priority: '3' });
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      await api.post('/ideas', {
        title: form.title,
        description: form.description || undefined,
        priority: Number(form.priority),
      });
      toast.success('Idea added');
      onAdded();
      onClose();
      setForm({ title: '', description: '', priority: '3' });
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to add');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="New idea" description="Add to the backlog and prioritise later.">
      <form onSubmit={submit} className="space-y-4">
        <Field label="Title">
          <Input
            required
            value={form.title}
            onChange={(e) => setForm((f) => ({ ...f, title: e.target.value }))}
            placeholder="e.g. Drone-based canopy imaging"
          />
        </Field>
        <Field label="Description">
          <Textarea value={form.description} onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))} />
        </Field>
        <Field label="Priority">
          <Select value={form.priority} onChange={(e) => setForm((f) => ({ ...f, priority: e.target.value }))}>
            {[0, 1, 2, 3, 4, 5].map((p) => (
              <option key={p} value={p}>
                {p} {p === 1 ? 'star' : 'stars'}
              </option>
            ))}
          </Select>
        </Field>
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={loading}>
            Add idea
          </Button>
        </div>
      </form>
    </Modal>
  );
}
