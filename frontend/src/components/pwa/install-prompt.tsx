'use client';

import { Download, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { usePwaInstall } from '@/lib/pwa-install-context';

/** Bottom sheet when Chrome fires the native install prompt on mobile. */
export function InstallPrompt() {
  const { canInstall, bannerDismissed, dismissBanner, install, hasNativePrompt } = usePwaInstall();

  if (!canInstall || bannerDismissed || !hasNativePrompt) return null;

  return (
    <div
      role="region"
      aria-label="Install Santim app"
      className={cn(
        'fixed bottom-4 left-4 right-4 z-50 mx-auto max-w-md animate-in rounded-2xl border border-border bg-surface p-4 shadow-xl lg:hidden',
      )}
    >
      <div className="flex items-start gap-3">
        <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
          <Download className="h-5 w-5" aria-hidden />
        </span>
        <div className="min-w-0 flex-1">
          <p className="font-semibold">Download Santim app</p>
          <p className="mt-0.5 text-sm text-muted">
            Install on your home screen for quick access and a full-screen app experience.
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            <Button size="sm" onClick={() => void install()}>
              Install now
            </Button>
            <Button size="sm" variant="outline" onClick={dismissBanner}>
              Not now
            </Button>
          </div>
        </div>
        <button
          type="button"
          onClick={dismissBanner}
          className="rounded-lg p-1 text-muted hover:bg-surface-muted hover:text-foreground"
          aria-label="Dismiss install prompt"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}
