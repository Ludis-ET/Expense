'use client';

import { useState } from 'react';
import useSWR, { mutate as globalMutate } from 'swr';
import { toast } from 'sonner';
import {
  BadgeCheck,
  Building2,
  Landmark,
  Lock,
  RefreshCw,
  Stethoscope,
  TriangleAlert,
  Wallet,
} from 'lucide-react';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { InfoHint } from '@/components/ui/info-hint';
import { financeIcon } from '@/components/finance/icons';
import { api, ApiError } from '@/lib/api';
import { useMoney } from '@/lib/amount-visibility';
import { cn } from '@/lib/utils';
import type { Category, MoneyHealth, MoneyRepairResult } from '@/lib/types';

/**
 * The Money Doctor.
 *
 * Santim now proves its own books balance after every write, and this is where
 * that proof is visible. Shipping it in the open rather than hiding it behind a
 * flag is deliberate: it turns the scariest class of bug - a number quietly
 * being wrong - into something a person can see and fix in one tap.
 *
 * The healthy state is the one users will nearly always see, so it is designed
 * first: a calm, complete picture of where their money is, not an empty page
 * with nothing to report.
 */
export function MoneyDoctor() {
  const { data, isLoading, mutate } = useSWR<MoneyHealth>('/money/health');
  const { data: categoriesData } = useSWR<{ items: Category[] }>('/categories');
  const [fixing, setFixing] = useState(false);
  const [settling, setSettling] = useState<string | null>(null);
  const { money } = useMoney(data?.currency);

  async function fix() {
    setFixing(true);
    try {
      const result = await api.post<MoneyRepairResult>('/money/health/fix');
      if (result.actions.length === 0) {
        toast.success('Nothing needed fixing - your money already adds up.');
      } else {
        toast.success(
          result.actions.length === 1
            ? result.actions[0]!.explanation
            : `Made ${result.actions.length} corrections. Everything balances again.`,
        );
      }
      await mutate();
      void globalMutate((key) => typeof key === 'string' && key.startsWith('/'));
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Could not repair');
    } finally {
      setFixing(false);
    }
  }

  async function settle(accountId: string) {
    const category = (categoriesData?.items ?? []).find((c) => c.kind === 'EXPENSE' && !c.archived);
    if (!category) {
      toast.error('Create an expense category first, so the difference has somewhere to be filed.');
      return;
    }
    setSettling(accountId);
    try {
      await api.post('/money/drift/settle', { accountId, categoryId: category.id });
      toast.success('Recorded the difference. This wallet now matches the bank.');
      await mutate();
      void globalMutate((key) => typeof key === 'string' && key.startsWith('/'));
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : 'Could not settle that');
    } finally {
      setSettling(null);
    }
  }

  if (isLoading || !data) {
    return (
      <Card className="p-5">
        <div className="h-40 animate-pulse rounded-xl bg-surface-muted" />
      </Card>
    );
  }

  const problems = data.problems.length;
  const drifted = data.drift.length;

  return (
    <div className="space-y-4">
      {/* Verdict */}
      <Card
        className={cn(
          'overflow-hidden p-5',
          data.healthy ? 'border-emerald-500/30' : 'border-amber-500/40',
        )}
      >
        <div className="flex items-start gap-4">
          <span
            className={cn(
              'grid h-11 w-11 shrink-0 place-items-center rounded-full',
              data.healthy ? 'bg-emerald-500/10' : 'bg-amber-500/10',
            )}
          >
            {data.healthy ? (
              <BadgeCheck className="h-5 w-5 text-emerald-600 dark:text-emerald-400" />
            ) : (
              <Stethoscope className="h-5 w-5 text-amber-600 dark:text-amber-400" />
            )}
          </span>

          <div className="min-w-0 flex-1">
            <h2 className="flex items-center gap-2 text-base font-semibold">
              {data.healthy ? 'Your money adds up' : 'Something does not add up'}
              <InfoHint>
                Santim keeps two sets of numbers: the cash in your wallets, and the money your plans
                have set aside. This check re-derives both from scratch and confirms they agree -
                that every plan&apos;s pot is backed by real money sitting in a real wallet, and that
                no wallet has promised out more than it holds.
              </InfoHint>
            </h2>
            <p className="mt-0.5 text-sm text-muted">
              {data.healthy
                ? `Every plan's money is backed by a wallet that really holds it. Last checked just now.`
                : `${problems === 1 ? '1 thing needs' : `${problems} things need`} putting right.`}
            </p>
          </div>

          <div className="flex shrink-0 gap-2">
            <Button variant="outline" size="sm" onClick={() => void mutate()} className="gap-1.5">
              <RefreshCw className="h-3.5 w-3.5" />
              Re-check
            </Button>
            {!data.healthy && (
              <Button size="sm" loading={fixing} onClick={fix}>
                Fix it
              </Button>
            )}
          </div>
        </div>

        {problems > 0 && (
          <ul className="mt-4 space-y-2 border-t border-border pt-4">
            {data.problems.map((p, i) => (
              <li key={`${p.code}-${i}`} className="flex items-start gap-2.5 text-sm">
                <TriangleAlert className="mt-0.5 h-4 w-4 shrink-0 text-amber-600 dark:text-amber-400" />
                <span className="text-foreground">{p.message}</span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      {/* Where the money is */}
      <div className="grid gap-3 sm:grid-cols-3">
        {[
          { label: 'In your wallets', value: data.money.real, Icon: Wallet, tone: 'text-foreground' },
          { label: 'Set aside in plans', value: data.money.reserved, Icon: Lock, tone: 'text-primary' },
          {
            label: 'Ready to assign',
            value: data.money.readyToAssign,
            Icon: Landmark,
            tone: 'text-emerald-600 dark:text-emerald-400',
          },
        ].map(({ label, value, Icon, tone }) => (
          <Card key={label} className="p-4">
            <div className="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted">
              <Icon className="h-3.5 w-3.5" />
              {label}
            </div>
            <p className={cn('mt-1.5 text-xl font-semibold tabular-nums', tone)}>{money(value)}</p>
          </Card>
        ))}
      </div>

      {/* What the bank says */}
      {drifted > 0 && (
        <Card className="p-5">
          <h3 className="flex items-center gap-2 text-sm font-semibold">
            <Building2 className="h-4 w-4 text-primary" />
            Your bank says something different
            <InfoHint>
              Every bank message Santim reads carries the balance the bank thinks you have. When that
              disagrees with Santim&apos;s figure, something happened that was never recorded - a fee,
              a card payment, cash withdrawn without a message. Recording the difference keeps the
              wallet honest instead of letting the gap grow.
            </InfoHint>
          </h3>

          <ul className="mt-3 space-y-3">
            {data.drift.map((row) => (
              <li
                key={row.account.id}
                className="flex flex-wrap items-center gap-3 rounded-xl border border-border p-3"
              >
                <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-surface-muted">
                  {(() => {
                    const Icon = financeIcon(row.account.icon ?? 'wallet');
                    return <Icon className="h-4 w-4" style={{ color: row.account.color ?? undefined }} />;
                  })()}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{row.account.name}</p>
                  <p className="text-xs text-muted">
                    Santim {money(row.santimBalance)} · bank {money(row.bankBalance)}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-sm font-semibold tabular-nums text-amber-600 dark:text-amber-400">
                    {Number(row.difference) > 0 ? '+' : ''}
                    {money(row.difference)}
                  </p>
                  <p className="text-[11px] text-muted">
                    {row.direction === 'missing-spending' ? 'spending not recorded' : 'money not recorded'}
                  </p>
                </div>
                <Button
                  size="sm"
                  variant="outline"
                  loading={settling === row.account.id}
                  onClick={() => settle(row.account.id)}
                >
                  Record it
                </Button>
              </li>
            ))}
          </ul>
        </Card>
      )}

      {/* The breakdown, so the numbers above are checkable rather than trusted */}
      <div className="grid gap-3 lg:grid-cols-2">
        <Card className="p-5">
          <h3 className="text-sm font-semibold">Wallet by wallet</h3>
          <ul className="mt-3 space-y-2.5">
            {data.wallets.map((w) => {
              const Icon = financeIcon(w.icon ?? 'wallet');
              const reserved = Number(w.reserved);
              const real = Number(w.real);
              const pct = real > 0 ? Math.min(100, (reserved / real) * 100) : 0;
              return (
                <li key={w.id}>
                  <div className="flex items-center gap-2 text-sm">
                    <Icon className="h-4 w-4 shrink-0" style={{ color: w.color ?? undefined }} />
                    <span className="min-w-0 flex-1 truncate font-medium">{w.name}</span>
                    <span className="tabular-nums text-muted">{money(w.free)} free</span>
                  </div>
                  {/* The bar is the point: how much of this wallet is spoken for. */}
                  <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-surface-muted">
                    <div
                      className="h-full rounded-full bg-primary/70"
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                </li>
              );
            })}
          </ul>
        </Card>

        <Card className="p-5">
          <h3 className="text-sm font-semibold">What each plan is holding</h3>
          {data.plans.length === 0 ? (
            <p className="mt-3 text-sm text-muted">
              No plan is holding money right now. Everything you have is free to assign.
            </p>
          ) : (
            <ul className="mt-3 space-y-2">
              {data.plans.map((p) => {
                const Icon = financeIcon(p.icon ?? 'piggy-bank');
                return (
                  <li key={p.id} className="flex items-center gap-2 text-sm">
                    <Icon className="h-4 w-4 shrink-0" style={{ color: p.color ?? undefined }} />
                    <span className="min-w-0 flex-1 truncate font-medium">{p.name}</span>
                    <span className="tabular-nums text-muted">{money(p.holding)}</span>
                  </li>
                );
              })}
            </ul>
          )}
        </Card>
      </div>
    </div>
  );
}
