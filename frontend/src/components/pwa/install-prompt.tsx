'use client';

import { useEffect, useState } from 'react';
import { Download, Smartphone, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { usePwaInstall } from '@/lib/pwa-install-context';
import { ANDROID_APP, isAndroid } from '@/lib/android-app';

/**
 * Bottom sheet shown when Chrome offers the native install prompt.
 *
 * On Android this leads with the APK instead: installing the web app to the
 * home screen gets you the same thing you are already looking at, whereas the
 * Android build can read your bank SMS. Offering the weaker option first would
 * be doing the user a disservice.
 */
export function InstallPrompt() {
  const { canInstall, bannerDismissed, dismissBanner, install, hasNativePrompt } = usePwaInstall();
  const [android, setAndroid] = useState(false);

  useEffect(() => setAndroid(isAndroid()), []);

  if (bannerDismissed) return null;
  if (!android && (!canInstall || !hasNativePrompt)) return null;

  return (
    <div
      role="region"
      aria-label={android ? 'Get the Santim Android app' : 'Install Santim app'}
      className={cn(
        'fixed bottom-4 left-4 right-4 z-50 mx-auto max-w-md animate-in rounded-2xl border border-border bg-surface p-4 shadow-xl lg:hidden',
      )}
    >
      <div className="flex items-start gap-3">
        <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-primary/10 text-primary">
          {android ? (
            <Smartphone className="h-5 w-5" aria-hidden />
          ) : (
            <Download className="h-5 w-5" aria-hidden />
          )}
        </span>
        <div className="min-w-0 flex-1">
          <p className="font-semibold">
            {android ? 'Get the Santim Android app' : 'Download Santim app'}
          </p>
          <p className="mt-0.5 text-sm text-muted">
            {android
              ? 'Reads your bank SMS and fills in transactions for you — one tap to confirm.'
              : 'Install on your home screen for quick access and a full-screen app experience.'}
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            {android ? (
              <a
                href={ANDROID_APP.url}
                download
                onClick={dismissBanner}
                className="inline-flex h-8 items-center justify-center gap-1.5 rounded-xl bg-primary px-3 text-sm font-medium text-primary-foreground shadow-sm shadow-primary/25 transition-all hover:brightness-110 active:scale-[0.98]"
              >
                <Download className="h-4 w-4" aria-hidden />
                Download
              </a>
            ) : (
              <Button size="sm" onClick={() => void install()}>
                Install now
              </Button>
            )}
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
