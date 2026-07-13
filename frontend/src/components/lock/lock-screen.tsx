'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Delete, Fingerprint, Lock, Shield } from 'lucide-react';
import { Brand } from '@/components/brand';
import { Button } from '@/components/ui/button';
import { useAppLock } from '@/lib/app-lock-context';
import { useAuth } from '@/lib/auth';
import { cn } from '@/lib/utils';

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'back'] as const;

export function LockScreen() {
  const { user } = useAuth();
  const { locked, ready, hasBiometric, pinLength, unlockWithPin, unlockWithBiometrics } = useAppLock();
  const [pin, setPin] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [shake, setShake] = useState(false);
  const triedBio = useRef(false);
  const digits = Math.min(8, Math.max(4, pinLength || 4));

  const attemptPin = useCallback(
    async (value: string) => {
      if (value.length < 4 || busy) return;
      setBusy(true);
      setError(null);
      const res = await unlockWithPin(value);
      setBusy(false);
      if (res.ok) {
        setPin('');
        return;
      }
      setShake(true);
      setError(res.error ?? 'Incorrect PIN');
      setPin('');
      window.setTimeout(() => setShake(false), 400);
    },
    [busy, unlockWithPin],
  );

  const press = (key: (typeof KEYS)[number]) => {
    if (busy) return;
    setError(null);
    if (key === 'back') {
      setPin((p) => p.slice(0, -1));
      return;
    }
    if (!key || pin.length >= digits) return;
    const next = pin + key;
    setPin(next);
    if (next.length === digits) void attemptPin(next);
  };

  const tryBiometric = useCallback(async () => {
    if (!hasBiometric || busy) return;
    setBusy(true);
    setError(null);
    const res = await unlockWithBiometrics();
    setBusy(false);
    if (!res.ok && res.error) setError(res.error);
  }, [busy, hasBiometric, unlockWithBiometrics]);

  useEffect(() => {
    if (!locked || !ready || !hasBiometric || triedBio.current) return;
    triedBio.current = true;
    const t = window.setTimeout(() => void tryBiometric(), 350);
    return () => window.clearTimeout(t);
  }, [locked, ready, hasBiometric, tryBiometric]);

  useEffect(() => {
    if (!locked) {
      triedBio.current = false;
      setPin('');
      setError(null);
    }
  }, [locked]);

  useEffect(() => {
    if (!locked) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key >= '0' && e.key <= '9') {
        e.preventDefault();
        press(e.key as '0');
      } else if (e.key === 'Backspace') {
        e.preventDefault();
        press('back');
      } else if (e.key === 'Enter' && pin.length >= 4) {
        e.preventDefault();
        void attemptPin(pin);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [locked, pin, attemptPin, busy, digits]);

  if (!ready || !locked) return null;

  return (
    <div
      className="fixed inset-0 z-[200] flex flex-col items-center justify-center bg-mesh px-6"
      role="dialog"
      aria-modal="true"
      aria-label="App locked"
    >
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_at_top,_var(--glow),_transparent_55%)]" />

      <div className="relative z-10 flex w-full max-w-sm flex-col items-center">
        <Brand />
        <div className="mt-8 flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10 text-primary shadow-inner">
          <Lock className="h-7 w-7" />
        </div>
        <h1 className="mt-4 text-xl font-semibold tracking-tight">Santim is locked</h1>
        <p className="mt-1 text-center text-sm text-muted">
          {user?.name ? `Welcome back, ${user.name.split(' ')[0]}` : 'Enter your PIN to continue'}
        </p>

        <div className={cn('mt-8 flex gap-3', shake && 'animate-lock-shake')} aria-live="polite">
          {Array.from({ length: digits }).map((_, i) => (
            <span
              key={i}
              className={cn(
                'h-3 w-3 rounded-full border-2 transition-colors',
                i < pin.length ? 'border-primary bg-primary' : 'border-border bg-transparent',
              )}
            />
          ))}
        </div>

        {error && <p className="mt-3 text-sm font-medium text-danger">{error}</p>}

        {hasBiometric && (
          <Button type="button" variant="outline" className="mt-6 gap-2" disabled={busy} onClick={() => void tryBiometric()}>
            <Fingerprint className="h-4 w-4" />
            Unlock with biometrics
          </Button>
        )}

        <div className="mt-8 grid w-full max-w-[280px] grid-cols-3 gap-3">
          {KEYS.map((key, i) =>
            key === '' ? (
              <span key={`empty-${i}`} />
            ) : (
              <button
                key={key}
                type="button"
                disabled={busy}
                onClick={() => press(key)}
                className={cn(
                  'flex h-14 items-center justify-center rounded-2xl border border-border bg-surface text-xl font-semibold shadow-sm transition active:scale-95',
                  'hover:bg-surface-muted disabled:opacity-50',
                  key === 'back' && 'text-muted',
                )}
                aria-label={key === 'back' ? 'Delete' : key}
              >
                {key === 'back' ? <Delete className="h-5 w-5" /> : key}
              </button>
            ),
          )}
        </div>

        <p className="mt-8 flex items-center gap-1.5 text-xs text-muted">
          <Shield className="h-3.5 w-3.5" />
          PIN & biometrics stay on this device
        </p>
      </div>
    </div>
  );
}
