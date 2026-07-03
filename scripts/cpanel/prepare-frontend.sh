#!/usr/bin/env bash
# Builds a standalone Next.js bundle for FTP upload to cPanel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/deploy/frontend"
STANDALONE="$ROOT/frontend/.next/standalone"

if [ -z "${BACKEND_URL:-}" ]; then
  echo "❌ BACKEND_URL is required (e.g. https://santim.lunafh.com/backend)"
  exit 1
fi

# Path-based hosting: frontend at /frontend, API at /backend on the same domain.
NEXT_BASE_PATH="${NEXT_BASE_PATH:-${CPANEL_FRONTEND_BASE_PATH:-/frontend}}"
NEXT_PUBLIC_API_BASE="${NEXT_PUBLIC_API_BASE:-${CPANEL_API_BASE_PATH:-/backend/api/v1}}"

echo "🧹 Cleaning previous frontend deploy folder..."
rm -rf "$OUT"
mkdir -p "$OUT"

echo "🔨 Building Next.js (BACKEND_URL=$BACKEND_URL, NEXT_BASE_PATH=${NEXT_BASE_PATH:-/}, NEXT_PUBLIC_API_BASE=${NEXT_PUBLIC_API_BASE:-/api/v1})..."
cd "$ROOT/frontend"
BACKEND_URL="$BACKEND_URL" \
  NEXT_BASE_PATH="$NEXT_BASE_PATH" \
  NEXT_PUBLIC_API_BASE="$NEXT_PUBLIC_API_BASE" \
  pnpm build

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
