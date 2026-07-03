'use client';

import Link from 'next/link';
import { ArrowRight, TrendingDown, TrendingUp, Wallet } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { DashboardData } from '@/lib/types';

interface HeroBalanceProps {
  data: DashboardData;
  money: (v: number | string) => string;
  userName?: string;
}

export function HeroBalance({ data, money, userName }: HeroBalanceProps) {
  const net = Number(data.month.net);
  const income = Number(data.month.income);
  const expense = Number(data.month.expense);
  const savingsRate = income > 0 ? Math.round((net / income) * 100) : null;

  const hour = new Date().getHours();
  const greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

  return (
    <div className="relative overflow-hidden rounded-2xl border border-border bg-gradient-to-br from-primary via-primary to-accent p-6 text-primary-foreground shadow-lg shadow-primary/20 md:p-8">
      <div className="pointer-events-none absolute -right-16 -top-16 h-48 w-48 rounded-full bg-white/10 blur-2xl" />
      <div className="pointer-events-none absolute -bottom-8 -left-8 h-32 w-32 rounded-full bg-white/5 blur-xl" />
      <div className="bg-grid pointer-events-none absolute inset-0 opacity-10" />

      <div className="relative">
        <div className="flex items-start justify-between gap-4">
          <div>
            <p className="text-sm font-medium opacity-80">
              {greeting}{userName ? `, ${userName}` : ''}
            </p>
            <p className="mt-1 text-xs opacity-60">Total balance across all accounts</p>
          </div>
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-white/15 backdrop-blur-sm">
            <Wallet className="h-5 w-5" />
          </div>
        </div>

        <p className="mt-4 text-4xl font-bold tracking-tight tabular-nums md:text-5xl">
          {money(data.totalBalance)}
        </p>

        <div className="mt-6 flex flex-wrap gap-3">
          <div className="flex items-center gap-2 rounded-xl bg-white/15 px-3.5 py-2 backdrop-blur-sm">
            <TrendingUp className="h-4 w-4 opacity-80" />
            <div>
              <p className="text-[10px] font-medium uppercase tracking-wide opacity-70">Income</p>
              <p className="text-sm font-semibold tabular-nums">{money(income)}</p>
            </div>
            {data.month.incomeDeltaPct !== null && (
              <span className="ml-1 text-xs font-medium opacity-80">
                {data.month.incomeDeltaPct >= 0 ? '+' : ''}{data.month.incomeDeltaPct}%
              </span>
            )}
          </div>
          <div className="flex items-center gap-2 rounded-xl bg-white/15 px-3.5 py-2 backdrop-blur-sm">
            <TrendingDown className="h-4 w-4 opacity-80" />
            <div>
              <p className="text-[10px] font-medium uppercase tracking-wide opacity-70">Spent</p>
              <p className="text-sm font-semibold tabular-nums">{money(expense)}</p>
            </div>
            {data.month.expenseDeltaPct !== null && (
              <span className={cn(
                'ml-1 text-xs font-medium',
                (data.month.expenseDeltaPct ?? 0) > 0 ? 'opacity-90' : 'opacity-80',
              )}>
                {data.month.expenseDeltaPct >= 0 ? '+' : ''}{data.month.expenseDeltaPct}%
              </span>
            )}
          </div>
          {savingsRate !== null && (
            <div className="flex items-center gap-2 rounded-xl bg-white/15 px-3.5 py-2 backdrop-blur-sm">
              <div>
                <p className="text-[10px] font-medium uppercase tracking-wide opacity-70">Saved</p>
                <p className="text-sm font-semibold tabular-nums">{savingsRate}%</p>
              </div>
            </div>
          )}
        </div>

        {data.accounts.length > 0 && (
          <div className="mt-5 flex flex-wrap gap-2">
            {data.accounts.slice(0, 4).map((a) => (
              <span
                key={a.id}
                className="rounded-lg bg-white/10 px-2.5 py-1 text-xs font-medium backdrop-blur-sm"
                style={a.color ? { borderLeft: `3px solid ${a.color}` } : undefined}
              >
                {a.name}: {money(a.balance)}
              </span>
            ))}
            {data.accounts.length > 4 && (
              <Link href="/accounts" className="rounded-lg bg-white/10 px-2.5 py-1 text-xs font-medium backdrop-blur-sm hover:bg-white/20">
                +{data.accounts.length - 4} more
              </Link>
            )}
          </div>
        )}

        <Link
          href="/accounts"
          className="mt-5 inline-flex items-center gap-1.5 text-sm font-medium opacity-80 transition-opacity hover:opacity-100"
        >
          Manage accounts <ArrowRight className="h-3.5 w-3.5" />
        </Link>
      </div>
    </div>
  );
}
