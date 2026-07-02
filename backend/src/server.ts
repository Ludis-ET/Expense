import { createApp } from './app.js';
import { env } from './config/env.js';
import { logger } from './core/logger.js';
import { disconnectDb } from './core/db.js';

const app = createApp();

const server = app.listen(env.PORT, () => {
  logger.info(`Research-tracker API listening on http://localhost:${env.PORT} (${env.NODE_ENV})`);
});

async function shutdown(signal: string) {
  logger.info(`${signal} received, shutting down gracefully`);
  server.close(async () => {
    await disconnectDb();
    process.exit(0);
  });
  // Force-exit if connections don't drain in time.
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));
