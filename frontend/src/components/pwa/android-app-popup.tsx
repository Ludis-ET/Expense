'use client';

import { useEffect, useState } from 'react';
import { Download, MessageSquareText, Sparkles, X, Zap } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { ANDROID_APP, useAppAd } from '@/lib/android-app';

/**
 * The app ad.
 *
 * Slides up from the bottom on a random delay with one of several pitches, all
 * selling the thing the web app fundamentally cannot do: reading your bank SMS.
 * Android only - an APK is no use to anyone else.
 */
export function AndroidAppPopup() {
  const { visible, pitch, close, dismissForever } = useAppAd();
  const [entered, setEntered] = useState(false);

  // One frame at the starting transform, so the entrance actually animates
  // instead of the element appearing already in place.
  useEffect(() => {
    if (!visible) {
      setEntered(false);
      return;
    }
    const raf = requestAnimationFrame(() => setEntered(true));
    return () => cancelAnimationFrame(raf);
  }, [visible]);

  if (!visible) return null;

  return (
    <div
      role="dialog"
      aria-label="Get the Santim Android app"
      aria-modal="false"
      className={cn(
        'fixed inset-x-3 bottom-3 z-60 mx-auto max-w-md',
        'transition-all duration-500 ease-out motion-reduce:transition-none',
        entered ? 'translate-y-0 opacity-100' : 'translate-y-8 opacity-0',
      )}
    >
      <div className="relative overflow-hidden rounded-3xl border border-primary/25 bg-surface shadow-2xl shadow-primary/10">
        {/* Soft brand wash rather than a solid fill, so the card reads as part
            of the product instead of an interstitial. */}
        <div
          aria-hidden
          className="pointer-events-none absolute -right-16 -top-16 h-48 w-48 rounded-full bg-primary/20 blur-3xl"
        />
        <div
          aria-hidden
          className="pointer-events-none absolute -bottom-20 -left-16 h-44 w-44 rounded-full bg-primary/10 blur-3xl"
        />

        <button
          type="button"
          onClick={close}
          aria-label="Close"
          className="absolute right-3 top-3 z-10 rounded-full p-1.5 text-muted transition-colors hover:bg-surface-muted hover:text-foreground"
        >
          <X className="h-4 w-4" />
        </button>

        <div className="relative p-5">
          <span className="inline-flex items-center gap-1.5 rounded-full bg-primary/12 px-2.5 py-1 text-[11px] font-semibold uppercase tracking-wide text-primary">
            <Sparkles className="h-3 w-3" aria-hidden />
            Android app
          </span>

          <h2 className="mt-3 text-lg font-bold leading-snug">{pitch.headline}</h2>
          <p className="mt-1.5 text-sm leading-relaxed text-muted">{pitch.body}</p>

          <div className="mt-4 flex items-center gap-4 text-[11px] text-muted">
            <span className="inline-flex items-center gap-1.5">
              <MessageSquareText className="h-3.5 w-3.5 text-primary" aria-hidden />
              Reads bank SMS
            </span>
            <span className="inline-flex items-center gap-1.5">
              <Zap className="h-3.5 w-3.5 text-primary" aria-hidden />
              One-tap confirm
            </span>
          </div>

          <div className="mt-4 flex gap-2">
            {/* An anchor, not a button: this navigates to a file, and a button
                would break long-press and open-in-new-tab. */}
            <a
              href={ANDROID_APP.url}
              download
              onClick={dismissForever}
              className={cn(
                'inline-flex h-10 flex-1 items-center justify-center gap-2 rounded-xl px-4 text-sm font-medium',
                'bg-primary text-primary-foreground shadow-sm shadow-primary/25 transition-all',
                'hover:brightness-110 active:scale-[0.98]',
              )}
            >
              <Download className="h-4 w-4" aria-hidden />
              Get the app
            </a>
            <Button variant="ghost" size="md" onClick={dismissForever} className="shrink-0">
              Not interested
            </Button>
          </div>

          <p className="mt-3 text-[11px] leading-relaxed text-muted">
            Installed straight from here, not the Play Store — Google restricts SMS access, so an
            expense tracker cannot be listed there.
          </p>
        </div>
      </div>
    </div>
  );
}

