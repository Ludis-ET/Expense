# Deploy Santim backend to a cPanel subdomain (FTP + GitHub Actions)

This guide covers **backend only**: build in CI, upload over FTP, run as a cPanel Node.js app on a subdomain.

## Architecture

```
GitHub (push to main)
  → pnpm install + build (monorepo)
  → ensure real npm package-lock.json
  → FTP upload backend/.deploy/
  → cPanel Node.js App (npm install on host)
```

This repo is a **pnpm** monorepo. CI builds with pnpm. The FTP payload still includes an **npm** `package-lock.json` so cPanel’s “Run NPM Install” works without pnpm.

Secrets and `.env` are **never** uploaded. Configure them in cPanel.

---

## 1. Create the subdomain + Node.js app (cPanel)

1. **Subdomains** → create e.g. `api.yourdomain.com`.
2. **Setup Node.js App** (or “Application Manager”):
   - **Node.js version:** 20.x (or newer ≥20)
   - **Application mode:** Production
   - **Application root:** the folder for this subdomain (same path you will use as `FTP_SERVER_DIR`)
   - **Application URL:** `api.yourdomain.com`
   - **Application startup file:** `dist/server.js`
   - **Passenger log file:** optional but recommended
3. Under **Environment variables**, add at least:

| Variable | Example |
|----------|---------|
| `NODE_ENV` | `production` |
| `PORT` | leave default from cPanel / Passenger if provided |
| `DATABASE_URL` | your Postgres URL (`?sslmode=require` if needed) |
| `JWT_SECRET` | long random string (≥16 chars) |
| `JWT_EXPIRES_IN` | `15m` |
| `JWT_REFRESH_EXPIRES_IN` | `7d` |
| `CORS_ORIGINS` | `https://your-frontend.com,https://www.your-frontend.com` |
| `APP_URL` | `https://your-frontend.com` |
| `LOG_LEVEL` | `info` |

Optional: `AI_ENCRYPTION_KEY` (falls back to `JWT_SECRET`).

4. Do **not** put secrets in files under the app directory if you can avoid it. Prefer the cPanel env UI.

---

## 2. Create an FTP account

1. cPanel → **FTP Accounts** → create a user limited to the Node app directory if possible.
2. Note:
   - Host (often `ftp.yourdomain.com` or the server hostname/IP)
   - Username (often `user@domain` or `cpaneluser`)
   - Password
   - Remote path = Application root (must match `FTP_SERVER_DIR`)

Prefer **FTPS** (explicit TLS on port 21). Plain FTP works but is weaker.

---

## 3. GitHub repository secrets

Repo → **Settings** → **Secrets and variables** → **Actions** → **Secrets**:

| Secret | Example | Notes |
|--------|---------|--------|
| `FTP_SERVER` | `ftp.yourdomain.com` or `203.0.113.10` | Hostname or IP only. **No** `ftp://`, **no** path, **no** `https://` |
| `FTP_USERNAME` | `deploy@yourdomain.com` | |
| `FTP_PASSWORD` | `••••••••` | |
| `FTP_SERVER_DIR` | `/home/USER/api.yourdomain.com/` | **Must end with `/`** |

If Actions fails with `getaddrinfo ENOTFOUND`, `FTP_SERVER` does not resolve in DNS — fix the hostname/IP in the secret (check cPanel → FTP Accounts for the correct FTP host).

This action uses **FTP/FTPS**, not SFTP. If your host only offers SFTP, you need a different deploy method.

Optional **Variables** (not secrets):

| Variable | Default | Notes |
|----------|---------|--------|
| `FTP_PROTOCOL` | `ftps` | `ftp`, `ftps`, or `ftps-legacy` |
| `FTP_PORT` | `21` | Host-specific |

---

## 4. Workflow behavior

File: [`.github/workflows/deploy-backend-cpanel.yml`](../.github/workflows/deploy-backend-cpanel.yml)

| Trigger | When |
|---------|------|
| `push` to `main` / `master` | Only if `backend/**` (or the workflow file) changed |
| `workflow_dispatch` | Manual; supports **dry-run** (build only, no FTP) |

Pipeline steps (all logged):

1. Banner + secret presence checks (lengths only)
2. Checkout + Node 24 + pnpm 10
3. `pnpm install --frozen-lockfile` at repo root
4. `pnpm --filter @santim/backend build`
5. Validate / regenerate a real npm `package-lock.json` (isolated from the pnpm workspace)
6. `pnpm prepare:cpanel` → stages `backend/.deploy/`
7. Refuse upload if `.env` / credential files are staged
8. `SamKirkland/FTP-Deploy-Action` with verbose logs
9. Post-deploy checklist printed in the job log

`node_modules`, `.env`, and logs on the server are **excluded** from FTP sync so installs and secrets on the host are preserved.

---

## 5. First deploy checklist

After the first successful Actions run:

1. cPanel → Node.js App → **Run NPM Install**
2. **Restart** the application
3. Apply DB migrations (one-time / when migrations change), via SSH or cPanel terminal:

```bash
cd ~/api.yourdomain.com   # your Application root
npx prisma migrate deploy
```

4. Hit health (adjust path if your router differs):

```text
https://api.yourdomain.com/health
```

API routes live under `/api/v1/...`. If `/health` 404s, check Passenger/Node logs and that the startup file is `dist/server.js`.

---

## 6. Local dry-run (optional)

```bash
cd backend
npm ci
npm run build
npm run prepare:cpanel
# Inspect backend/.deploy/ — this is what FTP uploads
```

Or run the workflow manually in GitHub Actions with **dry_run = true**.

---

## 7. Troubleshooting

| Symptom | Likely fix |
|---------|------------|
| Actions fails on secrets | Add all four `FTP_*` secrets; ensure `FTP_SERVER_DIR` ends with `/` |
| FTP timeout / TLS errors | Set variable `FTP_PROTOCOL=ftps-legacy` or `ftp`; confirm port |
| App crash on start | Missing env vars; check cPanel error log; confirm startup file `dist/server.js` |
| Prisma engine error | Schema already targets `debian-openssl-3.0.x` + `rhel-openssl-3.0.x`; re-run NPM Install / Restart |
| CORS errors from frontend | Add the exact frontend origin(s) to `CORS_ORIGINS` |
| Old code still running | Restart Node app after FTP; hard-refresh clients |

---

## 8. What is uploaded vs not

**Uploaded:** `dist/`, `prisma/`, `scripts/`, `package.json`, `package-lock.json`, `DEPLOY_META.json`  
**Optional:** set `INCLUDE_GENERATED=1` in the workflow build step to also upload `generated/` (larger FTP payload).

**Never uploaded:** `.env*`, `node_modules/`, source `src/`, tests, local IDE files

**Installed on server:** dependencies via cPanel **Run NPM Install** (lockfile + `postinstall` → `prisma generate`)
