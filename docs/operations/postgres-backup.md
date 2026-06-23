# PostgreSQL Backup & Restore Runbook

> Status: active

> **When to use this runbook**: planning a backup strategy for a new Powernode deployment, automating backups on an existing deployment, recovering from data loss, or running a quarterly restore drill.
> Companion to [production-deployment.md](./production-deployment.md), which references but does not deeply cover backup procedure.

## Contents

- [What gets backed up](#what-gets-backed-up)
- [Backup procedure](#backup-procedure)
- [Retention policy](#retention-policy)
- [Restore procedure](#restore-procedure)
- [Quarterly restore drill](#quarterly-restore-drill)
- [pgvector considerations](#pgvector-considerations)
- [Point-in-time recovery (PITR)](#point-in-time-recovery-pitr)
- [Disaster scenarios](#disaster-scenarios)

## What gets backed up

A Powernode backup contains the full primary database dump, including:

- **All table data** — accounts, users, agents, conversations, messages, learnings, knowledge entries, shared memory pools, AI agent executions, audit logs.
- **Vector embeddings stored in pgvector columns** (e.g. `ai_knowledge_graph_nodes.embedding`, `ai_shared_knowledges.embedding`). Postgres backs these up as standard column data; no special handling is needed once the pgvector extension is installed on the restore target.
- **Schema** — all migrations, indexes (including pgvector HNSW indexes), constraints, sequences.
- **Extension declarations** — `CREATE EXTENSION pgvector` and `CREATE EXTENSION pgcrypto` are emitted by `pg_dump` and replayed on restore. **The pgvector extension binary must be installed on the restore target before restoring**; otherwise the restore fails on the `CREATE EXTENSION` line.

Not in the backup:
- **Vault secrets** — keys/secrets live in HashiCorp Vault and have their own backup process. The DB only stores Vault key paths, not values.
- **Generated PDFs/CSVs** — these live on the worker filesystem (`worker/storage/reports/`) and are regenerable from data. Snapshot the filesystem separately if you want point-in-time report continuity.
- **Sidekiq Redis state** — in-flight jobs. Sidekiq is treated as ephemeral; on restore, scheduled jobs will be re-emitted by their owning models.

## Backup procedure

### Automated backups (default)

Backups run as **worker maintenance jobs** — there is no shell script or cron entry to install. The standalone worker schedules them via sidekiq-scheduler (`worker/config/sidekiq.yml`):

| Schedule | Job (args) | What it does |
|----------|-----------|--------------|
| Daily, 02:00 UTC | `Maintenance::ScheduledBackupJob` (`full`) | Full database backup |
| Sunday, 03:00 UTC | `Maintenance::ScheduledBackupJob` (`schema_only`) | Schema-only backup |
| Daily, 04:00 UTC | `Maintenance::BackupCleanupJob` | Removes backups past the retention period |

`ScheduledBackupJob` asks the backend to create a `Database::Backup` row; `Maintenance::DatabaseBackupJob` then runs `pg_dump -Fc` (PostgreSQL custom format — compressed and `pg_restore`-compatible) and records the file path, size, and SHA-256 checksum. Each run writes `${BACKUP_DIR}/<database>_<type>_<YYYYMMDD_HHMMSS>.dump`.

The worker reads these environment variables (from `worker/.env` or the operator's preferred env file):

| Variable | Purpose |
|----------|---------|
| `DATABASE_HOST` | Database host (default `localhost`) |
| `DATABASE_PORT` | Database port (default `5432`) |
| `DATABASE_USERNAME` | Postgres role with `pg_dump` access (default `postgres`) |
| `DATABASE_PASSWORD` | Password for that role |
| `DATABASE_NAME` | Application database name (`powernode_production`) |
| `BACKUP_DIR` | Local backup directory (default `/var/backups/powernode`) |
| `BACKUP_RETENTION_DAYS` | Local retention used by the cleanup job (default 30) |

Off-host replication (S3, etc.) is **not** built in — sync `${BACKUP_DIR}` to durable, off-host storage with your own tooling (e.g. an `aws s3 sync` cron, or a filesystem snapshot) so losing the host doesn't lose the backups with it.

### Manual ad-hoc backup

Before a risky migration, take an out-of-band backup with the same `pg_dump` the worker uses (custom format, so `pg_restore` can read it):

```bash
sudo -u postgres \
  pg_dump -Fc -h localhost -U postgres -d powernode_production \
  -f /var/backups/powernode/pre_migration_$(date +%Y%m%d_%H%M%S).dump
```

### Backup verification

`DatabaseBackupJob` records each backup's file size and SHA-256 checksum on its `Database::Backup` row (visible via the admin maintenance API). Spot-check the dump on disk — and any off-host copy you replicate to:

```bash
ls -la /var/backups/powernode/ | tail
```

A backup smaller than ~10% of the previous successful backup is suspicious — investigate before relying on it.

## Retention policy

| Tier | Retention | Storage |
|------|-----------|---------|
| Daily | 30 days | Local disk (`BACKUP_DIR`) |
| Weekly | 13 weeks | S3 (move oldest-of-week before cleanup; rotate via lifecycle policy) |
| Monthly | 12 months | S3 (set lifecycle to Glacier for archival cost reduction) |

`BACKUP_RETENTION_DAYS=30`, read by `Maintenance::BackupCleanupJob` (daily at 04:00 UTC), handles local cleanup. Weekly/monthly tiering happens via an S3 lifecycle policy on whatever off-host copy you maintain — Powernode does not currently ship one. Sample policy:

```json
{
  "Rules": [
    {
      "ID": "weekly-glacier",
      "Status": "Enabled",
      "Prefix": "backups/",
      "Transitions": [
        { "Days": 90, "StorageClass": "GLACIER" }
      ],
      "Expiration": { "Days": 365 }
    }
  ]
}
```

## Restore procedure

> Restores run `pg_restore --clean --if-exists` against the target database (the same command `Maintenance::DatabaseRestoreJob` uses) — it **drops and recreates every object it restores**. Never run it against production without an explicit recovery decision.

### Pre-flight checklist

1. Stop all Powernode services so they don't write during restore:
   ```bash
   sudo systemctl stop powernode.target
   ```
2. Confirm the pgvector + pgcrypto extensions are installed on the restore target:
   ```bash
   sudo -u postgres psql -d postgres -c "SELECT name FROM pg_available_extensions WHERE name IN ('vector','pgcrypto');"
   ```
   Both rows must come back. Install via `apt install postgresql-16-pgvector` (or the version-matched package — the platform standardizes on PostgreSQL 16) before continuing.
3. Validate the backup file integrity (custom-format dumps carry a table of contents `pg_restore` can read without restoring):
   ```bash
   pg_restore -l /var/backups/powernode/powernode_production_full_20260518_020000.dump > /dev/null && echo "dump OK"
   ```

### Restore from local file

```bash
sudo -u postgres \
  pg_restore --clean --if-exists --no-owner --no-privileges \
  -h localhost -U postgres -d powernode_production \
  /var/backups/powernode/powernode_production_full_20260518_020000.dump
```

### Restore from an off-host copy (e.g. S3)

Backups are local files, so first pull the dump back to the restore host, then restore it the same way:

```bash
aws s3 cp \
  s3://your-bucket/backups/powernode_production_full_20260518_020000.dump \
  /var/backups/powernode/

sudo -u postgres \
  pg_restore --clean --if-exists --no-owner --no-privileges \
  -h localhost -U postgres -d powernode_production \
  /var/backups/powernode/powernode_production_full_20260518_020000.dump
```

### Post-restore verification

After `pg_restore` completes (custom-format restores can print non-fatal warnings — only `FATAL`/connection errors abort the restore):

1. **Schema version**:
   ```bash
   cd /opt/powernode/server && bundle exec rails db:migrate:status | tail -20
   ```
   No `down` rows should appear past the latest backup's recorded migration.
2. **Row counts** against an expected baseline:
   ```bash
   sudo -u postgres psql powernode_production -c "
     SELECT 'users' AS table, COUNT(*) FROM users
     UNION ALL SELECT 'accounts', COUNT(*) FROM accounts
     UNION ALL SELECT 'ai_agents', COUNT(*) FROM ai_agents
     UNION ALL SELECT 'audit_logs', COUNT(*) FROM audit_logs;"
   ```
3. **Vector indexes**:
   ```bash
   sudo -u postgres psql powernode_production -c "
     SELECT indexname FROM pg_indexes
      WHERE indexdef LIKE '%hnsw%' OR indexdef LIKE '%ivfflat%';"
   ```
   All HNSW/IVFFlat indexes from before the restore should be present.
4. **App boot**:
   ```bash
   sudo systemctl start powernode.target
   sudo scripts/systemd/powernode-installer.sh status
   ```
   All services should be `active (running)` within 30 seconds.

## Quarterly restore drill

Production backups that have never been tested for restore are not backups — they are unverified files. Run a drill at minimum every 90 days:

1. Provision a throwaway database on a non-production host (`createdb powernode_restore_drill`).
2. Restore the most recent production backup into it.
3. Run the [post-restore verification](#post-restore-verification) steps; record row counts, duration, any error output.
4. Boot a Powernode instance pointed at the drill DB (`POSTGRES_DB=powernode_restore_drill`), verify a few API endpoints respond (`/api/v1/health`, `/api/v1/auth/login` with a known user).
5. Tear down the drill DB (`dropdb powernode_restore_drill`).
6. Log results to your incident response tooling.

A failed drill is a P1 — your stated RTO does not hold until it is resolved.

## pgvector considerations

- **Extension binary version**: pgvector 0.5.0 changed index format. If you restore a 0.5+ backup onto a 0.4.x server you will get index-corruption errors. Match the extension version on the restore target. Check with `SELECT extversion FROM pg_extension WHERE extname = 'vector';`.
- **HNSW build time**: HNSW indexes are large. On a database with millions of vector rows, the `CREATE INDEX` statements emitted by `pg_dump` can take 30+ minutes on restore. Plan recovery windows accordingly.
- **Embedding column sizes**: existing embedding columns are 1536 dims (OpenAI) and 768 dims (Ollama-default). A dump preserves these. If you change embedding model post-restore you will need to re-embed. There is **no** `ai:reembed` rake task — the worker ships no rake tasks. Re-embedding is driven by the worker's scheduled `AiSkillLifecycleMaintenanceJob` (the monthly run re-embeds skills — see [worker-operations.md](./worker-operations.md) Scheduled Jobs); for other vector columns there is currently no one-shot operator command, so treat a full re-embed as a manual/not-yet-automated step.

## Point-in-time recovery (PITR)

Powernode does not ship a PITR setup out of the box — the recommended path for organizations needing PITR:

1. Enable WAL archiving in `postgresql.conf`:
   ```
   wal_level = replica
   archive_mode = on
   archive_command = 'aws s3 cp %p s3://${WAL_BUCKET}/wal/%f'
   ```
2. Take regular base backups with `pg_basebackup -D /backups/base -F t -z -X stream`.
3. Configure `recovery.conf` (Postgres 11) or `postgresql.auto.conf` recovery target settings (Postgres 12+) on the restore host.

If PITR is required for compliance, retain WAL archives for at least the legal retention window for transactional data (often 7 years for financial records — confer with your compliance team).

## Disaster scenarios

| Scenario | Response |
|----------|----------|
| Corrupted table after a bad migration | Restore the most recent backup into a sidecar DB, `pg_dump --table=<name>` the affected table, `psql` it into production. Avoid full-DB restore if isolated. |
| Entire database lost (volume failure) | Provision new DB host, install pgvector matching version, restore from latest backup, point services at new host, run [post-restore verification](#post-restore-verification). |
| Region failure | Restore from cross-region S3 copy of latest backup into a host in a healthy region. Update DNS / load balancer to point at new endpoint. |
| Ransomware encryption of backup directory | Restore from S3 (assumed immutable / versioned / cross-region). If S3 is also compromised, your RPO is whatever the oldest off-platform archive provides — this is why monthly Glacier tier is non-optional. |

## See also

- [production-deployment.md](./production-deployment.md) — initial deployment + service management
- [docker-swarm.md](./docker-swarm.md) — Swarm-specific operations
- [performance-tuning.md](./performance-tuning.md) — Postgres tuning parameters

_Last verified: 2026-06-04_
