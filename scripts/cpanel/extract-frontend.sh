#!/usr/bin/env bash
# Run in cPanel Terminal after CI/CD uploads santim-frontend.tgz
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f santim-frontend.tgz ]; then
  echo "❌ santim-frontend.tgz not found in $(pwd)"
  exit 1
fi

echo "📦 Extracting santim-frontend.tgz..."
tar xzf santim-frontend.tgz

if [ -f frontend/server.js ]; then
  STARTUP="frontend/server.js"
elif [ -f server.js ]; then
  STARTUP="server.js"
else
  echo "❌ server.js not found"
  exit 1
fi

if ! find node_modules -path '*/next/package.json' 2>/dev/null | grep -q .; then
  echo "❌ next not found in node_modules"
  exit 1
fi

echo "✅ Frontend ready"
echo "   cPanel startup file → $STARTUP"
echo "   Restart Node.js app"
