'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { LogOut, Lock, Menu, Plus, Search, Sparkles } from 'lucide-react';
import { Avatar } from '@/components/ui/misc';
import { Button } from '@/components/ui/button';
import { AmountVisibilityToggle } from '@/components/amount-visibility-toggle';
import { CurrencySelector } from '@/components/finance/currency-selector';
import { DownloadAppButton } from '@/components/pwa/download-app-button';
import { ThemeToggle } from '@/components/theme-toggle';
import { NotificationsMenu } from './notifications-menu';
import { openAssistant } from '@/components/ai/assistant-fab';
import { useAuth } from '@/lib/auth';
import { useOptionalAppLock } from '@/lib/app-lock-context';

export function Topbar({ onMenu }: { onMenu: () => void }) {
  const { user, logout } = useAuth();
  const appLock = useOptionalAppLock();
  const router = useRouter();
  const [menuOpen, setMenuOpen] = useState(false);

  const openCommandPalette = () => {
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'k', ctrlKey: true, bubbles: true }));
  };

  return (
    <header className="glass sticky top-0 z-20 flex h-14 items-center gap-1.5 border-b border-border px-2.5 pt-[env(safe-area-inset-top)] sm:gap-3 sm:px-4 lg:h-16 lg:px-8">
      <button
        onClick={onMenu}
        className="rounded-xl p-2 text-muted transition-colors hover:bg-surface-muted lg:hidden"
        aria-label="Menu"
      >
        <Menu className="h-5 w-5" />
      </button>

      <button
        onClick={openCommandPalette}
        className="hidden items-center gap-2 rounded-xl border border-border bg-surface-muted/50 px-3.5 py-2 text-sm text-muted transition-colors hover:bg-surface-muted sm:flex"
      >
        <Search className="h-4 w-4" />
        <span>Search or jump to…</span>
        <kbd className="ml-4 rounded border border-border bg-surface px-1.5 py-0.5 text-[10px] font-medium">⌘K</kbd>
      </button>

      <div className="flex-1" />

      <div className="flex items-center gap-1 sm:gap-2">
        <CurrencySelector variant="header" />
        <button
          type="button"
          onClick={() => openAssistant('ask')}
          className="rounded-xl p-2 text-primary transition-colors hover:bg-primary/10 lg:hidden"
          aria-label="Ask Santim"
          title="Ask Santim"
        >
          <Sparkles className="h-5 w-5" />
        </button>
        <DownloadAppButton size="sm" variant="primary" className="hidden sm:inline-flex lg:hidden" label="App" />
        <Button size="sm" onClick={() => router.push('/transactions?add=1')} className="hidden shadow-sm sm:inline-flex">
          <Plus className="h-4 w-4" />
          <span className="hidden sm:inline">Add</span>
        </Button>
        <button
          onClick={openCommandPalette}
          className="rounded-xl p-2 text-muted transition-colors hover:bg-surface-muted sm:hidden"
          aria-label="Search"
        >
          <Search className="h-5 w-5" />
        </button>
        <AmountVisibilityToggle />
        {/* {appLock?.enabled && (
          <button
            type="button"
            onClick={() => appLock.lock()}
            className="rounded-xl p-2 text-muted transition-colors hover:bg-surface-muted hover:text-foreground"
            aria-label="Lock app"
            title="Lock app"
          >
            <Lock className="h-5 w-5" />
          </button>
        )} */}
        <ThemeToggle />
        <NotificationsMenu />
        <div className="relative">
          <button
            onClick={() => setMenuOpen((o) => !o)}
            className="flex items-center gap-2 rounded-xl p-1 pr-1.5 transition-colors hover:bg-surface-muted sm:pr-2"
          >
            <Avatar name={user?.name ?? '?'} className="h-8 w-8 text-[10px]" />
            <span className="hidden text-sm font-medium md:block">{user?.name?.split(' ')[0]}</span>
          </button>
          {menuOpen && (
            <>
              <div className="fixed inset-0 z-40" onClick={() => setMenuOpen(false)} />
              <div className="absolute right-0 z-50 mt-2 w-56 overflow-hidden rounded-xl border border-border bg-surface shadow-xl animate-in">
                <div className="border-b border-border px-4 py-3">
                  <p className="truncate text-sm font-medium">{user?.name}</p>
                  <p className="truncate text-xs text-muted">{user?.email}</p>
                </div>
                <button
                  onClick={() => {
                    setMenuOpen(false);
                    openAssistant('ask');
                  }}
                  className="flex w-full items-center gap-2 px-4 py-2.5 text-sm transition-colors hover:bg-surface-muted lg:hidden"
                >
                  <Sparkles className="h-4 w-4 text-primary" /> Ask Santim
                </button>
                <button
                  onClick={() => {
                    setMenuOpen(false);
                    if (appLock?.enabled) appLock.lock();
                    else router.push('/settings#app-lock');
                  }}
                  className="flex w-full items-center gap-2 px-4 py-2.5 text-sm transition-colors hover:bg-surface-muted"
                >
                  <Lock className="h-4 w-4" /> {appLock?.enabled ? 'Lock app' : 'Set up app lock'}
                </button>
                <button
                  onClick={logout}
                  className="flex w-full items-center gap-2 px-4 py-2.5 text-sm text-danger transition-colors hover:bg-surface-muted"
                >
                  <LogOut className="h-4 w-4" /> Sign out
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </header>
  );
}
