#!/usr/bin/env bash
# Builds a production-ready backend bundle for FTP upload to cPanel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/deploy/backend"

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

echo "✅ Prisma client bundled in node_modules/.prisma/client"

echo "✅ Backend deploy package ready → deploy/backend/"
echo "   cPanel startup file: boot.js"
echo "   cPanel env var: SKIP_PRISMA_GENERATE=1"
du -sh "$OUT"
