/**
 * cPanel entrypoint — starts the API using a pre-built Prisma client.
 * Do NOT run `prisma generate` here; it OOMs on shared hosting.
 *
 * Set as cPanel "Application startup file": boot.js
 * Set env var: SKIP_PRISMA_GENERATE=1
 */
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const clientDir = join(root, 'node_modules', '.prisma', 'client');

const hasClient =
  existsSync(join(clientDir, 'default.js')) ||
  existsSync(join(clientDir, 'index.js'));

if (!hasClient) {
  console.error('');
  console.error('❌ Prisma client not found in node_modules/.prisma/client');
  console.error('');
  console.error('   Fix: redeploy from GitHub Actions (includes pre-built client).');
  console.error('   Do NOT click "Run NPM Install" on cPanel — it cannot generate Prisma.');
  console.error('');
  console.error('   In cPanel → Setup Node.js App, set:');
  console.error('   • Application startup file → boot.js');
  console.error('   • SKIP_PRISMA_GENERATE → 1');
  console.error('');
  process.exit(1);
}

await import('./dist/server.js');
