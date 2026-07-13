'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { useTheme } from 'next-themes';
import {
  ArrowLeftRight,
  BarChart3,
  HandCoins,
  LayoutDashboard,
  Lock,
  Moon,
  PiggyBank,
  Plus,
  Search,
  Settings,
  Sparkles,
  Sun,
  Wallet,
} from 'lucide-react';
import { openAssistant } from '@/components/ai/assistant-fab';
import { cn } from '@/lib/utils';
import { useOptionalAppLock } from '@/lib/app-lock-context';

interface Command {
  id: string;
  label: string;
  hint?: string;
  icon: React.ComponentType<{ className?: string }>;
  run: () => void;
}

export function CommandPalette() {
  const router = useRouter();
  const { resolvedTheme, setTheme } = useTheme();
  const appLock = useOptionalAppLock();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [active, setActive] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  const commands = useMemo<Command[]>(() => {
    const go = (path: string) => () => {
      router.push(path);
      setOpen(false);
    };
    const items: Command[] = [
      { id: 'add', label: 'Add transaction', hint: 'quick add', icon: Plus, run: go('/transactions?add=1') },
      { id: 'dashboard', label: 'Go to Dashboard', icon: LayoutDashboard, run: go('/dashboard') },
      { id: 'transactions', label: 'Go to Transactions', icon: ArrowLeftRight, run: go('/transactions') },
      { id: 'recurring', label: 'Go to Recurring rules', icon: ArrowLeftRight, run: go('/transactions?tab=recurring') },
      { id: 'accounts', label: 'Go to Accounts', icon: Wallet, run: go('/accounts') },
      { id: 'plan', label: 'Go to Budgets & Goals', icon: PiggyBank, run: go('/budgets') },
      { id: 'goals', label: 'Go to Savings goals', icon: PiggyBank, run: go('/budgets?tab=goals') },
      { id: 'tab', label: 'Go to Money Tab', hint: 'loans & IOUs', icon: HandCoins, run: go('/tab') },
      { id: 'analytics', label: 'Go to Analytics', icon: BarChart3, run: go('/analytics') },
      { id: 'assistant', label: 'Ask about your money', hint: 'AI', icon: Sparkles, run: () => { openAssistant('ask'); setOpen(false); } },
      { id: 'household', label: 'Couples & shared accounts', icon: Wallet, run: go('/settings#household') },
      { id: 'settings', label: 'Go to Settings', icon: Settings, run: go('/settings') },
      { id: 'app-lock', label: 'App lock settings', icon: Lock, run: go('/settings#app-lock') },
    ];
    if (appLock?.enabled) {
      items.push({
        id: 'lock-now',
        label: 'Lock Santim now',
        hint: 'PIN / biometrics',
        icon: Lock,
        run: () => {
          appLock.lock();
          setOpen(false);
        },
      });
    }
    items.push({
      id: 'theme',
      label: 'Toggle theme',
      icon: resolvedTheme === 'dark' ? Sun : Moon,
      run: () => {
        setTheme(resolvedTheme === 'dark' ? 'light' : 'dark');
        setOpen(false);
      },
    });
    return items;
  }, [router, resolvedTheme, setTheme, appLock]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return commands;
    return commands.filter((c) => (c.label + (c.hint ?? '')).toLowerCase().includes(q));
  }, [commands, query]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        setOpen((o) => !o);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  useEffect(() => {
    if (open) {
      setQuery('');
      setActive(0);
      setTimeout(() => inputRef.current?.focus(), 10);
    }
  }, [open]);

  useEffect(() => setActive(0), [query]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[60] flex items-start justify-center p-4 pt-[14vh]">
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" onClick={() => setOpen(false)} />
      <div className="card relative z-10 w-full max-w-lg overflow-hidden shadow-2xl animate-in">
        <div className="flex items-center gap-3 border-b border-border px-4">
          <Search className="h-4.5 w-4.5 text-muted" />
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'ArrowDown') {
                e.preventDefault();
                setActive((a) => Math.min(a + 1, filtered.length - 1));
              } else if (e.key === 'ArrowUp') {
                e.preventDefault();
                setActive((a) => Math.max(a - 1, 0));
              } else if (e.key === 'Enter') {
                e.preventDefault();
                filtered[active]?.run();
              } else if (e.key === 'Escape') {
                setOpen(false);
              }
            }}
            placeholder="Search commands…"
            className="h-12 flex-1 bg-transparent text-sm outline-none placeholder:text-muted"
          />
          <kbd className="rounded border border-border px-1.5 py-0.5 text-[10px] text-muted">ESC</kbd>
        </div>
        <ul className="max-h-80 overflow-y-auto p-2">
          {filtered.length === 0 && <li className="px-3 py-6 text-center text-sm text-muted">No commands.</li>}
          {filtered.map((c, i) => (
            <li key={c.id}>
              <button
                onMouseEnter={() => setActive(i)}
                onClick={c.run}
                className={cn(
                  'flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-left text-sm',
                  i === active ? 'bg-primary/10 text-primary' : 'text-foreground hover:bg-surface-muted',
                )}
              >
                <c.icon className="h-4 w-4 shrink-0" />
                <span className="flex-1">{c.label}</span>
                {c.hint && <span className="text-xs text-muted">{c.hint}</span>}
              </button>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
