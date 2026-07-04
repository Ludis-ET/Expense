#!/usr/bin/env bash
# Builds Next.js standalone + santim-frontend.tgz for reliable FTP upload.
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

echo "📋 Assembling standalone bundle..."
cp -a "$STANDALONE/." "$OUT/"

# Monorepo standalone: deps live in root node_modules/, app in frontend/.
# Do NOT cp -a frontend/. → OUT/ (that overwrites root node_modules and drops `next`).
if [ -f "$OUT/frontend/server.js" ]; then
  echo "📁 Flattening monorepo layout (keeping root node_modules)..."
  ROOT_NODE_MODULES="$OUT/node_modules"
  SAVED_NM=$(mktemp -d)
  if [ -d "$ROOT_NODE_MODULES" ]; then
    cp -a "$ROOT_NODE_MODULES/." "$SAVED_NM/"
  fi
  cp "$OUT/frontend/server.js" "$OUT/server.js"
  if [ -d "$OUT/frontend/.next" ]; then
    mkdir -p "$OUT/.next"
    cp -a "$OUT/frontend/.next/." "$OUT/.next/"
  fi
  rm -rf "$OUT/frontend"
  mkdir -p "$OUT/node_modules"
  if [ -d "$SAVED_NM" ] && [ "$(ls -A "$SAVED_NM" 2>/dev/null)" ]; then
    cp -a "$SAVED_NM/." "$OUT/node_modules/"
  fi
  rm -rf "$SAVED_NM"
fi

mkdir -p "$OUT/.next"
cp -r "$ROOT/frontend/.next/static" "$OUT/.next/static"
[ -d "$ROOT/frontend/public" ] && cp -r "$ROOT/frontend/public" "$OUT/public"

if [ ! -f "$OUT/server.js" ]; then
  echo "❌ server.js missing"
  exit 1
fi

if ! (cd "$OUT" && node -e "require.resolve('next/package.json')" >/dev/null 2>&1); then
  echo "❌ next package not resolvable — standalone bundle incomplete"
  ls -la "$OUT/" || true
  ls -la "$OUT/node_modules/" 2>/dev/null | head -20 || true
  exit 1
fi

echo "✅ next resolves from standalone node_modules"

cp "$ROOT/scripts/cpanel/extract-frontend.sh" "$OUT/extract-frontend.sh"
chmod +x "$OUT/extract-frontend.sh"

cat > "$OUT/EXTRACT.txt" <<'EOF'
Run in cPanel Terminal after FTP upload:

  cd ~/santim.lunafh.com/frontend
  tar xzf santim-frontend.tgz

cPanel → Node.js app → startup file: server.js → Restart
EOF

echo "📦 Creating santim-frontend.tgz (includes node_modules/next)..."
mkdir -p "$FTP"
tar czf "$TGZ" -C "$OUT" .
cp "$TGZ" "$FTP/santim-frontend.tgz"

echo "✅ Frontend tarball ready ($(du -h "$TGZ" | cut -f1))"
tar tzf "$TGZ" | grep -E 'node_modules/.*next.*package\.json' | head -3 || tar tzf "$TGZ" | grep 'server.js'
