# Fix backend on cPanel — no Terminal needed

Use **only the cPanel web interface** (browser). Pick **Method A** first.

---

## Method A — Node.js App panel (easiest)

### Step 1 — Open your backend app

1. Log in to **cPanel**
2. Search **Setup Node.js App** (or **Application Manager**)
3. Click your **backend** application (`santim.lunafh.com` / `api` — whichever runs the API)

### Step 2 — Run NPM Install

Look for a button named one of:

- **Run NPM Install**
- **NPM Install**
- **Run JS script** → then choose install

Click it and wait until it finishes (can take 1–3 minutes).  
This installs packages and runs `prisma generate` via the `postinstall` script.

### Step 3 — Change the startup file

Find **Application startup file** and change:

| From | To |
|------|-----|
| `dist/server.js` | **`boot.js`** |

`boot.js` generates the Prisma client every time the app starts, so you never need Terminal.

### Step 4 — Upload `boot.js` if it is missing

If `boot.js` is not on the server yet:

1. cPanel → **File Manager**
2. Go to `santim.lunafh.com/backend/`
3. Click **+ File** → name it `boot.js`
4. Paste the contents from your repo file `backend/boot.js`
5. Save

Or push to GitHub and let CI/CD deploy it (Method C).

### Step 5 — Restart

Back in **Setup Node.js App** → click **Restart**.

### Step 6 — Test

Open in your browser:

```
https://YOUR-API-DOMAIN/health
```

You should see JSON like `{"status":"ok",...}`.

---

## Method B — Cron Job (if “Run NPM Install” is missing)

### Step 1 — Create the cron

1. cPanel → **Cron Jobs**
2. Under **Add New Cron Job**:
   - **Common Settings**: Once Per Minute (temporarily)
   - **Command**:

```bash
cd /home/lunafhin/santim.lunafh.com/backend && npm install --omit=dev && node node_modules/prisma/build/index.js generate
```

3. Click **Add New Cron Job**

### Step 2 — Wait 2 minutes, then delete the cron

Delete the job so it does not keep running every minute.

### Step 3 — Set startup file and restart

- Startup file → **`boot.js`**
- **Restart** the Node.js app

---

## Method C — Redeploy from GitHub

Push to `main`. CI builds a full backend bundle (with Prisma client) and FTP-uploads it.

After deploy:

1. Startup file → **`boot.js`**
2. **Restart**

---

## Checklist

| Step | Where in cPanel |
|------|-----------------|
| Install packages | Setup Node.js App → **Run NPM Install** |
| Or one-time install | Cron Jobs (Method B) |
| Startup file = `boot.js` | Setup Node.js App |
| `DATABASE_URL` set | Environment variables |
| Restart app | **Restart** |
