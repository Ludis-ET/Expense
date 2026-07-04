import Link from 'next/link';
import {
  ArrowLeftRight,
  ArrowRight,
  BarChart3,
  CheckCircle2,
  Globe2,
  Lock,
  PiggyBank,
  Repeat,
  Sparkles,
  Target,
} from 'lucide-react';
import { Brand } from '@/components/brand';
import { ThemeToggle } from '@/components/theme-toggle';
import { Button } from '@/components/ui/button';

const features = [
  { icon: ArrowLeftRight, title: 'Income & expenses', desc: 'Log every birr in and out across cash, bank and mobile-money - with categories, payees and tags.' },
  { icon: PiggyBank, title: 'Budgets that nudge', desc: 'Set monthly limits per category and get notified before you overspend, not after.' },
  { icon: Target, title: 'Savings goals', desc: 'Save towards an emergency fund, a trip or a new laptop, and see exactly how much per month it takes.' },
  { icon: Repeat, title: 'Recurring on autopilot', desc: 'Salary, rent and subscriptions post themselves on schedule - or just remind you.' },
  { icon: BarChart3, title: 'Personal analytics', desc: 'Daily, weekly and monthly trends, a spending heatmap, top payees and an “unnecessary spend” meter.' },
  { icon: Sparkles, title: 'AI money assistant', desc: 'Ask questions about your spending and get a personalized monthly review - using your own AI key.' },
];

const stats = [
  { value: '3', label: 'Account types' },
  { value: '19', label: 'Default categories' },
  { value: '100%', label: 'Private to you' },
  { value: 'ETB', label: 'Birr-first' },
];

