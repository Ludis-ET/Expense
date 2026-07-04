'use client';

import type { ReactNode } from 'react';
import { ThemeProvider } from 'next-themes';
import { SWRConfig } from 'swr';
import { Toaster } from 'sonner';
import { ConfirmProvider } from '@/components/ui/confirm-dialog';
import { fetcher } from '@/lib/api';
import { AuthProvider } from '@/lib/auth';

export function Providers({ children }: { children: ReactNode }) {
  return (
    <ThemeProvider attribute="class" defaultTheme="system" enableSystem disableTransitionOnChange>
      <SWRConfig value={{ fetcher, revalidateOnFocus: false, shouldRetryOnError: false }}>
        <AuthProvider>
          <ConfirmProvider>
            {children}
          </ConfirmProvider>
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
