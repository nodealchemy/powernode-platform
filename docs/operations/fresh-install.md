# Fresh Install — standing up a 0.4.0 database

How to build a Powernode database from the **0.4.0 baselines** (post-squash). Companion:
[../contributing/conventions/migrations-and-seeds.md](../contributing/conventions/migrations-and-seeds.md).

## Prerequisites

- **PostgreSQL 16+** (UUIDv7 uses a portable shim function; PG18 native is auto-detected — no action needed).
- Four PostgreSQL extensions, created **once per database by a superuser** — the app DB role typically
  lacks `CREATE EXTENSION`:

  ```sql
  -- as the postgres superuser, against the target database:
  CREATE EXTENSION IF NOT EXISTS ltree;
  CREATE EXTENSION IF NOT EXISTS pg_trgm;
  CREATE EXTENSION IF NOT EXISTS pgcrypto;
  CREATE EXTENSION IF NOT EXISTS vector;
  ```

  If you skip this, `db:schema:load` fails on the first `enable_extension`. (`uuidv7()` itself is **not** an
  extension — the `setup_uuidv7` baseline defines it as a plain SQL function, no superuser needed.)

## Core mode (public only — the default self-hosted install)

```bash
cd server
# 1. create the database (as a role that owns it)
RAILS_ENV=<env> bundle exec rails db:create        # or createdb <name>
# 2. (superuser) create the 4 extensions in that database — see above
# 3. load the schema (core + public extensions = ~418 tables)
BUNDLE_GEMFILE=Gemfile POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 RAILS_ENV=<env> bundle exec rails db:schema:load
# 4. seed (core tier always; add demo data with POWERNODE_SEED_DEMO=1)
BUNDLE_GEMFILE=Gemfile POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 RAILS_ENV=<env> bundle exec rails db:seed
```

`db:schema:load` reads the committed **core-only** `schema.rb`. Because `schema.rb` carries the
self-bootstrapping `uuidv7()` function guard, the load works on a clean database with no migration replay.

## Full mode (with private extensions present on disk)

The committed `schema.rb` excludes private-extension tables, so build core from the schema, then **migrate**
the private baselines on top (they are timestamp-banded `> S` to replay cleanly after the core load):

```bash
cd server
# 1–2. create DB + the 4 extensions (as above)
# 3. load core schema, then migrate private extensions (business, etc.)
BUNDLE_GEMFILE=Gemfile.private POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1 RAILS_ENV=<env> bundle exec rails db:schema:load
BUNDLE_GEMFILE=Gemfile.private POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1 RAILS_ENV=<env> bundle exec rails db:migrate
# 4. seed
BUNDLE_GEMFILE=Gemfile.private POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1 RAILS_ENV=<env> bundle exec rails db:seed
```

A private extension is loaded only when present on disk **and** not listed in `config/extensions_state.json`
`disabled`. See [private-bundle notes](../contributing/conventions/extension-db-contributions.md).

## Verify

```bash
# table count (core mode ≈ 420 incl. schema_migrations + ar_internal_metadata)
psql -d <db> -tAc "select count(*) from information_schema.tables where table_schema='public';"
# leak guard — 0 private-extension tables in the committed public schema.rb
bash scripts/pattern-validation.sh   # "No private-extension table refs in public schema.rb ... ✓ PASS"
# migration status is clean
RAILS_ENV=<env> bundle exec rails db:migrate:status
```

## Test databases

`maintain_test_schema!` (in `spec/rails_helper.rb`) rebuilds the **test** DB from the core `schema.rb`. The
test database still needs the four extensions created by a superuser first. For a **full-mode** test database
(running private-extension specs), build it `db:schema:load` + `db:migrate` like full mode above and be aware
`maintain_test_schema!` will try to reload the core `schema.rb` — point private-extension specs at a
dedicated test DB (e.g. via `TEST_ENV_NUMBER`) to avoid it dropping the private tables.

## Gotchas

- `schema.rb` is **core-mode only** — never regenerate it in full mode (it would leak private tables). Auto
  dump-after-migrate is disabled; rebuild deliberately (core-mode `db:schema:dump`).
- The renames in 0.4.0 make this schema **incompatible** with a pre-0.4.0 live database's table names — a
  fresh install is clean, but an existing deployment needs the `data-migration.md` ETL before cutover.
