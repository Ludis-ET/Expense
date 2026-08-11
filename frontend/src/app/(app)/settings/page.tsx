"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { useTheme } from "next-themes";
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
} from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Field, Input, Select } from "@/components/ui/input";
import { Avatar } from "@/components/ui/misc";
import { InfoHint } from "@/components/ui/info-hint";
import {
  AvatarPicker,
  BannerPicker,
} from "@/components/settings/profile-look-pickers";
import { ExchangeRatesPanel } from "@/components/settings/exchange-rates-panel";
import { AiProviders } from "@/components/settings/ai-providers";
import { CategoryManager } from "@/components/settings/category-manager";
import { HouseholdPanel } from "@/components/settings/household-panel";
import { AppLockPanel } from "@/components/settings/app-lock-panel";
import { api, ApiError } from "@/lib/api";
import { formatEthiopian } from "@/lib/ethiopian-calendar";
import { useAuth } from "@/lib/auth";
import { AVATAR_IDS, BANNER_IDS, ProfileBanner } from "@/lib/profile-presets";
import { cn } from "@/lib/utils";

const LOCALES = [
  { code: "en", label: "English" },
  { code: "am", label: "አማርኛ (Amharic)" },
  { code: "om", label: "Afaan Oromoo" },
  { code: "ti", label: "ትግርኛ (Tigrinya)" },
];

const CURRENCIES = ["ETB", "USD", "EUR", "GBP", "KES", "AED"];

const SECTIONS: {
  id: string;
  label: string;
  short: string;
  icon: LucideIcon;
}[] = [
  { id: "profile", label: "Profile", short: "Profile", icon: User },
  { id: "appearance", label: "Appearance", short: "Look", icon: Palette },
  { id: "security", label: "Security", short: "Lock", icon: Shield },
  { id: "currencies", label: "Currencies", short: "Rates", icon: Coins },
  { id: "household", label: "Household", short: "Home", icon: Users },
  { id: "categories", label: "Categories", short: "Tags", icon: Tags },
  { id: "ai", label: "Assistant", short: "AI", icon: Sparkles },
];

const HASH_ALIASES: Record<string, string> = {
  "app-lock": "security",
};

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
      { rootMargin: "-25% 0px -65% 0px", threshold: 0 },
    );
    SECTIONS.forEach((s) => {
      const el = document.getElementById(s.id);
      if (el) observer.observe(el);
    });
    return () => observer.disconnect();
  }, []);
  return active;
}

