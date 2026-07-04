import type { MetadataRoute } from 'next';

const basePath = process.env.NEXT_BASE_PATH ?? '';

export default function manifest(): MetadataRoute.Manifest {
  const prefix = basePath.replace(/\/$/, '');

  return {
    name: 'Santim - Personal Finance',
    short_name: 'Santim',
    description: 'Track income and spending, budgets, goals, and analytics. Private birr-first finance.',
    start_url: `${prefix}/dashboard`,
    scope: prefix || '/',
    display: 'standalone',
    orientation: 'portrait-primary',
    background_color: '#f4f6f9',
    theme_color: '#059669',
    categories: ['finance', 'productivity'],
    icons: [
      {
        src: `${prefix}/icons/icon-192.png`,
        sizes: '192x192',
        type: 'image/png',
        purpose: 'any',
      },
      {
        src: `${prefix}/icons/icon-512.png`,
        sizes: '512x512',
        type: 'image/png',
        purpose: 'any',
      },
      {
        src: `${prefix}/icons/icon-512.png`,
        sizes: '512x512',
        type: 'image/png',
        purpose: 'maskable',
      },
    ],
  };
}
