import type { Metadata } from 'next';
import { Geist } from 'next/font/google';
import { Providers } from '@/components/providers';
import './globals.css';

const geistSans = Geist({ subsets: ['latin'], variable: '--font-geist-sans' });

export const metadata: Metadata = {
  title: {
    default: 'Santim - Personal income & expense tracker',
    template: '%s · Santim',
  },
  description:
    'Know where every birr goes. Track income and spending, set budgets, save towards goals, and get personalized insights - private to you.',
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
