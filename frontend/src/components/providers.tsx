'use client';

import type { ReactNode } from 'react';
import { ThemeProvider } from 'next-themes';
import { SWRConfig } from 'swr';
import { Toaster } from 'sonner';
import { ConfirmProvider } from '@/components/ui/confirm-dialog';
import { AmountVisibilityProvider } from '@/lib/amount-visibility';
import { AppLockProvider } from '@/lib/app-lock-context';
import { OfflineProvider } from '@/lib/offline/offline-context';
import { PwaInstallProvider } from '@/lib/pwa-install-context';
import { InstallPrompt } from '@/components/pwa/install-prompt';
import { SplashScreen } from '@/components/splash-screen';
import { CurrencyViewProvider } from '@/lib/currency-view-context';
import { fetcher } from '@/lib/api';
import { AuthProvider, useAuth } from '@/lib/auth';

function CurrencyViewBridge({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  return (
    <CurrencyViewProvider defaultCurrency={user?.currency ?? 'ETB'}>
      {children}
    </CurrencyViewProvider>
  );
}

export function Providers({ children }: { children: ReactNode }) {
  return (
    <ThemeProvider attribute="class" defaultTheme="system" enableSystem disableTransitionOnChange>
      <SplashScreen />
      <SWRConfig value={{ fetcher, revalidateOnFocus: false, shouldRetryOnError: false }}>
        <AuthProvider>
          <PwaInstallProvider>
            <CurrencyViewBridge>
              <AmountVisibilityProvider>
                <AppLockProvider>
                  <ConfirmProvider>
                    <OfflineProvider>
                      {children}
                    </OfflineProvider>
                  </ConfirmProvider>
                </AppLockProvider>
              </AmountVisibilityProvider>
            </CurrencyViewBridge>
            <InstallPrompt />
          </PwaInstallProvider>
          <Toaster
            position="top-right"
            toastOptions={{
              classNames: {
                toast: 'card !bg-surface !text-foreground !border-border',
              },
            }}
          />
        </AuthProvider>
      </SWRConfig>
    </ThemeProvider>
  );
}
