'use client';

import { Activity, Shield, TrendingUp, Wallet } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { DashboardData } from '@/lib/types';

interface HealthFactor {
  label: string;
  score: number;
  icon: React.ComponentType<{ className?: string }>;
}

function computeHealth(data: DashboardData): { score: number; factors: HealthFactor[]; label: string; color: string } {
  const income = Number(data.month.income);
  const expense = Number(data.month.expense);
  const net = Number(data.month.net);

  const savingsScore = income > 0 ? Math.min(100, Math.max(0, (net / income) * 100 + 50)) : 50;

  const budgetCount = data.budgetsAtRisk.length;
  const overCount = data.budgetsAtRisk.filter((b) => b.status === 'over').length;
  const budgetScore = budgetCount === 0 ? 85 : Math.max(0, 100 - overCount * 30 - (budgetCount - overCount) * 10);

  const unnecessary = Number(data.unnecessary.total);
  const unnecessaryScore =
    expense > 0 ? Math.max(0, 100 - (unnecessary / expense) * 200) : 90;

  const goalScore =
    data.goals.length > 0
      ? data.goals.reduce((s, g) => s + g.pct, 0) / data.goals.length
      : 60;

  const factors: HealthFactor[] = [
    { label: 'Savings', score: Math.round(savingsScore), icon: TrendingUp },
    { label: 'Budgets', score: Math.round(budgetScore), icon: Shield },
    { label: 'Discipline', score: Math.round(unnecessaryScore), icon: Activity },
    { label: 'Goals', score: Math.round(goalScore), icon: Wallet },
  ];

  const score = Math.round(factors.reduce((s, f) => s + f.score, 0) / factors.length);

  let label = 'Needs attention';
  let color = 'text-danger';
  if (score >= 80) {
    label = 'Excellent';
    color = 'text-emerald-500';
  } else if (score >= 60) {
    label = 'Good';
    color = 'text-primary';
  } else if (score >= 40) {
    label = 'Fair';
    color = 'text-warning';
  }

  return { score, factors, label, color };
}

export function FinancialHealth({ data }: { data: DashboardData }) {
  const { score, factors, label, color } = computeHealth(data);
  const circumference = 2 * Math.PI * 42;
  const offset = circumference - (score / 100) * circumference;

  return (
    <div className="card flex flex-col items-center p-6">
      <p className="mb-4 self-start text-sm font-medium text-muted">Financial health</p>
      <div className="relative">
        <svg width="120" height="120" className="-rotate-90">
          <circle cx="60" cy="60" r="42" fill="none" stroke="var(--surface-muted)" strokeWidth="8" />
          <circle
            cx="60"
            cy="60"
            r="42"
            fill="none"
            stroke="var(--primary)"
            strokeWidth="8"
            strokeLinecap="round"
            strokeDasharray={circumference}
            strokeDashoffset={offset}
            className="transition-all duration-1000 ease-out"
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-3xl font-bold tabular-nums">{score}</span>
          <span className={cn('text-xs font-semibold', color)}>{label}</span>
        </div>
      </div>
      <div className="mt-5 grid w-full grid-cols-2 gap-2">
        {factors.map((f) => (
          <div key={f.label} className="flex items-center gap-2 rounded-lg bg-surface-muted/60 px-2.5 py-2">
            <f.icon className="h-3.5 w-3.5 shrink-0 text-muted" />
            <div className="min-w-0 flex-1">
              <p className="truncate text-[10px] text-muted">{f.label}</p>
              <p className="text-xs font-semibold tabular-nums">{f.score}%</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
