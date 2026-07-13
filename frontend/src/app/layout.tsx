import type { Metadata, Viewport } from 'next';
import { Geist } from 'next/font/google';
import { Providers } from '@/components/providers';
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
    icon: [
      { url: withBase('/icons/icon.svg'), type: 'image/svg+xml' },
      { url: withBase('/icons/favicon-32.png'), sizes: '32x32', type: 'image/png' },
      { url: withBase('/icons/favicon-16.png'), sizes: '16x16', type: 'image/png' },
      { url: withBase('/icons/icon-192.png'), sizes: '192x192', type: 'image/png' },
    ],
    apple: [{ url: withBase('/icons/apple-touch-icon.png'), sizes: '180x180', type: 'image/png' }],
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
      </body>
    </html>
  );
}
