'use client';

import { useState } from 'react';
import useSWR from 'swr';
import { TrendingUp } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/misc';
import { InfoHint } from '@/components/ui/info-hint';
import { IncomeExpenseLine } from '@/components/charts/line';
import { SignedBarChart } from '@/components/charts/bar';
import { useMoney } from '@/lib/amount-visibility';
import { formatMonth } from '@/lib/format';
import { cn } from '@/lib/utils';
import type { IncomeVsExpense } from '@/lib/types';

const RANGES = [6, 12, 24] as const;

/**
 * "Jul", or "Jul 26" once the range is long enough that two Julys could appear
 * and an unqualified label would be ambiguous.
 */
function shortMonth(yyyyMm: string, span: number): string {
  const short = formatMonth(yyyyMm).slice(0, 3);
  return span > 12 ? `${short} ${yyyyMm.slice(2, 4)}` : short;
}

/**
 * The long line: income against expense, month by month, plus what share of
 * income survived each one. Everything else on this tab is that same series
 * asked a different way.
 */
export function AnalyticsTrends({ currency }: { currency: string }) {
  const { money } = useMoney();
  const [months, setMonths] = useState<number>(12);
  const { data } = useSWR<IncomeVsExpense>(
    `/analytics/income-vs-expense?months=${months}&currency=${encodeURIComponent(currency)}`,
  );

  if (!data) return <Skeleton className="h-80 rounded-2xl" />;

  const points = data.points.map((p) => ({
    label: shortMonth(p.month, months),
    income: Number(p.income),
    expense: Number(p.expense),
  }));
  const withData = data.points.filter((p) => Number(p.income) > 0 || Number(p.expense) > 0);

  const netBars = data.points.map((p) => ({
    label: shortMonth(p.month, months),
    value: Number(p.income) - Number(p.expense),
  }));
  const savings = data.points
    .filter((p) => p.savingsRate !== null)
    .map((p) => ({ label: formatMonth(p.month).slice(0, 3), value: p.savingsRate! }));

  const best = withData.reduce<{ month: string; net: number } | null>((acc, p) => {
    const net = Number(p.income) - Number(p.expense);
    return !acc || net > acc.net ? { month: p.month, net } : acc;
  }, null);
  const worst = withData.reduce<{ month: string; net: number } | null>((acc, p) => {
    const net = Number(p.income) - Number(p.expense);
    return !acc || net < acc.net ? { month: p.month, net } : acc;
  }, null);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="flex items-center gap-2 text-sm font-semibold">
          <TrendingUp className="h-4 w-4 text-muted" />
          Income against spending
          <InfoHint label="About the trend">
            Each point is one calendar month. Transfers between your own accounts are excluded, so
            the gap between the lines is real money kept or lost.
          </InfoHint>
        </h2>
        <div className="flex items-center gap-1 rounded-xl border border-border bg-surface-muted/40 p-1">
          {RANGES.map((r) => (
            <button
              key={r}
              type="button"
              onClick={() => setMonths(r)}
              className={cn(
                'rounded-lg px-3 py-1.5 text-xs font-semibold transition-all',
                months === r ? 'bg-foreground text-background shadow-sm' : 'text-muted hover:text-foreground',
              )}
            >
              {r}m
            </button>
          ))}
        </div>
      </div>

      {withData.length === 0 ? (
        <Card>
          <CardContent className="p-6 text-center text-sm text-muted">
            No income or spending in the last {months} months.
          </CardContent>
        </Card>
      ) : (
        <>
          <Card>
            <CardContent className="p-4 sm:p-5">
              <IncomeExpenseLine points={points} format={(v) => money(v)} />
              <div className="mt-3 flex flex-wrap items-center gap-4 text-xs text-muted">
                <span className="inline-flex items-center gap-1.5">
                  <span className="h-2 w-4 rounded-full bg-emerald-500" /> income
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <span className="h-2 w-4 rounded-full bg-rose-500" /> spending
                </span>
              </div>
            </CardContent>
          </Card>

          <div className="grid gap-4 lg:grid-cols-2">
            <Card>
              <CardContent className="p-4 sm:p-5">
                <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold">
                  Kept each month
                  <InfoHint label="About kept each month">
                    Income minus spending. Bars below the line are months you spent more than came
                    in — living off savings, or off someone else.
                  </InfoHint>
                </h3>
                <SignedBarChart data={netBars} format={(v) => money(v)} height={160} />
                {best && worst && (
                  <p className="mt-3 text-xs text-muted">
                    Best: <strong className="text-foreground">{formatMonth(best.month)}</strong> (
                    {money(best.net)}) · Worst:{' '}
                    <strong className="text-foreground">{formatMonth(worst.month)}</strong> (
                    {money(worst.net)})
                  </p>
                )}
              </CardContent>
            </Card>

            <Card>
              <CardContent className="p-4 sm:p-5">
                <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold">
                  Savings rate
                  <InfoHint label="About savings rate">
                    The share of each month&apos;s income you did not spend. Months with no income
                    are left out rather than shown as zero — nothing came in to save.
                  </InfoHint>
                </h3>
                {savings.length === 0 ? (
                  <p className="py-8 text-center text-sm text-muted">No income recorded yet.</p>
                ) : (
                  // A month where you spent more than came in has a negative
                  // savings rate, so this one has to be signed too.
                  <SignedBarChart
                    data={savings}
                    format={(v) => `${v}%`}
                    height={160}
                    positive="bg-primary"
                  />
                )}
              </CardContent>
            </Card>
          </div>
        </>
      )}
    </div>
  );
}
