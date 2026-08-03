'use client';

import useSWR from 'swr';
import { Snowflake, Sun } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/misc';
import { InfoHint } from '@/components/ui/info-hint';
import { BarChart } from '@/components/charts/bar';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type { SeasonalReport } from '@/lib/types';

/**
 * Is this month unusual *for me*?
 *
 * Every figure here carries the number of months it was averaged from, because
 * one January is an anecdote. Below three observed months the tab says so
 * plainly rather than drawing a seasonal curve out of a single year.
 */
export function AnalyticsSeasons({ currency }: { currency: string }) {
  const { money } = useMoney();
  const { data } = useSWR<SeasonalReport>(
    `/analytics/seasonal?weeks=12&currency=${encodeURIComponent(currency)}`,
  );

  if (!data) return <Skeleton className="h-80 rounded-2xl" />;

  const observed = data.months.filter((m) => m.samples > 0);
  const multiYear = data.years.length > 1;

  return (
    <div className="space-y-4">
      {data.monthsObserved < 3 && (
        <p className="rounded-xl border border-border bg-surface-muted/40 px-3 py-2 text-xs text-muted">
          Only {data.monthsObserved} month{data.monthsObserved === 1 ? '' : 's'} of history so far.
          Seasonal patterns need a year or two before they mean anything    this page will get more
          useful on its own.
        </p>
      )}

      <Card>
        <CardContent className="p-4 sm:p-5">
          <h2 className="mb-3 flex items-center gap-2 text-sm font-semibold">
            <Sun className="h-4 w-4 text-muted" />
            Your year in months
            <InfoHint label="About the seasonal average">
              Average spend for each calendar month across every year you have data for. A month is
              divided by how many times you have actually lived it, not by the age of the account,
              so a single observed January is shown as an average of one    check the sample count
              before reading much into it.
            </InfoHint>
          </h2>

          {observed.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted">No history yet.</p>
          ) : (
            <>
              <BarChart
                data={data.months.map((m) => ({
                  label: m.name.slice(0, 3),
                  value: Number(m.avgExpense),
                }))}
                format={(v) => money(v)}
                height={170}
              />

              <div className="mt-4 grid gap-3 sm:grid-cols-2">
                {data.dearestMonth && (
                  <Highlight
                    icon={Sun}
                    tone="warm"
                    label="Costliest month"
                    name={data.dearestMonth.name}
                    amount={money(data.dearestMonth.avgExpense)}
                    samples={data.dearestMonth.samples}
                  />
                )}
                {data.cheapestMonth && data.cheapestMonth.month !== data.dearestMonth?.month && (
                  <Highlight
                    icon={Snowflake}
                    tone="cool"
                    label="Quietest month"
                    name={data.cheapestMonth.name}
                    amount={money(data.cheapestMonth.avgExpense)}
                    samples={data.cheapestMonth.samples}
                  />
                )}
              </div>

              <ul className="mt-4 space-y-1">
                {observed.map((m) => (
                  <li key={m.month} className="flex items-center justify-between gap-3 text-xs">
                    <span className="min-w-0 truncate">
                      {m.name}
                      <span className="text-muted">
                        {' '}
                        · {m.samples} year{m.samples === 1 ? '' : 's'} of data
                      </span>
                    </span>
                    <span className="shrink-0 tabular-nums text-muted">
                      out {money(m.avgExpense)} · in {money(m.avgIncome)}
                    </span>
                  </li>
                ))}
              </ul>
            </>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="p-4 sm:p-5">
          <h2 className="mb-3 flex items-center gap-2 text-sm font-semibold">
            Year on year
            <InfoHint label="About the yearly comparison">
              Whole-calendar-year totals. The current year is still running, so it will always look
              smaller than a finished one until December.
            </InfoHint>
          </h2>

          {data.years.length === 0 ? (
            <p className="py-6 text-center text-sm text-muted">No history yet.</p>
          ) : (
            <>
              <div className="overflow-x-auto">
                <table className="w-full min-w-96 text-sm">
                  <thead>
                    <tr className="border-b border-border text-left text-xs text-muted">
                      <th className="pb-2 font-medium">Year</th>
                      <th className="pb-2 text-right font-medium">In</th>
                      <th className="pb-2 text-right font-medium">Out</th>
                      <th className="pb-2 text-right font-medium">Kept</th>
                      <th className="pb-2 text-right font-medium">Rate</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.years.map((y) => {
                      const net = Number(y.net);
                      const running = y.year === new Date().getUTCFullYear();
                      return (
                        <tr key={y.year} className="border-b border-border last:border-0">
                          <td className="py-2 font-medium tabular-nums">
                            {y.year}
                            {running && (
                              <span className="ml-1.5 text-[10px] font-normal text-muted">
                                so far
                              </span>
                            )}
                          </td>
                          <td className="py-2 text-right tabular-nums">{money(y.income)}</td>
                          <td className="py-2 text-right tabular-nums">{money(y.expense)}</td>
                          <td
                            className={cn(
                              'py-2 text-right font-semibold tabular-nums',
                              net >= 0
                                ? 'text-emerald-600 dark:text-emerald-400'
                                : 'text-rose-600 dark:text-rose-400',
                            )}
                          >
                            {net >= 0 ? '+' : '−'}
                            {money(Math.abs(net))}
                          </td>
                          <td className="py-2 text-right tabular-nums text-muted">
                            {y.savingsRate === null ? '  ' : `${y.savingsRate}%`}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
              {!multiYear && (
                <p className="mt-3 text-xs text-muted">
                  One year of data    there is nothing to compare it against yet.
                </p>
              )}
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function Highlight({
  icon: Icon,
  tone,
  label,
  name,
  amount,
  samples,
}: {
  icon: typeof Sun;
  tone: 'warm' | 'cool';
  label: string;
  name: string;
  amount: string;
  samples: number;
}) {
  return (
    <div
      className={cn(
        'rounded-xl border px-3 py-2.5',
        tone === 'warm'
          ? 'border-amber-500/25 bg-amber-500/5'
          : 'border-sky-500/25 bg-sky-500/5',
      )}
    >
      <p className="flex items-center gap-1.5 text-xs text-muted">
        <Icon
          className={cn('h-3.5 w-3.5', tone === 'warm' ? 'text-amber-500' : 'text-sky-500')}
        />
        {label}
      </p>
      <p className="mt-0.5 font-semibold">
        {name} <span className="tabular-nums">· {amount}</span>
      </p>
      <p className="text-[11px] text-muted">
        averaged over {samples} year{samples === 1 ? '' : 's'}
      </p>
    </div>
  );
}
