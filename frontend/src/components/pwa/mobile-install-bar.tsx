'use client';

import { Download, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { usePwaInstall } from '@/lib/pwa-install-context';

/** Sticky mobile banner prompting users to install the PWA. */
export function MobileInstallBar() {
  const { canInstall, bannerDismissed, dismissBanner, install, hasNativePrompt } = usePwaInstall();

  if (!canInstall || bannerDismissed) return null;

  return (
    <div
      role="region"
      aria-label="Download Santim app"
      className="border-b border-primary/20 bg-gradient-to-r from-primary/10 via-primary/5 to-transparent px-4 py-2.5 lg:hidden"
    >
      <div className="mx-auto flex max-w-7xl items-center gap-3">
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-primary/15 text-primary">
          <Download className="h-4 w-4" aria-hidden />
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold leading-tight">Download Santim app</p>
          <p className="truncate text-xs text-muted">
            {hasNativePrompt ? 'Install for full-screen access from your home screen.' : 'Add to home screen for an app-like experience.'}
          </p>
        </div>
        <Button size="sm" className="shrink-0 shadow-sm" onClick={() => void install()}>
          Install
        </Button>
        <button
          type="button"
          onClick={dismissBanner}
          className="shrink-0 rounded-lg p-1.5 text-muted hover:bg-surface-muted hover:text-foreground"
          aria-label="Dismiss download banner"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}