function resolveHashTarget(hash: string) {
  const raw = hash.replace(/^#/, "");
  if (!raw) return null;
  const id = HASH_ALIASES[raw] ?? raw;
  return SECTIONS.some((s) => s.id === id) ? id : null;
}

export default function SettingsPage() {
  const { user, refreshUser } = useAuth();
  const { theme, setTheme } = useTheme();
  const active = useActiveSection();
  const [form, setForm] = useState({
    name: user?.name ?? "",
    locale: user?.locale ?? "en",
    calendar: (user?.calendar ?? "gregorian") as string,
    currency: user?.currency ?? "ETB",
    firstDayOfWeek: String(user?.firstDayOfWeek ?? 1),
    avatarId: user?.avatarId ?? AVATAR_IDS[0]!,
    bannerId: user?.bannerId ?? BANNER_IDS[0]!,
  });
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!user) return;
    setForm((f) => ({
      ...f,
      name: user.name,
      locale: user.locale ?? "en",
      calendar: user.calendar ?? "gregorian",
      currency: user.currency,
      firstDayOfWeek: String(user.firstDayOfWeek ?? 1),
      avatarId: user.avatarId ?? AVATAR_IDS[0]!,
      bannerId: user.bannerId ?? BANNER_IDS[0]!,
    }));
  }, [user]);

  useEffect(() => {
    const jump = () => {
      const id = resolveHashTarget(window.location.hash);
      if (!id) return;
      requestAnimationFrame(() => {
        document
          .getElementById(id)
          ?.scrollIntoView({ behavior: "smooth", block: "start" });
      });
    };
    jump();
    window.addEventListener("hashchange", jump);
    return () => window.removeEventListener("hashchange", jump);
  }, []);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      await api.put("/users/me", {
        name: form.name,
        locale: form.locale,
        calendar: form.calendar,
        currency: form.currency,
        firstDayOfWeek: Number(form.firstDayOfWeek),
        avatarId: form.avatarId,
        bannerId: form.bannerId,
      });
      await refreshUser();
      toast.success("Profile updated");
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Failed to update");
    } finally {
      setLoading(false);
    }
  }

  function scrollTo(id: string) {
    document
      .getElementById(id)
      ?.scrollIntoView({ behavior: "smooth", block: "start" });
    const url = new URL(window.location.href);
    url.hash = id;
    window.history.replaceState(null, "", url);
  }

  return (
    <div className="animate-in mx-auto w-full min-w-0 max-w-5xl">
      {/* Hero */}
      <div className="relative overflow-hidden rounded-2xl border border-border bg-surface sm:rounded-3xl">
        <ProfileBanner bannerId={form.bannerId} className="h-24 sm:h-32" />
        <div className="flex flex-col gap-3 px-4 pb-4 sm:flex-row sm:items-end sm:justify-between sm:gap-4 sm:px-7 sm:pb-6">
          <div className="-mt-8 flex min-w-0 items-end gap-3 sm:-mt-12 sm:gap-4">
            <Avatar
              name={form.name || user?.name || "?"}
              avatarId={form.avatarId}
              className="h-14 w-14 shrink-0 rounded-2xl border-4 border-surface shadow-lg sm:h-24 sm:w-24"
            />
            <div className="min-w-0 pb-0.5 sm:pb-1">
              <h1 className="truncate text-base font-bold tracking-tight sm:text-2xl">
                {user?.name}
              </h1>
              <p className="truncate text-xs text-muted sm:text-sm">
                {user?.email}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2 self-start rounded-xl border border-border bg-surface/60 px-3 py-2 text-xs text-muted backdrop-blur sm:self-auto">
            <Coins className="h-3.5 w-3.5 shrink-0" />
            <span className="truncate">Default</span>
            <span className="font-semibold text-foreground">
              {form.currency}
            </span>
          </div>
        </div>
      </div>

      <div className="mt-5 grid min-w-0 gap-5 lg:mt-6 lg:grid-cols-[200px_minmax(0,1fr)] lg:gap-8">
        {/* Section nav   chip grid on phones, rail on desktop */}
        <nav
          aria-label="Settings sections"
          className="sticky top-14 z-10 -mx-3 border-b border-border/60 bg-background/90 px-3 py-2.5 backdrop-blur-md sm:-mx-4 sm:px-4 lg:top-20 lg:mx-0 lg:self-start lg:border-0 lg:bg-transparent lg:px-0 lg:py-0 lg:backdrop-blur-none"
        >
          {/* Mobile / tablet: equal-width icon chips that wrap instead of overflowing */}
          <div className="rounded-2xl border border-border bg-surface p-1.5 shadow-sm lg:hidden">
            <div className="flex flex-wrap gap-1">
              {SECTIONS.map((s) => {
                const isActive = active === s.id;
                return (
                  <button
                    key={s.id}
                    type="button"
                    onClick={() => scrollTo(s.id)}
                    aria-current={isActive ? "true" : undefined}
                    className={cn(
                      "flex min-h-14 min-w-17 flex-1 basis-[calc(25%-0.25rem)] flex-col items-center justify-center gap-1 rounded-xl px-1.5 py-2 text-[11px] font-medium transition-all sm:min-h-12 sm:basis-0 sm:flex-row sm:gap-2 sm:px-2.5 sm:text-xs",
                      isActive
                        ? "bg-primary text-primary-foreground shadow-sm"
                        : "text-muted hover:bg-surface-muted hover:text-foreground",
                    )}
                  >
                    <s.icon className="h-4 w-4 shrink-0" />
                    <span className="max-w-full truncate leading-none sm:hidden">
                      {s.short}
                    </span>
                    <span className="hidden max-w-full truncate leading-none sm:inline">
                      {s.label}
                    </span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Desktop rail */}
          <div className="hidden gap-1 rounded-2xl border border-border bg-surface p-1.5 lg:flex lg:flex-col">
            {SECTIONS.map((s) => {
              const isActive = active === s.id;
              return (
                <button
                  key={s.id}
                  type="button"
                  onClick={() => scrollTo(s.id)}
                  aria-current={isActive ? "true" : undefined}
                  className={cn(
                    "flex w-full items-center gap-2.5 rounded-xl px-3 py-2.5 text-sm font-medium transition-colors",
                    isActive
                      ? "bg-primary/10 text-primary"
                      : "text-muted hover:bg-surface-muted hover:text-foreground",
                  )}
                >
                  <s.icon className="h-4 w-4 shrink-0" />
                  {s.label}
                </button>
              );
            })}
          </div>
        </nav>

        {/* Content */}
        <div className="min-w-0 space-y-5 sm:space-y-6">
          <section id="profile" className="scroll-mt-44 lg:scroll-mt-24">
            <SectionHeader
              icon={User}
              title="Profile"
              description="Your details and money preferences."
            />
            <Card>
              <CardContent className="pt-5 sm:pt-6">
                <form onSubmit={save} className="space-y-5">
                  <div className="space-y-2">
                    <p className="text-sm font-medium">Avatar</p>
                    <p className="text-xs text-muted">
                      Pick an illustrated look for your profile.
                    </p>
                    <AvatarPicker
                      value={form.avatarId}
                      onChange={(avatarId) =>
                        setForm((f) => ({ ...f, avatarId }))
                      }
                    />
                  </div>
                  <div className="space-y-2">
                    <p className="text-sm font-medium">Settings banner</p>
                    <p className="text-xs text-muted">
                      Choose the header art at the top of this page.
                    </p>
                    <BannerPicker
                      value={form.bannerId}
                      onChange={(bannerId) =>
                        setForm((f) => ({ ...f, bannerId }))
                      }
                    />
                  </div>
                  <Field label="Full name">
                    <Input
                      required
                      value={form.name}
                      onChange={(e) =>
                        setForm((f) => ({ ...f, name: e.target.value }))
                      }
                    />
                  </Field>
                  <div className="grid gap-4 sm:grid-cols-2">
                    <Field label="Default currency">
                      <Select
                        value={form.currency}
                        onChange={(e) =>
                          setForm((f) => ({ ...f, currency: e.target.value }))
                        }
                      >
                        {CURRENCIES.map((c) => (
                          <option key={c} value={c}>
                            {c}
                          </option>
                        ))}
                      </Select>
                    </Field>
                    <Field label="Language">
                      <Select
                        value={form.locale}
                        onChange={(e) =>
                          setForm((f) => ({ ...f, locale: e.target.value }))
                        }
                      >
                        {LOCALES.map((l) => (
                          <option key={l.code} value={l.code}>
                            {l.label}
                          </option>
                        ))}
                      </Select>
                    </Field>
                    <Field label="First day of week">
                      <Select
                        value={form.firstDayOfWeek}
                        onChange={(e) =>
                          setForm((f) => ({
                            ...f,
                            firstDayOfWeek: e.target.value,
                          }))
                        }
                      >
                        <option value="1">Monday</option>
                        <option value="0">Sunday</option>
                      </Select>
                    </Field>
                    <Field
                      label="Calendar"
                      hint={
                        form.calendar === "ethiopian"
                          ? `Today: ${formatEthiopian(new Date())}`
                          : "Dates show in the Gregorian calendar"
                      }
                    >
                      <Select
                        value={form.calendar}
                        onChange={(e) =>
                          setForm((f) => ({ ...f, calendar: e.target.value }))
                        }
                      >
                        <option value="gregorian">Gregorian</option>
                        <option value="ethiopian">Ethiopian (ግዕዝ)</option>
                      </Select>
                    </Field>
                  </div>
                  <div className="flex justify-stretch sm:justify-end">
                    <Button
                      type="submit"
                      loading={loading}
                      className="w-full sm:w-auto"
                    >
                      Save changes
                    </Button>
                  </div>
                </form>
              </CardContent>
            </Card>
          </section>

          <section id="appearance" className="scroll-mt-44 lg:scroll-mt-24">
            <SectionHeader
              icon={Palette}
              title="Appearance"
              description="Choose how Santim looks to you."
            />
            <Card>
              <CardContent className="pt-5 sm:pt-6">
                <div className="grid grid-cols-3 gap-2 sm:gap-3">
                  {[
                    { value: "light", label: "Light", icon: Sun },
                    { value: "dark", label: "Dark", icon: Moon },
                    { value: "system", label: "System", icon: Monitor },
                  ].map((opt) => (
                    <button
                      key={opt.value}
                      type="button"
                      onClick={() => setTheme(opt.value)}
                      className={cn(
                        "flex flex-col items-center gap-1.5 rounded-xl border px-2 py-3 text-xs transition-all sm:gap-2 sm:p-4 sm:text-sm",
                        theme === opt.value
                          ? "border-primary bg-primary/5 text-primary shadow-sm"
                          : "border-border hover:bg-surface-muted",
                      )}
                    >
                      <opt.icon className="h-4 w-4 sm:h-5 sm:w-5" />
                      {opt.label}
                    </button>
                  ))}
                </div>
              </CardContent>
            </Card>
          </section>

          <section id="security" className="scroll-mt-44 lg:scroll-mt-24">
            <AppLockPanel />
          </section>

          <section id="currencies" className="scroll-mt-44 lg:scroll-mt-24">
            <ExchangeRatesPanel />
          </section>

          <section id="household" className="scroll-mt-44 lg:scroll-mt-24">
            <HouseholdPanel />
          </section>

          <section id="categories" className="scroll-mt-44 lg:scroll-mt-24">
            <CategoryManager />
          </section>

          <section id="ai" className="scroll-mt-44 lg:scroll-mt-24">
            <AiProviders />
          </section>
        </div>
      </div>
    </div>
  );
}

function SectionHeader({
  icon: Icon,
  title,
  description,
}: {
  icon: LucideIcon;
  title: string;
  description: string;
}) {
  return (
    <div className="mb-3 flex min-w-0 items-center gap-3">
      <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
        <Icon className="h-4 w-4" />
      </span>
      <div className="flex min-w-0 items-center gap-1.5">
        <h2 className="truncate font-semibold leading-tight">{title}</h2>
        <InfoHint label={`About ${title}`}>{description}</InfoHint>
      </div>
    </div>
  );
}
