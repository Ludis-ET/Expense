/**
 * Stages a production-ready FTP payload under backend/.deploy/
 * for cPanel Node.js + GitHub Actions FTP deploys.
 *
 * Uploads only what the server needs to run `npm install` + `npm start`.
 * Never copies .env / secrets.
 */
import {
  cpSync,
  existsSync,
  mkdirSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, '.deploy');

const REQUIRED = [
  { rel: 'dist/server.js', label: 'compiled server entry' },
  { rel: 'package.json', label: 'package manifest' },
  { rel: 'prisma/schema.prisma', label: 'Prisma schema' },
];

// Keep the FTP payload small: do not upload generated/ by default (~tens of MB
 // of Prisma engines). cPanel "Run NPM Install" runs postinstall → prisma generate.
 // Set INCLUDE_GENERATED=1 to ship a prebuilt client (useful if generate fails on host).
const COPY_PATHS = [
  'dist',
  'prisma',
  'scripts',
  ...(process.env.INCLUDE_GENERATED === '1' ? ['generated'] : []),
  'package.json',
  'package-lock.json',
];

function log(step, message) {
  const ts = new Date().toISOString();
  console.log(`[${ts}] [${step}] ${message}`);
}

function fail(message) {
  console.error(`[${new Date().toISOString()}] [ERROR] ${message}`);
  process.exit(1);
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 ** 2) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 ** 3) return `${(bytes / 1024 ** 2).toFixed(2)} MB`;
  return `${(bytes / 1024 ** 3).toFixed(2)} GB`;
}

function walkFiles(dir, files = []) {
  if (!existsSync(dir)) return files;
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    const st = statSync(full);
    if (st.isDirectory()) walkFiles(full, files);
    else files.push(full);
  }
  return files;
}

function dirSize(dir) {
  return walkFiles(dir).reduce((sum, f) => sum + statSync(f).size, 0);
}

log('INIT', 'Preparing cPanel FTP deploy payload');
log('INIT', `Backend root: ${root}`);
log('INIT', `Output directory: ${outDir}`);
log(
  'INIT',
  process.env.INCLUDE_GENERATED === '1'
    ? 'INCLUDE_GENERATED=1 — will copy generated/ Prisma client'
    : 'Skipping generated/ (host will run prisma generate via postinstall)',
);

for (const item of REQUIRED) {
  const full = join(root, item.rel);
  if (!existsSync(full)) {
    fail(`Missing ${item.label} at ${item.rel}. Run "npm run build" first.`);
  }
  log('CHECK', `OK — ${item.label} (${item.rel})`);
}

if (existsSync(outDir)) {
  log('CLEAN', 'Removing previous .deploy directory');
  rmSync(outDir, { recursive: true, force: true });
}
mkdirSync(outDir, { recursive: true });
log('CLEAN', 'Created empty .deploy directory');

for (const rel of COPY_PATHS) {
  const src = join(root, rel);
  if (!existsSync(src)) {
    if (rel === 'generated') {
      log('COPY', `SKIP — ${rel} missing (server postinstall will generate Prisma client)`);
      continue;
    }
    if (rel === 'package-lock.json') {
      log('COPY', `WARN — ${rel} missing; cPanel npm install may resolve versions differently`);
      continue;
    }
    fail(`Required path missing: ${rel}`);
  }

  const dest = join(outDir, rel);
  const st = statSync(src);
  if (st.isDirectory()) {
    cpSync(src, dest, { recursive: true });
    const files = walkFiles(dest).length;
    log('COPY', `DIR  ${rel}/ → ${files} files (${formatBytes(dirSize(dest))})`);
  } else {
    cpSync(src, dest);
    log('COPY', `FILE ${rel} (${formatBytes(st.size)})`);
  }
}

// Marker so operators can see which CI build landed on the server.
const meta = {
  preparedAt: new Date().toISOString(),
  preparedBy: 'backend/scripts/prepare-cpanel-deploy.mjs',
  nodeEngines: '>=20',
  startCommand: 'npm start',
  startupFile: 'dist/server.js',
  notes: [
    'Set environment variables in cPanel Node.js App (never commit .env).',
    'After first FTP upload: Run NPM Install, then Restart in cPanel.',
    'Run database migrations once: npx prisma migrate deploy',
  ],
};

writeFileSync(join(outDir, 'DEPLOY_META.json'), `${JSON.stringify(meta, null, 2)}\n`);
log('META', 'Wrote DEPLOY_META.json');

const allFiles = walkFiles(outDir);
const totalBytes = allFiles.reduce((sum, f) => sum + statSync(f).size, 0);

log('SUMMARY', '────────────────────────────────────────');
log('SUMMARY', `Files staged: ${allFiles.length}`);
log('SUMMARY', `Payload size: ${formatBytes(totalBytes)}`);
log('SUMMARY', 'Top-level contents:');
for (const name of readdirSync(outDir).sort()) {
  const full = join(outDir, name);
  const st = statSync(full);
  if (st.isDirectory()) {
    log('SUMMARY', `  📁 ${name}/ (${walkFiles(full).length} files, ${formatBytes(dirSize(full))})`);
  } else {
    log('SUMMARY', `  📄 ${name} (${formatBytes(st.size)})`);
  }
}

log('SUMMARY', 'Sample paths (first 25):');
for (const f of allFiles.slice(0, 25)) {
  log('SUMMARY', `  - ${relative(outDir, f)}`);
}
if (allFiles.length > 25) {
  log('SUMMARY', `  … and ${allFiles.length - 25} more`);
}

log('DONE', 'Deploy payload ready at backend/.deploy/');
