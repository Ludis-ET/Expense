#!/usr/bin/env bash
# Builds backend + single santim-backend.tgz for reliable FTP upload.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/deploy/backend"
TGZ="$ROOT/deploy/santim-backend.tgz"
FTP="$ROOT/deploy/ftp-backend"

echo "🧹 Cleaning previous backend deploy folder..."
rm -rf "$OUT" "$FTP" "$TGZ"
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
mkdir -p "$OUT/generated"
cp -a "$ROOT/backend/generated/client" "$OUT/generated/client"
cp -r "$ROOT/backend/prisma" "$OUT/prisma"
cp "$ROOT/backend/server.js" "$OUT/server.js"

if [ ! -f "$OUT/dist/server.js" ]; then
  echo "❌ deploy bundle missing dist/server.js"
  exit 1
fi

ROOT="$ROOT" OUT="$OUT" node <<'NODE'
const fs = require('fs');
const path = require('path');
const root = process.env.ROOT;
const out = process.env.OUT;
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'backend/package.json'), 'utf8'));
const { devDependencies, prisma: _p, postinstall, ...rest } = pkg;
const deps = { ...rest.dependencies };
// Keep prisma CLI for migrate deploy on server (must stay on v5, not npx latest).
deps.prisma = '5.22.0';
const deploy = {
  ...rest,
  dependencies: deps,
  scripts: {
    start: 'node server.js',
    'db:deploy': 'prisma migrate deploy',
  },
};
fs.writeFileSync(path.join(out, 'package.json'), JSON.stringify(deploy, null, 2));
NODE

find "$OUT/generated/client" -type f \( -name '*.ts' -o -name '*.map' \) -delete 2>/dev/null || true

cat > "$OUT/EXTRACT.txt" <<'EOF'
Run in cPanel Terminal after FTP upload:

  cd ~/santim.lunafh.com/backend
  tar xzf santim-backend.tgz
  npm install --omit=dev
  npm run db:deploy
  # seed (optional): run from your PC with pnpm db:seed, or: npx prisma@5.22.0 db seed

cPanel → Node.js app → startup file: server.js → Restart
EOF

cp "$ROOT/scripts/cpanel/extract-backend.sh" "$OUT/extract-backend.sh"
chmod +x "$OUT/extract-backend.sh"

echo "📦 Creating santim-backend.tgz..."
mkdir -p "$FTP"
tar czf "$TGZ" -C "$OUT" .
cp "$TGZ" "$FTP/santim-backend.tgz"

echo "✅ Backend tarball ready"
echo "   deploy/santim-backend.tgz ($(du -h "$TGZ" | cut -f1))"
echo "   Contains dist/server.js:"
tar tzf "$TGZ" | grep 'dist/server.js' || exit 1
