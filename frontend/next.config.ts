import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  // Minimal self-contained server bundle for cPanel / VPS Node.js hosting.
  output: 'standalone',
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
