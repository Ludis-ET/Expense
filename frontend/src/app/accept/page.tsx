'use client';

import { Suspense, useState } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import useSWR from 'swr';
import { toast } from 'sonner';
import { ArrowRight, Users } from 'lucide-react';
import { AuthShell } from '@/components/auth-shell';
import { Button } from '@/components/ui/button';
import { Field, Input } from '@/components/ui/input';
import { Spinner } from '@/components/ui/misc';
import { useAuth } from '@/lib/auth';
import { ApiError } from '@/lib/api';

interface InviteInfo {
  email: string;
  workspace: string;
  invitedBy: string;
  valid: boolean;
}

function AcceptInner() {
  const token = useSearchParams().get('token') ?? '';
  const { register } = useAuth();
  const { data, error, isLoading } = useSWR<InviteInfo>(token ? `/invitations/info/${token}` : null);
  const [form, setForm] = useState({ name: '', password: '' });
  const [loading, setLoading] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!data) return;
    setLoading(true);
    try {
      await register({ name: form.name, email: data.email, password: form.password, inviteToken: token });
      toast.success(`Welcome to ${data.workspace}!`);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Could not accept invitation');
      setLoading(false);
    }
  }

  if (!token) {
    return <Invalid message="No invitation token was provided." />;
  }
  if (isLoading) {
    return (
      <div className="flex justify-center py-10">
        <Spinner className="h-6 w-6" />
      </div>
    );
  }
  if (error || !data || !data.valid) {
    return <Invalid message="This invitation is invalid or has expired." />;
  }

  return (
    <AuthShell title={`Join ${data.workspace}`} subtitle={`${data.invitedBy} invited you to collaborate`}>
      <div className="mb-5 flex items-center gap-3 rounded-xl border border-border bg-surface-muted/50 p-3">
        <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary/10 text-primary">
          <Users className="h-4.5 w-4.5" />
        </div>
        <div className="text-sm">
          Joining as <span className="font-medium">{data.email}</span>
        </div>
      </div>
      <form onSubmit={submit} className="space-y-4">
        <Field label="Your name">
          <Input required value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
        </Field>
        <Field label="Choose a password" hint="At least 8 characters">
          <Input
            type="password"
            required
            minLength={8}
            value={form.password}
            onChange={(e) => setForm((f) => ({ ...f, password: e.target.value }))}
          />
        </Field>
        <Button type="submit" loading={loading} className="w-full" size="lg">
          Accept &amp; join <ArrowRight className="h-4 w-4" />
        </Button>
      </form>
    </AuthShell>
  );
}

function Invalid({ message }: { message: string }) {
  return (
    <AuthShell title="Invitation" subtitle="Something's not right">
      <p className="text-sm text-muted">{message}</p>
      <Link href="/register" className="mt-4 inline-block text-sm font-medium text-primary hover:underline">
        Create your own workspace instead →
      </Link>
    </AuthShell>
  );
}

export default function AcceptPage() {
  return (
    <Suspense fallback={<div className="flex min-h-screen items-center justify-center"><Spinner /></div>}>
      <AcceptInner />
    </Suspense>
  );
}
