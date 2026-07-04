'use client';

import Link from 'next/link';
import { ArrowRight } from 'lucide-react';
import { PageHeader } from '@/components/ui/misc';
import { CurrencyBadge, currencyScopeHint } from '@/components/finance/currency-badge';
import { DashboardAnalytics } from '@/components/finance/dashboard-analytics';
import { useCurrencyView } from '@/lib/currency-view-context';

export default function AnalyticsPage() {
  const { activeCurrency } = useCurrencyView();

  return (
    <div className="animate-in space-y-6">
      <PageHeader
        title="Analytics"
        description={currencyScopeHint(activeCurrency)}
        badge={<CurrencyBadge />}
      />
      <DashboardAnalytics />
      <Link
        href="/dashboard"
        className="inline-flex items-center gap-1.5 text-sm font-medium text-muted transition-colors hover:text-primary"
      >
        ← Back to dashboard
      </Link>
    </div>
  );
}
