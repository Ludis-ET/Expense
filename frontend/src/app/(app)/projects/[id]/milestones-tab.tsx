'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { Check, Circle, Clock, Plus, Trash2 } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Modal } from '@/components/ui/modal';
import { Field, Input } from '@/components/ui/input';
import { StatusBadge } from '@/components/ui/badge';
import { EmptyState } from '@/components/ui/misc';
import { CalendarDate } from '@/components/calendar-date';
import { api, ApiError } from '@/lib/api';
import type { MilestoneStatus, ProjectDetail } from '@/lib/types';

const NEXT_STATUS: Record<MilestoneStatus, MilestoneStatus> = {
  PENDING: 'IN_PROGRESS',
  IN_PROGRESS: 'DONE',
  DONE: 'PENDING',
};

const STATUS_ICON = {
  PENDING: Circle,
  IN_PROGRESS: Clock,
  DONE: Check,
};

export function MilestonesTab({ project, onChange }: { project: ProjectDetail; onChange: () => void }) {
  const [modalOpen, setModalOpen] = useState(false);

  async function cycleStatus(id: string, status: MilestoneStatus) {
    try {
      await api.patch(`/milestones/${id}`, { status: NEXT_STATUS[status] });
      onChange();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to update');
    }
  }

  async function remove(id: string) {
    try {
      await api.del(`/milestones/${id}`);
      toast.success('Milestone deleted');
      onChange();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to delete');
    }
  }

  return (
    <Card>
      <CardContent>
        <div className="mb-4 flex items-center justify-between">
          <h3 className="font-semibold">Milestones ({project.milestones.length})</h3>
          <Button size="sm" onClick={() => setModalOpen(true)}>
            <Plus className="h-4 w-4" /> Add milestone
          </Button>
        </div>

        {!project.milestones.length ? (
          <EmptyState title="No milestones yet" description="Break the project into trackable checkpoints." />
        ) : (
          <div className="divide-y divide-border">
            {project.milestones.map((m) => {
              const Icon = STATUS_ICON[m.status];
              return (
                <div key={m.id} className="flex items-center gap-3 py-3">
                  <button
                    onClick={() => cycleStatus(m.id, m.status)}
                    className={`rounded-full p-1.5 transition-colors ${
                      m.status === 'DONE'
                        ? 'bg-emerald-500/10 text-emerald-500'
                        : 'text-muted hover:bg-surface-muted'
                    }`}
                    title="Click to advance status"
                  >
                    <Icon className="h-4 w-4" />
                  </button>
                  <div className="min-w-0 flex-1">
                    <p className={`text-sm ${m.status === 'DONE' ? 'text-muted line-through' : 'font-medium'}`}>
                      {m.description}
                    </p>
                    {m.dueDate && (
                      <p className="text-xs text-muted">
                        Due <CalendarDate value={m.dueDate} />
                      </p>
                    )}
                  </div>
                  <StatusBadge.Milestone status={m.status} />
                  <button
                    onClick={() => remove(m.id)}
                    className="rounded-md p-1.5 text-muted transition-colors hover:bg-surface-muted hover:text-danger"
                    aria-label="Delete"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                </div>
              );
            })}
          </div>
        )}
      </CardContent>

      <AddMilestoneModal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        projectId={project.id}
        onAdded={onChange}
      />
    </Card>
  );
}

function AddMilestoneModal({
  open,
  onClose,
  projectId,
  onAdded,
}: {
  open: boolean;
  onClose: () => void;
  projectId: string;
  onAdded: () => void;
}) {
  const [form, setForm] = useState({ description: '', dueDate: '' });
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      await api.post('/milestones', {
        projectId,
        description: form.description,
        dueDate: form.dueDate ? new Date(form.dueDate).toISOString() : undefined,
      });
      toast.success('Milestone added');
      onAdded();
      onClose();
      setForm({ description: '', dueDate: '' });
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to add');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="Add milestone">
      <form onSubmit={submit} className="space-y-4">
        <Field label="Description">
          <Input
            required
            value={form.description}
            onChange={(e) => setForm((f) => ({ ...f, description: e.target.value }))}
            placeholder="e.g. Data collection complete"
          />
        </Field>
        <Field label="Due date">
          <Input type="date" value={form.dueDate} onChange={(e) => setForm((f) => ({ ...f, dueDate: e.target.value }))} />
        </Field>
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={loading}>
            Add milestone
          </Button>
        </div>
      </form>
    </Modal>
  );
}
