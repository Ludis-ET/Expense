'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { useAuth } from '@/lib/auth';
import {
  type AppLockConfig,
  type AutoLockMinutes,
  clearLockConfig,
  clearSessionUnlocked,
  enrollBiometric,
  hashPin,
  isPlatformAuthenticatorAvailable,
  isSessionUnlocked,
  isWebAuthnAvailable,
  loadLockConfig,
  markSessionUnlocked,
  saveLockConfig,
  unlockWithBiometric,
  validatePin,
  verifyPin,
} from '@/lib/app-lock-crypto';

interface AppLockContextValue {
  ready: boolean;
  enabled: boolean;
  locked: boolean;
  pinLength: number;
  hasBiometric: boolean;
  biometricAvailable: boolean;
  autoLockMinutes: AutoLockMinutes;
  lockOnBlur: boolean;
  lock: () => void;
  unlockWithPin: (pin: string) => Promise<{ ok: boolean; error?: string }>;
  unlockWithBiometrics: () => Promise<{ ok: boolean; error?: string }>;
  enableLock: (pin: string) => Promise<{ ok: boolean; error?: string }>;
  changePin: (currentPin: string, nextPin: string) => Promise<{ ok: boolean; error?: string }>;
  disableLock: (pin: string) => Promise<{ ok: boolean; error?: string }>;
  enrollBiometrics: () => Promise<{ ok: boolean; error?: string }>;
  removeBiometrics: () => void;
  setAutoLockMinutes: (minutes: AutoLockMinutes) => void;
  setLockOnBlur: (value: boolean) => void;
  touchActivity: () => void;
}

const AppLockContext = createContext<AppLockContextValue | null>(null);

