# Deploy Santim to cPanel (lunafh.com — path-based + FTP CI/CD)

This guide walks you through hosting **Santim** on cPanel at **santim.lunafh.com**, with the API under `/backend` and the Next.js app under `/frontend`, plus automatic deployments from GitHub Actions over FTP.

| URL | App | Server folder |
| --- | --- | --- |
| `https://santim.lunafh.com/frontend` | Frontend (Next.js) | `/home/lunafhin/santim.lunafh.com/frontend` |
| `https://santim.lunafh.com/backend` | Backend (Express API) | `/home/lunafhin/santim.lunafh.com/backend` |

Both apps live under one domain folder — no separate `api.*` subdomain.

---

## What you need before starting

1. **cPanel hosting** with **Node.js Selector** (Setup Node.js App) — Node **20+** required.
2. **santim.lunafh.com** added in cPanel (subdomain or addon domain).
3. **PostgreSQL** on cPanel (see [Part 2.5](#part-25--create-postgresql-database-in-cpanel)).
4. This repo pushed to GitHub on the `main` branch.
5. **FTP access** — account `ludis@lunafh.com` scoped to `/home/lunafhin/santim.lunafh.com`.

---

## Part 1 — Domain and folder layout

### 1.1 Subdomain / document root

In cPanel → **Domains** or **Subdomains**, confirm **santim.lunafh.com** exists with document root:

```
/home/lunafhin/santim.lunafh.com
```

### 1.2 Create backend and frontend folders

In **File Manager** (or via FTP after first deploy), you need two subfolders:

```
/home/lunafhin/santim.lunafh.com/
├── backend/     ← Express API (FTP + Node.js app)
└── frontend/    ← Next.js app (FTP + Node.js app)
```

GitHub Actions uploads build artifacts into these paths. You do **not** need separate `api.santim.lunafh.com` — the API is served at **`/backend`**.

---

## Part 2 — FTP account

### Your FTP account (lunafh.com)

| Setting | Value |
| --- | --- |
| **Host (`CPANEL_FTP_HOST`)** | **Server hostname from cPanel** — see below (NOT `santim.lunafh.com`) |
| **Username** | `ludis@lunafh.com` |
| **Password** | The password you generated in cPanel (never commit this) |
| **Port** | `21` (FTP) |

#### How to find the correct FTP host

**Recommended if hostname fails:** use the server **IP address**.

1. cPanel home → right sidebar → **General Information**
2. Copy **Shared IP Address** (e.g. `198.51.100.42`)
3. GitHub → **Settings** → **Secrets** → edit `CPANEL_FTP_HOST` → paste **only the IP**

**Or** use the FTP hostname:

1. cPanel → **FTP Accounts**
2. Find `ludis@lunafh.com` → **Configure FTP Client**
3. Copy **FTP Server** (e.g. `ftp.lunafh.com` or `server123.lunafh.com`)
4. Paste into `CPANEL_FTP_HOST` — **hostname or IP only**:
   - ✅ `198.51.100.42`
   - ✅ `ftp.lunafh.com`
   - ❌ `ftp://ftp.lunafh.com`
   - ❌ `santim.lunafh.com`
   - ❌ `ludis@lunafh.com`

Because this FTP user is rooted at `santim.lunafh.com`, GitHub secrets use **relative** paths:

| Secret | Value |
| --- | --- |
| `CPANEL_FTP_BACKEND_PATH` | `/backend/` |
| `CPANEL_FTP_FRONTEND_PATH` | `/frontend/` |

If deploy fails with “directory not found”, open **FTP Accounts** → **Configure FTP Client** on the site folder and confirm the exact remote path your host expects.

---

## Part 2.5 — Create PostgreSQL database in cPanel

Santim uses **PostgreSQL** via Prisma (`DATABASE_URL`).

### Your database (already created)

| Item | Full name |
| --- | --- |
| cPanel user | `lunafhin` |
| Database user | `lunafhin_ludis` |
| Database name | `lunafhin_santim` |
| Password | *(the one you generated — store only in cPanel)* |

### Build the `DATABASE_URL`

Because the API runs **on the same server** as PostgreSQL, use **localhost**:

```
postgresql://lunafhin_ludis:YOUR_PASSWORD@localhost:5432/lunafhin_santim
```

**Password special characters:** URL-encode `@`, `#`, `/`, `%` in the connection string:

| Character | Encoded |
| --- | --- |
| `@` | `%40` |
| `#` | `%23` |
| `/` | `%2F` |
| `%` | `%25` |

If Prisma fails with an SSL error on localhost, append `?sslmode=disable`.

### Set `DATABASE_URL` on the backend Node.js app

cPanel → **Setup Node.js App** → backend app → **Environment variables** → add `DATABASE_URL`. Do **not** put this in git or GitHub.

### Run migrations (after first deploy)

```bash
cd ~/santim.lunafh.com/backend
npx prisma migrate deploy
```

Optional demo data: `npx prisma db seed`

Then **Restart** the backend Node.js app.

### Verify

```
https://santim.lunafh.com/backend/health
```

---

## Part 3 — Set up the backend Node.js app

cPanel → **Setup Node.js App** → **Create Application**:

| Field | Value |
| --- | --- |
| Node.js version | **20.x** (or latest ≥ 20) |
| Application mode | **Production** |
| Application root | `santim.lunafh.com/backend` |
| Application URL | `santim.lunafh.com/backend` |
| Application startup file | `dist/server.js` |

### Backend environment variables

| Variable | Value |
| --- | --- |
| `NODE_ENV` | `production` |
| `PORT` | Leave blank — cPanel injects `PORT` |
| `DATABASE_URL` | `postgresql://lunafhin_ludis:...@localhost:5432/lunafhin_santim` |
| `JWT_SECRET` | Long random string (≥ 16 chars) |
| `CORS_ORIGINS` | `https://santim.lunafh.com` |
| `APP_URL` | `https://santim.lunafh.com/frontend` |
| `LOG_LEVEL` | `info` |

Generate a JWT secret locally:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"
```

Click **Save**, deploy via FTP, run migrations, then **Restart**.

### Verify the API

```
https://santim.lunafh.com/backend/health
```

---

## Part 4 — Set up the frontend Node.js app

**Setup Node.js App** → **Create Application**:

| Field | Value |
| --- | --- |
| Node.js version | **20.x** |
| Application mode | **Production** |
| Application root | `santim.lunafh.com/frontend` |
| Application URL | `santim.lunafh.com/frontend` |
| Application startup file | `server.js` |

### Frontend build-time settings (GitHub Variables)

The production bundle is built in GitHub Actions with:

| Variable | Value |
| --- | --- |
| `CPANEL_BACKEND_URL` | `https://santim.lunafh.com/backend` |
| `CPANEL_FRONTEND_BASE_PATH` | `/frontend` |
| `CPANEL_API_BASE_PATH` | `/backend/api/v1` |

- `NEXT_BASE_PATH=/frontend` — pages and assets load under `/frontend`.
- `NEXT_PUBLIC_API_BASE=/backend/api/v1` — browser calls the API on the same domain (no separate subdomain).

Optional server-side vars on cPanel:

| Variable | Value |
| --- | --- |
| `NODE_ENV` | `production` |
| `PORT` | (leave blank) |

Click **Save**, then **Restart** after each deploy.

### Enable HTTPS (SSL)

cPanel → **SSL/TLS Status** → run **AutoSSL** for `santim.lunafh.com`.

---

## Part 5 — Configure GitHub Actions secrets & variables

GitHub repo → **Settings** → **Secrets and variables** → **Actions**.

### 5.1 Repository secrets

| Secret name | Value |
| --- | --- |
| `CPANEL_FTP_HOST` | `203.0.113.10` (**Shared IP** from cPanel — not `santim.lunafh.com`) |
| `CPANEL_FTP_USERNAME` | `ludis@lunafh.com` |
| `CPANEL_FTP_PASSWORD` | Your generated FTP password |
| `CPANEL_FTP_PROTOCOL` | `sftp` (default — most cPanel hosts; use `ftp` or `ftps` if needed) |
| `CPANEL_FTP_PORT` | `22` for SFTP, `21` for FTP (optional — auto-selected) |
| `CPANEL_FTP_BACKEND_PATH` | `/backend/` |
| `CPANEL_FTP_FRONTEND_PATH` | `/frontend/` |

### 5.2 Repository variables

| Variable name | Value |
| --- | --- |
| `CPANEL_BACKEND_URL` | `https://santim.lunafh.com/backend` |
| `CPANEL_FRONTEND_BASE_PATH` | `/frontend` |
| `CPANEL_API_BASE_PATH` | `/backend/api/v1` |

### 5.3 Optional — GitHub Environment

The workflow uses a `production` environment. To add approval gates:

1. **Settings** → **Environments** → **New environment** → name it `production`.
2. Add required reviewers or deployment branches.

---

## Part 6 — How CI/CD works

Workflow: [`.github/workflows/cpanel-deploy.yml`](../.github/workflows/cpanel-deploy.yml)

### On every push / pull request to `main`

| Step | What happens |
| --- | --- |
| CI | Lint, typecheck, test, smoke build |

### On push to `main` (or manual trigger)

| Step | What happens |
| --- | --- |
| Build backend | TypeScript + Prisma client + prod deps → `deploy/backend/` |
| Build frontend | Next.js standalone with `CPANEL_BACKEND_URL`, base path, and API path |
| FTP upload | Backend → `/backend/`, frontend → `/frontend/` |
| Summary | Post-deploy checklist in the Actions log |

### Manual deploy

GitHub → **Actions** → **🚀 CI/CD — cPanel FTP Deploy** → **Run workflow** → branch `main`.

### After each deploy

1. cPanel → **Setup Node.js App** → **Restart** both apps.
2. Check Node.js app logs if something fails.

---

## Part 7 — First-time deployment checklist

- [ ] `santim.lunafh.com` document root is `/home/lunafhin/santim.lunafh.com`
- [ ] `backend/` and `frontend/` folders exist (or will be created by FTP deploy)
- [ ] Node.js apps: backend (`dist/server.js`) and frontend (`server.js`) at `/backend` and `/frontend`
- [ ] PostgreSQL: `lunafhin_santim` + user `lunafhin_ludis` — `DATABASE_URL` on backend app
- [ ] `JWT_SECRET`, `CORS_ORIGINS`, `APP_URL` set on backend app
- [ ] SSL enabled for `santim.lunafh.com`
- [ ] All GitHub secrets and variables set (see [Quick reference](#quick-reference--all-github-configuration))
- [ ] Push to `main` or run workflow manually
- [ ] `npx prisma migrate deploy` in `~/santim.lunafh.com/backend` (first time)
- [ ] Restart both Node.js apps
- [ ] Open `https://santim.lunafh.com/frontend` and register / log in

---

## Part 8 — Troubleshooting

### FTP deploy fails — `ENOTFOUND` / "server doesn't seem to exist"

GitHub cannot resolve `CPANEL_FTP_HOST`. **Use your server IP** (most reliable):

1. cPanel → **General Information** → **Shared IP Address**
2. GitHub → **Secrets** → `CPANEL_FTP_HOST` → set to that IP only (e.g. `203.0.113.10`)
3. Re-run the deploy workflow

Do **not** use `santim.lunafh.com` or `ludis@lunafh.com` as the host.

If FTP connects but auth fails, try secret `CPANEL_FTP_PROTOCOL` = `ftps`.

### FTP deploy fails — "Login authentication failed"

- Confirm host, `ludis@lunafh.com`, and password in GitHub secrets.
- Some hosts require the full username format `user@domain.com` (you already use this).

### FTP deploy succeeds but site shows 503 / blank page

- Restart both Node.js apps in cPanel.
- Confirm startup files: backend `dist/server.js`, frontend `server.js`.
- Check **Application URL** matches `santim.lunafh.com/backend` and `santim.lunafh.com/frontend`.

### Frontend loads but API calls fail (CORS / 404)

- `CPANEL_BACKEND_URL` must be `https://santim.lunafh.com/backend` (no trailing slash).
- `CPANEL_API_BASE_PATH` must be `/backend/api/v1`.
- Backend `CORS_ORIGINS` must include `https://santim.lunafh.com`.
- Re-deploy after changing GitHub variables (frontend must rebuild).

### Wrong paths / 404 on pages

- `CPANEL_FRONTEND_BASE_PATH` must be `/frontend`.
- Open the app at `https://santim.lunafh.com/frontend`, not the domain root.

### Database connection errors

- Use `localhost` (not `lunafh.com`) when the API runs on the same server.
- Use full names: `lunafhin_ludis` and `lunafhin_santim`.
- URL-encode special characters in the password.
- Confirm the DB user has ALL PRIVILEGES on the database in **PostgreSQL Databases**.

### `prisma migrate deploy` not found

- Run from `~/santim.lunafh.com/backend`.
- Ensure deploy uploaded the `prisma/` folder (CI does this automatically).

### Build works locally but fails in GitHub Actions

- Check the Actions log for the failing step.
- Ensure `pnpm-lock.yaml` is committed.

---

## Part 9 — Local dry-run (optional)

```bash
# From repo root
pnpm install

# Backend
chmod +x scripts/cpanel/prepare-backend.sh
./scripts/cpanel/prepare-backend.sh
# Output → deploy/backend/

# Frontend (lunafh.com paths)
export BACKEND_URL=https://santim.lunafh.com/backend
export NEXT_BASE_PATH=/frontend
export NEXT_PUBLIC_API_BASE=/backend/api/v1
chmod +x scripts/cpanel/prepare-frontend.sh
./scripts/cpanel/prepare-frontend.sh
# Output → deploy/frontend/
```

Upload those folders with FileZilla to verify FTP paths before enabling GitHub Actions.

---

## Architecture overview

```
┌─────────────────────────────────────────────────────────────┐
│  GitHub (push to main)                                      │
│    └── Actions: lint → test → build → FTP upload            │
└──────────────────────────┬──────────────────────────────────┘
                           │ FTP ludis@lunafh.com
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  cPanel — santim.lunafh.com                                 │
│  /home/lunafhin/santim.lunafh.com/                          │
│                                                             │
│  /frontend/                    /backend/                    │
│  ┌──────────────────┐            ┌──────────────────┐       │
│  │ Next.js          │  browser   │ Express + Prisma │       │
│  │ server.js        │ ─────────▶ │ dist/server.js   │       │
│  │ basePath=/frontend│ /backend/ │                  │       │
│  └──────────────────┘   api/v1  └────────┬─────────┘       │
│                                           │                 │
│                                           ▼                 │
│                                  PostgreSQL (localhost)     │
│                                  lunafhin_santim            │
└─────────────────────────────────────────────────────────────┘
```

The browser loads the UI at `santim.lunafh.com/frontend` and calls `santim.lunafh.com/backend/api/v1` on the same origin.

---

## Quick reference — all GitHub configuration

| Name | Type | Value |
| --- | --- | --- |
| `CPANEL_FTP_HOST` | Secret | cPanel **Shared IP** (e.g. `203.0.113.10`) |
| `CPANEL_FTP_USERNAME` | Secret | `ludis@lunafh.com` |
| `CPANEL_FTP_PASSWORD` | Secret | *(your generated password)* |
| `CPANEL_FTP_PROTOCOL` | Secret | `sftp` (recommended) |
| `CPANEL_FTP_PORT` | Secret | `22` (optional) |
| `CPANEL_FTP_BACKEND_PATH` | Secret | `/backend/` |
| `CPANEL_FTP_FRONTEND_PATH` | Secret | `/frontend/` |
| `CPANEL_BACKEND_URL` | Variable | `https://santim.lunafh.com/backend` |
| `CPANEL_FRONTEND_BASE_PATH` | Variable | `/frontend` |
| `CPANEL_API_BASE_PATH` | Variable | `/backend/api/v1` |

---

## Security reminders

- Never commit FTP passwords, database passwords, or `.env` files to git.
- Use a strong, unique `JWT_SECRET` in production.
- Keep `DATABASE_URL` only in cPanel Node.js app settings.
- Enable AutoSSL / HTTPS on `santim.lunafh.com` before going live.
