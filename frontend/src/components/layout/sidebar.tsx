'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  ArrowLeftRight,
  BarChart3,
  BookOpen,
  HandCoins,
  LayoutDashboard,
  Lock,
  PiggyBank,
  Settings,
  Sparkles,
  Wallet,
  X,
} from 'lucide-react';
import { Brand } from '@/components/brand';
import { Avatar } from '@/components/ui/misc';
import { cn } from '@/lib/utils';
import { useAuth } from '@/lib/auth';

const navGroups = [
  {
    label: 'Overview',
    items: [{ href: '/dashboard', label: 'Dashboard', icon: LayoutDashboard }],
  },
  {
    label: 'Money',
    items: [
      { href: '/transactions', label: 'Transactions', icon: ArrowLeftRight },
      { href: '/accounts', label: 'Accounts', icon: Wallet },
    ],
  },
  {
    label: 'Insights',
    items: [
      { href: '/analytics', label: 'Analytics', icon: BarChart3 },
      { href: '/guides', label: 'Guides', icon: BookOpen },
    ],
  },
  {
    label: 'Plan',
    items: [
      { href: '/budgets', label: 'Budgets & Goals', icon: PiggyBank },
      { href: '/locks', label: 'Spend Locks', icon: Lock },
      { href: '/wishlist', label: 'Wishlist', icon: Sparkles },
      { href: '/tab', label: 'Money Tab', icon: HandCoins },
    ],
  },
];

const bottomNav = [{ href: '/settings', label: 'Settings', icon: Settings }];

export function Sidebar({ open, onClose }: { open: boolean; onClose: () => void }) {
  const pathname = usePathname();
  const { user } = useAuth();

  const isActive = (href: string) => pathname === href || pathname.startsWith(href + '/');

  return (
    <>
      {open && (
        <div className="fixed inset-0 z-30 bg-black/60 backdrop-blur-sm lg:hidden" onClick={onClose} />
      )}
      <aside
        className={cn(
          'fixed inset-y-0 left-0 z-40 flex w-[260px] flex-col border-r border-border bg-surface transition-transform duration-300 ease-out lg:translate-x-0',
          open ? 'translate-x-0' : '-translate-x-full',
        )}
      >
        <div className="flex h-16 items-center justify-between px-5">
          <Brand />
          <button onClick={onClose} className="rounded-lg p-1.5 text-muted transition-colors hover:bg-surface-muted lg:hidden" aria-label="Close menu">
            <X className="h-5 w-5" />
          </button>
        </div>

        <nav className="flex-1 space-y-5 overflow-y-auto px-3 py-2">
          {navGroups.map((group) => (
            <div key={group.label}>
              <p className="mb-1.5 px-3 text-[10px] font-semibold uppercase tracking-widest text-muted">
                {group.label}
              </p>
              <div className="space-y-0.5">
                {group.items.map((item) => {
                  const active = isActive(item.href);
                  return (
                    <Link
                      key={item.href}
                      href={item.href}
                      onClick={onClose}
                      className={cn(
                        'group relative flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-all',
                        active
                          ? 'bg-primary/10 text-primary'
                          : 'text-muted hover:bg-surface-muted hover:text-foreground',
                      )}
                    >
                      {active && (
                        <span className="absolute left-0 top-1/2 h-6 w-1 -translate-y-1/2 rounded-r-full bg-primary" />
                      )}
                      <item.icon className={cn('h-4.5 w-4.5', active && 'text-primary')} />
                      {item.label}
                    </Link>
                  );
                })}
              </div>
            </div>
          ))}
        </nav>

        <div className="border-t border-border p-3">
          {bottomNav.map((item) => {
            const active = isActive(item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={onClose}
                className={cn(
                  'flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-all',
                  active ? 'bg-primary/10 text-primary' : 'text-muted hover:bg-surface-muted hover:text-foreground',
                )}
              >
                <item.icon className="h-4.5 w-4.5" />
                {item.label}
              </Link>
            );
          })}

          {user && (
            <div className="mt-2 flex items-center gap-3 rounded-xl bg-surface-muted/60 px-3 py-3">
              <Avatar name={user.name} className="h-8 w-8 text-[10px]" />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{user.name}</p>
                <p className="truncate text-[11px] text-muted">{user.email}</p>
              </div>
            </div>
          )}
        </div>
      </aside>
    </>
  );
}
