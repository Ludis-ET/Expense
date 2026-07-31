'use client';

import Link from 'next/link';
import { PageHeader } from '@/components/ui/misc';
import { AnalyticsPage } from '@/components/analytics/analytics-page';

export default function Analytics() {
  return (
    <div className="animate-in space-y-4">
      <PageHeader
        title="Analytics"
        description="Three questions: are you living within your means, where did the money actually go, and how much of it is genuinely free to spend. Everything here is read-only - each card links to the screen where you would act on it."
      />
      <AnalyticsPage />
      <Link
        href="/dashboard"
        className="inline-flex items-center gap-1.5 text-sm font-medium text-muted transition-colors hover:text-primary"
      >
        ← Back to dashboard
      </Link>
    </div>
  );
}
