# Deploy Santim on cPanel using Terminal

Use **cPanel Terminal** to clone the repo, install deps, build, and migrate. No FTP upload of `node_modules` needed.

Your site layout (path-based on one domain):

| URL | App |
|-----|-----|
| `https://santim.lunafh.com/frontend` | Next.js |
| `https://santim.lunafh.com/backend` | Express API |

---

## Part 1 — One-time cPanel setup

### 1.1 Enable Terminal

cPanel → search **Terminal** → open it.

### 1.2 Install pnpm (recommended)

```bash
corepack enable
corepack prepare pnpm@10.24.0 --activate
pnpm -v
```

If `corepack` is not available, the deploy scripts fall back to `npm`.

### 1.3 Clone the project

```bash
cd ~
git clone https://github.com/YOUR_USER/Expense.git
cd Expense
```

If you already have files under `santim.lunafh.com`, you can clone there instead:

```bash
cd ~/santim.lunafh.com
git clone https://github.com/YOUR_USER/Expense.git repo
cd repo
```

### 1.4 Create Node.js apps

cPanel → **Setup Node.js App** → create **two** apps:

**Backend API**

| Field | Value |
|-------|--------|
| Node.js version | 20+ |
| Application root | `Expense/backend` (path to your clone) |
| Application URL | map to `/backend` or use subdomain |
| Startup file | **`dist/server.js`** |

**Frontend**

| Field | Value |
|-------|--------|
| Node.js version | 20+ |
| Application root | `Expense/frontend/run` (created by deploy script) |
| Application URL | map to `/frontend` |
| Startup file | **`server.js`** |

---

## Part 2 — Backend environment

### 2.1 Create `.env` on the server

In Terminal:

```bash
cd ~/Expense/backend
cp .env.example .env
nano .env
```

Set these (use your real Neon URL and secrets):

```env
NODE_ENV=production
PORT=4000

DATABASE_URL=postgresql://neondb_owner:PASSWORD@ep-....neon.tech/neondb?sslmode=require

JWT_SECRET=your-long-random-secret
CORS_ORIGINS=https://santim.lunafh.com
APP_URL=https://santim.lunafh.com/frontend

LOG_LEVEL=info
```

Save (`Ctrl+O`, Enter, `Ctrl+X` in nano).

### 2.2 Also set env vars in cPanel Node.js app (backend)

In **Setup Node.js App** → backend app → **Environment variables**, add the same `DATABASE_URL`, `JWT_SECRET`, `CORS_ORIGINS`, `APP_URL`, `NODE_ENV=production`.

cPanel injects `PORT` automatically — leave it blank or unset.

---

## Part 3 — Deploy backend (Terminal)

From the repo root:

```bash
cd ~/Expense
bash scripts/cpanel/deploy-on-server.sh
```

This runs:

1. `pnpm install` (or `npm install`)
2. `prisma generate` + TypeScript build
3. `prisma migrate deploy` (applies migrations to Neon)

Then in cPanel → **Setup Node.js App** → backend → **Restart**.

### Test backend

```bash
curl https://santim.lunafh.com/backend/health
```

Expected: `{"status":"ok",...}`

---

## Part 4 — Deploy frontend (Terminal)

```bash
cd ~/Expense
export BACKEND_URL=https://santim.lunafh.com/backend
export NEXT_BASE_PATH=/frontend
bash scripts/cpanel/deploy-frontend-on-server.sh
```

This builds Next.js and assembles `frontend/run/` with `server.js`.

Point the **frontend** Node.js app root to `Expense/frontend/run`, startup **`server.js`**, then **Restart**.

Open: `https://santim.lunafh.com/frontend`

---

## Part 5 — Seed demo data (optional)

```bash
cd ~/Expense/backend
pnpm db:seed
# or: npm run db:seed
```

Login: `demo@example.com` / `password123`

---

## Updating after you push to GitHub

Every time you change code:

```bash
cd ~/Expense
git pull origin main
bash scripts/cpanel/deploy-on-server.sh
bash scripts/cpanel/deploy-frontend-on-server.sh
```

Restart both Node.js apps in cPanel.

---

## Troubleshooting

### `prisma generate` runs out of memory

Try:

```bash
export NODE_OPTIONS="--max-old-space-size=512"
bash scripts/cpanel/deploy-on-server.sh
```

If it still fails, build on your PC and pull only built artifacts:

```bash
# On your PC: commit is not needed — build locally, then rsync/scp dist + generated/client to server
pnpm --filter @santim/backend build
# Upload backend/dist and backend/generated to server via File Manager
```

### `CategoryKind` / Prisma client errors

Run build again — client lives in `backend/generated/client/`:

```bash
cd ~/Expense/backend
npm run build
```

### Database connection failed

- Use Neon **pooled** connection string with `?sslmode=require`
- Check `DATABASE_URL` in both `.env` and cPanel Node.js env vars

### Frontend API calls fail

- Rebuild frontend with correct `BACKEND_URL`
- Backend `CORS_ORIGINS` must include `https://santim.lunafh.com`

---

## Quick command cheat sheet

```bash
cd ~/Expense && git pull

# Backend
bash scripts/cpanel/deploy-on-server.sh

# Frontend
export BACKEND_URL=https://santim.lunafh.com/backend
export NEXT_BASE_PATH=/frontend
bash scripts/cpanel/deploy-frontend-on-server.sh

# Restart both apps in cPanel UI
```
