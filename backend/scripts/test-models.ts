import { PrismaClient } from '@prisma/client';
import { decryptSecret } from '../src/core/crypto.js';
import dotenv from 'dotenv';
dotenv.config();

const prisma = new PrismaClient();

async function main() {
  const settings = await prisma.aiSetting.findFirst();
  if (!settings) {
    console.log('No AI settings found in database.');
    return;
  }

  const providers = settings.providers as { id: string; keyEnc?: string | null }[];
  const google = providers.find(p => p.id === 'google');
  if (!google || !google.keyEnc) {
    console.log('No Google provider with an API key found in the database.');
    return;
  }

  const apiKey = decryptSecret(google.keyEnc);
  console.log('Successfully decrypted API key. Fetching available models...');

  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models?key=${encodeURIComponent(apiKey)}`);
  
  if (!response.ok) {
    const errorText = await response.text();
    console.error(`Error fetching models: ${response.status} ${response.statusText}`, errorText);
    return;
  }

  const data = await response.json();
  const geminiModels = (data as { models: { name: string; displayName: string }[] }).models.filter((m) => m.name.includes('gemini'));
  console.log('\nAvailable Gemini Models:');
  for (const model of geminiModels) {
    console.log(`- ${model.name} (${model.displayName})`);
  }
}

main().catch(console.error).finally(() => prisma.$disconnect());
