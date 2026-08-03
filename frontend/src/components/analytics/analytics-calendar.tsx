'use client';

import { useState } from 'react';
import useSWR from 'swr';
import { CalendarDays, ChevronLeft, ChevronRight } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/misc';
import { InfoHint } from '@/components/ui/info-hint';
import { SpendHeatmap } from '@/components/charts/heatmap';
import { BarChart } from '@/components/charts/bar';
import { useMoney } from '@/lib/amount-visibility';
import type { SeasonalReport, SpendHeatmapData } from '@/lib/types';

/**
 * Time-of-day-of-week-of-year view: the calendar grid for density, the weekday
 * profile for habit, and recent weeks for pace.
 */
export function AnalyticsCalendar({ month, currency }: { month: string; currency: string }) {
  const { money } = useMoney();
  const [year, setYear] = useState(() => Number(month.slice(0, 4)));
  const cur = encodeURIComponent(currency);

  const { data: heat } = useSWR<SpendHeatmapData>(
    `/analytics/heatmap?year=${year}&currency=${cur}`,
  );
  const { data: seasonal } = useSWR<SeasonalReport>(
    `/analytics/seasonal?weeks=12&currency=${cur}`,
  );

  const thisYear = new Date().getUTCFullYear();

  return (
    <div className="space-y-4">
      <Card>
        <CardContent className="p-4 sm:p-5">
          <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
            <h2 className="flex items-center gap-2 text-sm font-semibold">
              <CalendarDays className="h-4 w-4 text-muted" />
              Every day of {year}
              <InfoHint label="About the calendar">
                One square per day, darker where you spent more. Empty squares are days with no
                spending at all    the gaps are as informative as the dark patches.
              </InfoHint>
            </h2>
            <div className="flex items-center gap-1">
              <button
                type="button"
                onClick={() => setYear((y) => y - 1)}
                className="rounded-lg p-1.5 text-muted transition-colors hover:bg-surface-muted hover:text-foreground"
                aria-label="Previous year"
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
              <span className="min-w-12 text-center text-sm font-semibold tabular-nums">{year}</span>
              <button
                type="button"
                onClick={() => setYear((y) => Math.min(thisYear, y + 1))}
                disabled={year >= thisYear}
                className="rounded-lg p-1.5 text-muted transition-colors hover:bg-surface-muted hover:text-foreground disabled:opacity-30"
                aria-label="Next year"
              >
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          </div>

          {!heat ? (
            <Skeleton className="h-32" />
          ) : heat.days.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted">No spending recorded in {year}.</p>
          ) : (
            <div className="overflow-x-auto">
              <SpendHeatmap
                days={heat.days.map((d) => ({ date: d.date, total: Number(d.total) }))}
                year={year}
                format={(v) => money(v)}
              />
            </div>
          )}
        </CardContent>
      </Card>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardContent className="p-4 sm:p-5">
            <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold">
              Which day you spend
              <InfoHint label="About the weekday profile">
                Average spend on days of each weekday that saw any spending, across your whole
                history. Dividing by days that actually had spending    rather than by every
                calendar day    stops a quiet Sunday from flattering the average.
              </InfoHint>
            </h3>
            {!seasonal ? (
              <Skeleton className="h-40" />
            ) : seasonal.daysOfWeek.every((d) => d.samples === 0) ? (
              <p className="py-8 text-center text-sm text-muted">No spending recorded yet.</p>
            ) : (
              <>
                <BarChart
                  data={seasonal.daysOfWeek.map((d) => ({
                    label: d.name.slice(0, 3),
                    value: Number(d.avgSpend),
                  }))}
                  format={(v) => money(v)}
                  height={150}
                />
                {seasonal.heaviestDay && (
                  <p className="mt-3 text-xs text-muted">
                    <strong className="text-foreground">{seasonal.heaviestDay.name}</strong> is your
                    heaviest day, averaging {money(seasonal.heaviestDay.avgSpend)} across{' '}
                    {seasonal.heaviestDay.samples} of them.
                  </p>
                )}
              </>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-4 sm:p-5">
            <h3 className="mb-3 flex items-center gap-2 text-sm font-semibold">
              The last 12 weeks
              <InfoHint label="About recent weeks">
                Monday-based weeks. A week with nothing in it is drawn as a zero rather than skipped,
                so a gap in spending stays visible.
              </InfoHint>
            </h3>
            {!seasonal ? (
              <Skeleton className="h-40" />
            ) : (
              <BarChart
                data={seasonal.weekly.map((w) => ({ label: w.label, value: Number(w.expense) }))}
                format={(v) => money(v)}
                height={150}
              />
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
