import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    // Provide a valid config so src/config/env.ts validates without a real .env.
    env: {
      NODE_ENV: 'test',
      DATABASE_URL: 'postgresql://user:pass@localhost:5432/test',
      JWT_SECRET: 'test-secret-at-least-16-chars-long',
      CORS_ORIGINS: '',
    },
  },
});
