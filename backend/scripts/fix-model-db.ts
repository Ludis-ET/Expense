import { PrismaClient } from '@prisma/client';
import dotenv from 'dotenv';
dotenv.config();

const prisma = new PrismaClient();

async function main() {
  const settingsList = await prisma.aiSetting.findMany();
  for (const settings of settingsList) {
    const providers = settings.providers as { id: string; model?: string }[];
    let updated = false;
    for (const p of providers) {
      if (p.id === 'google' && p.model === 'gemini-1.5-pro') {
        p.model = 'gemini-3.1-pro-preview';
        updated = true;
      }
    }
    if (updated) {
      await prisma.aiSetting.update({
        where: { id: settings.id },
        data: { providers },
      });
      console.log(`Updated model for user ${settings.userId} to gemini-3.1-pro-preview`);
    }
  }
}

main().catch(console.error).finally(() => prisma.$disconnect());
