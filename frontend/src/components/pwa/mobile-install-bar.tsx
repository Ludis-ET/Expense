'use client';

import { useEffect, useState } from 'react';
import { Download, Smartphone, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { usePwaInstall } from '@/lib/pwa-install-context';
import { ANDROID_APP, isAndroid } from '@/lib/android-app';

/**
 * Sticky top banner on mobile.
 *
 * On Android it advertises the real app - the one that reads bank SMS - since
 * that is a genuinely different product from the web version, not just a
 * shortcut to it. Elsewhere it keeps offering the add-to-home-screen install.
 */
export function MobileInstallBar() {
  const { canInstall, bannerDismissed, dismissBanner, install, hasNativePrompt } = usePwaInstall();
  const [android, setAndroid] = useState(false);

  useEffect(() => setAndroid(isAndroid()), []);

  if (bannerDismissed) return null;
  if (!android && !canInstall) return null;

  return (
    <div
      role="region"
      aria-label={android ? 'Get the Santim Android app' : 'Install Santim'}
      className="border-b border-primary/20 bg-gradient-to-r from-primary/10 via-primary/5 to-transparent px-4 py-2.5 lg:hidden"
    >
      <div className="mx-auto flex max-w-7xl items-center gap-3">
        <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-primary/15 text-primary">
          {android ? (
            <Smartphone className="h-4 w-4" aria-hidden />
          ) : (
            <Download className="h-4 w-4" aria-hidden />
          )}
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold leading-tight">
            {android ? 'Let your bank SMS do the typing' : 'Download Santim app'}
          </p>
          <p className="truncate text-xs text-muted">
            {android
              ? 'The Android app reads your bank messages automatically.'
              : hasNativePrompt
                ? 'Install for full-screen access from your home screen.'
                : 'Add to home screen for an app-like experience.'}
          </p>
        </div>

        {android ? (
          <a
            href={ANDROID_APP.url}
            download
            className="inline-flex h-8 shrink-0 items-center justify-center rounded-xl bg-primary px-3 text-sm font-medium text-primary-foreground shadow-sm shadow-primary/25 transition-all hover:brightness-110 active:scale-[0.98]"
          >
            Get it
          </a>
        ) : (
          <Button size="sm" className="shrink-0 shadow-sm" onClick={() => void install()}>
            Install
          </Button>
        )}

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
