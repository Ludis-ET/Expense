import { PrismaClient } from '../generated/client/index.js';
import { randomAvatarId, randomBannerId } from '../src/modules/users/profile-presets.js';

const prisma = new PrismaClient();

async function main() {
  const users = await prisma.user.findMany({ select: { id: true } });
  for (const u of users) {
    await prisma.user.update({
      where: { id: u.id },
      data: { avatarId: randomAvatarId(), bannerId: randomBannerId() },
    });
  }
  console.log(`Randomized avatar/banner for ${users.length} user(s)`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
