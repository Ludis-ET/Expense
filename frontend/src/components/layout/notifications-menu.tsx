'use client';

import { useState } from 'react';
import useSWR from 'swr';
import { Bell, CheckCheck } from 'lucide-react';
import { api } from '@/lib/api';
import { relativeTime } from '@/lib/format';
import { cn } from '@/lib/utils';
import type { Notification } from '@/lib/types';

interface NotificationData {
  items: Notification[];
  unread: number;
}

export function NotificationsMenu() {
  const [open, setOpen] = useState(false);
  const { data, mutate } = useSWR<NotificationData>('/notifications', { refreshInterval: 30_000 });

  const unread = data?.unread ?? 0;

  async function markAll() {
    await api.post('/notifications/read-all');
    void mutate();
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
                data.items.map((n) => (
                  <div
                    key={n.id}
                    className={cn(
                      'border-b border-border px-4 py-3 last:border-0',
                      !n.readFlag && 'bg-primary/5',
                    )}
                  >
                    <div className="flex items-start gap-2">
                      {!n.readFlag && <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-primary" />}
                      <div className={cn(!n.readFlag ? '' : 'pl-4')}>
                        <p className="text-sm leading-snug">{n.message}</p>
                        <p className="mt-1 text-xs text-muted">{relativeTime(n.createdAt)}</p>
                      </div>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
