#!/usr/bin/env bash
# Run in cPanel Terminal after CI/CD uploads santim-frontend.tgz
# Usage:  cd ~/santim.lunafh.com/frontend && bash extract-frontend.sh
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f santim-frontend.tgz ]; then
  echo "❌ santim-frontend.tgz not found in $(pwd)"
  exit 1
fi

echo "📦 Extracting santim-frontend.tgz..."
tar xzf santim-frontend.tgz

if [ ! -f server.js ]; then
  echo "❌ server.js missing after extract"
  exit 1
fi

if [ ! -d node_modules/next ]; then
  echo "❌ node_modules/next missing — tarball incomplete"
  exit 1
fi

echo "✅ Frontend ready (server.js + node_modules/next)"
echo "   cPanel → Node.js app → startup: server.js → Restart"
