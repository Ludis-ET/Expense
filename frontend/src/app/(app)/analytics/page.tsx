'use client';

import Link from 'next/link';
import { ArrowRight } from 'lucide-react';
import { PageHeader } from '@/components/ui/misc';
import { DashboardAnalytics } from '@/components/finance/dashboard-analytics';

export default function AnalyticsPage() {
  return (
    <div className="animate-in space-y-6">
      <PageHeader
        title="Analytics"
        description="Trends, breakdowns, burn rate, heatmap, and where your money really goes."
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
