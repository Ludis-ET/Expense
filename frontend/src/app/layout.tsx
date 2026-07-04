import type { Metadata, Viewport } from 'next';
import { Geist } from 'next/font/google';
import { Providers } from '@/components/providers';
import { InstallPrompt } from '@/components/pwa/install-prompt';
import { withBase } from '@/lib/base-path';
import './globals.css';

const geistSans = Geist({ subsets: ['latin'], variable: '--font-geist-sans' });

const APP_NAME = 'Santim';
const APP_DESCRIPTION =
  'Know where every birr goes. Track income and spending, set budgets, save towards goals, and get personalized insights - private to you.';

export const metadata: Metadata = {
  applicationName: APP_NAME,
  title: {
    default: 'Santim - Personal income & expense tracker',
    template: '%s · Santim',
  },
  description: APP_DESCRIPTION,
  manifest: withBase('/manifest.webmanifest'),
  appleWebApp: {
    capable: true,
    statusBarStyle: 'default',
    title: APP_NAME,
  },
  formatDetection: { telephone: false },
  icons: {
    icon: withBase('/icons/icon-192.png'),
    apple: withBase('/icons/apple-touch-icon.png'),
  },
  openGraph: {
    type: 'website',
    siteName: APP_NAME,
    title: 'Santim - Personal income & expense tracker',
    description: APP_DESCRIPTION,
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#059669' },
    { media: '(prefers-color-scheme: dark)', color: '#080b12' },
  ],
  width: 'device-width',
  initialScale: 1,
  maximumScale: 5,
  viewportFit: 'cover',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className={`${geistSans.variable} antialiased`}>
        <Providers>{children}</Providers>
        <InstallPrompt />
      </body>
    </html>
  );
}
