'use client';

import { useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Copy, Mail, Trash2, UserPlus } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input, Select } from '@/components/ui/input';
import { Avatar, Skeleton } from '@/components/ui/misc';
import { Badge } from '@/components/ui/badge';
import { api, ApiError } from '@/lib/api';
import type { Role } from '@/lib/types';

interface Member {
  id: string;
  name: string;
  email: string;
  role: Role;
}
interface Invite {
  id: string;
  email: string;
  role: Role;
  status: 'PENDING' | 'ACCEPTED' | 'REVOKED';
  createdAt: string;
}

const ROLES: Role[] = ['RESEARCHER', 'PROJECT_LEAD', 'REVIEWER', 'FINANCE_OFFICER', 'FUNDER', 'ADMIN'];

export function Members() {
  const { data: members } = useSWR<Member[]>('/users');
  const { data: invites, mutate } = useSWR<Invite[]>('/invitations');
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<Role>('RESEARCHER');
  const [loading, setLoading] = useState(false);
  const [lastLink, setLastLink] = useState('');

  async function invite(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      const res = await api.post<{ link: string }>('/invitations', { email, role });
      setLastLink(res.link);
      setEmail('');
      toast.success('Invitation created — share the link');
      await mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to invite');
    } finally {
      setLoading(false);
    }
  }

  async function revoke(id: string) {
    try {
      await api.del(`/invitations/${id}`);
      await mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to revoke');
    }
  }

  function copy(link: string) {
    navigator.clipboard?.writeText(link);
    toast.success('Link copied');
  }

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle>Members &amp; invitations</CardTitle>
          <CardDescription>Invite friends, family or collaborators into your workspace.</CardDescription>
        </div>
      </CardHeader>
      <CardContent className="space-y-5">
        {/* Invite form */}
        <form onSubmit={invite} className="flex flex-col gap-2 sm:flex-row">
          <Input
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="friend@example.com"
            className="flex-1"
          />
          <Select value={role} onChange={(e) => setRole(e.target.value as Role)} className="sm:w-44">
            {ROLES.map((r) => (
              <option key={r} value={r}>
                {r.replace(/_/g, ' ').toLowerCase().replace(/^\w/, (c) => c.toUpperCase())}
              </option>
            ))}
          </Select>
          <Button type="submit" loading={loading}>
            <UserPlus className="h-4 w-4" /> Invite
          </Button>
        </form>

        {lastLink && (
          <div className="flex items-center gap-2 rounded-lg border border-primary/30 bg-primary/5 p-2.5">
            <input readOnly value={lastLink} className="flex-1 truncate bg-transparent text-xs text-muted outline-none" />
            <Button size="sm" variant="outline" onClick={() => copy(lastLink)}>
              <Copy className="h-3.5 w-3.5" /> Copy
            </Button>
          </div>
        )}

        {/* Current members */}
        <div>
          <h4 className="mb-2 text-sm font-semibold">Members</h4>
          {!members ? (
            <Skeleton className="h-16" />
          ) : (
            <div className="divide-y divide-border">
              {members.map((m) => (
                <div key={m.id} className="flex items-center gap-3 py-2.5">
                  <Avatar name={m.name} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">{m.name}</p>
                    <p className="truncate text-xs text-muted">{m.email}</p>
                  </div>
                  <Badge tone={m.role === 'ADMIN' ? 'primary' : 'neutral'}>{m.role.replace(/_/g, ' ').toLowerCase()}</Badge>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Pending invites */}
        {invites && invites.filter((i) => i.status === 'PENDING').length > 0 && (
          <div>
            <h4 className="mb-2 text-sm font-semibold">Pending invitations</h4>
            <div className="divide-y divide-border">
              {invites
                .filter((i) => i.status === 'PENDING')
                .map((inv) => (
                  <div key={inv.id} className="flex items-center gap-3 py-2.5">
                    <Mail className="h-4 w-4 text-muted" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm">{inv.email}</p>
                      <p className="text-xs text-muted">{inv.role.replace(/_/g, ' ').toLowerCase()}</p>
                    </div>
                    <button
                      onClick={() => revoke(inv.id)}
                      className="rounded-md p-1.5 text-muted hover:bg-surface-muted hover:text-danger"
                      aria-label="Revoke"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>
                ))}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
