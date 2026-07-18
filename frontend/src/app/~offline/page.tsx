'use client';

import Link from 'next/link';
import { WifiOff } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { withBase } from '@/lib/base-path';

export default function OfflinePage() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-mesh px-6 text-center">
      <span className="flex h-16 w-16 items-center justify-center rounded-2xl bg-surface-muted text-muted">
        <WifiOff className="h-8 w-8" aria-hidden />
      </span>
      <h1 className="mt-6 text-2xl font-bold">You&apos;re offline</h1>
      <p className="mt-2 max-w-sm text-sm text-muted">
        This page hasn&apos;t been opened before, so there&apos;s no saved copy yet. Pages you&apos;ve
        already visited work offline — and anything you add or edit is saved and synced when you reconnect.
      </p>
      <Button className="mt-6" onClick={() => window.location.reload()}>
        Try again
      </Button>
      <Link href={withBase('/dashboard')} className="mt-3 text-sm font-medium text-primary hover:underline">
        Back to dashboard
      </Link>
    </div>
  );
}
