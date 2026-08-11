/** Generates Prisma client after install when the generated output is missing. */
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const client = join(root, "generated/client/index.js");
const prismaCli = join(root, "node_modules", "prisma", "build", "index.js");

if (process.env.SKIP_PRISMA_GENERATE === "1") {
  process.exit(0);
}

if (existsSync(client)) {
  process.exit(0);
}

if (!existsSync(prismaCli)) {
  console.warn(
    "[postinstall] prisma CLI not found at node_modules/prisma; skipping generate",
  );
  process.exit(0);
}

// Invoke the local CLI directly   bare `prisma` is often missing from PATH
// during npm lifecycle scripts (CI, some cPanel installs).
execFileSync(process.execPath, [prismaCli, "generate"], {
  cwd: root,
  stdio: "inherit",
  env: {
    ...process.env,
    // prisma generate reads the schema datasource URL; a placeholder is enough
    DATABASE_URL:
      process.env.DATABASE_URL ||
      "postgresql://build:build@127.0.0.1:5432/build?schema=public",
  },
});
