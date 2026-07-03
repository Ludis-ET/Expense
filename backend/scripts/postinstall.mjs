/**
 * Generates Prisma client locally/CI. Skipped on cPanel (SKIP_PRISMA_GENERATE=1).
 */
import { execSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const client = join(root, 'generated/client/index.js');

if (process.env.SKIP_PRISMA_GENERATE === '1') {
  process.exit(0);
}

if (existsSync(client)) {
  process.exit(0);
}

execSync('prisma generate', { cwd: root, stdio: 'inherit' });