export default function LandingPage() {
  return (
    <div className="min-h-screen">
      {/* Nav */}
      <header className="sticky top-0 z-40 border-b border-border/70 bg-background/80 backdrop-blur-lg">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-5 py-3.5">
          <Brand />
          <nav className="hidden items-center gap-7 text-sm text-muted md:flex">
            <a href="#features" className="transition-colors hover:text-foreground">Features</a>
            <a href="#local" className="transition-colors hover:text-foreground">Made local</a>
            <a href="#cta" className="transition-colors hover:text-foreground">Get started</a>
          </nav>
          <div className="flex items-center gap-2">
            <ThemeToggle />
            <Link href="/login" className="hidden sm:block">
              <Button variant="ghost" size="sm">Sign in</Button>
            </Link>
            <Link href="/register">
              <Button size="sm">Get started</Button>
            </Link>
          </div>
        </div>
      </header>

      {/* Hero */}
      <section className="relative overflow-hidden bg-grid">
        <div className="pointer-events-none absolute left-1/2 top-0 h-[480px] w-[820px] -translate-x-1/2 rounded-full bg-primary/20 blur-[140px]" />
        <div className="relative mx-auto max-w-6xl px-5 py-20 text-center md:py-28">
          <div className="animate-in mx-auto mb-5 inline-flex items-center gap-2 rounded-full border border-border bg-surface px-3.5 py-1.5 text-xs font-medium text-muted">
            <Sparkles className="h-3.5 w-3.5 text-primary" />
            Personal finance, birr-first
          </div>
          <h1 className="animate-in mx-auto max-w-3xl text-4xl font-bold leading-tight tracking-tight md:text-6xl">
            Know where every{' '}
            <span className="bg-gradient-to-r from-emerald-500 to-teal-500 bg-clip-text text-transparent">birr goes</span>
          </h1>
          <p className="animate-in mx-auto mt-5 max-w-xl text-base text-muted md:text-lg">
            Santim brings your income, spending, budgets and savings goals together - with analytics that actually
            tell you something, all private to you.
          </p>
          <div className="animate-in mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
            <Link href="/register">
              <Button size="lg" className="w-full sm:w-auto">
                Start free <ArrowRight className="h-4 w-4" />
              </Button>
            </Link>
            <Link href="/login">
              <Button size="lg" variant="outline" className="w-full sm:w-auto">
                Live demo
              </Button>
            </Link>
          </div>
          <p className="mt-4 text-xs text-muted">Demo login: demo@example.com · password123</p>

          {/* Stat strip */}
          <div className="mx-auto mt-14 grid max-w-3xl grid-cols-2 gap-4 sm:grid-cols-4">
            {stats.map((s) => (
              <div key={s.label} className="card px-4 py-5">
                <div className="text-2xl font-bold text-primary">{s.value}</div>
                <div className="mt-1 text-xs text-muted">{s.label}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Features */}
      <section id="features" className="mx-auto max-w-6xl px-5 py-20">
        <div className="mx-auto mb-12 max-w-2xl text-center">
          <h2 className="text-3xl font-bold tracking-tight">Everything your money needs</h2>
          <p className="mt-3 text-muted">
            One simple app replacing the notebook, the spreadsheet and the guesswork.
          </p>
        </div>
        <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {features.map((f) => (
            <div key={f.title} className="card group p-6 transition-all hover:-translate-y-0.5 hover:shadow-lg">
              <div className="mb-4 inline-flex h-11 w-11 items-center justify-center rounded-xl bg-primary/10 text-primary transition-colors group-hover:bg-primary group-hover:text-primary-foreground">
                <f.icon className="h-5.5 w-5.5" />
              </div>
              <h3 className="font-semibold">{f.title}</h3>
              <p className="mt-1.5 text-sm leading-relaxed text-muted">{f.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Local section */}
      <section id="local" className="border-y border-border bg-surface/50">
        <div className="mx-auto grid max-w-6xl items-center gap-10 px-5 py-20 lg:grid-cols-2">
          <div>
            <div className="mb-4 inline-flex items-center gap-2 rounded-full bg-primary/10 px-3 py-1 text-xs font-medium text-primary">
              <Globe2 className="h-3.5 w-3.5" /> Made for how you actually spend
            </div>
            <h2 className="text-3xl font-bold tracking-tight">Birr-first, with an Ethiopian touch</h2>
            <p className="mt-4 text-muted">
              Track cash, bank and mobile-money wallets like Telebirr side by side, with categories that match real
              life - from family support to airtime top-ups.
            </p>
            <ul className="mt-6 space-y-3">
              {[
                'Ethiopian Birr (ETB) by default, with multi-currency accounts',
                'Optional Ethiopian (Geʿez) calendar display',
                'Cash, bank and mobile-money account types',
                'Your data stays private to your own account',
              ].map((item) => (
                <li key={item} className="flex items-start gap-3 text-sm">
                  <CheckCircle2 className="mt-0.5 h-5 w-5 shrink-0 text-emerald-500" />
                  <span>{item}</span>
                </li>
              ))}
            </ul>
          </div>
          <div className="card overflow-hidden p-0">
            <div className="border-b border-border bg-surface-muted/60 px-5 py-3 text-xs font-medium text-muted">
              This month · July
            </div>
            <div className="space-y-4 p-6">
              <div className="flex items-center justify-between">
                <span className="text-sm text-muted">Food & Groceries budget</span>
                <span className="text-sm font-semibold">72%</span>
              </div>
              <div className="h-2.5 w-full overflow-hidden rounded-full bg-surface-muted">
                <div className="h-full w-[72%] rounded-full bg-gradient-to-r from-primary to-accent" />
              </div>
              <div className="grid grid-cols-3 gap-3 pt-2">
                {[
                  ['Income', 'Br 45k'],
                  ['Spent', 'Br 31k'],
                  ['Saved', 'Br 14k'],
                ].map(([k, v]) => (
                  <div key={k} className="rounded-lg bg-surface-muted px-3 py-3">
                    <div className="text-xs text-muted">{k}</div>
                    <div className="mt-0.5 text-sm font-semibold">{v}</div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* CTA */}
      <section id="cta" className="mx-auto max-w-6xl px-5 py-24">
        <div className="card relative overflow-hidden bg-gradient-to-br from-emerald-600 via-primary to-teal-600 px-8 py-16 text-center text-white">
          <div className="pointer-events-none absolute inset-0 bg-grid opacity-20" />
          <h2 className="relative text-3xl font-bold tracking-tight md:text-4xl">Ready to take control of your money?</h2>
          <p className="relative mx-auto mt-3 max-w-md text-white/85">
            Create your account in seconds. No credit card, no fuss.
          </p>
          <div className="relative mt-8 flex justify-center">
            <Link href="/register">
              <Button size="lg" className="bg-white text-primary hover:bg-white/90">
                Create your account <ArrowRight className="h-4 w-4" />
              </Button>
            </Link>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-border">
        <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 px-5 py-8 text-sm text-muted sm:flex-row">
          <Brand />
          <p>© {new Date().getFullYear()} Santim. A personal-finance demo.</p>
        </div>
      </footer>
    </div>
  );
}
