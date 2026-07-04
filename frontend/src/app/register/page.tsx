'use client';

import { useState } from 'react';
import Link from 'next/link';
import { toast } from 'sonner';
import { ArrowRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Field, Input } from '@/components/ui/input';
import { useAuth } from '@/lib/auth';
import { ApiError } from '@/lib/api';
import { AuthShell } from '@/components/auth-shell';

export default function RegisterPage() {
  const { register } = useAuth();
  const [form, setForm] = useState({ name: '', email: '', password: '' });
  const [loading, setLoading] = useState(false);

  const set = (k: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm((f) => ({ ...f, [k]: e.target.value }));

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      await register(form);
      toast.success('Account created - welcome!');
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Something went wrong');
      setLoading(false);
    }
  }

  return (
    <AuthShell title="Create your account" subtitle="Start tracking your money in minutes">
      <form onSubmit={onSubmit} className="space-y-4">
        <Field label="Your name">
          <Input required value={form.name} onChange={set('name')} placeholder="Kiflay Mehari" />
        </Field>
        <Field label="Email">
          <Input type="email" autoComplete="email" required value={form.email} onChange={set('email')} />
        </Field>
        <Field label="Password" hint="At least 8 characters">
          <Input
            type="password"
            autoComplete="new-password"
            required
            minLength={8}
            value={form.password}
            onChange={set('password')}
          />
        </Field>
        <Button type="submit" loading={loading} className="w-full" size="lg">
          Create account <ArrowRight className="h-4 w-4" />
        </Button>
      </form>
      <p className="mt-6 text-center text-sm text-muted">
        Already have an account?{' '}
        <Link href="/login" className="font-medium text-primary hover:underline">
          Sign in
        </Link>
      </p>
    </AuthShell>
  );
}
