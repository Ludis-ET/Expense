/**
 * cPanel entrypoint — generates Prisma client before starting the API.
 * Set this as the Node.js "Application startup file" in cPanel (not dist/server.js).
 */
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));

function runPrismaGenerate() {
  const prismaCli = join(root, 'node_modules', 'prisma', 'build', 'index.js');
  if (!existsSync(prismaCli)) {
    console.error('');
    console.error('❌ Prisma is not installed in node_modules.');
    console.error('   In cPanel → Setup Node.js App → click "Run NPM Install", then Restart.');
    console.error('');
    process.exit(1);
  }
  console.log('🗄️  Generating Prisma client...');
  execFileSync(process.execPath, [prismaCli, 'generate'], { cwd: root, stdio: 'inherit' });
  console.log('✅ Prisma client ready');
}

runPrismaGenerate();
await import('./dist/server.js');
