# cPanel FTP path fix

FTP uploads were landing in wrong nested folders because GitHub secrets used **full server paths** like:

```
/home/lunafhin/santim.lunafh.com/backend/   ❌ WRONG
```

FTP only understands paths **relative to your FTP home** (usually `~/santim.lunafh.com/`).

---

## Correct GitHub secrets

| Secret | Value |
|--------|--------|
| `CPANEL_FTP_BACKEND_PATH` | **`/backend/`** |
| `CPANEL_FTP_FRONTEND_PATH` | **`/frontend/`** |

Do **not** include `/home/lunafhin/` or the domain name.

The workflow now auto-strips those prefixes if you paste the full path by mistake.

---

## Clean up wrong folders (File Manager or Terminal)

Delete the accidentally created nested folder:

```bash
rm -rf ~/santim.lunafh.com/home
rm -rf ~/santim.lunafh.com/santim.lunafh.com
```

Or in File Manager, delete any `home/` folder inside `santim.lunafh.com/`.

---

## After fixing secrets

1. Update GitHub secrets to `/backend/` and `/frontend/`
2. Re-run GitHub Actions deploy (CI **clears** each folder, then uploads fresh `.tgz`)
3. Terminal:

```bash
cd ~/santim.lunafh.com/backend
tar xzf santim-backend.tgz
npm install --omit=dev
npm run db:deploy

cd ~/santim.lunafh.com/frontend
tar xzf santim-frontend.tgz
```

4. Restart Node.js apps

**Important:** CI deletes everything in `backend/` and `frontend/` before upload.  
Set `DATABASE_URL`, `JWT_SECRET`, etc. in **cPanel → Node.js App → Environment variables** — not in a `.env` file on the server (it gets wiped).

---

## Where files should land

```
~/santim.lunafh.com/
├── backend/
│   ├── santim-backend.tgz
│   ├── dist/
│   ├── server.js
│   └── prisma/
└── frontend/
    ├── santim-frontend.tgz
    └── frontend/server.js
```
