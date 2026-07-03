'use client';

import { useState } from 'react';
import useSWR from 'swr';
import { toast } from 'sonner';
import { Heart, LogOut, UserPlus, Users } from 'lucide-react';
import { Checkbox } from '@/components/ui/checkbox';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Field, Input } from '@/components/ui/input';
import { Avatar } from '@/components/ui/misc';
import { api, ApiError } from '@/lib/api';
import type { Account, HouseholdOverview } from '@/lib/types';

interface InviteItem {
  id: string;
  token: string;
  householdName: string;
  invitedBy: string;
  expiresAt: string;
}

export function HouseholdPanel() {
  const { data: household, mutate } = useSWR<HouseholdOverview | null>('/household');
  const { data: invites, mutate: mutateInvites } = useSWR<{ items: InviteItem[] }>('/household/invites');
  const { data: accountsData, mutate: mutateAccounts } = useSWR<{ items: Account[] }>('/accounts');
  const [householdName, setHouseholdName] = useState('Our Household');
  const [inviteEmail, setInviteEmail] = useState('');
  const [loading, setLoading] = useState(false);
  const [sharingId, setSharingId] = useState<string | null>(null);

  async function createHousehold() {
    setLoading(true);
    try {
      await api.post('/household', { name: householdName });
      toast.success('Household created');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setLoading(false);
    }
  }

  async function sendInvite(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      await api.post('/household/invite', { email: inviteEmail });
      toast.success('Invite sent');
      setInviteEmail('');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setLoading(false);
    }
  }

  async function acceptInvite(token: string) {
    try {
      await api.post('/household/accept', { token });
      toast.success('Joined household!');
      void mutate();
      void mutateInvites();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  async function leaveHousehold() {
    if (!confirm('Leave this household? Shared accounts will be unshared.')) return;
    try {
      await api.post('/household/leave');
      toast.success('Left household');
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    }
  }

  async function toggleShare(accountId: string, shared: boolean) {
    setSharingId(accountId);
    try {
      await api.put(`/household/accounts/${accountId}/share`, { shared });
      toast.success(shared ? 'Account shared' : 'Account unshared');
      void mutateAccounts();
      void mutate();
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed');
    } finally {
      setSharingId(null);
    }
  }

  return (
    <Card id="household">
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Heart className="h-4 w-4 text-primary" /> Couples & shared accounts
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        {(invites?.items ?? []).length > 0 && (
          <div className="rounded-xl border border-primary/30 bg-primary/5 p-4">
            <p className="text-sm font-medium">Pending invites</p>
            <ul className="mt-2 space-y-2">
              {invites!.items.map((i) => (
                <li key={i.id} className="flex items-center justify-between text-sm">
                  <span>{i.invitedBy} invited you to <strong>{i.householdName}</strong></span>
                  <Button size="sm" onClick={() => acceptInvite(i.token)}>Accept</Button>
                </li>
              ))}
            </ul>
          </div>
        )}

        {!household ? (
          <div>
            <p className="text-sm text-muted">Create a household to connect with your partner and share wallets.</p>
            <div className="mt-4 flex flex-col gap-2 sm:flex-row sm:items-end">
              <div className="flex-1">
                <Field label="Household name">
                  <Input value={householdName} onChange={(e) => setHouseholdName(e.target.value)} placeholder="Our Household" />
                </Field>
              </div>
              <Button onClick={createHousehold} loading={loading}>
                <Users className="h-4 w-4" /> Create
              </Button>
            </div>
          </div>
        ) : (
          <>
            <div className="flex items-center justify-between">
              <div>
                <p className="font-semibold">{household.name}</p>
                <p className="text-xs text-muted">You are the {household.role.toLowerCase()}</p>
              </div>
              <Button variant="outline" size="sm" onClick={leaveHousehold}>
                <LogOut className="h-4 w-4" /> Leave
              </Button>
            </div>

            <div>
              <p className="mb-2 text-sm font-medium">Members</p>
              <ul className="space-y-2">
                {household.members.map((m) => (
                  <li key={m.id} className="flex items-center gap-3 rounded-lg bg-surface-muted/50 px-3 py-2">
                    <Avatar name={m.name} className="h-8 w-8 text-[10px]" />
                    <div className="flex-1">
                      <p className="text-sm font-medium">{m.isYou ? `${m.name} (you)` : m.name}</p>
                      <p className="text-xs text-muted">{m.email}</p>
                    </div>
                    <span className="text-xs text-muted capitalize">{m.role.toLowerCase()}</span>
                  </li>
                ))}
              </ul>
            </div>

            {household.role === 'OWNER' && (
              <form onSubmit={sendInvite} className="flex flex-col gap-2 sm:flex-row sm:items-end">
                <div className="flex-1">
                  <Field label="Invite partner by email">
                    <Input type="email" required value={inviteEmail} onChange={(e) => setInviteEmail(e.target.value)} placeholder="partner@email.com" />
                  </Field>
                </div>
                <Button type="submit" loading={loading}>
                  <UserPlus className="h-4 w-4" /> Invite
                </Button>
              </form>
            )}

            <div>
              <p className="mb-2 text-sm font-medium">Share accounts</p>
              <p className="mb-3 text-xs text-muted">Shared accounts are visible to all household members.</p>
              <ul className="space-y-2">
                {(accountsData?.items ?? []).filter((a) => !a.archived).map((a) => (
                  <li key={a.id} className="flex items-center justify-between rounded-lg border border-border px-3 py-2.5">
                    <span className="text-sm font-medium">{a.name}</span>
                    <Checkbox
                      checked={!!a.isShared}
                      loading={sharingId === a.id}
                      onChange={(checked) => toggleShare(a.id, checked)}
                      label="Shared"
                    />
                  </li>
                ))}
              </ul>
            </div>
          </>
        )}
      </CardContent>
    </Card>
  );
}
