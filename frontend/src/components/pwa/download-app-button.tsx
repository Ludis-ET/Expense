'use client';

import { useEffect, useState } from 'react';
import { Download, Smartphone } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import { usePwaInstall } from '@/lib/pwa-install-context';
import { ANDROID_APP, isAndroid } from '@/lib/android-app';

interface DownloadAppButtonProps {
  size?: 'sm' | 'md';
  variant?: 'primary' | 'outline' | 'ghost';
  className?: string;
  showIcon?: boolean;
  label?: string;
}

/**
 * Gets the user onto the best version of Santim their device can run.
 *
 * On Android that is the APK, which is the only build that can read bank SMS.
 * Everywhere else it falls back to installing the PWA - handing an iPhone or a
 * desktop an Android package would be worse than useless.
 */
export function DownloadAppButton({
  size = 'sm',
  variant = 'outline',
  className,
  showIcon = true,
  label,
}: DownloadAppButtonProps) {
  const { canInstall, install } = usePwaInstall();
  const [android, setAndroid] = useState(false);

  // Deferred to an effect: the user agent is not available during SSR, and
  // deciding at render time would hydrate the wrong button.
  useEffect(() => setAndroid(isAndroid()), []);

  if (android) {
    return (
      <a
        href={ANDROID_APP.url}
        download
        className={cn(
          'inline-flex shrink-0 items-center justify-center gap-1.5 rounded-xl font-medium transition-all active:scale-[0.98]',
          size === 'sm' ? 'h-8 px-3 text-sm' : 'h-10 px-4 text-sm',
          variant === 'primary'
            ? 'bg-primary text-primary-foreground shadow-sm shadow-primary/25 hover:brightness-110'
            : variant === 'outline'
              ? 'border border-border bg-surface hover:bg-surface-muted'
              : 'hover:bg-surface-muted',
          className,
        )}
      >
        {showIcon && <Smartphone className="h-4 w-4" aria-hidden />}
        {label ?? 'Get the Android app'}
      </a>
    );
  }

  if (!canInstall) return null;

  return (
    <Button
      type="button"
      size={size}
      variant={variant}
      className={cn('shrink-0', className)}
      onClick={() => void install()}
    >
      {showIcon && <Download className="h-4 w-4" aria-hidden />}
      {label ?? 'Install app'}
    </Button>
  );
}
