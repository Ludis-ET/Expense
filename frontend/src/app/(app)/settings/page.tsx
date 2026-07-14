'use client';

import { useEffect, useState } from 'react';
import { toast } from 'sonner';
import { useTheme } from 'next-themes';
import {
  Monitor,
  Moon,
  Sun,
  User,
  Palette,
  Shield,
  Coins,
  Users,
  Tags,
  Sparkles,
  type LucideIcon,
} from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Field, Input, Select } from '@/components/ui/input';
import { Avatar } from '@/components/ui/misc';
import { ExchangeRatesPanel } from '@/components/settings/exchange-rates-panel';
import { AiProviders } from '@/components/settings/ai-providers';
import { CategoryManager } from '@/components/settings/category-manager';
import { HouseholdPanel } from '@/components/settings/household-panel';
import { AppLockPanel } from '@/components/settings/app-lock-panel';
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

const CURRENCIES = ['ETB', 'USD', 'EUR', 'GBP', 'KES', 'AED'];

const SECTIONS: { id: string; label: string; icon: LucideIcon }[] = [
  { id: 'profile', label: 'Profile', icon: User },
  { id: 'appearance', label: 'Appearance', icon: Palette },
  { id: 'security', label: 'Security', icon: Shield },
  { id: 'currencies', label: 'Currencies', icon: Coins },
  { id: 'household', label: 'Household', icon: Users },
  { id: 'categories', label: 'Categories', icon: Tags },
  { id: 'ai', label: 'Assistant', icon: Sparkles },
];

/** Highlight the nav item for whichever section is in view. */
function useActiveSection() {
  const [active, setActive] = useState(SECTIONS[0]!.id);
  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
        if (visible[0]) setActive(visible[0].target.id);
      },
      { rootMargin: '-25% 0px -65% 0px', threshold: 0 },
    );
    SECTIONS.forEach((s) => {
      const el = document.getElementById(s.id);
      if (el) observer.observe(el);
    });
    return () => observer.disconnect();
  }, []);
  return active;
}

