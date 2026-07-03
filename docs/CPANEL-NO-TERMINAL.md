# Fix backend on cPanel — no Terminal needed

**Important:** Do **not** run `prisma generate` on cPanel. It uses WebAssembly and runs **out of memory** on shared hosting. The Prisma client must be **pre-built by GitHub Actions** and uploaded via FTP.

---

## Method A — GitHub deploy (recommended)

### Step 1 — Push to `main`

GitHub Actions builds the backend on Linux (with plenty of RAM), runs `prisma generate`, and FTP-uploads the full bundle including `node_modules/.prisma/client`.

### Step 2 — Configure cPanel Node.js app

1. **Setup Node.js App** → open your backend app
2. Set **Application startup file** → **`boot.js`**
3. Add environment variable:

| Name | Value |
|------|-------|
| `SKIP_PRISMA_GENERATE` | `1` |
| `DATABASE_URL` | your Neon connection string |
| `JWT_SECRET` | your secret |
| `NODE_ENV` | `production` |
| `CORS_ORIGINS` | `https://santim.lunafh.com` (your frontend URL) |

4. Click **Save** → **Restart**

### Step 3 — Do NOT click "Run NPM Install"

That button tries to run Prisma on the server and will fail with **Out of memory**. The FTP deploy already includes everything.

### Step 4 — Test

```
https://YOUR-API-DOMAIN/health
```

---

## Method B — File Manager only (manual upload)

If GitHub deploy is not set up yet:

1. On your PC, ask someone with a dev machine to run:
   ```bash
   ./scripts/cpanel/prepare-backend.sh
   ```
2. Zip the `deploy/backend/` folder (must include `node_modules/`)
3. cPanel → **File Manager** → `santim.lunafh.com/backend/`
4. Upload and extract the zip (overwrite existing files)
5. Set startup file → **`boot.js`**, env `SKIP_PRISMA_GENERATE=1`, **Restart**

---

## cPanel settings checklist

| Setting | Value |
|---------|-------|
| Application startup file | **`boot.js`** |
| `SKIP_PRISMA_GENERATE` | **`1`** |
| `DATABASE_URL` | Neon URL |
| Run NPM Install | **Never** (causes OOM) |
| Cron with prisma generate | **Never** (causes OOM) |

---

## Still failing?

**"Prisma client not found"**  
→ `node_modules/.prisma/client` was not uploaded. Redeploy from GitHub or upload the full `deploy/backend` zip including `node_modules`.

**"Out of memory" / WebAssembly**  
→ Something is still running `prisma generate`. Remove it from the start command. Use `boot.js`, not `npm start` with generate. Set `SKIP_PRISMA_GENERATE=1`.

**CategoryKind export error**  
→ Same root cause — client not generated. Redeploy with full `node_modules`.

**Database migrations**  
→ Run from your local PC (not cPanel):
```bash
cd backend
pnpm db:deploy
```
Uses your Neon `DATABASE_URL` — no server terminal needed.
