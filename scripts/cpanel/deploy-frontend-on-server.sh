#!/usr/bin/env bash
# Run on cPanel Terminal from the repo root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FRONTEND="$ROOT/frontend"
RUN="$FRONTEND/run"
STANDALONE="$FRONTEND/.next/standalone"

export BACKEND_URL="${BACKEND_URL:-https://santim.lunafh.com/backend}"
export NEXT_BASE_PATH="${NEXT_BASE_PATH:-/frontend}"

echo "🚀 Santim frontend — cPanel terminal deploy"
echo "   BACKEND_URL=$BACKEND_URL"
echo "   NEXT_BASE_PATH=$NEXT_BASE_PATH"

cd "$ROOT"

if command -v pnpm >/dev/null 2>&1; then
  pnpm install --frozen-lockfile
  BACKEND_URL="$BACKEND_URL" NEXT_BASE_PATH="$NEXT_BASE_PATH" pnpm --filter @santim/frontend build
else
  cd "$FRONTEND" && npm install
  BACKEND_URL="$BACKEND_URL" NEXT_BASE_PATH="$NEXT_BASE_PATH" npm run build
fi

rm -rf "$RUN"
mkdir -p "$RUN"
cp -a "$STANDALONE/." "$RUN/"

APP_DIR="$RUN"
[ -d "$RUN/frontend" ] && APP_DIR="$RUN/frontend"

mkdir -p "$APP_DIR/.next/static"
cp -r "$FRONTEND/.next/static/." "$APP_DIR/.next/static/"
[ -d "$FRONTEND/public" ] && cp -r "$FRONTEND/public" "$APP_DIR/public"

REL="${APP_DIR#$RUN/}/server.js"
echo "✅ Frontend ready in frontend/run/"
echo "   App root → frontend/run"
echo "   Startup file → $REL"
