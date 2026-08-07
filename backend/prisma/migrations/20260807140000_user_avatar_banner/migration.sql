-- Curated profile look: preset avatar + settings banner (random on signup).
ALTER TABLE "users" ADD COLUMN "avatarId" TEXT NOT NULL DEFAULT 'ember';
ALTER TABLE "users" ADD COLUMN "bannerId" TEXT NOT NULL DEFAULT 'aurora';

-- Drop defaults so new rows must set them explicitly (app always picks at random).
ALTER TABLE "users" ALTER COLUMN "avatarId" DROP DEFAULT;
ALTER TABLE "users" ALTER COLUMN "bannerId" DROP DEFAULT;
