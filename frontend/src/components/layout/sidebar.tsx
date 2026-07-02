'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { BarChart3, FileText, FolderKanban, Lightbulb, Network, Settings, Wallet, X } from 'lucide-react';
import { Brand } from '@/components/brand';
import { cn } from '@/lib/utils';

const nav = [
  { href: '/dashboard', label: 'Dashboard', icon: BarChart3 },
  { href: '/projects', label: 'Projects', icon: FolderKanban },
  { href: '/budget', label: 'Budget', icon: Wallet },
  { href: '/ideas', label: 'Ideas', icon: Lightbulb },
  { href: '/insights', label: 'Insights', icon: Network },
  { href: '/reports', label: 'Reports', icon: FileText },
  { href: '/settings', label: 'Settings', icon: Settings },
];

export function Sidebar({ open, onClose }: { open: boolean; onClose: () => void }) {
  const pathname = usePathname();

  return (
    <>
      {open && <div className="fixed inset-0 z-30 bg-black/50 backdrop-blur-sm lg:hidden" onClick={onClose} />}
      <aside
        className={cn(
          'fixed inset-y-0 left-0 z-40 flex w-64 flex-col border-r border-border bg-surface transition-transform lg:translate-x-0',
          open ? 'translate-x-0' : '-translate-x-full',
        )}
      >
        <div className="flex h-16 items-center justify-between border-b border-border px-5">
          <Brand />
          <button onClick={onClose} className="rounded-md p-1 text-muted hover:bg-surface-muted lg:hidden">
            <X className="h-5 w-5" />
          </button>
        </div>
        <nav className="flex-1 space-y-1 p-3">
          {nav.map((item) => {
            const active = pathname === item.href || pathname.startsWith(item.href + '/');
            return (
              <Link
                key={item.href}
                href={item.href}
                onClick={onClose}
                className={cn(
                  'flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors',
                  active
                    ? 'bg-primary/10 text-primary'
                    : 'text-muted hover:bg-surface-muted hover:text-foreground',
                )}
              >
                <item.icon className="h-4.5 w-4.5" />
                {item.label}
              </Link>
            );
          })}
        </nav>
        <div className="m-3 rounded-xl border border-border bg-surface-muted/60 p-4 text-xs text-muted">
          <p className="font-medium text-foreground">MVP build</p>
          <p className="mt-1 leading-relaxed">Auth · Projects · Budget · Ideas. Publications & datasets next.</p>
        </div>
      </aside>
    </>
  );
}
