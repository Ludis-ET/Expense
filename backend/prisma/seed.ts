import bcrypt from 'bcryptjs';
import { ExpenseStatus, PrismaClient, ProjectStatus, Role, TeamRole } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  const org = await prisma.organization.upsert({
    where: { id: 'seed-org' },
    update: {},
    create: { id: 'seed-org', name: 'Addis Ababa University', country: 'ET' },
  });

  const passwordHash = await bcrypt.hash('password123', 12);

  const admin = await prisma.user.upsert({
    where: { email: 'admin@example.com' },
    update: {},
    create: {
      email: 'admin@example.com',
      name: 'Abebe Bekele',
      passwordHash,
      role: Role.ADMIN,
      locale: 'am',
      orgId: org.id,
    },
  });

  const researcher = await prisma.user.upsert({
    where: { email: 'researcher@example.com' },
    update: {},
    create: {
      email: 'researcher@example.com',
      name: 'Hanna Tesfaye',
      passwordHash,
      role: Role.RESEARCHER,
      orgId: org.id,
    },
  });

  const project = await prisma.project.create({
    data: {
      title: 'Drought-resistant Teff Varieties',
      summary: 'Field trials of drought-tolerant teff across three regions.',
      status: ProjectStatus.ACTIVE,
      currency: 'ETB',
      orgId: org.id,
      leadUserId: admin.id,
      team: {
        create: [
          { userId: admin.id, role: TeamRole.PI },
          { userId: researcher.id, role: TeamRole.COLLABORATOR },
        ],
      },
      budgetItems: {
        create: [
          { category: 'equipment', plannedAmount: 250000, currency: 'ETB' },
          { category: 'travel', plannedAmount: 80000, currency: 'ETB' },
          { category: 'personnel', plannedAmount: 600000, currency: 'ETB' },
        ],
      },
      milestones: {
        create: [
          { description: 'Site selection complete', status: 'DONE' },
          { description: 'First planting season data collected', status: 'IN_PROGRESS', dueDate: daysFromNow(21) },
          { description: 'Mid-term report submitted', status: 'PENDING', dueDate: daysFromNow(60) },
        ],
      },
      publications: {
        create: [
          {
            title: 'Yield stability of teff landraces under water stress',
            journal: 'Journal of Agronomy',
            doi: '10.1000/teff.2025.001',
            authorList: 'Bekele A., Tesfaye H.',
            pubDate: daysFromNow(-90),
            keywords: ['teff', 'drought', 'agronomy'],
            citationCount: 14,
          },
        ],
      },
      datasets: {
        create: [
          { title: 'Rainfall & yield panel 2024', description: 'Three-region panel dataset', format: 'CSV' },
        ],
      },
    },
    include: { budgetItems: true },
  });

  // A couple of expenses against the first budget item to populate the budget rollup.
  const firstBudget = project.budgetItems[0];
  if (firstBudget) {
    await prisma.expense.createMany({
      data: [
        {
          budgetItemId: firstBudget.id,
          userId: researcher.id,
          amount: 45000,
          currency: 'ETB',
          description: 'Soil moisture sensors',
          status: ExpenseStatus.APPROVED,
        },
        {
          budgetItemId: firstBudget.id,
          userId: researcher.id,
          amount: 12000,
          currency: 'ETB',
          description: 'Field tablets',
          status: ExpenseStatus.PENDING,
        },
      ],
    });
  }

  await prisma.idea.createMany({
    data: [
      { userId: admin.id, projectId: project.id, title: 'Add drone-based canopy imaging', priority: 4 },
      { userId: researcher.id, title: 'Mobile data-collection app for field staff', priority: 3 },
      { userId: researcher.id, title: 'Partner with regional ag bureaus', priority: 2 },
    ],
  });

  await prisma.notification.createMany({
    data: [
      { userId: admin.id, type: 'expense', message: 'New expense awaiting approval: Field tablets', link: `/projects/${project.id}` },
      { userId: admin.id, type: 'milestone', message: 'Milestone "First planting season data collected" is due soon' },
    ],
  });

  // eslint-disable-next-line no-console
  console.log(`Seeded org=${org.id}, admin=${admin.email}, project=${project.id}`);
  console.log('Login with admin@example.com / password123');
}

function daysFromNow(days: number): Date {
  return new Date(Date.now() + days * 24 * 60 * 60 * 1000);
}

main()
  .catch((e) => {
    // eslint-disable-next-line no-console
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
