#!/usr/bin/env bash
# Run in cPanel Terminal after CI/CD uploads santim-backend.tgz
# Usage:  cd ~/santim.lunafh.com/backend && bash extract-backend.sh
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f santim-backend.tgz ]; then
  echo "❌ santim-backend.tgz not found in $(pwd)"
  echo "   Wait for GitHub Actions FTP step to finish, or check File Manager."
  exit 1
fi

echo "📦 Extracting santim-backend.tgz..."
tar xzf santim-backend.tgz

if [ ! -f dist/server.js ]; then
  echo "❌ dist/server.js still missing after extract — tarball may be corrupt"
  exit 1
fi

echo "✅ Extracted dist/server.js"

if [ ! -d node_modules/express ]; then
  echo "📥 Running npm install --omit=dev ..."
  npm install --omit=dev
else
  echo "ℹ️  node_modules already present — skip npm install or run manually"
fi

echo ""
echo "✅ Done! Next steps:"
echo "   1. npx prisma migrate deploy"
echo "   2. npx prisma db seed          (optional)"
echo "   3. cPanel → Node.js app → startup file: server.js → Restart"
