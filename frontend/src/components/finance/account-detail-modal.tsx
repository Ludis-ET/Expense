'use client';

import Link from 'next/link';
import useSWR from 'swr';
import { Modal } from '@/components/ui/modal';
import { Button } from '@/components/ui/button';
import { EmptyState } from '@/components/ui/misc';
import { InfoHint } from '@/components/ui/info-hint';
import { TransactionList } from '@/components/finance/transaction-list';
import { financeIcon } from '@/components/finance/icons';
import { useMoney } from '@/lib/amount-visibility';
import type { Account, Transaction } from '@/lib/types';

export function AccountDetailModal({
  account,
  onClose,
  onEdit,
  onDelete,
}: {
  account: Account | null;
  onClose: () => void;
  onEdit: (account: Account) => void;
  onDelete: (account: Account) => void;
}) {
  const { money } = useMoney(account?.currency);
  const { data, isLoading } = useSWR<{ items: Transaction[] }>(
    account ? `/transactions?accountId=${account.id}&pageSize=40&sort=date_desc` : null,
  );

  const transactions = data?.items ?? [];
  const plans = new Map<string, { id: string; name: string; icon?: string | null; color?: string | null; currency: string; spent: number; count: number }>();
  for (const tx of transactions) {
    if (!tx.budget) continue;
    const current = plans.get(tx.budget.id) ?? {
      id: tx.budget.id,
      name: tx.budget.name,
      icon: tx.budget.icon ?? null,
      color: tx.budget.color ?? null,
      currency: tx.budget.currency,
      spent: 0,
      count: 0,
    };
    if (tx.kind === 'EXPENSE') current.spent += Number(tx.amount);
    current.count += 1;
    plans.set(tx.budget.id, current);
  }
  const planRows = [...plans.values()].sort((a, b) => b.spent - a.spent);

  const income = transactions.filter((tx) => tx.kind === 'INCOME').reduce((sum, tx) => sum + Number(tx.amount), 0);
  const expense = transactions.filter((tx) => tx.kind === 'EXPENSE').reduce((sum, tx) => sum + Number(tx.amount), 0);
  const transfers = transactions.filter((tx) => tx.kind === 'TRANSFER').length;

  if (!account) return null;

  const Icon = financeIcon(account.icon);
  const color = account.color ?? '#64748b';

  return (
    <Modal open={!!account} onClose={onClose} title={account.name} className="sm:max-w-5xl">
      <div className="space-y-5">
        <div
          className="overflow-hidden rounded-3xl border border-border bg-surface-muted/40 p-5 shadow-sm"
          style={{
            backgroundImage:
              'linear-gradient(135deg, rgba(0,0,0,0.02) 0%, transparent 40%, rgba(0,0,0,0.01) 100%)',
          }}
        >
          <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
            <div className="flex items-start gap-4">
              <span
                className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl shadow-sm ring-1 ring-border/60"
                style={{ backgroundColor: `${color}22`, color }}
              >
                <Icon className="h-7 w-7" />
              </span>
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <h3 className="text-2xl font-semibold tracking-tight">{account.name}</h3>
                  {account.isDefault && <span className="rounded-full bg-primary/10 px-2 py-0.5 text-[10px] font-semibold text-primary">default</span>}
                  {account.archived && <span className="rounded-full bg-surface-muted px-2 py-0.5 text-[10px] font-semibold text-muted">archived</span>}
                </div>
                <p className="mt-1 text-sm text-muted">{account.type.replace('_', ' ').toLowerCase()} · {account.currency}</p>
                <p className="mt-3 text-3xl font-bold tabular-nums">{money(account.balance)}</p>
                <p className="mt-1 text-xs text-muted">{money(account.realBalance)} real · {money(account.lockedAmount)} in plan pots</p>
              </div>
            </div>

            <div className="flex gap-2">
              <Button variant="outline" onClick={() => onEdit(account)}>Edit</Button>
              <Button variant="outline" className="text-danger hover:bg-danger/10" onClick={() => onDelete(account)}>Delete</Button>
            </div>
          </div>

          <div className="mt-4 grid gap-3 sm:grid-cols-3">
            <div className="rounded-2xl bg-surface/80 p-4">
              <p className="text-[11px] uppercase tracking-widest text-muted">Income</p>
              <p className="mt-1 text-lg font-semibold tabular-nums">{money(income)}</p>
            </div>
            <div className="rounded-2xl bg-surface/80 p-4">
              <p className="text-[11px] uppercase tracking-widest text-muted">Expenses</p>
              <p className="mt-1 text-lg font-semibold tabular-nums">{money(expense)}</p>
            </div>
            <div className="rounded-2xl bg-surface/80 p-4">
              <p className="text-[11px] uppercase tracking-widest text-muted">Transfers</p>
              <p className="mt-1 text-lg font-semibold tabular-nums">{transfers}</p>
            </div>
          </div>
        </div>

        <div className="grid gap-5 lg:grid-cols-[1.1fr_0.9fr]">
          <div className="space-y-3 rounded-2xl border border-border bg-surface p-4">
            <div className="flex items-center justify-between gap-3">
              <div>
                <h4 className="text-sm font-semibold">Transactions</h4>
                <p className="text-xs text-muted">Latest movements for this account</p>
              </div>
              <span className="text-xs text-muted">{isLoading ? 'Loading…' : `${transactions.length} shown`}</span>
            </div>
            {transactions.length === 0 && !isLoading ? (
              <EmptyState title="No transactions" description="This account has no recorded transactions yet." />
            ) : (
              <TransactionList items={transactions} compact />
            )}
          </div>

          <div className="space-y-3 rounded-2xl border border-border bg-surface p-4">
            <div className="flex items-center gap-1.5">
              <h4 className="text-sm font-semibold">Plans using this account</h4>
              <InfoHint label="About plans using this account">
                Budget plan activity pulled from the transactions above.
              </InfoHint>
            </div>
            {planRows.length === 0 ? (
              <EmptyState title="No linked plans" description="No budget plans have charged this account yet." />
            ) : (
              <div className="space-y-3">
                {planRows.map((plan) => {
                  const PlanIcon = financeIcon(plan.icon ?? 'wallet');
                  return (
                    <Link
                      key={plan.id}
                      href={`/budgets/${plan.id}`}
                      className="flex items-center gap-3 rounded-2xl border border-border bg-surface-muted/40 p-3 transition-colors hover:bg-surface-muted"
                    >
                      <span
                        className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl"
                        style={{ backgroundColor: `${plan.color ?? '#6366f1'}22`, color: plan.color ?? '#6366f1' }}
                      >
                        <PlanIcon className="h-5 w-5" />
                      </span>
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-medium">{plan.name}</p>
                        <p className="text-xs text-muted">{plan.count} transaction{plan.count === 1 ? '' : 's'} · {plan.currency}</p>
                      </div>
                      <p className="shrink-0 text-sm font-semibold tabular-nums">{money(plan.spent)}</p>
                    </Link>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      </div>
    </Modal>
  );
}
