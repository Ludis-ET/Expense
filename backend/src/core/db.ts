import { PrismaClient } from '@prisma/client';
import { env } from '../config/env.js';

// Single shared Prisma client for the process.
export const prisma = new PrismaClient({
  log: env.NODE_ENV === 'development' ? ['warn', 'error'] : ['error'],
});

export async function disconnectDb(): Promise<void> {
  await prisma.$disconnect();
}
