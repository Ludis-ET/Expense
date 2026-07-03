'use client';

import { useRouter } from 'next/navigation';
import { ArrowLeftRight, BarChart3, PiggyBank, Plus, Repeat, Sparkles, Target } from 'lucide-react';
import { cn } from '@/lib/utils';

const actions = [
  { label: 'Add expense', icon: Plus, href: '/transactions?add=1', color: 'from-emerald-500 to-teal-600' },
  { label: 'Transfer', icon: ArrowLeftRight, href: '/transactions?transfer=1', color: 'from-blue-500 to-indigo-600' },
  { label: 'Set budget', icon: PiggyBank, href: '/budgets', color: 'from-amber-500 to-orange-600' },
  { label: 'New goal', icon: Target, href: '/goals', color: 'from-violet-500 to-purple-600' },
  { label: 'Recurring', icon: Repeat, href: '/recurring', color: 'from-cyan-500 to-blue-600' },
  { label: 'Ask AI', icon: Sparkles, href: '/assistant', color: 'from-pink-500 to-rose-600' },
  { label: 'Analytics', icon: BarChart3, href: '/analytics', color: 'from-slate-500 to-slate-700' },
];

export function QuickActions({ className }: { className?: string }) {
  const router = useRouter();

  return (
    <div className={cn('flex gap-2 overflow-x-auto pb-1 scrollbar-none', className)}>
      {actions.map((a) => (
        <button
          key={a.label}
          onClick={() => router.push(a.href)}
          className="group flex shrink-0 items-center gap-2.5 rounded-xl border border-border bg-surface px-4 py-2.5 text-sm font-medium shadow-sm transition-all hover:-translate-y-0.5 hover:shadow-md"
        >
          <span className={cn('flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br text-white shadow-sm', a.color)}>
            <a.icon className="h-4 w-4" />
          </span>
          {a.label}
        </button>
      ))}
    </div>
  );
}
