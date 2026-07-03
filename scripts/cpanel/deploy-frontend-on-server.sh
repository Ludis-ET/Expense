#!/usr/bin/env bash
# Run on cPanel Terminal from the repo root.
# Example:  cd ~/Expense && bash scripts/cpanel/deploy-frontend-on-server.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FRONTEND="$ROOT/frontend"
RUN="$FRONTEND/run"
STANDALONE="$FRONTEND/.next/standalone"

export BACKEND_URL="${BACKEND_URL:-https://santim.lunafh.com/backend}"
export NEXT_BASE_PATH="${NEXT_BASE_PATH:-/frontend}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Santim frontend — cPanel terminal deploy"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   BACKEND_URL=$BACKEND_URL"
echo "   NEXT_BASE_PATH=$NEXT_BASE_PATH"

cd "$ROOT"

if command -v pnpm >/dev/null 2>&1; then
  echo "📦 pnpm install..."
  pnpm install --frozen-lockfile
  echo "🔨 Build frontend..."
  BACKEND_URL="$BACKEND_URL" NEXT_BASE_PATH="$NEXT_BASE_PATH" pnpm --filter @santim/frontend build
else
  echo "📦 npm install (frontend)..."
  cd "$FRONTEND"
  npm install
  echo "🔨 Build frontend..."
  BACKEND_URL="$BACKEND_URL" NEXT_BASE_PATH="$NEXT_BASE_PATH" npm run build
fi

if [ ! -d "$STANDALONE" ]; then
  echo "❌ Standalone build not found at frontend/.next/standalone"
  exit 1
fi

echo "📋 Assembling run/ bundle..."
rm -rf "$RUN"
mkdir -p "$RUN"
cp -a "$STANDALONE/." "$RUN/"

if [ -f "$RUN/frontend/server.js" ] && [ ! -f "$RUN/server.js" ]; then
  cp -a "$RUN/frontend/." "$RUN/"
  rm -rf "$RUN/frontend"
fi

mkdir -p "$RUN/.next"
cp -r "$FRONTEND/.next/static" "$RUN/.next/static"
[ -d "$FRONTEND/public" ] && cp -r "$FRONTEND/public" "$RUN/public"

echo ""
echo "✅ Frontend ready in frontend/run/"
echo "   cPanel Node.js app root → frontend/run"
echo "   Startup file → server.js"
echo "   Then click Restart"
