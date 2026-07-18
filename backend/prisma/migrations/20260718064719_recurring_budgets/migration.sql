-- CreateEnum
CREATE TYPE "BudgetPeriod" AS ENUM ('WEEKLY', 'MONTHLY', 'QUARTERLY', 'YEARLY');

-- AlterTable
ALTER TABLE "budgets" ADD COLUMN     "endDate" TIMESTAMP(3),
ADD COLUMN     "period" "BudgetPeriod" NOT NULL DEFAULT 'MONTHLY',
ADD COLUMN     "rollover" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "startDate" TIMESTAMP(3);
