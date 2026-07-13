'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { ArrowLeftRight, LayoutDashboard, PiggyBank, Plus, Sparkles, Wallet } from 'lucide-react';
import { openAssistant } from '@/components/ai/assistant-fab';
import { cn } from '@/lib/utils';
import { withBase } from '@/lib/base-path';

const tabs = [
  { href: '/dashboard', label: 'Home', icon: LayoutDashboard },
  { href: '/transactions', label: 'Activity', icon: ArrowLeftRight },
  { href: '/transactions?add=1', label: 'Add', icon: Plus, accent: true },
  { href: '/accounts', label: 'Wallets', icon: Wallet },
  { href: '/budgets', label: 'Plan', icon: PiggyBank },
] as const;

export function MobileBottomNav() {
  const pathname = usePathname();

  return (
    <nav
      className="fixed inset-x-0 bottom-0 z-30 lg:hidden"
      aria-label="Main navigation"
    >
      <div className="border-t border-border/80 bg-surface/90 shadow-[0_-8px_30px_rgba(12,18,34,0.06)] backdrop-blur-xl dark:shadow-[0_-8px_30px_rgba(0,0,0,0.35)] pb-[env(safe-area-inset-bottom)]">
        <ul className="relative mx-auto grid max-w-lg grid-cols-5 items-end px-2 pt-1.5">
          {tabs.map((tab) => {
            const baseHref = tab.href.split('?')[0]!;
            const active =
              !('accent' in tab && tab.accent) &&
              (pathname === tab.href ||
                (baseHref !== '/dashboard' && pathname.startsWith(baseHref)));
            const Icon = tab.icon;
            const isAccent = 'accent' in tab && tab.accent;

            return (
              <li key={tab.href} className="flex justify-center">
                <Link
                  href={withBase(tab.href)}
                  className={cn(
                    'group relative flex w-full flex-col items-center gap-0.5 rounded-2xl px-1 py-1.5 text-[10px] font-medium transition-colors',
                    isAccent ? 'text-primary' : active ? 'text-primary' : 'text-muted',
                  )}
                  aria-current={active ? 'page' : undefined}
                >
                  {isAccent ? (
                    <span className="-mt-5 mb-0.5 flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-primary to-accent text-primary-foreground shadow-lg shadow-primary/30 ring-4 ring-background transition-transform active:scale-95">
                      <Icon className="h-5 w-5" strokeWidth={2.5} />
                    </span>
                  ) : (
                    <span
                      className={cn(
                        'flex h-8 w-8 items-center justify-center rounded-xl transition-colors',
                        active && 'bg-primary/10',
                      )}
                    >
                      <Icon className="h-[18px] w-[18px]" strokeWidth={active ? 2.25 : 2} />
                    </span>
                  )}
                  <span className={cn(isAccent && 'mt-0.5')}>{tab.label}</span>
                  {active && !isAccent && (
                    <span className="absolute inset-x-5 -bottom-0.5 h-0.5 rounded-full bg-primary" />
                  )}
                </Link>
              </li>
            );
          })}
        </ul>

        <div className="px-3 pb-2.5 pt-0.5">
          <button
            type="button"
            onClick={() => openAssistant('ask')}
            className="flex w-full items-center justify-center gap-2 rounded-2xl bg-primary/[0.08] px-3 py-2 text-xs font-semibold text-primary transition-colors hover:bg-primary/12 active:scale-[0.99]"
            aria-label="Open money assistant"
          >
            <Sparkles className="h-3.5 w-3.5" />
            Ask Santim
          </button>
        </div>
      </div>
    </nav>
  );
}
