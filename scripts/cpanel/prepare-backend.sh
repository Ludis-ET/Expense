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
cp -r "$ROOT/backend/prisma" "$OUT/prisma"

echo "📥 Installing production npm dependencies (linux x64)..."
cd "$OUT"
npm install --omit=dev --no-audit --no-fund

echo "🗄️  Generating Prisma client in deploy bundle..."
npx prisma generate

echo "✅ Backend deploy package ready → deploy/backend/"
echo "   cPanel startup file: boot.js"
du -sh "$OUT"
