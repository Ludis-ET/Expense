'use client';

import { useEffect, useState } from 'react';
import { BrandMark } from '@/components/brand';
import { cn } from '@/lib/utils';

const SESSION_KEY = 'santim.splash.shown';
const HOLD_MS = 1900; // fully visible
const FADE_MS = 550; // fade-out duration

type Phase = 'pending' | 'showing' | 'hiding' | 'gone';

/**
 * Animated brand splash shown once per browser session on first load. Renders
 * nothing on the server and on sessions that have already seen it, so it never
 * blocks or double-flashes. Respects prefers-reduced-motion via CSS.
 */
export function SplashScreen() {
  const [phase, setPhase] = useState<Phase>('pending');

  useEffect(() => {
    if (typeof window === 'undefined') return;
    if (sessionStorage.getItem(SESSION_KEY)) {
      setPhase('gone');
      return;
    }
    setPhase('showing');
    const t1 = setTimeout(() => setPhase('hiding'), HOLD_MS);
    const t2 = setTimeout(() => {
      sessionStorage.setItem(SESSION_KEY, '1');
      setPhase('gone');
    }, HOLD_MS + FADE_MS);
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
    };
  }, []);

  if (phase === 'pending' || phase === 'gone') return null;

  return (
    <div
      role="status"
      aria-label="Loading Santim"
      className={cn(
        'fixed inset-0 z-[200] flex flex-col items-center justify-center overflow-hidden bg-background transition-opacity ease-out',
        phase === 'hiding' ? 'pointer-events-none opacity-0' : 'opacity-100',
      )}
      style={{ transitionDuration: `${FADE_MS}ms` }}
    >
      {/* Ambient background */}
      <div className="pointer-events-none absolute inset-0 bg-grid opacity-[0.35]" />
      <div className="animate-splash-orb pointer-events-none absolute -left-16 top-1/4 h-72 w-72 rounded-full bg-emerald-500/25 blur-[110px]" />
      <div className="animate-splash-orb-2 pointer-events-none absolute -right-10 bottom-1/4 h-80 w-80 rounded-full bg-teal-400/20 blur-[120px]" />

      {/* Logo + draw ring */}
      <div className="relative flex h-44 w-44 items-center justify-center">
        <svg viewBox="0 0 120 120" className="absolute inset-0 h-full w-full -rotate-90" aria-hidden>
          <defs>
            <linearGradient id="splash-ring-grad" x1="0%" y1="0%" x2="100%" y2="100%">
              <stop offset="0%" stopColor="#34d399" />
              <stop offset="100%" stopColor="#0d9488" />
            </linearGradient>
          </defs>
          <circle
            cx="60"
            cy="60"
            r="48"
            fill="none"
            stroke="currentColor"
            strokeWidth="3"
            className="text-border/60"
          />
          <circle
            cx="60"
            cy="60"
            r="48"
            fill="none"
            stroke="url(#splash-ring-grad)"
            strokeWidth="4"
            strokeLinecap="round"
            strokeDasharray="302"
            className="animate-splash-ring"
          />
        </svg>
        <div className="animate-splash-pop relative">
          <div className="absolute inset-0 -z-10 animate-pulse rounded-[28%] bg-primary/40 blur-2xl" />
          <BrandMark className="h-20 w-20 shadow-xl shadow-primary/30" />
        </div>
      </div>

      {/* Wordmark + tagline */}
      <div className="animate-in animate-in-delay-2 mt-8 text-center">
        <p className="text-3xl font-bold tracking-tight">
          San<span className="text-primary">tim</span>
        </p>
        <p className="animate-in animate-in-delay-3 mt-1.5 text-sm text-muted">
          Know where every birr goes
        </p>
      </div>

      {/* Slim indeterminate progress bar */}
      <div className="animate-in animate-in-delay-3 mt-8 h-1 w-40 overflow-hidden rounded-full bg-surface-muted">
        <div className="animate-splash-sweep h-full w-1/3 rounded-full bg-gradient-to-r from-emerald-400 to-teal-500" />
      </div>
    </div>
  );
}
