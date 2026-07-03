#!/usr/bin/env bash
# Optional: slim FTP bundle (no node_modules). Prefer terminal deploy — see docs/DEPLOY-CPANEL-TERMINAL.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/deploy/backend"

echo "🧹 Cleaning previous backend deploy folder..."
rm -rf "$OUT"
mkdir -p "$OUT"

echo "🔨 Compiling TypeScript + generating Prisma client..."
cd "$ROOT"
pnpm --filter @santim/backend build

if [ ! -f "$ROOT/backend/generated/client/index.js" ]; then
  echo "❌ generated/client missing — run prisma generate"
  exit 1
fi

echo "📋 Copying application files (no node_modules)..."
cp -r "$ROOT/backend/dist" "$OUT/dist"
cp -r "$ROOT/backend/generated/client" "$OUT/generated/client"
cp -r "$ROOT/backend/prisma" "$OUT/prisma"

node - "$ROOT" "$OUT" <<'NODE'
const fs = require('fs');
const path = require('path');
const root = process.argv[1];
const out = process.argv[2];
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'backend/package.json'), 'utf8'));
const { devDependencies, prisma: _p, postinstall, ...rest } = pkg;
const deps = { ...rest.dependencies };
delete deps.prisma;
const deploy = {
  ...rest,
  dependencies: deps,
  scripts: { start: 'node dist/server.js', 'db:deploy': 'prisma migrate deploy' },
};
fs.writeFileSync(path.join(out, 'package.json'), JSON.stringify(deploy, null, 2));
NODE

find "$OUT/generated/client" -type f \( -name '*.ts' -o -name '*.map' \) -delete 2>/dev/null || true

echo "✅ Slim backend bundle → deploy/backend/"
du -sh "$OUT"
