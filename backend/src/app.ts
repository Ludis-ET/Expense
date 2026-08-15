import express, { type Express } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { pinoHttp } from 'pino-http';
import './core/context.js'; // registers the Express.Request augmentation
import { env, isProd } from './config/env.js';
import { logger } from './core/logger.js';
import { apiRouter } from './routes.js';
import { errorHandler, notFoundHandler } from './core/middleware/error-handler.js';
import { globalLimiter } from './core/middleware/rate-limit.js';

export function createApp(): Express {
  const app = express();

  app.disable('x-powered-by');

  // Behind Render's proxy every request otherwise reports the proxy's address,
  // which would make the IP-keyed limiters treat all users as one client.
  app.set('trust proxy', 1);

  app.use(helmet());
  app.use(
    cors({
      // Fail closed in production. The old fallback reflected *any* origin with
      // credentials enabled whenever CORS_ORIGINS was unset - harmless while
      // auth is a Bearer token, and a full CSRF hole the day it becomes a
      // cookie. Development keeps the permissive default.
      origin: env.CORS_ORIGINS.length > 0 ? env.CORS_ORIGINS : !isProd,
      credentials: true,
    }),
  );
  app.use(express.json({ limit: '1mb' }));
  app.use(pinoHttp({ logger }));

  // Liveness/readiness probe for Kubernetes & load balancers.
  app.get('/health', (_req, res) => res.json({ status: 'ok', uptime: process.uptime() }));

  app.use('/api/v1', globalLimiter, apiRouter);

  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
