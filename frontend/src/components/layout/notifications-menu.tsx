'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import useSWR from 'swr';
import {
  Bell,
  CheckCheck,
  Target,
  Sparkles,
  Star,
  ShoppingBag,
  AlertTriangle,
  CalendarClock,
  ChevronRight,
  type LucideIcon,
} from 'lucide-react';
import { api } from '@/lib/api';
import { relativeTime } from '@/lib/format';
import { cn } from '@/lib/utils';
import type { Notification } from '@/lib/types';

interface NotificationData {
  items: Notification[];
  unread: number;
}

/** Map a notification type to an icon + accent colour. */
function typeMeta(type: string): { icon: LucideIcon; cls: string; bg: string } {
  if (type.startsWith('goal')) return { icon: Target, cls: 'text-emerald-600 dark:text-emerald-400', bg: 'bg-emerald-500/12' };
  if (type === 'wishlist_funded') return { icon: Sparkles, cls: 'text-violet-600 dark:text-violet-400', bg: 'bg-violet-500/12' };
  if (type === 'wishlist_promoted') return { icon: Star, cls: 'text-amber-600 dark:text-amber-400', bg: 'bg-amber-500/12' };
  if (type === 'wishlist_bought') return { icon: ShoppingBag, cls: 'text-rose-600 dark:text-rose-400', bg: 'bg-rose-500/12' };
  if (type === 'budget_alert') return { icon: AlertTriangle, cls: 'text-amber-600 dark:text-amber-400', bg: 'bg-amber-500/12' };
  if (type === 'recurring_due') return { icon: CalendarClock, cls: 'text-sky-600 dark:text-sky-400', bg: 'bg-sky-500/12' };
  return { icon: Bell, cls: 'text-primary', bg: 'bg-primary/10' };
}

export function NotificationsMenu() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const { data, mutate } = useSWR<NotificationData>('/notifications', { refreshInterval: 30_000 });

  const unread = data?.unread ?? 0;

  async function markAll() {
    await api.post('/notifications/read-all');
    void mutate();
  }

  async function openNotification(n: Notification) {
    setOpen(false);
    // Optimistically mark read, then persist.
    if (!n.readFlag) {
      void mutate(
        (prev) =>
          prev
            ? {
                items: prev.items.map((x) => (x.id === n.id ? { ...x, readFlag: true } : x)),
                unread: Math.max(0, prev.unread - 1),
              }
            : prev,
        { revalidate: false },
      );
      try {
        await api.post(`/notifications/${n.id}/read`);
      } catch {
        void mutate();
      }
    }
    if (n.link) router.push(n.link);
  }

  return (
    <div className="relative">
      <button
        onClick={() => setOpen((o) => !o)}
        className="relative inline-flex h-9 w-9 items-center justify-center rounded-lg border border-border text-muted transition-colors hover:bg-surface-muted hover:text-foreground"
        aria-label="Notifications"
      >
        <Bell className="h-4.5 w-4.5" />
        {unread > 0 && (
          <span className="absolute -right-1 -top-1 flex h-4.5 min-w-4.5 items-center justify-center rounded-full bg-danger px-1 text-[10px] font-bold text-white">
            {unread > 9 ? '9+' : unread}
          </span>
        )}
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute right-0 z-50 mt-2 w-80 overflow-hidden rounded-xl border border-border bg-surface shadow-xl animate-in">
            <div className="flex items-center justify-between border-b border-border px-4 py-3">
              <span className="text-sm font-semibold">Notifications</span>
              {unread > 0 && (
                <button onClick={markAll} className="flex items-center gap-1 text-xs text-primary hover:underline">
                  <CheckCheck className="h-3.5 w-3.5" /> Mark all read
                </button>
              )}
            </div>
            <div className="max-h-80 overflow-y-auto">
              {!data?.items.length ? (
                <p className="px-4 py-8 text-center text-sm text-muted">You&apos;re all caught up 🎉</p>
              ) : (
                data.items.map((n) => {
                  const meta = typeMeta(n.type);
                  const Icon = meta.icon;
                  const clickable = !!n.link;
                  return (
                    <button
                      key={n.id}
                      type="button"
                      onClick={() => openNotification(n)}
                      className={cn(
                        'flex w-full items-start gap-3 border-b border-border px-4 py-3 text-left transition-colors last:border-0 hover:bg-surface-muted',
                        !n.readFlag && 'bg-primary/5',
                      )}
                    >
                      <span className={cn('mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg', meta.bg, meta.cls)}>
                        <Icon className="h-4 w-4" />
                      </span>
                      <div className="min-w-0 flex-1">
                        <p className="text-sm leading-snug">{n.message}</p>
                        <p className="mt-1 flex items-center gap-1 text-xs text-muted">
                          {relativeTime(n.createdAt)}
                          {clickable && <span className="text-primary">· View</span>}
                        </p>
                      </div>
                      {!n.readFlag && <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-primary" />}
                      {clickable && <ChevronRight className="mt-1 h-4 w-4 shrink-0 text-muted" />}
                    </button>
                  );
                })
              )}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
