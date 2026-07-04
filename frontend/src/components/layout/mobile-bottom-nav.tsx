'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { ArrowLeftRight, LayoutDashboard, PiggyBank, Plus, Wallet } from 'lucide-react';
import { cn } from '@/lib/utils';
import { withBase } from '@/lib/base-path';

const tabs = [
  { href: '/dashboard', label: 'Home', icon: LayoutDashboard },
  { href: '/transactions', label: 'Activity', icon: ArrowLeftRight },
  { href: '/transactions?add=1', label: 'Add', icon: Plus, accent: true },
  { href: '/accounts', label: 'Accounts', icon: Wallet },
  { href: '/budgets', label: 'Plan', icon: PiggyBank },
];

export function MobileBottomNav() {
  const pathname = usePathname();

  return (
    <nav
      className="fixed bottom-0 left-0 right-0 z-30 border-t border-border bg-surface/95 backdrop-blur-lg pb-[env(safe-area-inset-bottom)] lg:hidden"
      aria-label="Main navigation"
    >
      <ul className="mx-auto flex max-w-lg items-stretch justify-around px-1 pt-1">
        {tabs.map((tab) => {
          const baseHref = tab.href.split('?')[0]!;
          const active = tab.accent
            ? false
            : pathname === tab.href || (baseHref !== '/dashboard' && pathname.startsWith(baseHref));
          const Icon = tab.icon;
          return (
            <li key={tab.href} className="flex-1">
              <Link
                href={withBase(tab.href)}
                className={cn(
                  'flex min-h-[52px] flex-col items-center justify-center gap-0.5 rounded-xl px-1 py-1.5 text-[10px] font-medium transition-colors',
                  tab.accent
                    ? '-mt-3 text-primary-foreground'
                    : active
                      ? 'text-primary'
                      : 'text-muted hover:text-foreground',
                )}
                aria-current={active ? 'page' : undefined}
              >
                <span
                  className={cn(
                    'flex h-9 w-9 items-center justify-center rounded-xl',
                    tab.accent && 'bg-primary shadow-md shadow-primary/30',
                  )}
                >
                  <Icon className={cn('h-5 w-5', tab.accent && 'text-primary-foreground')} />
                </span>
                {tab.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
