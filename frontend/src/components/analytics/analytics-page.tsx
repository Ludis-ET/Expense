'use client';

import { useState } from 'react';
import Link from 'next/link';
import useSWR from 'swr';
import {
  AlertTriangle,
  ArrowDownRight,
  ArrowUpRight,
  CircleEllipsis,
  HandCoins,
  Lock,
  Repeat,
  Scale,
  Sparkles,
  Target,
  Wallet,
} from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { EmptyState, Skeleton } from '@/components/ui/misc';
import { InfoHint } from '@/components/ui/info-hint';
import { financeIcon } from '@/components/finance/icons';
import { CurrencyBadge } from '@/components/finance/currency-badge';
import { MonthNavigator, currentMonth } from '@/components/finance/month-navigator';
import { CalendarDate } from '@/components/calendar-date';
import { useMoney } from '@/lib/amount-visibility';
import { useCurrencyView } from '@/lib/currency-view-context';
import { cn } from '@/lib/utils';
import type { AnalyticsPageData } from '@/lib/types';

/**
 * The analytics page: three questions, in order.
 *
 *   1. Am I living within my means?          -> Net cash flow
 *   2. Where did it actually go?             -> Unplanned share, plan discipline
 *   3. How much is genuinely mine to spend?  -> Reserved vs available, the floor
 *
 * Everything else - wants and IOUs - sits below the fold because it shapes next
 * month rather than this one. Nothing here edits: every card deep-links to the
 * screen where you would act on it.
 */
export function AnalyticsPage() {
  const { activeCurrency } = useCurrencyView();
  const [month, setMonth] = useState(currentMonth());
  const { data, isLoading } = useSWR<AnalyticsPageData>(
    `/analytics/page?month=${month}&currency=${encodeURIComponent(activeCurrency)}`,
  );

  if (isLoading || !data) return <PageSkeleton />;

  // Balances, plan cycles, rules and IOUs describe today, not the month in
  // view. Scrolling back does not rewind them, so those cards say so.
  const pastMonth = month < currentMonth();

  const nothingYet =
    Number(data.cashFlow.income) === 0 &&
    Number(data.cashFlow.expense) === 0 &&
    Number(data.cash.real) === 0;

  return (
    <div className="space-y-4">
      {/* Scope: the month, and which currency's world we are in. */}
      <div className="flex flex-wrap items-center justify-between gap-2 rounded-2xl border border-border bg-surface px-3 py-2">
        <MonthNavigator month={month} onChange={setMonth} />
        <div className="flex items-center gap-2">
          {data.period.inProgress && (
            <span className="rounded-full bg-amber-500/10 px-2.5 py-1 text-[11px] font-semibold text-amber-600 dark:text-amber-400">
              {data.period.daysElapsed} of {data.period.daysInMonth} days
            </span>
          )}
          <CurrencyBadge />
        </div>
      </div>

      {!data.scope.complete && (
        <Honesty>
          Totals cover {data.scope.currency} only — no rate is set for{' '}
          {data.scope.missingRates.join(', ')}. Add one in Settings to see everything together.
        </Honesty>
      )}

      {nothingYet ? (
        <FirstRun currency={data.scope.currency} />
      ) : (
        <>
          <CashFlowCard data={data} />
          <UnplannedCard data={data} />
          <ReservedCard data={data} pastMonth={pastMonth} />
          <PlanDisciplineCard data={data} pastMonth={pastMonth} />
          <CommitmentsCard data={data} pastMonth={pastMonth} />
          <div className="grid gap-4 lg:grid-cols-2">
            <WishlistCard data={data} pastMonth={pastMonth} />
            <LedgerCard data={data} pastMonth={pastMonth} />
          </div>
        </>
      )}
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Shared furniture                                                            */
/* -------------------------------------------------------------------------- */

function Section({
  icon: Icon,
  title,
  hint,
  href,
  linkLabel,
  asOfNow = false,
  pastMonth = false,
  children,
}: {
  icon: typeof Wallet;
  title: string;
  hint: string;
  href?: string;
  linkLabel?: string;
  /**
   * True for cards that describe the present rather than the month in view -
   * balances, live plan cycles, active rules, open IOUs. Scrolling back to June
   * does not rewind those, so they say so instead of pretending.
   */
  asOfNow?: boolean;
  pastMonth?: boolean;
  children: React.ReactNode;
}) {
  return (
    <Card>
      <CardContent className="p-4 sm:p-5">
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
          <h2 className="flex items-center gap-2 text-sm font-semibold">
            <Icon className="h-4 w-4 text-muted" />
            {title}
            <InfoHint label={`About ${title}`}>{hint}</InfoHint>
            {asOfNow && pastMonth && (
              <span className="rounded-full bg-surface-muted px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-muted">
                as of today
              </span>
            )}
          </h2>
          {href && (
            <Link href={href} className="text-xs font-medium text-primary hover:underline">
              {linkLabel ?? 'Open'}
            </Link>
          )}
        </div>
        {children}
      </CardContent>
    </Card>
  );
}

/** Where the page admits what it doesn't know. */
function Honesty({ children }: { children: React.ReactNode }) {
  return (
    <p className="flex items-start gap-2 rounded-xl border border-amber-500/25 bg-amber-500/5 px-3 py-2 text-xs text-muted">
      <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0 text-amber-500" />
      <span>{children}</span>
    </p>
  );
}

/** A comparison that stays silent rather than inventing a baseline. */
function Delta({ pct, invert = false }: { pct: number | null; invert?: boolean }) {
  if (pct === null) return <span className="text-xs text-muted">no last month to compare</span>;
  const up = pct > 0;
  const good = invert ? !up : up;
  const Icon = up ? ArrowUpRight : ArrowDownRight;
  return (
    <span
      className={cn(
        'inline-flex items-center gap-0.5 text-xs font-semibold',
        pct === 0
          ? 'text-muted'
          : good
            ? 'text-emerald-600 dark:text-emerald-400'
            : 'text-rose-600 dark:text-rose-400',
      )}
    >
      <Icon className="h-3 w-3" />
      {Math.abs(pct)}% vs last month
    </span>
  );
}

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div>
      <p className="text-xs text-muted">{label}</p>
      <p className="text-lg font-bold tabular-nums">{value}</p>
      {sub && <p className="text-[11px] text-muted">{sub}</p>}
    </div>
  );
}

