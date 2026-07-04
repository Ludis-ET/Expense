#!/usr/bin/env bash
# Builds Next.js standalone + santim-frontend.tgz (flat layout — extract in place).
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

echo "📋 Copying standalone bundle..."
cp -a "$STANDALONE/." "$OUT/"

# pnpm monorepo standalone: deps in root node_modules/, app in frontend/.
# Flatten so tar extracts server.js directly into the folder (no frontend/ subfolder).
if [ -f "$OUT/frontend/server.js" ]; then
  echo "📁 Flattening monorepo layout → server.js at deploy root..."
  NM_BACKUP=$(mktemp -d)
  if [ -d "$OUT/node_modules" ]; then
    cp -a "$OUT/node_modules/." "$NM_BACKUP/"
  fi
  cp "$OUT/frontend/server.js" "$OUT/server.js"
  if [ -f "$OUT/frontend/package.json" ]; then
    cp "$OUT/frontend/package.json" "$OUT/package.json"
  fi
  mkdir -p "$OUT/.next"
  if [ -d "$OUT/frontend/.next" ]; then
    cp -a "$OUT/frontend/.next/." "$OUT/.next/"
  fi
  if [ -d "$OUT/frontend/public" ]; then
    cp -a "$OUT/frontend/public" "$OUT/public"
  fi
  rm -rf "$OUT/frontend"
  mkdir -p "$OUT/node_modules"
  if [ -d "$NM_BACKUP" ] && [ "$(ls -A "$NM_BACKUP" 2>/dev/null)" ]; then
    cp -a "$NM_BACKUP/." "$OUT/node_modules/"
  fi
  rm -rf "$NM_BACKUP"
fi

mkdir -p "$OUT/.next/static"
cp -a "$ROOT/frontend/.next/static/." "$OUT/.next/static/"

if [ -d "$ROOT/frontend/public" ] && [ ! -d "$OUT/public" ]; then
  cp -a "$ROOT/frontend/public" "$OUT/public"
fi

if [ ! -f "$OUT/server.js" ]; then
  echo "❌ server.js missing at deploy root"
  exit 1
fi

if ! find "$OUT/node_modules" -path '*/next/package.json' 2>/dev/null | grep -q .; then
  echo "❌ next not found under node_modules"
  ls -la "$OUT/node_modules/" 2>/dev/null | head -20 || true
  exit 1
fi

echo "✅ Flat bundle ready — server.js at root"

cp "$ROOT/scripts/cpanel/extract-frontend.sh" "$OUT/extract-frontend.sh"
chmod +x "$OUT/extract-frontend.sh"

cat > "$OUT/EXTRACT.txt" <<'EOF'
  cd ~/santim.lunafh.com/frontend
  tar xzf santim-frontend.tgz
  cPanel startup file: server.js
EOF

echo "📦 Creating santim-frontend.tgz..."
mkdir -p "$FTP"
tar czf "$TGZ" -C "$OUT" .
cp "$TGZ" "$FTP/santim-frontend.tgz"

echo "✅ Frontend tarball ready ($(du -h "$TGZ" | cut -f1))"
echo "   Extract → server.js in same folder as .tgz"
tar tzf "$TGZ" | grep -E '^(\./)?server.js$' || tar tzf "$TGZ" | grep 'server.js' | head -3
