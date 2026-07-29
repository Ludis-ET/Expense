'use client';

import { Activity, HelpCircle, PiggyBank, Shield, TrendingUp } from 'lucide-react';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type { DashboardData } from '@/lib/types';

interface Factor {
  label: string;
  /** 0-100, or null when there is not enough data to judge. */
  score: number | null;
  /** The real figure the score came from, shown under the label. */
  detail: string;
  icon: React.ComponentType<{ className?: string }>;
}

/**
 * Every factor is derived from live figures and shows the number behind it, so
 * the score is auditable rather than a vibe. A factor with nothing to measure
 * scores `null` and is left out of the average instead of being guessed at.
 */
function computeHealth(data: DashboardData, money: (v: number | string) => string) {
  const income = Number(data.month.income);
  const expense = Number(data.month.expense);
  const net = Number(data.month.net);
  const unnecessary = Number(data.unnecessary?.total ?? 0);

  // 1. Savings rate: what share of income you kept this month.
  const savingsRate = income > 0 ? (net / income) * 100 : null;
  const savings: Factor = {
    label: 'Savings rate',
    // 20% saved is the common target, so that maps to a full score.
    score: savingsRate === null ? null : clamp((savingsRate / 20) * 100),
    detail:
      savingsRate === null
        ? 'no income yet this month'
        : `${Math.round(savingsRate)}% of ${money(income)} kept`,
    icon: TrendingUp,
  };

  // 2. Plan health: are your active plans still holding money?
  const atRisk = data.budgetsAtRisk.length;
  const activePlans = data.budgetTotals?.activeCount ?? 0;
  const plans: Factor = {
    label: 'Plans',
    score: activePlans === 0 ? null : clamp(((activePlans - atRisk) / activePlans) * 100),
    detail:
      activePlans === 0
        ? 'no plans yet'
        : atRisk === 0
          ? `all ${activePlans} on track`
          : `${atRisk} of ${activePlans} running low`,
    icon: Shield,
  };

  // 3. Funding: how much of what you planned is actually set aside.
  const planned = Number(data.budgetTotals?.planned ?? 0);
  const funded = Number(data.budgetTotals?.funded ?? 0);
  const funding: Factor = {
    label: 'Funded',
    score: planned === 0 ? null : clamp((funded / planned) * 100),
    detail:
      planned === 0
        ? 'nothing planned yet'
        : `${money(funded)} of ${money(planned)} set aside`,
    icon: PiggyBank,
  };

  // 4. Discipline: how much of your spending you flagged as unnecessary.
  const wasteShare = expense > 0 ? (unnecessary / expense) * 100 : null;
  const discipline: Factor = {
    label: 'Discipline',
    // 10% of spend on impulse buys zeroes it out; nothing wasted is full marks.
    score: wasteShare === null ? null : clamp(100 - wasteShare * 10),
    detail:
      wasteShare === null
        ? 'no spending yet this month'
        : unnecessary === 0
          ? 'nothing flagged unnecessary'
          : `${money(unnecessary)} unnecessary (${Math.round(wasteShare)}%)`,
    icon: Activity,
  };

  const factors = [savings, plans, funding, discipline];
  const scored = factors.filter((f) => f.score !== null);
  const score =
    scored.length === 0
      ? null
      : Math.round(scored.reduce((s, f) => s + (f.score ?? 0), 0) / scored.length);

  let label = 'Not enough data';
  let color = 'text-muted';
  if (score !== null) {
    if (score >= 80) {
      label = 'Excellent';
      color = 'text-emerald-500';
    } else if (score >= 60) {
      label = 'Good';
      color = 'text-primary';
    } else if (score >= 40) {
      label = 'Fair';
      color = 'text-warning';
    } else {
      label = 'Needs attention';
      color = 'text-danger';
    }
  }

  return { score, factors, label, color, measured: scored.length };
}

const clamp = (n: number) => Math.max(0, Math.min(100, Math.round(n)));

export function FinancialHealth({ data }: { data: DashboardData }) {
  const { money } = useMoney();
  const { score, factors, label, color, measured } = computeHealth(data, money);
  const circumference = 2 * Math.PI * 42;
  const shown = score ?? 0;
  const offset = circumference - (shown / 100) * circumference;

  return (
    <div className="card flex flex-col items-center p-6">
      <div className="mb-4 flex w-full items-center justify-between gap-2">
        <p className="text-sm font-medium text-muted">Financial health</p>
        <span
          title={`Averaged over the ${measured} factor${measured === 1 ? '' : 's'} there is data for.`}
          className="text-muted"
        >
          <HelpCircle className="h-3.5 w-3.5" />
        </span>
      </div>

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
          <span className="text-3xl font-bold tabular-nums">{score ?? '-'}</span>
          <span className={cn('text-xs font-semibold', color)}>{label}</span>
        </div>
      </div>

      <div className="mt-5 w-full space-y-1.5">
        {factors.map((f) => (
          <div
            key={f.label}
            className="flex items-center gap-2.5 rounded-lg bg-surface-muted/60 px-2.5 py-2"
          >
            <f.icon className="h-4 w-4 shrink-0 text-muted" />
            <div className="min-w-0 flex-1">
              <p className="truncate text-xs font-medium">{f.label}</p>
              <p className="truncate text-[10px] text-muted">{f.detail}</p>
            </div>
            {f.score === null ? (
              <span className="shrink-0 text-[10px] font-medium text-muted">-</span>
            ) : (
              <span className="flex shrink-0 items-center gap-1.5">
                <span className="h-1 w-8 overflow-hidden rounded-full bg-border">
                  <span
                    className={cn(
                      'block h-full rounded-full transition-all duration-700',
                      f.score >= 70
                        ? 'bg-emerald-500'
                        : f.score >= 40
                          ? 'bg-primary'
                          : 'bg-warning',
                    )}
                    style={{ width: `${f.score}%` }}
                  />
                </span>
                <span className="w-7 text-right text-[10px] font-semibold tabular-nums">
                  {f.score}
                </span>
              </span>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
