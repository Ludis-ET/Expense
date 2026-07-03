'use client';

import Link from 'next/link';
import { Heart, UserPlus, Users } from 'lucide-react';
import { Avatar } from '@/components/ui/misc';
import { Button } from '@/components/ui/button';
import type { HouseholdOverview } from '@/lib/types';

export function HouseholdWidget({
  household,
  money,
}: {
  household: HouseholdOverview | null;
  money: (v: number | string) => string;
}) {
  if (!household) {
    return (
      <div className="card flex flex-col items-center p-6 text-center">
        <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary/10 text-primary">
          <Users className="h-6 w-6" />
        </span>
        <p className="mt-3 font-semibold">Couples & shared accounts</p>
        <p className="mt-1 max-w-xs text-sm text-muted">
          Connect with your partner to share wallets and track household money together.
        </p>
        <Link href="/settings#household" className="mt-4">
          <Button size="sm">
            <UserPlus className="h-4 w-4" /> Set up household
          </Button>
        </Link>
      </div>
    );
  }

  return (
    <div className="card p-5">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Heart className="h-4 w-4 text-primary" />
          <p className="font-semibold">{household.name}</p>
        </div>
        <Link href="/settings#household" className="text-xs font-medium text-primary hover:underline">
          Manage
        </Link>
      </div>

      <div className="mt-4 flex -space-x-2">
        {household.members.map((m) => (
          <Avatar key={m.id} name={m.name} className="h-9 w-9 border-2 border-surface text-[10px]" />
        ))}
      </div>
      <p className="mt-2 text-xs text-muted">
        {household.members.map((m) => m.isYou ? 'You' : m.name.split(' ')[0]).join(' & ')}
      </p>

      {household.sharedAccounts.length > 0 && (
        <div className="mt-4 rounded-xl bg-surface-muted/60 p-3">
          <p className="text-[10px] font-medium uppercase tracking-wide text-muted">Shared balance</p>
          <p className="mt-0.5 text-xl font-bold tabular-nums">{money(household.sharedBalance)}</p>
          <p className="mt-1 text-xs text-muted">
            {household.sharedAccounts.map((a) => a.name).join(', ')}
          </p>
        </div>
      )}

      {household.pendingInvites > 0 && (
        <p className="mt-3 text-xs text-warning">{household.pendingInvites} pending invite(s)</p>
      )}
    </div>
  );
}
