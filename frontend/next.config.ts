import type { NextConfig } from 'next';

// Path-based cPanel deploy: NEXT_BASE_PATH=/frontend, API at /backend/api/v1
const basePath = process.env.NEXT_BASE_PATH ?? '';

const nextConfig: NextConfig = {
  output: 'standalone',
  basePath,
  reactStrictMode: true,
  eslint: { ignoreDuringBuilds: true },
  env: {
    NEXT_PUBLIC_API_BASE:
      process.env.NEXT_PUBLIC_API_BASE ??
      (basePath ? '/backend/api/v1' : '/api/v1'),
  },
  async rewrites() {
    const backend = process.env.BACKEND_URL ?? 'http://localhost:4000';
    return [{ source: '/api/:path*', destination: `${backend}/api/:path*` }];
  },
};

export default nextConfig;
