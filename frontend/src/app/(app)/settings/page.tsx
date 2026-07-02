'use client';

import { useState } from 'react';
import { toast } from 'sonner';
import { useTheme } from 'next-themes';
import { Monitor, Moon, Sun } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Field, Input, Select } from '@/components/ui/input';
import { Avatar, PageHeader } from '@/components/ui/misc';
import { AiProviders } from '@/components/settings/ai-providers';
import { Members } from '@/components/settings/members';
import { api, ApiError } from '@/lib/api';
import { formatEthiopian } from '@/lib/ethiopian-calendar';
import { useAuth } from '@/lib/auth';
import { cn } from '@/lib/utils';

const LOCALES = [
  { code: 'en', label: 'English' },
  { code: 'am', label: 'አማርኛ (Amharic)' },
  { code: 'om', label: 'Afaan Oromoo' },
  { code: 'ti', label: 'ትግርኛ (Tigrinya)' },
];

export default function SettingsPage() {
  const { user, refreshUser } = useAuth();
  const { theme, setTheme } = useTheme();
  const [form, setForm] = useState({
    name: user?.name ?? '',
    locale: user?.locale ?? 'en',
    calendar: user?.calendar ?? 'gregorian',
    orcidId: user?.orcidId ?? '',
  });
  const [loading, setLoading] = useState(false);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      await api.put('/users/me', {
        name: form.name,
        locale: form.locale,
        calendar: form.calendar,
        orcidId: form.orcidId || undefined,
      });
      await refreshUser();
      toast.success('Profile updated');
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to update');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="max-w-2xl">
      <PageHeader title="Settings" description="Manage your profile, collaborators and AI providers." />

      <Card className="mb-6">
        <CardHeader>
          <div>
            <CardTitle>Profile</CardTitle>
            <CardDescription>Your personal details and researcher identity.</CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          <div className="mb-5 flex items-center gap-4">
            <Avatar name={user?.name ?? '?'} className="h-14 w-14 text-lg" />
            <div>
              <p className="font-medium">{user?.name}</p>
              <p className="text-sm text-muted">{user?.email}</p>
              <span className="mt-1 inline-block rounded-full bg-surface-muted px-2 py-0.5 text-xs text-muted">
                {user?.role?.replace(/_/g, ' ')}
              </span>
            </div>
          </div>
          <form onSubmit={save} className="space-y-4">
            <Field label="Full name">
              <Input required value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
            </Field>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="Language">
                <Select value={form.locale} onChange={(e) => setForm((f) => ({ ...f, locale: e.target.value }))}>
                  {LOCALES.map((l) => (
                    <option key={l.code} value={l.code}>
                      {l.label}
                    </option>
                  ))}
                </Select>
              </Field>
              <Field label="ORCID iD" hint="Format: 0000-0000-0000-0000">
                <Input
                  value={form.orcidId}
                  onChange={(e) => setForm((f) => ({ ...f, orcidId: e.target.value }))}
                  placeholder="0000-0002-1825-0097"
                />
              </Field>
              <Field
                label="Calendar"
                hint={
                  form.calendar === 'ethiopian'
                    ? `Today: ${formatEthiopian(new Date())}`
                    : 'Dates show in the Gregorian calendar'
                }
              >
                <Select value={form.calendar} onChange={(e) => setForm((f) => ({ ...f, calendar: e.target.value }))}>
                  <option value="gregorian">Gregorian</option>
                  <option value="ethiopian">Ethiopian (ግዕዝ)</option>
                </Select>
              </Field>
            </div>
            <div className="flex justify-end">
              <Button type="submit" loading={loading}>
                Save changes
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <div>
            <CardTitle>Appearance</CardTitle>
            <CardDescription>Choose how ResearchTracker looks to you.</CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-3 gap-3">
            {[
              { value: 'light', label: 'Light', icon: Sun },
              { value: 'dark', label: 'Dark', icon: Moon },
              { value: 'system', label: 'System', icon: Monitor },
            ].map((opt) => (
              <button
                key={opt.value}
                onClick={() => setTheme(opt.value)}
                className={cn(
                  'flex flex-col items-center gap-2 rounded-xl border p-4 text-sm transition-colors',
                  theme === opt.value ? 'border-primary bg-primary/5 text-primary' : 'border-border hover:bg-surface-muted',
                )}
              >
                <opt.icon className="h-5 w-5" />
                {opt.label}
              </button>
            ))}
          </div>
        </CardContent>
      </Card>

      <div className="mt-6 space-y-6">
        <Members />
        <AiProviders />
      </div>
    </div>
  );
}
