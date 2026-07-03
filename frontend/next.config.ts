import type { NextConfig } from 'next';

// Set NEXT_BASE_PATH=/frontend when the app is served under a subdirectory (e.g. santim.lunafh.com/frontend).
const basePath = process.env.NEXT_BASE_PATH ?? '';

const nextConfig: NextConfig = {
  // Minimal self-contained server bundle for cPanel / VPS Node.js hosting.
  output: 'standalone',
  basePath,
  reactStrictMode: true,
  // Lint is run explicitly via `pnpm lint`; don't fail production builds on nits.
  eslint: { ignoreDuringBuilds: true },
  // Proxy /api/* to the backend in dev so the browser stays same-origin
  // (no CORS preflight) and tokens flow cleanly.
  async rewrites() {
    const backend = process.env.BACKEND_URL ?? 'http://localhost:4000';
    return [{ source: '/api/:path*', destination: `${backend}/api/:path*` }];
  },
};

export default nextConfig;
