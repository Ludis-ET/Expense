# cPanel deploy options

## Recommended: Terminal deploy

If you have **cPanel Terminal**, use this guide:

**[docs/DEPLOY-CPANEL-TERMINAL.md](./DEPLOY-CPANEL-TERMINAL.md)**

Quick start:

```bash
cd ~/Expense
git pull
bash scripts/cpanel/deploy-on-server.sh
bash scripts/cpanel/deploy-frontend-on-server.sh
# Restart Node.js apps in cPanel
```

---

## Alternative: GitHub FTP (no terminal)

See workflow `.github/workflows/cpanel-deploy.yml` and slim bundle via `scripts/cpanel/prepare-backend.sh`.

FTP is optional — terminal deploy is simpler and more reliable.
