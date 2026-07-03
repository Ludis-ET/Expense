/**
 * Skips prisma generate on cPanel (SKIP_PRISMA_GENERATE=1) or when client
 * is already bundled. Prisma CLI uses WebAssembly and OOMs on shared hosting.
 */
import { execSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const clientDir = join(root, 'node_modules', '.prisma', 'client');

function clientExists() {
  return (
    existsSync(join(clientDir, 'default.js')) ||
    existsSync(join(clientDir, 'index.js'))
  );
}

if (process.env.SKIP_PRISMA_GENERATE === '1') {
  if (!clientExists()) {
    console.warn('⚠️  SKIP_PRISMA_GENERATE=1 but no pre-built Prisma client found.');
  }
  process.exit(0);
}

if (clientExists()) {
  process.exit(0);
}

execSync('prisma generate', { cwd: root, stdio: 'inherit' });