/**
 * A two-tone bar. Width is the meaning; the label beside it repeats the number,
 * so nothing depends on colour alone.
 */
function Bar({ pct, tone }: { pct: number; tone: string }) {
  return (
    <div className="h-2 w-full overflow-hidden rounded-full bg-surface-muted">
      <div
        className={cn('h-full rounded-full transition-all duration-500', tone)}
        style={{ width: `${Math.min(100, Math.max(0, pct))}%` }}
      />
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* 1. Net cash flow                                                            */
/* -------------------------------------------------------------------------- */

function CashFlowCard({ data }: { data: AnalyticsPageData }) {
  const { money } = useMoney();
  const { cashFlow, period } = data;
  const net = Number(cashFlow.net);
  const positive = net >= 0;

  return (
    <Card>
      <CardContent className="p-5">
        <div className="flex items-center gap-2">
          <p className="text-xs font-semibold uppercase tracking-widest text-muted">
            {positive ? 'Kept this month' : 'Overspent this month'}
          </p>
          <InfoHint label="About net cash flow">
            Everything that came in, less everything that went out, for the month in view.
            Transfers between your own accounts are not counted either way — moving money is not
            earning or spending it.
          </InfoHint>
        </div>

        <p
          className={cn(
            'mt-1 text-4xl font-bold tabular-nums',
            positive ? 'text-emerald-600 dark:text-emerald-400' : 'text-rose-600 dark:text-rose-400',
          )}
        >
          {positive ? '+' : '−'}
          {money(Math.abs(net))}
        </p>
        <div className="mt-1">
          <Delta pct={cashFlow.deltaNetPct} />
        </div>

        <div className="mt-4 grid grid-cols-2 gap-4">
          <Stat label="Came in" value={money(cashFlow.income)} />
          <Stat label="Went out" value={money(cashFlow.expense)} />
        </div>

        {cashFlow.savingsRate !== null && (
          <p className="mt-3 text-sm text-muted">
            You kept <strong className="text-foreground">{cashFlow.savingsRate}%</strong> of what
            came in.
          </p>
        )}

        {period.inProgress && (
          <p className="mt-2 text-[11px] text-muted">
            {period.daysInMonth - period.daysElapsed} days still to go — this figure is not final.
          </p>
        )}
      </CardContent>
    </Card>
  );
}

/* -------------------------------------------------------------------------- */
/* 2. Unplanned share                                                          */
/* -------------------------------------------------------------------------- */

function UnplannedCard({ data }: { data: AnalyticsPageData }) {
  const { money } = useMoney();
  const { unplanned } = data;
  const planned = Number(unplanned.totalExpense) - Number(unplanned.amount);
  const noSpend = Number(unplanned.totalExpense) === 0;

  return (
    <Section
      icon={CircleEllipsis}
      title="Planned vs unplanned"
      hint="How much of this month's spending went through a plan you had set money aside for, and how much just happened. A high unplanned share is the signal to turn your recurring surprises into plans."
      href="/budgets"
      linkLabel="Plans"
    >
      {noSpend ? (
        <p className="text-sm text-muted">No spending recorded this month.</p>
      ) : (
        <>
          <div className="flex items-end justify-between gap-3">
            <div>
              <p className="text-3xl font-bold tabular-nums">{unplanned.pct}%</p>
              <p className="text-xs text-muted">unplanned — {money(unplanned.amount)}</p>
            </div>
            <div className="text-right">
              <p className="text-lg font-semibold tabular-nums">{money(planned)}</p>
              <p className="text-xs text-muted">through a plan</p>
            </div>
          </div>
          <div className="mt-3">
            <Bar pct={unplanned.pct} tone="bg-amber-500" />
          </div>
          <p className="mt-3 text-sm text-muted">
            {unplanned.pct >= 50
              ? 'More than half your spending had no plan behind it. Pick the biggest repeat offender and give it one.'
              : unplanned.pct >= 25
                ? 'A quarter or more slipped through unplanned. Worth a look at what keeps landing there.'
                : 'Most of your spending went through a plan you had already set money aside for.'}
          </p>
        </>
      )}
    </Section>
  );
}

/* -------------------------------------------------------------------------- */
/* 3. Reserved vs available                                                    */
/* -------------------------------------------------------------------------- */

function ReservedCard({ data, pastMonth }: { data: AnalyticsPageData; pastMonth: boolean }) {
  const { money } = useMoney();
  const { cash } = data;

  return (
    <Section
      icon={Lock}
      title="What is actually free"
      hint="Filling a plan does not move money out of your account — it just stops counting as available. This is the split: what is physically there, what plans have reserved, and what is genuinely yours to spend right now."
      href="/accounts"
      linkLabel="Accounts"
      asOfNow
      pastMonth={pastMonth}
    >
      <div className="grid grid-cols-3 gap-3">
        <Stat label="In accounts" value={money(cash.real)} />
        <Stat label="Reserved" value={money(cash.locked)} sub={`${cash.lockedPct}% of it`} />
        <Stat label="Free to spend" value={money(cash.available)} />
      </div>
      <div className="mt-3">
        <Bar pct={cash.lockedPct} tone="bg-primary" />
      </div>
      <p className="mt-3 text-sm text-muted">
        {Number(cash.available) <= 0
          ? 'Every birr you hold is spoken for. Give money back from a plan before spending outside one.'
          : `${money(cash.available)} is unreserved across ${cash.accountCount} account${cash.accountCount === 1 ? '' : 's'} — everything else is already promised to a plan.`}
      </p>
    </Section>
  );
}

/* -------------------------------------------------------------------------- */
/* 4. Plan discipline                                                          */
/* -------------------------------------------------------------------------- */

function PlanDisciplineCard({ data, pastMonth }: { data: AnalyticsPageData; pastMonth: boolean }) {
  const { money } = useMoney();
  const { plans } = data;
  const [showAll, setShowAll] = useState(false);
  const rows = showAll ? plans.items : plans.items.slice(0, 4);

  return (
    <Section
      icon={Target}
      title="Plan discipline"
      hint="Spending measured against what each cycle OPENED with, not what the plan was later changed to. Raising a plan mid-month to cover an overspend still reads as an overspend here — drift and discipline are different problems and one combined number hides both. Cycles are the plan's own periods, which may not line up with the calendar month."
      href="/budgets"
      linkLabel="All plans"
      asOfNow
      pastMonth={pastMonth}
    >
      {plans.items.length === 0 ? (
        <p className="text-sm text-muted">
          No active plans yet. A plan is how you decide what money is for before you spend it.
        </p>
      ) : (
        <>
          <div className="flex flex-wrap items-end justify-between gap-3">
            <Stat
              label="Spent of what was planned"
              value={`${plans.totals.pctOfOpening}%`}
              sub={`${money(plans.totals.spent)} of ${money(plans.totals.opening)}`}
            />
            {Number(plans.totals.adjusted) !== 0 && (
              <p className="text-xs text-muted">
                plans were{' '}
                <strong
                  className={cn(
                    Number(plans.totals.adjusted) > 0
                      ? 'text-emerald-600 dark:text-emerald-400'
                      : 'text-amber-600 dark:text-amber-400',
                  )}
                >
                  {Number(plans.totals.adjusted) > 0 ? 'raised' : 'cut'} by{' '}
                  {money(Math.abs(Number(plans.totals.adjusted)))}
                </strong>{' '}
                mid-cycle
              </p>
            )}
          </div>

          <ul className="mt-4 space-y-3">
            {rows.map((p) => {
              const Icon = financeIcon(p.icon ?? 'wallet');
              const over = p.pctOfOpening > 100;
              const adjusted = Number(p.adjusted);
              return (
                <li key={p.id}>
                  <Link href={`/budgets/${p.id}`} className="group block">
                    <div className="flex items-center justify-between gap-2">
                      <span className="flex min-w-0 items-center gap-2 text-sm font-medium">
                        <Icon className="h-3.5 w-3.5 shrink-0" style={{ color: p.color ?? undefined }} />
                        <span className="truncate group-hover:underline">{p.name}</span>
                      </span>
                      <span className="shrink-0 text-xs tabular-nums text-muted">
                        {money(p.spent)} of {money(p.openingPlanned)}
                        <strong className={cn('ml-1.5', over && 'text-rose-600 dark:text-rose-400')}>
                          {p.pctOfOpening}%
                        </strong>
                      </span>
                    </div>
                    <div className="mt-1.5">
                      <Bar pct={p.pctOfOpening} tone={over ? 'bg-rose-500' : 'bg-primary'} />
                    </div>
                    {adjusted !== 0 && (
                      <p className="mt-1 text-[11px] text-muted">
                        {adjusted > 0 ? 'raised' : 'cut'} by {money(Math.abs(adjusted))} mid-cycle ·
                        now {money(p.planned)}
                      </p>
                    )}
                  </Link>
                </li>
              );
            })}
          </ul>

          {plans.items.length > 4 && (
            <button
              type="button"
              onClick={() => setShowAll((v) => !v)}
              className="mt-3 text-xs font-medium text-primary hover:underline"
            >
              {showAll ? 'Show less' : `Show all ${plans.items.length}`}
            </button>
          )}

          {plans.overspentCount > 0 && (
            <p className="mt-3 text-sm text-muted">
              <strong className="text-foreground">{plans.overspentCount}</strong> plan
              {plans.overspentCount === 1 ? ' has' : 's have'} gone past what they opened with — either
              the plan was too small or the spending was.
            </p>
          )}
        </>
      )}
    </Section>
  );
}

/* -------------------------------------------------------------------------- */
/* 5. The fixed floor                                                          */
/* -------------------------------------------------------------------------- */

const CADENCE: Record<string, string> = {
  DAILY: 'day',
  WEEKLY: 'week',
  MONTHLY: 'month',
  YEARLY: 'year',
};

function cadenceLabel(frequency: string, interval: number) {
  const noun = CADENCE[frequency] ?? 'month';
  return interval === 1 ? `every ${noun}` : `every ${interval} ${noun}s`;
}

function CommitmentsCard({ data, pastMonth }: { data: AnalyticsPageData; pastMonth: boolean }) {
  const { money } = useMoney();
  const { commitments, cashFlow } = data;
  const out = Number(commitments.monthlyOut);
  const discretionary = Number(cashFlow.income) - out;

  return (
    <Section
      icon={Repeat}
      title="Your fixed floor"
      hint="Every active recurring rule converted to what it costs per month — a fortnightly rule counts as roughly half a weekly one, not the same. This is the money that is spoken for before you decide anything."
      href="/transactions?tab=recurring"
      linkLabel="Recurring"
      asOfNow
      pastMonth={pastMonth}
    >
      {commitments.items.length === 0 ? (
        <p className="text-sm text-muted">
          Nothing recurring set up. Adding your rent and subscriptions makes the rest of this page
          honest about what is really discretionary.
        </p>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-4">
            <Stat
              label="Committed out"
              value={`${money(commitments.monthlyOut)}/mo`}
              sub={
                commitments.shareOfIncome !== null
                  ? `${commitments.shareOfIncome}% of what came in`
                  : undefined
              }
            />
            {Number(commitments.monthlyIn) > 0 && (
              <Stat label="Committed in" value={`${money(commitments.monthlyIn)}/mo`} />
            )}
          </div>

          {Number(cashFlow.income) > 0 && (
            <p className="mt-3 text-sm text-muted">
              After fixed costs, about{' '}
              <strong className="text-foreground">{money(Math.max(0, discretionary))}</strong> of this
              month&apos;s income was yours to decide on.
            </p>
          )}

          <ul className="mt-3 space-y-1.5">
            {commitments.items.slice(0, 5).map((r) => (
              <li key={r.id} className="flex items-center justify-between gap-3 text-xs">
                <span className="min-w-0 truncate">
                  {r.name}
                  <span className="text-muted"> · {cadenceLabel(r.frequency, r.interval)}</span>
                  {!r.autoPost && <span className="text-muted"> · reminder only</span>}
                </span>
                <span className="shrink-0 tabular-nums text-muted">
                  {money(r.monthlyEquivalent)}/mo
                </span>
              </li>
            ))}
          </ul>
        </>
      )}
    </Section>
  );
}

/* -------------------------------------------------------------------------- */
/* 6. Wants                                                                    */
/* -------------------------------------------------------------------------- */

function WishlistCard({ data, pastMonth }: { data: AnalyticsPageData; pastMonth: boolean }) {
  const { money } = useMoney();
  const { wishlist } = data;
  const total = wishlist.wanting + wishlist.planned + wishlist.bought;

  return (
    <Section
      icon={Sparkles}
      title="Wants in motion"
      hint="Wanting means the idea exists. Planned means money is being set aside for it. Bought means you got there. A pile stuck in Wanting is a signal to choose; a pile stuck in Planned is a signal to fund."
      href="/budgets?tab=wishlist"
      linkLabel="Wishlist"
      asOfNow
      pastMonth={pastMonth}
    >
      {total === 0 ? (
        <p className="text-sm text-muted">
          Nothing on the list. Parking a want here stops it living in your head.
        </p>
      ) : (
        <>
          <div className="flex items-center gap-2 text-sm">
            <Funnel n={wishlist.wanting} label="wanting" />
            <span className="text-muted">→</span>
            <Funnel n={wishlist.planned} label="planned" />
            <span className="text-muted">→</span>
            <Funnel n={wishlist.bought} label="bought" />
          </div>
          {Number(wishlist.plannedValue) > 0 && (
            <p className="mt-3 text-sm text-muted">
              <strong className="text-foreground">{money(wishlist.plannedValue)}</strong> is being
              planned for.
            </p>
          )}
          <p className="mt-1 text-xs text-muted">
            {wishlist.avgDaysToBuy !== null
              ? `Typically ${wishlist.avgDaysToBuy} days from planning one to buying it.`
              : wishlist.avgDaysToPlan !== null
                ? `Typically ${wishlist.avgDaysToPlan} days before a want gets a plan.`
                : 'Not enough history yet to say how long these take.'}
          </p>
        </>
      )}
    </Section>
  );
}

function Funnel({ n, label }: { n: number; label: string }) {
  return (
    <span className="flex-1 rounded-xl bg-surface-muted/60 px-2 py-2 text-center">
      <span className="block text-xl font-bold tabular-nums">{n}</span>
      <span className="block text-[11px] text-muted">{label}</span>
    </span>
  );
}

/* -------------------------------------------------------------------------- */
/* 7. IOUs                                                                     */
/* -------------------------------------------------------------------------- */

function LedgerCard({ data, pastMonth }: { data: AnalyticsPageData; pastMonth: boolean }) {
  const { money } = useMoney();
  const { ledger } = data;
  const nothing =
    Number(ledger.lent) === 0 &&
    Number(ledger.borrowed) === 0 &&
    Number(ledger.expectedIn) === 0 &&
    Number(ledger.expectedOut) === 0;

  return (
    <Section
      icon={HandCoins}
      title="Owed and owing"
      hint="What is still outstanding after part-payments, not the original amount — a 5,000 loan repaid down to 1,000 counts as 1,000. Open entries only."
      href="/tab"
      linkLabel="Money Tab"
      asOfNow
      pastMonth={pastMonth}
    >
      {nothing ? (
        <p className="text-sm text-muted">Nothing outstanding either way.</p>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-4">
            <Stat
              label="Owed to you"
              value={money(ledger.lent)}
              sub={`${ledger.lentCount} open`}
            />
            <Stat
              label="You owe"
              value={money(ledger.borrowed)}
              sub={`${ledger.borrowedCount} open`}
            />
          </div>

          {/* Money you are waiting on, or committed to, that is not a loan. */}
          {(Number(ledger.expectedIn) > 0 || Number(ledger.expectedOut) > 0) && (
            <p className="mt-3 text-xs text-muted">
              Also expecting{' '}
              {Number(ledger.expectedIn) > 0 && (
                <strong className="text-foreground">{money(ledger.expectedIn)} in</strong>
              )}
              {Number(ledger.expectedIn) > 0 && Number(ledger.expectedOut) > 0 && ' and '}
              {Number(ledger.expectedOut) > 0 && (
                <strong className="text-foreground">{money(ledger.expectedOut)} out</strong>
              )}
              .
            </p>
          )}

          {ledger.counterparties.length > 0 && (
            <ul className="mt-3 space-y-1.5">
              {ledger.counterparties.map((c) => (
                <li key={`${c.name}-${c.kind}`} className="flex items-center justify-between gap-3 text-xs">
                  <span className="min-w-0 truncate">
                    {c.name}
                    <span className="text-muted">
                      {' '}
                      · {c.kind === 'LENT' ? 'owes you' : c.kind === 'BORROWED' ? 'you owe' : 'expected'}
                    </span>
                    {c.dueDate && (
                      <span className={cn('text-muted', c.overdue && 'text-rose-600 dark:text-rose-400')}>
                        {' '}
                        · {c.overdue ? 'overdue ' : 'due '}
                        <CalendarDate value={c.dueDate} />
                      </span>
                    )}
                  </span>
                  <span className="shrink-0 tabular-nums text-muted">{money(c.outstanding)}</span>
                </li>
              ))}
            </ul>
          )}

          {ledger.overdueCount > 0 && (
            <p className="mt-3 text-sm text-muted">
              <strong className="text-foreground">{ledger.overdueCount}</strong> past their due date
              — worth a message.
            </p>
          )}
        </>
      )}
    </Section>
  );
}

/* -------------------------------------------------------------------------- */
/* Empty and loading                                                           */
/* -------------------------------------------------------------------------- */

/**
 * A brand-new account has nothing to analyse, so say what to do rather than
 * showing a wall of zeroes.
 */
function FirstRun({ currency }: { currency: string }) {
  return (
    <Card>
      <CardContent className="p-6">
        <EmptyState
          icon={<Scale className="h-5 w-5" />}
          title="Nothing to weigh up yet"
          description={`Once you have a few ${currency} transactions this page will tell you whether you are living within your means, where the money went, and how much is genuinely free.`}
          action={
            <Link
              href="/transactions"
              className="text-sm font-medium text-primary hover:underline"
            >
              Record a transaction →
            </Link>
          }
        />
      </CardContent>
    </Card>
  );
}

function PageSkeleton() {
  return (
    <div className="space-y-4">
      <Skeleton className="h-14 rounded-2xl" />
      <Skeleton className="h-48 rounded-2xl" />
      <Skeleton className="h-40 rounded-2xl" />
      <Skeleton className="h-40 rounded-2xl" />
    </div>
  );
}
