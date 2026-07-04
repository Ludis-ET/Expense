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

if [ -f "$RUN/frontend/server.js" ]; then
  NM_BACKUP=$(mktemp -d)
  [ -d "$RUN/node_modules" ] && cp -a "$RUN/node_modules/." "$NM_BACKUP/"
  cp "$RUN/frontend/server.js" "$RUN/server.js"
  mkdir -p "$RUN/.next"
  [ -d "$RUN/frontend/.next" ] && cp -a "$RUN/frontend/.next/." "$RUN/.next/"
  rm -rf "$RUN/frontend"
  mkdir -p "$RUN/node_modules"
  [ -d "$NM_BACKUP" ] && cp -a "$NM_BACKUP/." "$RUN/node_modules/"
  rm -rf "$NM_BACKUP"
fi

mkdir -p "$RUN/.next/static"
cp -a "$FRONTEND/.next/static/." "$RUN/.next/static/"

echo "✅ Frontend ready in frontend/run/ — startup: server.js"