export function AppLockProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const [config, setConfig] = useState<AppLockConfig | null>(null);
  const [ready, setReady] = useState(false);
  const [locked, setLocked] = useState(false);
  const [biometricAvailable, setBiometricAvailable] = useState(false);
  const lastActivityRef = useRef(Date.now());
  const configRef = useRef(config);
  configRef.current = config;

  useEffect(() => {
    const stored = loadLockConfig();
    setConfig(stored);
    if (stored?.enabled) {
      setLocked(!isSessionUnlocked());
    }
    setReady(true);
    void isPlatformAuthenticatorAvailable().then(setBiometricAvailable);
  }, []);

  // Re-lock when auth user clears (logout)
  useEffect(() => {
    if (!user) {
      clearSessionUnlocked();
      if (configRef.current?.enabled) setLocked(true);
    }
  }, [user]);

  const persist = useCallback((next: AppLockConfig | null) => {
    setConfig(next);
    if (next) saveLockConfig(next);
    else clearLockConfig();
  }, []);

  const lock = useCallback(() => {
    if (!configRef.current?.enabled) return;
    clearSessionUnlocked();
    setLocked(true);
  }, []);

  const unlock = useCallback(() => {
    markSessionUnlocked();
    lastActivityRef.current = Date.now();
    setLocked(false);
  }, []);

  const unlockWithPin = useCallback(
    async (pin: string) => {
      const cfg = configRef.current;
      if (!cfg?.enabled) return { ok: false, error: 'Lock is not enabled' };
      const ok = await verifyPin(pin, cfg);
      if (!ok) return { ok: false, error: 'Incorrect PIN' };
      unlock();
      return { ok: true };
    },
    [unlock],
  );

  const unlockWithBiometrics = useCallback(async () => {
    const cfg = configRef.current;
    if (!cfg?.credentialId) return { ok: false, error: 'Biometrics not set up' };
    const ok = await unlockWithBiometric(cfg.credentialId);
    if (!ok) return { ok: false, error: 'Biometric unlock failed or was cancelled' };
    unlock();
    return { ok: true };
  }, [unlock]);

  const enableLock = useCallback(
    async (pin: string) => {
      const err = validatePin(pin);
      if (err) return { ok: false, error: err };
      const { salt, hash } = await hashPin(pin);
      const next: AppLockConfig = {
        enabled: true,
        salt,
        pinHash: hash,
        pinLength: pin.length,
        credentialId: null,
        autoLockMinutes: 2,
        lockOnBlur: true,
        updatedAt: new Date().toISOString(),
      };
      persist(next);
      markSessionUnlocked();
      setLocked(false);
      return { ok: true };
    },
    [persist],
  );

  const changePin = useCallback(
    async (currentPin: string, nextPin: string) => {
      const cfg = configRef.current;
      if (!cfg?.enabled) return { ok: false, error: 'Lock is not enabled' };
      if (!(await verifyPin(currentPin, cfg))) return { ok: false, error: 'Current PIN is incorrect' };
      const err = validatePin(nextPin);
      if (err) return { ok: false, error: err };
      const { salt, hash } = await hashPin(nextPin);
      persist({
        ...cfg,
        salt,
        pinHash: hash,
        pinLength: nextPin.length,
        updatedAt: new Date().toISOString(),
      });
      return { ok: true };
    },
    [persist],
  );

  const disableLock = useCallback(
    async (pin: string) => {
      const cfg = configRef.current;
      if (!cfg?.enabled) return { ok: true };
      if (!(await verifyPin(pin, cfg))) return { ok: false, error: 'Incorrect PIN' };
      persist(null);
      clearSessionUnlocked();
      setLocked(false);
      return { ok: true };
    },
    [persist],
  );

  const enrollBiometrics = useCallback(async () => {
    const cfg = configRef.current;
    if (!cfg?.enabled || !user) return { ok: false, error: 'Enable PIN lock first' };
    if (!isWebAuthnAvailable()) return { ok: false, error: 'Biometrics not supported here' };
    try {
      const credentialId = await enrollBiometric({
        id: user.id,
        email: user.email,
        name: user.name,
      });
      persist({ ...cfg, credentialId, updatedAt: new Date().toISOString() });
      return { ok: true };
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : 'Biometric setup failed' };
    }
  }, [persist, user]);

  const removeBiometrics = useCallback(() => {
    const cfg = configRef.current;
    if (!cfg) return;
    persist({ ...cfg, credentialId: null, updatedAt: new Date().toISOString() });
  }, [persist]);

  const setAutoLockMinutes = useCallback(
    (minutes: AutoLockMinutes) => {
      const cfg = configRef.current;
      if (!cfg) return;
      persist({ ...cfg, autoLockMinutes: minutes, updatedAt: new Date().toISOString() });
    },
    [persist],
  );

  const setLockOnBlur = useCallback(
    (value: boolean) => {
      const cfg = configRef.current;
      if (!cfg) return;
      persist({ ...cfg, lockOnBlur: value, updatedAt: new Date().toISOString() });
    },
    [persist],
  );

  const touchActivity = useCallback(() => {
    lastActivityRef.current = Date.now();
  }, []);

  // Idle auto-lock + blur lock
  useEffect(() => {
    if (!config?.enabled || locked) return;

    const onActivity = () => {
      lastActivityRef.current = Date.now();
    };

    const events = ['pointerdown', 'keydown', 'touchstart', 'scroll'] as const;
    for (const ev of events) window.addEventListener(ev, onActivity, { passive: true });

    const interval = window.setInterval(() => {
      const cfg = configRef.current;
      if (!cfg?.enabled || cfg.autoLockMinutes <= 0) return;
      const idleMs = Date.now() - lastActivityRef.current;
      if (idleMs >= cfg.autoLockMinutes * 60_000) {
        clearSessionUnlocked();
        setLocked(true);
      }
    }, 15_000);

    const onVisibility = () => {
      const cfg = configRef.current;
      if (!cfg?.enabled || !cfg.lockOnBlur) return;
      if (document.visibilityState === 'hidden') {
        // Remember when we left; lock if away long enough or immediately if autoLock is 0 with blur
        lastActivityRef.current = Date.now();
      } else if (document.visibilityState === 'visible') {
        const awayMs = Date.now() - lastActivityRef.current;
        // Lock if away > 30s, or if auto-lock is immediate-ish
        const threshold = cfg.autoLockMinutes === 0 ? 30_000 : Math.min(cfg.autoLockMinutes * 60_000, 60_000);
        if (awayMs >= threshold) {
          clearSessionUnlocked();
          setLocked(true);
        }
      }
    };
    document.addEventListener('visibilitychange', onVisibility);

    return () => {
      for (const ev of events) window.removeEventListener(ev, onActivity);
      window.clearInterval(interval);
      document.removeEventListener('visibilitychange', onVisibility);
    };
  }, [config?.enabled, locked]);

  const value = useMemo<AppLockContextValue>(
    () => ({
      ready,
      enabled: !!config?.enabled,
      locked: !!config?.enabled && locked,
      pinLength: config?.pinLength ?? 4,
      hasBiometric: !!config?.credentialId,
      biometricAvailable,
      autoLockMinutes: config?.autoLockMinutes ?? 2,
      lockOnBlur: config?.lockOnBlur ?? true,
      lock,
      unlockWithPin,
      unlockWithBiometrics,
      enableLock,
      changePin,
      disableLock,
      enrollBiometrics,
      removeBiometrics,
      setAutoLockMinutes,
      setLockOnBlur,
      touchActivity,
    }),
    [
      ready,
      config,
      locked,
      biometricAvailable,
      lock,
      unlockWithPin,
      unlockWithBiometrics,
      enableLock,
      changePin,
      disableLock,
      enrollBiometrics,
      removeBiometrics,
      setAutoLockMinutes,
      setLockOnBlur,
      touchActivity,
    ],
  );

  return <AppLockContext.Provider value={value}>{children}</AppLockContext.Provider>;
}

export function useAppLock() {
  const ctx = useContext(AppLockContext);
  if (!ctx) throw new Error('useAppLock must be used within AppLockProvider');
  return ctx;
}

export function useOptionalAppLock() {
  return useContext(AppLockContext);
}
