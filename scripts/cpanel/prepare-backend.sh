#!/usr/bin/env bash
# Builds a production-ready backend bundle for FTP upload to cPanel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/deploy/backend"
VENDOR="$OUT/vendor/node_modules"

echo "🧹 Cleaning previous backend deploy folder..."
rm -rf "$OUT"
mkdir -p "$OUT"

echo "🔨 Compiling TypeScript..."
cd "$ROOT"
pnpm --filter @santim/backend build

echo "📋 Copying dist, package.json, prisma migrations, and boot entrypoint..."
cp -r "$ROOT/backend/dist" "$OUT/dist"
cp "$ROOT/backend/package.json" "$OUT/package.json"
cp "$ROOT/backend/boot.js" "$OUT/boot.js"
mkdir -p "$OUT/scripts"
cp "$ROOT/backend/scripts/postinstall.mjs" "$OUT/scripts/postinstall.mjs"
cp -r "$ROOT/backend/prisma" "$OUT/prisma"

echo "📥 Installing production npm dependencies (linux x64)..."
cd "$OUT"
npm install --omit=dev --no-audit --no-fund

echo "🗄️  Generating Prisma client in deploy bundle (runs on CI only, not on cPanel)..."
npx prisma generate

if [ ! -f "$OUT/node_modules/.prisma/client/default.js" ] && [ ! -f "$OUT/node_modules/.prisma/client/index.js" ]; then
  echo "❌ Prisma client missing after generate — deploy bundle is incomplete"
  exit 1
fi

echo "📦 Moving deps to vendor/node_modules (avoids cPanel node_modules symlink conflict)..."
mkdir -p "$OUT/vendor"
mv "$OUT/node_modules" "$VENDOR"

echo "🧹 Pruning non-runtime files from vendor/node_modules..."
# Source, tests, and docs are not needed at runtime — shrinks FTP upload ~60%.
rm -rf "$VENDOR/zod/src" 2>/dev/null || true
find "$VENDOR" -type d \( \
  -name test -o -name tests -o -name __tests__ -o -name coverage -o \
  -name docs -o -name examples -o -name .github \
\) -prune -exec rm -rf {} + 2>/dev/null || true
find "$VENDOR" -type f \( \
  -name '*.map' -o -name '*.md' -o -name '*.markdown' -o -name 'LICENSE' -o -name 'LICENSE.*' \
\) -delete 2>/dev/null || true
find "$VENDOR" -type f \( -name '*.ts' -o -name '*.cts' -o -name '*.mts' \) \
  ! -path '*/.prisma/*' -delete 2>/dev/null || true

if [ ! -f "$VENDOR/.prisma/client/default.js" ] && [ ! -f "$VENDOR/.prisma/client/index.js" ]; then
  echo "❌ Prisma client missing in vendor/node_modules"
  exit 1
fi

echo "✅ Prisma client bundled in vendor/node_modules/.prisma/client"
du -sh "$OUT" "$VENDOR"
echo "✅ Backend deploy package ready → deploy/backend/"
echo "   cPanel startup file: boot.js"
echo "   cPanel env var: SKIP_PRISMA_GENERATE=1"
