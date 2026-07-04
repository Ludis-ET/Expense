#!/usr/bin/env bash
# Run in cPanel Terminal after CI/CD uploads santim-frontend.tgz
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f santim-frontend.tgz ]; then
  echo "❌ santim-frontend.tgz not found in $(pwd)"
  exit 1
fi

echo "📦 Extracting santim-frontend.tgz into $(pwd)..."
tar xzf santim-frontend.tgz

if [ ! -f server.js ]; then
  echo "❌ server.js not found at deploy root after extract"
  exit 1
fi

if ! find node_modules -path '*/next/package.json' 2>/dev/null | grep -q .; then
  echo "❌ next not found in node_modules"
  exit 1
fi

echo "✅ Frontend ready — server.js is in this folder"
echo "   cPanel startup file → server.js"
echo "   Restart Node.js app"
