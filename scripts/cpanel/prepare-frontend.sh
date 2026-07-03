#!/usr/bin/env bash
# Builds a standalone Next.js bundle for FTP upload to cPanel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/deploy/frontend"
STANDALONE="$ROOT/frontend/.next/standalone"

if [ -z "${BACKEND_URL:-}" ]; then
  echo "❌ BACKEND_URL is required (e.g. https://api.yourdomain.com)"
  exit 1
fi

echo "🧹 Cleaning previous frontend deploy folder..."
rm -rf "$OUT"
mkdir -p "$OUT"

echo "🔨 Building Next.js (BACKEND_URL=$BACKEND_URL)..."
cd "$ROOT/frontend"
BACKEND_URL="$BACKEND_URL" pnpm build

if [ ! -d "$STANDALONE" ]; then
  echo "❌ Standalone output not found. Ensure next.config.ts has output: 'standalone'."
  exit 1
fi

echo "📋 Assembling standalone bundle..."
cp -a "$STANDALONE/." "$OUT/"

# Monorepo builds nest the app under frontend/ — flatten for simpler cPanel setup.
if [ -f "$OUT/frontend/server.js" ] && [ ! -f "$OUT/server.js" ]; then
  echo "📁 Detected monorepo layout — flattening frontend/ into deploy root..."
  cp -a "$OUT/frontend/." "$OUT/"
  rm -rf "$OUT/frontend"
fi

echo "📦 Copying static assets..."
mkdir -p "$OUT/.next"
cp -r "$ROOT/frontend/.next/static" "$OUT/.next/static"

if [ -d "$ROOT/frontend/public" ]; then
  cp -r "$ROOT/frontend/public" "$OUT/public"
fi

if [ ! -f "$OUT/server.js" ]; then
  echo "❌ server.js not found in deploy package. Check the standalone build output."
  exit 1
fi

echo "✅ Frontend deploy package ready → deploy/frontend/"
echo "   Startup file for cPanel Node.js app: server.js"
du -sh "$OUT"