export default function SettingsPage() {
  const { user, refreshUser } = useAuth();
  const { theme, setTheme } = useTheme();
  const active = useActiveSection();
  const [form, setForm] = useState({
    name: user?.name ?? '',
    locale: user?.locale ?? 'en',
    calendar: (user?.calendar ?? 'gregorian') as string,
    currency: user?.currency ?? 'ETB',
    firstDayOfWeek: String(user?.firstDayOfWeek ?? 1),
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
        currency: form.currency,
        firstDayOfWeek: Number(form.firstDayOfWeek),
      });
      await refreshUser();
      toast.success('Profile updated');
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Failed to update');
    } finally {
      setLoading(false);
    }
  }

  function scrollTo(id: string) {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  return (
    <div className="animate-in mx-auto max-w-5xl">
      {/* Hero */}
      <div className="relative overflow-hidden rounded-3xl border border-border">
        <div className="h-28 bg-gradient-to-br from-primary/80 via-violet-500/70 to-sky-500/70 sm:h-32" />
        <div className="flex flex-col gap-4 px-4 pb-5 sm:flex-row sm:items-end sm:justify-between sm:px-7 sm:pb-6">
          <div className="-mt-10 flex min-w-0 items-end gap-3 sm:-mt-12 sm:gap-4">
            <Avatar
              name={user?.name ?? '?'}
              className="h-16 w-16 shrink-0 rounded-2xl border-4 border-surface text-xl shadow-lg sm:h-24 sm:w-24 sm:text-2xl"
            />
            <div className="min-w-0 pb-1">
              <h1 className="truncate text-lg font-bold tracking-tight sm:text-2xl">{user?.name}</h1>
              <p className="truncate text-sm text-muted">{user?.email}</p>
            </div>
          </div>
          <div className="hidden items-center gap-2 rounded-xl border border-border bg-surface/60 px-3 py-2 text-xs text-muted backdrop-blur sm:flex">
            <Coins className="h-3.5 w-3.5" /> Default currency
            <span className="font-semibold text-foreground">{form.currency}</span>
          </div>
        </div>
      </div>

      <div className="mt-6 grid gap-8 lg:grid-cols-[220px_1fr]">
        {/* Section nav */}
        <nav className="sticky top-14 z-10 -mx-3 bg-background/85 px-3 py-2 backdrop-blur sm:top-16 lg:top-20 lg:mx-0 lg:self-start lg:bg-transparent lg:px-0 lg:py-0 lg:backdrop-blur-none">
          <div className="flex gap-1 overflow-x-auto rounded-2xl border border-border bg-surface p-1.5 [-ms-overflow-style:none] [scrollbar-width:none] lg:flex-col lg:overflow-visible [&::-webkit-scrollbar]:hidden">
            {SECTIONS.map((s) => {
              const isActive = active === s.id;
              return (
                <button
                  key={s.id}
                  type="button"
                  onClick={() => scrollTo(s.id)}
                  className={cn(
                    'flex shrink-0 items-center gap-2.5 rounded-xl px-3 py-2 text-sm font-medium transition-colors',
                    isActive
                      ? 'bg-primary/10 text-primary'
                      : 'text-muted hover:bg-surface-muted hover:text-foreground',
                  )}
                >
                  <s.icon className="h-4 w-4" />
                  {s.label}
                </button>
              );
            })}
          </div>
        </nav>

        {/* Content */}
        <div className="min-w-0 space-y-6">
          <section id="profile" className="scroll-mt-24">
            <SectionHeader icon={User} title="Profile" description="Your details and money preferences." />
            <Card>
              <CardContent className="pt-6">
                <form onSubmit={save} className="space-y-4">
                  <Field label="Full name">
                    <Input required value={form.name} onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
                  </Field>
                  <div className="grid gap-4 sm:grid-cols-2">
                    <Field label="Default currency">
                      <Select value={form.currency} onChange={(e) => setForm((f) => ({ ...f, currency: e.target.value }))}>
                        {CURRENCIES.map((c) => (
                          <option key={c} value={c}>{c}</option>
                        ))}
                      </Select>
                    </Field>
                    <Field label="Language">
                      <Select value={form.locale} onChange={(e) => setForm((f) => ({ ...f, locale: e.target.value }))}>
                        {LOCALES.map((l) => (
                          <option key={l.code} value={l.code}>{l.label}</option>
                        ))}
                      </Select>
                    </Field>
                    <Field label="First day of week">
                      <Select value={form.firstDayOfWeek} onChange={(e) => setForm((f) => ({ ...f, firstDayOfWeek: e.target.value }))}>
                        <option value="1">Monday</option>
                        <option value="0">Sunday</option>
                      </Select>
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
                    <Button type="submit" loading={loading}>Save changes</Button>
                  </div>
                </form>
              </CardContent>
            </Card>
          </section>

          <section id="appearance" className="scroll-mt-24">
            <SectionHeader icon={Palette} title="Appearance" description="Choose how Santim looks to you." />
            <Card>
              <CardContent className="pt-6">
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
                        'flex flex-col items-center gap-2 rounded-xl border p-4 text-sm transition-all',
                        theme === opt.value
                          ? 'border-primary bg-primary/5 text-primary shadow-sm'
                          : 'border-border hover:bg-surface-muted',
                      )}
                    >
                      <opt.icon className="h-5 w-5" />
                      {opt.label}
                    </button>
                  ))}
                </div>
              </CardContent>
            </Card>
          </section>

          <section id="security" className="scroll-mt-24">
            <AppLockPanel />
          </section>

          <section id="currencies" className="scroll-mt-24">
            <ExchangeRatesPanel />
          </section>

          <section id="household" className="scroll-mt-24">
            <HouseholdPanel />
          </section>

          <section id="categories" className="scroll-mt-24">
            <CategoryManager />
          </section>

          <section id="ai" className="scroll-mt-24">
            <AiProviders />
          </section>
        </div>
      </div>
    </div>
  );
}

function SectionHeader({ icon: Icon, title, description }: { icon: LucideIcon; title: string; description: string }) {
  return (
    <div className="mb-3 flex items-center gap-3">
      <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-primary/10 text-primary">
        <Icon className="h-4.5 w-4.5" />
      </span>
      <div>
        <h2 className="font-semibold leading-tight">{title}</h2>
        <p className="text-xs text-muted">{description}</p>
      </div>
    </div>
  );
}
