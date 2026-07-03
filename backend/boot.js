/**
 * cPanel entrypoint — wires vendor/node_modules then starts the API.
 * Do NOT run `prisma generate` here; it OOMs on shared hosting.
 *
 * cPanel settings:
 *   Application startup file → boot.js
 *   SKIP_PRISMA_GENERATE → 1
 */
import { existsSync, lstatSync, rmSync, symlinkSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const vendorModules = join(root, 'vendor', 'node_modules');
const legacyModules = join(root, 'node_modules');

function prismaClientDir(modulesRoot) {
  return join(modulesRoot, '.prisma', 'client');
}

function hasPrismaClient(modulesRoot) {
  const dir = prismaClientDir(modulesRoot);
  return existsSync(join(dir, 'default.js')) || existsSync(join(dir, 'index.js'));
}

function linkVendorModules() {
  if (!existsSync(vendorModules)) {
    return legacyModules;
  }

  if (existsSync(legacyModules)) {
    try {
      const stat = lstatSync(legacyModules);
      // cPanel often leaves a broken symlink or file named node_modules — replace it.
      if (stat.isSymbolicLink() || !stat.isDirectory()) {
        rmSync(legacyModules, { recursive: true, force: true });
      } else if (hasPrismaClient(legacyModules)) {
        return legacyModules;
      } else {
        rmSync(legacyModules, { recursive: true, force: true });
      }
    } catch {
      rmSync(legacyModules, { recursive: true, force: true });
    }
  }

  if (!existsSync(legacyModules)) {
    symlinkSync(vendorModules, legacyModules, 'dir');
  }

  return legacyModules;
}

const modulesRoot = linkVendorModules();

if (!hasPrismaClient(modulesRoot)) {
  console.error('');
  console.error('❌ Prisma client not found in vendor/node_modules/.prisma/client');
  console.error('');
  console.error('   Fix: redeploy from GitHub Actions (full bundle with vendor/node_modules).');
  console.error('   In File Manager, delete backend/node_modules if it is a broken file/link.');
  console.error('   Do NOT click "Run NPM Install" on cPanel.');
  console.error('');
  process.exit(1);
}

await import('./dist/server.js');
