#!/usr/bin/env bash
# Run on cPanel Terminal from the repo root after git pull.
# Example:  cd ~/Expense && bash scripts/cpanel/deploy-on-server.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Santim backend — cPanel terminal deploy"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -f "$ROOT/backend/.env" ]; then
  echo ""
  echo "❌ Missing backend/.env"
  echo "   cp backend/.env.example backend/.env"
  echo "   Then set DATABASE_URL, JWT_SECRET, CORS_ORIGINS, APP_URL"
  exit 1
fi

if command -v pnpm >/dev/null 2>&1; then
  echo "📦 pnpm install..."
  pnpm install --frozen-lockfile
  echo "🔨 Build backend..."
  pnpm --filter @santim/backend build
  echo "🗄️  Migrate database..."
  pnpm --filter @santim/backend db:deploy
else
  echo "📦 npm install (backend)..."
  cd "$ROOT/backend"
  npm install
  echo "🔨 Build backend..."
  npm run build
  echo "🗄️  Migrate database..."
  npm run db:deploy
fi

echo ""
echo "✅ Backend ready!"
echo "   Startup file in cPanel Node.js app: dist/server.js"
echo "   Then click Restart in Setup Node.js App"
