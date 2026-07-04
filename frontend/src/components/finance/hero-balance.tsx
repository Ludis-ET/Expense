'use client';

import Link from 'next/link';
import { ArrowRight, Calendar, TrendingDown, TrendingUp, Wallet } from 'lucide-react';
import { formatEthiopian } from '@/lib/ethiopian-calendar';
import { useCurrencyView } from '@/lib/currency-view-context';
import { cn } from '@/lib/utils';
import type { DashboardData } from '@/lib/types';

interface HeroBalanceProps {
  data: DashboardData;
  money: (v: number | string) => string;
  userName?: string;
}

export function HeroBalance({ data, money, userName }: HeroBalanceProps) {
  const { activeCurrency, activeBreakdown, convertedTotal } = useCurrencyView();

  const month = activeBreakdown?.month ?? data.month;
  const balance = activeBreakdown?.totalBalance ?? data.totalBalance;
  const accounts = data.accounts.filter((a) => a.currency === activeCurrency);

  const net = Number(month.net);
  const income = Number(month.income);
  const expense = Number(month.expense);
  const savingsRate = income > 0 ? Math.round((net / income) * 100) : null;

  const now = new Date();
  const gregorian = now.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
  const ethiopian = formatEthiopian(now);

  const hour = now.getHours();
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
            <div className="mt-2 flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-3">
              <span className="flex items-center gap-1.5 text-xs opacity-75">
                <Calendar className="h-3.5 w-3.5" />
                {gregorian}
              </span>
              <span className="hidden text-white/40 sm:inline">·</span>
              <span className="text-xs font-medium opacity-90">
                ግዕዝ · {ethiopian}
              </span>
            </div>
          </div>
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-white/15 backdrop-blur-sm">
            <Wallet className="h-5 w-5" />
          </div>
        </div>

        <p className="mt-1 text-xs opacity-60">
          Total balance · {activeCurrency}
        </p>

        <p className="mt-3 text-4xl font-bold tracking-tight tabular-nums md:text-5xl">
          {money(balance)}
        </p>

        {convertedTotal && !convertedTotal.complete && convertedTotal.missingRates.length > 0 && (
          <p className="mt-2 text-xs opacity-75">
            Other currencies are not included. Add exchange rates in Settings to see a combined total.
          </p>
        )}

        <div className="mt-6 flex flex-wrap gap-3">
          <div className="flex items-center gap-2 rounded-xl bg-white/15 px-3.5 py-2 backdrop-blur-sm">
            <TrendingUp className="h-4 w-4 opacity-80" />
            <div>
              <p className="text-[10px] font-medium uppercase tracking-wide opacity-70">Income</p>
              <p className="text-sm font-semibold tabular-nums">{money(income)}</p>
            </div>
            {month.incomeDeltaPct !== null && (
              <span className="ml-1 text-xs font-medium opacity-80">
                {month.incomeDeltaPct >= 0 ? '+' : ''}{month.incomeDeltaPct}%
              </span>
            )}
          </div>
          <div className="flex items-center gap-2 rounded-xl bg-white/15 px-3.5 py-2 backdrop-blur-sm">
            <TrendingDown className="h-4 w-4 opacity-80" />
            <div>
              <p className="text-[10px] font-medium uppercase tracking-wide opacity-70">Spent</p>
              <p className="text-sm font-semibold tabular-nums">{money(expense)}</p>
            </div>
            {month.expenseDeltaPct !== null && (
              <span className={cn('ml-1 text-xs font-medium', (month.expenseDeltaPct ?? 0) > 0 ? 'opacity-90' : 'opacity-80')}>
                {month.expenseDeltaPct >= 0 ? '+' : ''}{month.expenseDeltaPct}%
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

        {accounts.length > 0 && (
          <div className="mt-5 flex flex-wrap gap-2">
            {accounts.slice(0, 4).map((a) => (
              <span
                key={a.id}
                className="rounded-lg bg-white/10 px-2.5 py-1 text-xs font-medium backdrop-blur-sm border-l-[3px]"
                style={a.color ? { borderLeftColor: a.color } : undefined}
              >
                {a.name}{a.isShared ? ' · shared' : ''}: {money(a.balance)}
              </span>
            ))}
            {data.accounts.filter((a) => a.currency === activeCurrency).length > 4 && (
              <Link href="/accounts" className="rounded-lg bg-white/10 px-2.5 py-1 text-xs font-medium backdrop-blur-sm hover:bg-white/20">
                +{data.accounts.filter((a) => a.currency === activeCurrency).length - 4} more
              </Link>
            )}
          </div>
        )}

        <Link href="/accounts" className="mt-5 inline-flex items-center gap-1.5 text-sm font-medium opacity-80 transition-opacity hover:opacity-100">
          Manage accounts <ArrowRight className="h-3.5 w-3.5" />
        </Link>
      </div>
    </div>
  );
}
