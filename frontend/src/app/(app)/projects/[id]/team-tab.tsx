'use client';

import { useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Plus, X } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Modal } from '@/components/ui/modal';
import { Field, Select } from '@/components/ui/input';
import { Avatar } from '@/components/ui/misc';
import { Badge } from '@/components/ui/badge';
import { api, ApiError } from '@/lib/api';
import type { ProjectDetail, TeamRole } from '@/lib/types';

interface OrgUser {
  id: string;
  name: string;
  email: string;
  role: string;
}

const TEAM_ROLES: TeamRole[] = ['PI', 'CO_PI', 'COLLABORATOR', 'REVIEWER'];

export function TeamTab({ project, onChange }: { project: ProjectDetail; onChange: () => void }) {
  const [modalOpen, setModalOpen] = useState(false);

  async function removeMember(userId: string) {
    try {
      await api.del(`/projects/${project.id}/team/${userId}`);
      toast.success('Member removed');
      onChange();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to remove');
    }
  }

  return (
    <Card>
      <CardContent>
        <div className="mb-4 flex items-center justify-between">
          <h3 className="font-semibold">Team members ({project.team.length})</h3>
          <Button size="sm" onClick={() => setModalOpen(true)}>
            <Plus className="h-4 w-4" /> Add member
          </Button>
        </div>
        <div className="divide-y divide-border">
          {project.team.map((m) => (
            <div key={m.userId} className="flex items-center gap-3 py-3">
              <Avatar name={m.user.name} />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{m.user.name}</p>
                <p className="truncate text-xs text-muted">{m.user.email}</p>
              </div>
              <Badge tone={m.role === 'PI' ? 'primary' : 'neutral'}>{m.role.replace(/_/g, '-')}</Badge>
              {m.role !== 'PI' && (
                <button
                  onClick={() => removeMember(m.userId)}
                  className="rounded-md p-1.5 text-muted transition-colors hover:bg-surface-muted hover:text-danger"
                  aria-label="Remove"
                >
                  <X className="h-4 w-4" />
                </button>
              )}
            </div>
          ))}
        </div>
      </CardContent>

      <AddMemberModal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        projectId={project.id}
        existing={project.team.map((m) => m.userId)}
        onAdded={onChange}
      />
    </Card>
  );
}

function AddMemberModal({
  open,
  onClose,
  projectId,
  existing,
  onAdded,
}: {
  open: boolean;
  onClose: () => void;
  projectId: string;
  existing: string[];
  onAdded: () => void;
}) {
  const { data: users } = useSWR<OrgUser[]>(open ? '/users' : null);
  const [userId, setUserId] = useState('');
  const [role, setRole] = useState<TeamRole>('COLLABORATOR');
  const [loading, setLoading] = useState(false);

  const available = (users ?? []).filter((u) => !existing.includes(u.id));

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!userId) return;
    setLoading(true);
    try {
      await api.post(`/projects/${projectId}/team`, { userId, role });
      toast.success('Member added');
      onAdded();
      onClose();
      setUserId('');
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to add member');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="Add team member" description="Pick someone from your organisation.">
      <form onSubmit={submit} className="space-y-4">
        <Field label="Person">
          <Select value={userId} onChange={(e) => setUserId(e.target.value)} required>
            <option value="" disabled>
              {available.length ? 'Select a person…' : 'Everyone is already on the team'}
            </option>
            {available.map((u) => (
              <option key={u.id} value={u.id}>
                {u.name} ({u.email})
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Role">
          <Select value={role} onChange={(e) => setRole(e.target.value as TeamRole)}>
            {TEAM_ROLES.map((r) => (
              <option key={r} value={r}>
                {r.replace(/_/g, '-')}
              </option>
            ))}
          </Select>
        </Field>
        <div className="flex justify-end gap-2 pt-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={loading} disabled={!userId}>
            Add member
          </Button>
        </div>
      </form>
    </Modal>
  );
}
