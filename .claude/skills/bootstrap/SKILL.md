---
name: bootstrap
description: Bootstrap dev environment - migrations, seeds, services, smoke tests
disable-model-invocation: true
---

# Bootstrap Dev Environment

Validate and fix the development environment end-to-end. Follow this process exactly:

## Step 1: Check Pending Migrations

```bash
cd server && bundle exec rails db:migrate:status
```

If any migrations are **down**, run `bundle exec rails db:migrate`.

## Step 2: Audit Seed Files

Use Grep and Read to scan `server/db/seeds/` files for:
- `class_name:` references that don't match actual models in `server/app/models/`
- Missing `foreign_key:` paired with `class_name:`
- Hardcoded UUIDs that may conflict

Report any issues found before proceeding.

## Step 3: Run Seeds

```bash
cd server && bundle exec rails db:seed 2>&1
```

If seeds fail:
1. Read the error message carefully
2. Identify the failing seed file and line
3. Read the seed file and the related model
4. Fix the seed file (association name, missing record, validation error)
5. Re-run `bundle exec rails db:seed`
6. **Max 3 attempts** — if still failing, stop and report the error

## Step 4: Restart Services

```bash
sudo systemctl restart powernode-backend@default
sudo systemctl restart powernode-worker@default
```

Wait 5 seconds, then check status:

```bash
sudo scripts/systemd/powernode-installer.sh status
```

## Step 5: Smoke Test

Run these health checks:

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/v1/health
curl -s -o /dev/null -w "%{http_code}" http://localhost:4567/
```

Expected: `200` for both. Report any failures.

## Step 6: Summary

Report:
- Migrations applied (if any)
- Seed issues found and fixed (if any)
- Service status
- Smoke test results
