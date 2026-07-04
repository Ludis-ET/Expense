#!/usr/bin/env bash
# Builds Next.js standalone + santim-frontend.tgz for reliable FTP upload.
# Keeps monorepo layout (frontend/server.js + root node_modules) — do not flatten.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/deploy/frontend"
TGZ="$ROOT/deploy/santim-frontend.tgz"
FTP="$ROOT/deploy/ftp-frontend"
STANDALONE="$ROOT/frontend/.next/standalone"

if [ -z "${BACKEND_URL:-}" ]; then
  echo "❌ BACKEND_URL is required (e.g. https://santim.lunafh.com/backend)"
  exit 1
fi

NEXT_BASE_PATH="${NEXT_BASE_PATH:-${CPANEL_FRONTEND_BASE_PATH:-/frontend}}"
NEXT_PUBLIC_API_BASE="${NEXT_PUBLIC_API_BASE:-${CPANEL_API_BASE_PATH:-/backend/api/v1}}"

echo "🧹 Cleaning previous frontend deploy folder..."
rm -rf "$OUT" "$FTP" "$TGZ"
mkdir -p "$OUT"

echo "🔨 Building Next.js..."
echo "   BACKEND_URL=$BACKEND_URL"
echo "   NEXT_BASE_PATH=$NEXT_BASE_PATH"
cd "$ROOT/frontend"
BACKEND_URL="$BACKEND_URL" \
  NEXT_BASE_PATH="$NEXT_BASE_PATH" \
  NEXT_PUBLIC_API_BASE="$NEXT_PUBLIC_API_BASE" \
  pnpm build

if [ ! -d "$STANDALONE" ]; then
  echo "❌ Standalone output not found"
  exit 1
fi

echo "📋 Copying standalone bundle (monorepo layout preserved)..."
cp -a "$STANDALONE/." "$OUT/"

# Next.js standalone does not copy static files — required for production.
APP_DIR="$OUT"
if [ -d "$OUT/frontend" ]; then
  APP_DIR="$OUT/frontend"
fi

mkdir -p "$APP_DIR/.next/static"
cp -r "$ROOT/frontend/.next/static/." "$APP_DIR/.next/static/"

if [ -d "$ROOT/frontend/public" ]; then
  cp -r "$ROOT/frontend/public" "$APP_DIR/public"
fi

if [ ! -f "$APP_DIR/server.js" ]; then
  echo "❌ server.js missing at $APP_DIR/server.js"
  exit 1
fi

# pnpm standalone uses node_modules/.pnpm — find next anywhere under node_modules.
if ! find "$OUT/node_modules" -path '*/next/package.json' 2>/dev/null | grep -q .; then
  echo "❌ next not found under node_modules"
  ls -la "$OUT/node_modules/" 2>/dev/null | head -20 || true
  exit 1
fi

echo "✅ next found in standalone node_modules"
echo "   cPanel startup file: ${APP_DIR#$OUT/}/server.js (relative to app root)"

REL_START="$APP_DIR/server.js"
REL_START="${REL_START#$OUT/}"

cp "$ROOT/scripts/cpanel/extract-frontend.sh" "$OUT/extract-frontend.sh"
chmod +x "$OUT/extract-frontend.sh"

cat > "$OUT/EXTRACT.txt" <<EOF
Run in cPanel Terminal:

  cd ~/santim.lunafh.com/frontend
  tar xzf santim-frontend.tgz

cPanel → Node.js app:
  Application root → frontend folder (this directory after extract)
  Startup file → $REL_START
  Restart
EOF

echo "📦 Creating santim-frontend.tgz..."
mkdir -p "$FTP"
tar czf "$TGZ" -C "$OUT" .
cp "$TGZ" "$FTP/santim-frontend.tgz"

echo "✅ Frontend tarball ready ($(du -h "$TGZ" | cut -f1))"
echo "   Startup: $REL_START"
tar tzf "$TGZ" | grep -E 'frontend/server.js|server.js' | head -3
