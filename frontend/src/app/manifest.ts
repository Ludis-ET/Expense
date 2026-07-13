import type { MetadataRoute } from 'next';

const basePath = process.env.NEXT_BASE_PATH ?? '';

export default function manifest(): MetadataRoute.Manifest {
  const prefix = basePath.replace(/\/$/, '');
  const scope = prefix || '/';
  // Absolute-from-origin paths so install works with or without a trailing slash.
  const startUrl = `${prefix}/dashboard`;

  return {
    id: scope,
    name: 'Santim - Personal Finance',
    short_name: 'Santim',
    description: 'Track income and spending, budgets, goals, and analytics. Private birr-first finance.',
    start_url: startUrl,
    scope,
    display: 'standalone',
    display_override: ['standalone', 'minimal-ui'],
    orientation: 'any',
    background_color: '#f4f6f9',
    theme_color: '#059669',
    lang: 'en',
    dir: 'ltr',
    categories: ['finance', 'productivity'],
    prefer_related_applications: false,
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
        src: `${prefix}/icons/icon-512-maskable.png`,
        sizes: '512x512',
        type: 'image/png',
        purpose: 'maskable',
      },
    ],
  };
}
