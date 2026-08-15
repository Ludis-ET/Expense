import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(4000),
  CORS_ORIGINS: z
    .string()
    .default('')
    .transform((s) => s.split(',').map((o) => o.trim()).filter(Boolean)),
  DATABASE_URL: z.string().min(1, 'DATABASE_URL is required'),
  JWT_SECRET: z.string().min(16, 'JWT_SECRET must be at least 16 characters'),
  JWT_EXPIRES_IN: z.string().default('15m'),
  JWT_REFRESH_EXPIRES_IN: z.string().default('7d'),
  // Optional dedicated key for encrypting stored AI provider keys. Falls back to JWT_SECRET.
  AI_ENCRYPTION_KEY: z.string().min(16).optional(),
  // Base URL used when building shareable invite links.
  APP_URL: z.string().default('http://localhost:3000'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  // Optional Android OTA: when set, GET /app/android-update advertises a newer APK.
  ANDROID_LATEST_VERSION_CODE: z.preprocess(
    (v) => (v === '' || v === undefined || v === null ? undefined : v),
    z.coerce.number().int().positive().optional(),
  ),
  ANDROID_LATEST_VERSION_NAME: z.string().optional(),
  ANDROID_APK_URL: z.preprocess(
    (v) => (typeof v === 'string' && v.trim() === '' ? undefined : v),
    z.string().url().optional(),
  ),
  ANDROID_CHANGELOG: z.string().default(''),
  ANDROID_FORCE_UPDATE: z
    .string()
    .optional()
    .transform((v) => v === '1' || v?.toLowerCase() === 'true'),
  ANDROID_MIN_VERSION_CODE: z.preprocess(
    (v) => (v === '' || v === undefined || v === null ? undefined : v),
    z.coerce.number().int().positive().optional(),
  ),
});

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  // Fail fast with a readable message instead of crashing deep inside the app.
  const issues = parsed.error.issues.map((i) => `  - ${i.path.join('.')}: ${i.message}`).join('\n');
  console.error(`Invalid environment configuration:\n${issues}`);
  process.exit(1);
}

export const env = parsed.data;
export const isProd = env.NODE_ENV === 'production';
export const isTest = env.NODE_ENV === 'test';

// A production deploy with no origin list used to reflect whatever origin asked,
// with credentials enabled. Refusing to boot is better than either of the two
// alternatives: silently permissive (the old behaviour) or silently blocking
// every browser request, which looks like a bug in the frontend.
if (isProd && env.CORS_ORIGINS.length === 0) {
  console.error(
    'CORS_ORIGINS must list the allowed origins in production, comma-separated.\n' +
      '  e.g. CORS_ORIGINS=https://santim.app,https://www.santim.app',
  );
  process.exit(1);
}
