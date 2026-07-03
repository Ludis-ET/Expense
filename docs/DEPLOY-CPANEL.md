# Deploy Santim to cPanel (subdomains + FTP CI/CD)

This guide walks you through hosting the **Santim** expense tracker on cPanel using two subdomains — one for the Next.js frontend and one for the Express API — with automatic deployments from GitHub Actions over FTP.

| Subdomain (example)     | App      | cPanel folder (example)              |
| ----------------------- | -------- | ------------------------------------ |
| `app.yourdomain.com`    | Frontend | `/home/you/app.yourdomain.com`       |
| `api.yourdomain.com`    | Backend  | `/home/you/api.yourdomain.com`       |

---

## What you need before starting

1. **cPanel hosting** with **Node.js Selector** (Setup Node.js App) — Node **20+** required.
2. A **domain** added to cPanel (your main domain or a addon domain).
3. A **PostgreSQL database** — use **cPanel PostgreSQL** (see [Part 2.5](#part-25--create-postgresql-database-in-cpanel)) if your host offers it, or an external service like [Neon](https://neon.tech).
4. A **GitHub repository** with this project pushed to the `main` branch.
5. **FTP access** to your cPanel account (host, username, password).

---

## Part 1 — Create subdomains in cPanel

### 1.1 Open Subdomains

1. Log in to **cPanel**.
2. Search for **Subdomains** (under *Domains*).
3. Click **Subdomains**.

### 1.2 Create the API subdomain

| Field        | Value                    |
| ------------ | ------------------------ |
| Subdomain    | `api`                    |
| Domain       | `yourdomain.com`         |
| Document Root| (auto) `api.yourdomain.com` |

Click **Create**. Note the full path, e.g.:

```
/home/yourcpaneluser/api.yourdomain.com
```

This is your **backend FTP path** (`CPANEL_FTP_BACKEND_PATH`).

### 1.3 Create the app subdomain

Repeat with:

| Field        | Value                    |
| ------------ | ------------------------ |
| Subdomain    | `app`                    |
| Domain       | `yourdomain.com`         |
| Document Root| (auto) `app.yourdomain.com` |

Note the path, e.g.:

```
/home/yourcpaneluser/app.yourdomain.com
```

This is your **frontend FTP path** (`CPANEL_FTP_FRONTEND_PATH`).

---

## Part 2 — FTP account (or use main account)

### Option A — Use your main cPanel FTP account

Your FTP credentials are usually:

| Setting  | Where to find it                                      |
| -------- | ----------------------------------------------------- |
| **Host** | Your server hostname, e.g. `ftp.yourdomain.com` or the server IP |
| **Username** | Your cPanel username                              |
| **Password** | Your cPanel password                              |
| **Port** | `21` (FTP) or `22` (SFTP if your host supports it)  |

In cPanel → **FTP Accounts**, the **Special FTP Accounts** section shows the main account.

### Option B — Create a dedicated FTP user (recommended)

1. cPanel → **FTP Accounts** → **Add FTP Account**.
2. **Login**: e.g. `deploy`
3. **Password**: generate a strong password.
4. **Directory**: `/` (root) so the user can write to both subdomain folders  
   — or restrict to `/home/you/` if your host allows it.
5. Click **Create FTP Account**.

FTP host is still usually `ftp.yourdomain.com` (not the FTP username).

---

## Part 2.5 — Create PostgreSQL database in cPanel

Santim uses **PostgreSQL** via Prisma (`DATABASE_URL`). If your cPanel has PostgreSQL, you can keep everything on the same server — no Neon account needed.

### Check that PostgreSQL is available

1. Log in to **cPanel**.
2. Search for **PostgreSQL** or **PostgreSQL Databases**.
3. If you only see **MySQL** / **MariaDB** and no PostgreSQL tools, your plan may not include it — use [Neon](https://neon.tech) instead (see troubleshooting below).

Common cPanel icons: **PostgreSQL Databases**, **phpPgAdmin**, or **Remote PostgreSQL**.

### Step 1 — Create the database

1. Open **PostgreSQL Databases**.
2. Under **Create New Database**, enter a name, e.g. `santim`.
3. Click **Create Database**.

cPanel prefixes names with your username. If your cPanel user is `johndoe`, the real database name becomes:

```
johndoe_santim
```

Write down the **full** name shown after creation.

### Step 2 — Create a database user

1. Scroll to **PostgreSQL Users** → **Add New User**.
2. Username: e.g. `santim` → full name becomes `johndoe_santim`.
3. Password: use **Generate Password** (save it somewhere safe).
4. Click **Create User**.

### Step 3 — Grant the user access to the database

1. Scroll to **Add User To Database**.
2. Select the user (`johndoe_santim`) and database (`johndoe_santim`).
3. Click **Submit** / **Add**.
4. Grant **ALL PRIVILEGES** if asked.

### Step 4 — Build the `DATABASE_URL`

Because your Node.js API runs **on the same server** as PostgreSQL, connect via **localhost** (not your domain name).

Standard format:

```
postgresql://FULL_USER:FULL_PASSWORD@localhost:5432/FULL_DATABASE_NAME
```

**Example** (replace with your real values):

```
postgresql://johndoe_santim:MyStr0ngP@ss@localhost:5432/johndoe_santim
```

**Password special characters:** if the password contains `@`, `#`, `/`, or `%`, URL-encode them in the connection string:

| Character | Encoded |
| --------- | ------- |
| `@`       | `%40`   |
| `#`       | `%23`   |
| `/`       | `%2F`   |
| `%`       | `%25`   |

Example: password `P@ss#1` → `P%40ss%231`

**SSL on localhost:** most cPanel PostgreSQL instances do **not** require SSL for local connections. Do **not** add `?sslmode=require` unless your host documentation says so. If Prisma fails with an SSL error, try:

```
postgresql://johndoe_santim:password@localhost:5432/johndoe_santim?sslmode=disable
```

**Port:** default is `5432`. Some hosts use a different port — check cPanel connection details or ask support.

### Step 5 — Set `DATABASE_URL` on the backend Node.js app

1. cPanel → **Setup Node.js App** → open your **API** application (`api.yourdomain.com`).
2. Under **Environment variables**, add:

| Variable       | Value                                      |
| -------------- | ------------------------------------------ |
| `DATABASE_URL` | Your full connection string from Step 4    |

3. Click **Save**.

Do **not** put this in git or in GitHub secrets unless you use a separate secret for DB — it lives only in cPanel.

### Step 6 — Run migrations (after first deploy)

After FTP deploy uploads the backend files:

```bash
cd ~/api.yourdomain.com
npx prisma migrate deploy
```

Optional demo data:

```bash
npx prisma db seed
```

Then **Restart** the API Node.js app in cPanel.

### Step 7 — Verify the connection

```bash
cd ~/api.yourdomain.com
npx prisma db execute --stdin <<< "SELECT 1;"
```

Or open **phpPgAdmin** in cPanel, log in with your DB user, and confirm tables exist after migration.

Test the API:

```
https://api.yourdomain.com/health
```

### cPanel PostgreSQL vs Neon

| | cPanel PostgreSQL | Neon (external) |
| --- | --- | --- |
| **Where data lives** | Same server as your app | Cloud (separate) |
| **Connection host** | `localhost` | `ep-xxx.neon.tech` |
| **SSL** | Usually not needed locally | `?sslmode=require` |
| **Best for** | Host includes Postgres | Host is MySQL-only or you want managed backups |

Both work with Santim — only `DATABASE_URL` changes.

---

## Part 3 — Set up the backend Node.js app

### 3.1 Open Node.js Selector

cPanel → search **Setup Node.js App** (or **Application Manager**).

### 3.2 Create the API application

Click **Create Application** and fill in:

| Field                 | Value                                      |
| --------------------- | ------------------------------------------ |
| Node.js version       | **20.x** (or latest available ≥ 20)        |
| Application mode      | **Production**                             |
| Application root      | `api.yourdomain.com`                       |
| Application URL       | `api.yourdomain.com`                       |
| Application startup file | `dist/server.js`                       |

Click **Create**.

### 3.3 Backend environment variables

In the same Node.js app screen, add **Environment variables**:

| Variable            | Example value                                      |
| ------------------- | -------------------------------------------------- |
| `NODE_ENV`          | `production`                                       |
| `PORT`              | Leave blank — cPanel injects `PORT` automatically  |
| `DATABASE_URL`      | `postgresql://johndoe_santim:pass@localhost:5432/johndoe_santim` (see [Part 2.5](#part-25--create-postgresql-database-in-cpanel)) |
| `JWT_SECRET`        | Long random string (≥ 16 chars)                    |
| `CORS_ORIGINS`      | `https://app.yourdomain.com`                       |
| `APP_URL`           | `https://app.yourdomain.com`                       |
| `LOG_LEVEL`         | `info`                                             |

Generate a JWT secret locally:

```bash
node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"
```

Click **Save**.

### 3.4 Run database migrations (first time only)

After the first FTP deploy uploads the backend files:

1. cPanel → **Terminal** (or SSH into the server).
2. Run:

```bash
cd ~/api.yourdomain.com
npx prisma migrate deploy
```

Optional — seed demo data:

```bash
npx prisma db seed
```

3. Back in **Setup Node.js App**, click **Restart** on the API app.

### 3.5 Verify the API

Open in a browser or curl:

```
https://api.yourdomain.com/health
```

---

## Part 4 — Set up the frontend Node.js app

### 4.1 Create the frontend application

Again in **Setup Node.js App** → **Create Application**:

| Field                 | Value                                      |
| --------------------- | ------------------------------------------ |
| Node.js version       | **20.x**                                   |
| Application mode      | **Production**                             |
| Application root      | `app.yourdomain.com`                       |
| Application URL       | `app.yourdomain.com`                       |
| Application startup file | `server.js`                           |

### 4.2 Frontend environment variables

The standalone Next.js bundle bakes in the API proxy URL at **build time** via `BACKEND_URL` in GitHub Actions. You typically do **not** need `BACKEND_URL` on the server unless you rebuild locally.

Optional server-side vars:

| Variable   | Value        |
| ---------- | ------------ |
| `NODE_ENV` | `production` |
| `PORT`     | (leave blank — cPanel sets it) |

Click **Save**, then **Restart** after each deploy.

### 4.3 Enable HTTPS (SSL)

cPanel → **SSL/TLS Status** → run **AutoSSL** for both subdomains so the app loads over `https://`.

---

## Part 5 — Configure GitHub Actions secrets & variables

Go to your GitHub repo → **Settings** → **Secrets and variables** → **Actions**.

### 5.1 Repository secrets

Click **New repository secret** for each:

| Secret name                   | Value (example)                              |
| ----------------------------- | -------------------------------------------- |
| `CPANEL_FTP_HOST`             | `ftp.yourdomain.com`                         |
| `CPANEL_FTP_USERNAME`         | `yourcpaneluser` or `deploy@yourdomain.com`  |
| `CPANEL_FTP_PASSWORD`         | Your FTP password                            |
| `CPANEL_FTP_PORT`             | `21` (optional — defaults to 21)             |
| `CPANEL_FTP_BACKEND_PATH`       | `/api.yourdomain.com/`                       |
| `CPANEL_FTP_FRONTEND_PATH`      | `/app.yourdomain.com/`                       |

**FTP path notes:**

- Paths are relative to the FTP user's home directory.
- For the main cPanel FTP user, use `/api.yourdomain.com/` and `/app.yourdomain.com/` (leading and trailing slashes help the deploy action).
- If deploy fails with "directory not found", open **FTP Accounts** → **Configure FTP Client** on a subdomain folder to see the exact remote path your host expects.

### 5.2 Repository variables

Go to the **Variables** tab:

| Variable name          | Value (example)                    |
| ---------------------- | ---------------------------------- |
| `CPANEL_BACKEND_URL`   | `https://api.yourdomain.com`       |

This URL is used during the frontend build so `/api/*` requests proxy to your live API.

### 5.3 Optional — GitHub Environment

The workflow uses a `production` environment. To add approval gates:

1. **Settings** → **Environments** → **New environment** → name it `production`.
2. Add required reviewers or deployment branches.

---

## Part 6 — How CI/CD works

Workflow file: [`.github/workflows/cpanel-deploy.yml`](../.github/workflows/cpanel-deploy.yml)

### On every push / pull request to `main`

| Step | Emoji log | What happens                          |
| ---- | --------- | ------------------------------------- |
| CI   | 🧪        | Lint, typecheck, test, smoke build    |

### On push to `main` (or manual trigger)

| Step | Emoji log | What happens                                      |
| ---- | --------- | ------------------------------------------------- |
| Build backend  | 🏗️ | TypeScript compile + Prisma client + prod deps |
| Build frontend | 🏗️ | Next.js standalone with your `CPANEL_BACKEND_URL` |
| FTP upload API | 📤 | Upload `deploy/backend/` to API subdomain folder  |
| FTP upload app | 📤 | Upload `deploy/frontend/` to app subdomain folder |
| Summary        | 🎉 | Prints post-deploy checklist in Actions log       |

### Manual deploy

GitHub → **Actions** → **🚀 CI/CD — cPanel FTP Deploy** → **Run workflow** → branch `main` → **Run workflow**.

### After each deploy

1. cPanel → **Setup Node.js App** → **Restart** both apps.
2. Check logs in the Node.js app panel if something fails.

---

## Part 7 — First-time deployment checklist

Use this order:

- [ ] Subdomains `api` and `app` created in cPanel
- [ ] Node.js apps created for both subdomains (startup files: `dist/server.js` and `server.js`)
- [ ] PostgreSQL database created in cPanel ([Part 2.5](#part-25--create-postgresql-database-in-cpanel)) or Neon — `DATABASE_URL` set on backend app
- [ ] `JWT_SECRET` and `CORS_ORIGINS` set on backend app
- [ ] SSL enabled on both subdomains
- [ ] All GitHub secrets and `CPANEL_BACKEND_URL` variable set
- [ ] Push to `main` or run workflow manually
- [ ] Run `npx prisma migrate deploy` in backend folder (first time)
- [ ] Restart both Node.js apps in cPanel
- [ ] Open `https://app.yourdomain.com` and register / log in

---

## Part 8 — Troubleshooting

### FTP deploy fails — "Login authentication failed"

- Double-check host, username, and password in GitHub secrets.
- Some hosts require the full FTP username like `user@domain.com`.
- Try port `21` vs explicit FTPS if your host requires it.

### FTP deploy succeeds but site shows 503 / blank page

- Restart the Node.js app in cPanel.
- Confirm **Application startup file** matches:
  - Backend: `dist/server.js`
  - Frontend: `server.js`
- Open **Node.js app logs** in cPanel for stack traces.

### Frontend loads but API calls fail (CORS / 404)

- Ensure `CPANEL_BACKEND_URL` is `https://api.yourdomain.com` (no trailing slash).
- Ensure backend `CORS_ORIGINS` includes `https://app.yourdomain.com`.
- Re-deploy after changing `CPANEL_BACKEND_URL` (frontend must rebuild).

### Database connection errors

**cPanel PostgreSQL:**

- Use `localhost` as host (not `yourdomain.com`) when the API runs on the same server.
- Use the **full** prefixed names: `cpaneluser_dbname` and `cpaneluser_dbuser`.
- URL-encode special characters in the password (`@` → `%40`, etc.).
- If you see SSL errors, append `?sslmode=disable` to `DATABASE_URL`.
- Confirm the DB user is added to the database with ALL PRIVILEGES in **PostgreSQL Databases**.

**Neon / external PostgreSQL:**

- Use a **pooled** connection string with `?sslmode=require`.
- Confirm `DATABASE_URL` is set in the backend Node.js app env (not only in `.env` on your laptop).

### `prisma migrate deploy` not found

- Run it from the backend deploy folder on the server: `~/api.yourdomain.com`.
- Ensure the deploy uploaded the `prisma/` folder (CI does this automatically).

### Build works locally but fails in GitHub Actions

- Check the Actions log for the failing step (🧪 CI vs 📤 CD).
- Ensure `pnpm-lock.yaml` is committed.

---

## Part 9 — Local dry-run (optional)

Test the deploy bundles on your machine before pushing:

```bash
# From repo root
pnpm install

# Backend package
chmod +x scripts/cpanel/prepare-backend.sh
./scripts/cpanel/prepare-backend.sh
# Output → deploy/backend/

# Frontend package (use your real API URL)
export BACKEND_URL=https://api.yourdomain.com
chmod +x scripts/cpanel/prepare-frontend.sh
./scripts/cpanel/prepare-frontend.sh
# Output → deploy/frontend/
```

Upload those folders manually with FileZilla to verify FTP paths before enabling GitHub Actions.

---

## Architecture overview

```
┌─────────────────────────────────────────────────────────────┐
│  GitHub (push to main)                                      │
│    └── Actions: lint → test → build → FTP upload            │
└──────────────────────────┬──────────────────────────────────┘
                           │ FTP (host / user / password)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  cPanel server                                              │
│                                                             │
│  app.yourdomain.com          api.yourdomain.com             │
│  ┌──────────────────┐        ┌──────────────────┐           │
│  │ Next.js          │ /api/* │ Express + Prisma │           │
│  │ server.js        │───────▶│ dist/server.js   │           │
│  └──────────────────┘ proxy  └────────┬─────────┘           │
│                                        │                    │
│                                        ▼                    │
│                               PostgreSQL (Neon)             │
└─────────────────────────────────────────────────────────────┘
```

The browser only talks to `app.yourdomain.com`. Next.js rewrites `/api/v1/*` to `api.yourdomain.com`, so tokens stay same-origin and CORS stays simple.

---

## Quick reference — all GitHub configuration

| Name                         | Type     | Example                          |
| ---------------------------- | -------- | -------------------------------- |
| `CPANEL_FTP_HOST`            | Secret   | `ftp.yourdomain.com`             |
| `CPANEL_FTP_USERNAME`        | Secret   | `cpaneluser`                     |
| `CPANEL_FTP_PASSWORD`        | Secret   | `••••••••`                       |
| `CPANEL_FTP_PORT`            | Secret   | `21`                             |
| `CPANEL_FTP_BACKEND_PATH`    | Secret   | `/api.yourdomain.com/`           |
| `CPANEL_FTP_FRONTEND_PATH`   | Secret   | `/app.yourdomain.com/`           |
| `CPANEL_BACKEND_URL`         | Variable | `https://api.yourdomain.com`     |

---

## Security reminders

- Never commit FTP passwords or `.env` files to git.
- Use strong, unique `JWT_SECRET` in production.
- Prefer a dedicated FTP account with access limited to deploy folders.
- Enable AutoSSL / HTTPS on both subdomains before going live.
