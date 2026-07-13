'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { InstallInstructionsModal } from '@/components/pwa/install-instructions-modal';

export type PwaPlatform = 'ios' | 'android' | 'other';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

interface PwaInstallContextValue {
  installed: boolean;
  isMobile: boolean;
  platform: PwaPlatform;
  canInstall: boolean;
  hasNativePrompt: boolean;
  instructionsOpen: boolean;
  openInstructions: () => void;
  closeInstructions: () => void;
  install: () => Promise<void>;
  dismissBanner: () => void;
  bannerDismissed: boolean;
}

const BANNER_DISMISS_KEY = 'santim-install-dismissed';

const PwaInstallContext = createContext<PwaInstallContextValue | null>(null);

function detectPlatform(): PwaPlatform {
  const ua = navigator.userAgent;
  if (/iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) {
    return 'ios';
  }
  if (/Android/.test(ua)) return 'android';
  return 'other';
}

function isStandalone(): boolean {
  return (
    window.matchMedia('(display-mode: standalone)').matches ||
    (window.navigator as Navigator & { standalone?: boolean }).standalone === true
  );
}

function isMobileDevice(): boolean {
  const ua = navigator.userAgent;
  if (/Android|iPhone|iPad|iPod|Mobile/i.test(ua)) return true;
  return window.matchMedia('(max-width: 768px)').matches;
}

export function PwaInstallProvider({ children }: { children: ReactNode }) {
  const [installed, setInstalled] = useState(false);
  const [isMobile, setIsMobile] = useState(false);
  const [platform, setPlatform] = useState<PwaPlatform>('other');
  const [prompt, setPrompt] = useState<BeforeInstallPromptEvent | null>(null);
  const [instructionsOpen, setInstructionsOpen] = useState(false);
  const [bannerDismissed, setBannerDismissed] = useState(false);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    setInstalled(isStandalone());
    setIsMobile(isMobileDevice());
    setPlatform(detectPlatform());
    try {
      setBannerDismissed(localStorage.getItem(BANNER_DISMISS_KEY) === '1');
    } catch {
      /* ignore */
    }
    setReady(true);

    const onPrompt = (e: Event) => {
      e.preventDefault();
      setPrompt(e as BeforeInstallPromptEvent);
    };
    const onInstalled = () => {
      setInstalled(true);
      setPrompt(null);
    };

    window.addEventListener('beforeinstallprompt', onPrompt);
    window.addEventListener('appinstalled', onInstalled);
    return () => {
      window.removeEventListener('beforeinstallprompt', onPrompt);
      window.removeEventListener('appinstalled', onInstalled);
    };
  }, []);

  const install = useCallback(async () => {
    if (prompt) {
      await prompt.prompt();
      const { outcome } = await prompt.userChoice;
      if (outcome === 'accepted') {
        setPrompt(null);
        setInstalled(true);
      }
      return;
    }
    setInstructionsOpen(true);
  }, [prompt]);

  const dismissBanner = useCallback(() => {
    try {
      localStorage.setItem(BANNER_DISMISS_KEY, '1');
    } catch {
      /* ignore */
    }
    setBannerDismissed(true);
  }, []);

  const value = useMemo(
    (): PwaInstallContextValue => ({
      installed: ready ? installed : false,
      isMobile: ready ? isMobile : false,
      platform,
      canInstall: ready && !installed && (isMobile || !!prompt),
      hasNativePrompt: !!prompt,
      instructionsOpen,
      openInstructions: () => setInstructionsOpen(true),
      closeInstructions: () => setInstructionsOpen(false),
      install,
      dismissBanner,
      bannerDismissed: ready ? bannerDismissed : true,
    }),
    [
      ready,
      installed,
      isMobile,
      platform,
      prompt,
      instructionsOpen,
      install,
      dismissBanner,
      bannerDismissed,
    ],
  );

  return (
    <PwaInstallContext.Provider value={value}>
      {children}
      <InstallInstructionsModal />
    </PwaInstallContext.Provider>
  );
}

export function usePwaInstall() {
  const ctx = useContext(PwaInstallContext);
  if (!ctx) throw new Error('usePwaInstall must be used within PwaInstallProvider');
  return ctx;
}
