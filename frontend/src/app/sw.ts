import { defaultCache } from '@serwist/next/worker';
import {
  CacheableResponsePlugin,
  ExpirationPlugin,
  NetworkFirst,
  type PrecacheEntry,
  type RuntimeCaching,
  type SerwistGlobalConfig,
  Serwist,
} from 'serwist';

declare global {
  interface WorkerGlobalScope extends SerwistGlobalConfig {
    __SW_MANIFEST: (PrecacheEntry | string)[] | undefined;
  }
}

declare const self: ServiceWorkerGlobalScope;

const swBase = self.location.pathname.replace(/\/sw\.js$/, '');
const offlineUrl = `${swBase}/~offline`;

// Serve the last-seen version of a page / API response when the network is
// unavailable, so the installed app opens and shows data offline. Mutations
// (POST/PUT/DELETE) are never cached — the app queues those in its own outbox.
const runtimeCaching: RuntimeCaching[] = [
  {
    // Full-page navigations: try network briefly, else the cached page.
    matcher: ({ request }) => request.mode === 'navigate',
    handler: new NetworkFirst({
      cacheName: 'pages',
      networkTimeoutSeconds: 3,
      plugins: [
        new ExpirationPlugin({ maxEntries: 64, maxAgeSeconds: 7 * 24 * 60 * 60 }),
        new CacheableResponsePlugin({ statuses: [0, 200] }),
      ],
    }),
  },
  {
    // Read API calls: fresh when online, cached copy when offline.
    matcher: ({ url, request }) => request.method === 'GET' && /\/api\//.test(url.pathname),
    handler: new NetworkFirst({
      cacheName: 'api-cache',
      networkTimeoutSeconds: 5,
      plugins: [
        new ExpirationPlugin({ maxEntries: 200, maxAgeSeconds: 24 * 60 * 60 }),
        new CacheableResponsePlugin({ statuses: [0, 200] }),
      ],
    }),
  },
  ...defaultCache,
];

const serwist = new Serwist({
  precacheEntries: self.__SW_MANIFEST,
  skipWaiting: true,
  clientsClaim: true,
  navigationPreload: true,
  runtimeCaching,
  fallbacks: {
    entries: [
      {
        // Last resort only: shown when a navigation has no cached copy at all.
        url: offlineUrl,
        matcher({ request }) {
          return request.destination === 'document';
        },
      },
    ],
  },
});

serwist.addEventListeners();
