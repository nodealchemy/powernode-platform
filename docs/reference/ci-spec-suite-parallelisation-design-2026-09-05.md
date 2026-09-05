# powernode-system CI: spec-suite parallelisation and schema-materialisation design

**Status:** design only — nothing here is implemented. Audit = report only.
**Date:** 2026-09-05. Measured against run 1762 (`powernode/powernode-system` develop `eace9e55`, parent
develop `cd7fe58c6`).
**Scope:** `extensions/system/.gitea/workflows/ci.yaml`, jobs `rspec`, `provider-specs`, `worker-specs`,
`ci-hygiene`, and the test-database preparation they share.

---

## 0. Summary of the recommendation

| Ask | Recommendation |
|---|---|
| Topology | Static integer matrix of **6 rspec shard jobs** (`idx: [0..5]`), plus an `rspec-gate` job, plus a `db-schema-skew` job. `provider-specs` and `worker-specs` become independent (no `needs:` chain). |
| Isolation | **No `services:` block.** Each job starts its own postgres + redis with `docker run -p <bridge-ip>::5432` — the **kernel** picks the host port, so "port is already allocated" is impossible by construction. Addressed via the docker bridge gateway, which is the path already proven to work. |
| Schema | **Build the test DB from migrations** (`db:create db:migrate`, core + extension on the engine's migration path), not `db:schema:load` + stamping. Measured locally: 104 migrations in 10.9 s. Handles both skew directions; the stamping approach handles only one. A separate advisory job diffs a fresh migration-built dump against committed `schema.rb` and reports skew. |
| Timeouts | Shards 90 min, provider-specs 30, worker-specs 20, skew 15, gate 5, all others 15. Not proven honoured here, so every long step is also wrapped in `timeout(1)` with a budget 5 min under the job's, and the sidecar cleanup step is `if: always()`. |
| Sharding | **File-level, deterministic, self-computed** in every shard job from `rspec --dry-run --format json` (13.6 s locally) + greedy LPT by example count. N=6 gives 2481/2481/2481/2481/2481/2480 (directory split gives 8398/2168/2175/2144). Timing-weighted balancing is phase 2. |
| Migration | Five steps, each one push, each verified by a run and revertible; a probe workflow first so nothing rests on an unverified runner feature. |
| Green-while-testing-less | Gate asserts partition ∪ == all spec files and Σ planned == independent dry-run total; each shard asserts ran == planned. No cross-job data needed for the primary check. |

Three findings outside the brief that the lead should act on regardless (details in §8): the current
`ci-hygiene` reaper (and its copy in the parent repo) kills **every** postgres/redis container on the
host by image, so a concurrent run's — or the other repo's — live sidecars die on every push, and
scoping it is a **prerequisite** of this design (§9 step 0.5); `system_fleet_signal_states` is missing
from `schema.rb` on origin/develop **and** on the local `dev-loop/dev-improve` branch (a second live
skew instance, one that `schema:load`+`db:migrate` cannot repair, present in some local lane DBs and
absent in others, and one whose model swallows `PG::UndefinedTable` so the failure is silent); the
local per-lane rspec method shares redis db 15 and `FLUSHDB`s it at every suite start.

---

## 1. What was measured (evidence base)

### 1.1 Suite shape (rspec `--dry-run --format json`, local, against a migration-built probe DB)

Total **14 885** examples in **949** spec files (946 runnable — 3 are shared-example files whose examples
are attributed to the including spec; see §5.4). Matches the lead's count exactly.

| top-level dir | examples | | dir | examples |
|---|---:|---|---|---:|
| services | 8398 | | lint | 88 |
| models | 1907 | | schema | 88 |
| requests | 1826 | | scripts | 73 |
| docs | 1507 | | migrations | 67 |
| controllers | 318 | | lib | 54 |
| db | 300 | | system | 23 |
| integration | 207 | | serializers | 21 |
| | | | seeds / decorators / support | 3 / 2 / 3 |

`services/` by subdirectory: `system` 5906, `ai` 1421, `sdwan` 723, `acme` 194, `federation` 140.

Per-file distribution: median 10, mean 15.7, max **1092** (`docs/module_docs_mcp_call_signatures_spec.rb`
— one file, 7 % of the suite, and its examples are trivially cheap). Next largest:
`services/ai/tools/system_fleet_tool_spec.rb` 393, `services/ai/tools/sdwan_tool_spec.rb` 183.

Current four suites as ci.yaml defines them: controllers 2144, services 8398, models-lib 2168, misc 2175.

### 1.2 Throughput and timing (run 1762, job 12508, runner3)

- `Prepare test database` (db:create + db:schema:load + stamp): **2 m 07 s**.
- `rspec controllers`: 2147 examples, **31 m 19 s** → 68.6 examples/min (0.875 s/example). Request
  specs dominate this suite; unit-heavy shards will be faster per example. No per-example timing exists
  for the other 12 738 examples — every estimate below assumes the controllers rate and is therefore an
  upper bound.
- Extrapolated sequential total ≈ 217 min; container ceiling is `entrypoint=["/bin/sleep","10800"]`
  = 180 min. Confirmed in the log of every job on run 1762.

### 1.3 Runner facts read from run 1762 logs

- Runner reports `runner3(version:v3.2.0)`; three runners (`runner1..3`), all on the same host (`fna` per
  memory) and therefore the same docker daemon and bridge. This is why fixed host ports collide across
  runners and why `max-parallel` on one job cannot help even if honoured.
- Job containers: image `ghcr.io/catthehacker/ubuntu:act-24.04`, `network="bridge"`, name
  `GITEA-ACTIONS-TASK-<task>-WORKFLOW-ci-JOB-<job>-<hash>`.
- **The docker socket is mounted into job containers**: `ci-hygiene` ran `docker ps` / `docker rm -f`
  and succeeded (job 12507). This is the primitive the isolation design rests on, and it is already
  proven on this runner.
- Sidecars from `services:` are also started with `network="bridge"` and reached via `172.17.0.1`,
  as the long comment in ci.yaml records.

### 1.4 Features with evidence in this repo (usable) vs without (do not rely on)

| Feature | Evidence | Verdict |
|---|---|---|
| Static-list matrix + `${{ matrix.idx }}` in `run:` | `probe-matrix.yaml` (committed as the verification canary for the dynamic-build design; `build-platform-modules.yaml` depends on it) | usable |
| `needs.<job>.outputs.*` → step `env` | probe-matrix P1, "load-bearing" | usable |
| `needs:` ordering | ci.yaml comment: honoured on run 1676 | usable |
| `actions/upload-artifact@v3` | used in `build-disk-image.yaml` (v4 noted as GHES-only there) | usable if needed |
| `container:` job image | carve-conformance, probe-matrix | usable |
| docker CLI + socket in job | ci-hygiene job 12507 | usable |
| `concurrency:` group | deadlocked, run 1675 | **do not use** |
| `strategy.max-parallel` | ignored, run 1676 | **do not use** |
| `${{ }}` inside `services:` | never tried; ci.yaml warns it fails unsafe | **do not use** (design avoids `services:` entirely) |
| `timeout-minutes` | only use is `build-package-module.yaml` at 180 = the container ceiling, so it has never been observably exercised | **unverified** — set it, but do not depend on it (§4) |
| `$GITHUB_ENV`, `${{ github.run_id }}`, `needs.<job>.result` | not used anywhere in this repo | **unverified** — probe first (§6, step 0) |
| Matrix-job outputs to a downstream job | not used | **unverified** — design does not need it (§7.1) |

### 1.5 Schema-materialisation probe (local, this session)

- `TEST_ENV_NUMBER=_ciprobe RAILS_ENV=test rails db:create db:migrate` with the default (public-only)
  bundle: **104 migrations (50 core + 54 extension incl. the system baseline), 10.9 s wall, exit 0**,
  including the core data-only migration `20260905050000` (no-op on empty tables, as expected) and the
  extension's `20260905070000` rename migration (found nothing to rename, exited cleanly).
- A `db:schema:dump` of that DB vs committed `schema.rb`:
  - vs `origin/develop` (`define(version: 2026_09_04_150000)`): missing `system_platform_health_snapshots`
    **and** `system_fleet_signal_states`.
  - vs local `dev-loop/dev-improve` (`define(version: 2026_09_05_062000)`): missing
    `system_fleet_signal_states` (migration `20260905061000`, version **below** the schema version).
- `rails_helper`'s `check_all_pending!` passed against the migration-built DB (the dry-run loaded and
  enumerated all 14 885 examples), so the guard is satisfied without any stamping.

---

## 2. Topology

### 2.1 Jobs

```
ci-hygiene            reap ORPHANED sidecars by label + age (never by port)   ~15 s
db-schema-skew        migrate-from-zero, dump, diff vs schema.rb (advisory)   ~3 min
rspec  (matrix idx 0..5)   6 shard jobs, each self-contained                  ~36-45 min each
rspec-gate            needs: [rspec]; recomputes the partition, asserts coverage ~1 min
provider-specs        independent (own sidecars)                              ~10 min
worker-specs          independent (own redis sidecar)                         ~5 min
frontend-typecheck, frontend-jest, go-agent, ruby-syntax, todo-audit, rubocop  unchanged
```

`provider-specs` and `worker-specs` lose `needs: [ci-hygiene, rspec]` / `[ci-hygiene, provider-specs]`.
That chain existed *only* to serialise fixed host ports (its own comment says so: "the dependency exists
to sequence port usage, not to gate on rspec's result"). With kernel-allocated ports there is nothing to
sequence. `ci-hygiene` stays as the first job (`needs: ci-hygiene` on every sidecar-starting job) so a
runner that inherits orphans from a SIGKILLed job gets them reaped — but reaping is re-scoped (§2.3).

### 2.2 Why six shards

Arithmetic on a 3-runner pool at the measured 68.6 ex/min (upper bound):

| N | examples/shard | est. shard time | waves on 3 runners | rspec wall | notes |
|---|---:|---:|---:|---:|---|
| 1 (today) | 14 885 | 217 min | 1 | **> 180 min ceiling** | never finishes |
| 3 | 4 962 | 72 min | 1 | ~75 min | monopolises all 3 runners; 2× under ceiling only at the measured rate |
| 4 | 3 722 | 54 min | 2 | ~110 min | second wave has one job; poor packing |
| **6** | **2 481** | **36 min** | **2** | **~75 min** | fits 2 full waves; each shard 5× under the ceiling; a re-run costs 36 min not 72 |
| 8 | 1 861 | 27 min | 3 | ~85 min | more per-job overhead (checkout + bundle + prepare ≈ 3 min each) |

Six is the smallest N where each shard comfortably fits a 90-minute timeout even if the balance by
count is 30 % off in time, and where the pool packs into whole waves. The other ~7 jobs are short (all
finished within 3 minutes on run 1762) and slot around the shards. Expected end-to-end wall for the
whole workflow: **~80–90 min**, versus "never" today.

N is a single number in the workflow (`idx: [0,1,2,3,4,5]` + `CI_RSPEC_SHARDS: 6`); the partition
script reads both and refuses to run if they disagree (§5.3).

### 2.3 `ci-hygiene`, re-scoped

Today it reaps *anything* holding `:5432->`/`:6379->` and then, with no port filter at all,
*anything* from `redis:7` / `pgvector/pgvector:pg16` (`ancestor=` catch-all, `ci.yaml:52-53`; an
identical copy lives in the parent repo's `.gitea/workflows/extensions-bundle.yml:59-60` on the same
runner pool). On a 3-runner host that means run N+1's hygiene job (first thing it does) — from
either repo — `docker rm -f`s run N's live postgres while run N's rspec is mid-suite on another
runner. That is a
plausible mechanism for "downstream jobs get cancelled when the next push lands" and should be checked
against the logs of a run that died that way (a `PG::ConnectionBad` / `Redis::CannotConnectError`
appearing mid-progress-bar is the signature).

New rule: every sidecar this design starts carries labels
`powernode.ci=sidecar`, `powernode.ci.job=<job>-<idx>`, `powernode.ci.owner=<token>` and
`powernode.ci.deadline=<epoch>` (= start + the job's `timeout-minutes`). `ci-hygiene` reaps only
containers with `powernode.ci=sidecar` whose `deadline` is in the past. A live sidecar of a concurrent
run is therefore untouchable by construction, and an orphan from a SIGKILLed job is reaped on the next
run after its own deadline. `docker ps --filter label=...` is supported by every docker CLI; no port
matching remains.

---

## 3. Isolation by construction (postgres + redis per job)

### 3.1 Mechanism

Replace the `services:` block with a first step in every sidecar-needing job:

```bash
# discover the bridge gateway instead of hardcoding 172.17.0.1 (fallback kept)
GW=$(docker network inspect bridge -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)
GW=${GW:-172.17.0.1}
OWNER="${GITHUB_RUN_ID:-norun}-${GITHUB_JOB:-nojob}-${IDX:-0}-$(date +%s)-$RANDOM"
DEADLINE=$(( $(date +%s) + 90*60 ))
LABELS="--label powernode.ci=sidecar --label powernode.ci.owner=$OWNER --label powernode.ci.deadline=$DEADLINE"

PG=$(docker run -d $LABELS -p "$GW::5432" \
      --tmpfs /var/lib/postgresql/data:rw,size=2g \
      -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=powernode_test \
      pgvector/pgvector:pg16 -c fsync=off -c synchronous_commit=off -c full_page_writes=off)
RD=$(docker run -d $LABELS -p "$GW::6379" redis:7 --save '' --appendonly no)

PGPORT=$(docker port "$PG" 5432/tcp | head -1 | awk -F: '{print $NF}')
RDPORT=$(docker port "$RD" 6379/tcp | head -1 | awk -F: '{print $NF}')
for i in $(seq 1 60); do docker exec "$PG" pg_isready -U postgres -q && break; sleep 1; done
docker exec "$PG" pg_isready -U postgres   # fail loudly if still not ready

{ echo "DATABASE_URL=postgres://postgres:postgres@$GW:$PGPORT/powernode_test"
  echo "REDIS_URL=redis://$GW:$RDPORT/0"
  echo "CI_SIDECAR_OWNER=$OWNER"; } >> "$GITHUB_ENV"
```

and a last step, `if: always()`:
`docker ps -aq --filter "label=powernode.ci.owner=$CI_SIDECAR_OWNER" | xargs -r docker rm -f`.

### 3.2 Why this cannot produce "port is already allocated"

`-p <ip>::5432` (empty host-port field) makes dockerd `bind()` port 0, i.e. ask the kernel for a free
port from the ephemeral range. The kernel hands out a port that is free at that instant, atomically,
per socket. Two or six or twenty concurrent jobs each get a distinct port; there is no fixed number for
them to contend over, no scheduler feature to be ignored, and no `${{ }}` inside `services:` (the
untried path ci.yaml warns fails unsafe). The `ports:`-in-`services:` mechanism that produced every
collision so far is not used at all.

What this does **not** protect against: a reaper that matches on image. The current `ci-hygiene`
(and the parent repo's copy) `docker rm -f`s every `redis:7` / `pgvector/pgvector:pg16` container on
the host irrespective of port, so kernel-allocated ports solve the *bind* collision only; the reaper
must be scoped first (§2.3, §8.1, §9 step 0.5).

Addressing reuses exactly the path that already works on this runner: sidecar publishes to the host,
job container reaches the host at the bridge gateway. `localhost` and service-name DNS remain
unavailable for the reasons recorded in ci.yaml and are not needed. Binding to the gateway IP rather
than `0.0.0.0` keeps the throwaway postgres (password `postgres`) off the host's LAN interfaces — a
strict improvement on today.

### 3.3 Why `--tmpfs` and `fsync=off`

Memory records that three worktrees running `db:schema:load` concurrently on one disk turned a
sub-minute prep into 15 minutes (fsync contention). Six shard jobs on one host would recreate that on
the runner. A tmpfs data dir plus `fsync=off` removes the disk from the path entirely; the test DB is
~140 MB, the tmpfs cap is 2 GB, and the data is throwaway by definition. **Unverified: host RAM on
`fna`.** If it is tight, drop `--tmpfs` and keep only the postgres flags (which already eliminate
fsync); the 2 GB figure should be confirmed against `free -g` on the host before step 2 lands.

### 3.4 Redis per job, and per process

`Powernode::Redis` rewrites every URL to logical db **15** in `RAILS_ENV=test` (`TEST_DATABASE`,
`server/config/initializers/redis.rb`), and `rails_helper` `FLUSHDB`s it in `before(:suite)`. Two rspec
processes sharing one redis daemon therefore wipe each other at suite start regardless of `REDIS_URL`'s
db number. One redis container **per rspec process** (not per job) is the only isolation that does not
require a core change. It is cheap (`redis:7` starts in under a second). Cable is `adapter: test` in
the test env, so no second redis consumer exists.

The worker (`worker-specs`) uses `REDIS_URL` as given (`worker/config/application.rb:83`); its own
sidecar isolates it the same way.

### 3.5 Optional hardening: no host ports at all

`docker run --network container:<job-container-id>` puts the sidecar in the job's network namespace:
reachable at `localhost:5432`, nothing published on the host. The job can learn its own container ID
from `/proc/self/mountinfo` (the bind mounts of `/etc/hostname`, `/etc/hosts`, `/etc/resolv.conf`
carry `/var/lib/docker/containers/<id>/`). This removes the gateway dependency and the host-port
surface entirely, but it is **unverified on this runner** (act may set a hostname; the runner image
may mount those files differently). Probe it in step 0; adopt only if the probe passes. The design
does not depend on it.

---

## 4. Timeouts

| Job | `timeout-minutes` | in-step `timeout(1)` budget | rationale |
|---|---:|---:|---|
| rspec shard | 90 | 85 min | est. 36–45 min; 2× margin; half the 180-min container ceiling |
| provider-specs | 30 | 25 min | 4 files today |
| worker-specs | 20 | 15 min | 15 files |
| db-schema-skew | 15 | 10 min | migrate measured 11 s locally; ×20 headroom for a cold runner |
| rspec-gate | 5 | — | dry-run only |
| everything else | 15 | — | all finished in < 3 min on run 1762 |

`timeout-minutes` is set on every job (none has it today), but §1.4 shows it has never been observably
exercised on this runner. So every long `run:` is also wrapped:

```bash
timeout --signal=TERM --kill-after=60 $((85*60)) bundle exec rspec ... ; rc=$?
if [ $rc -eq 124 ]; then echo "::error::shard $IDX exceeded its 85-minute budget after $(...) examples"; fi
exit $rc
```

What a job does on hitting it: the step fails with exit 124 and a one-line error naming the shard and
its planned example count; the progress line printed so far shows how far it got; the `if: always()`
cleanup step still runs (the process was terminated, not the container); the gate job sees a failed
shard and the run is red. Nothing is retried automatically — a shard that needs > 85 min at these
sizes is a hung example or a runner problem, both of which must be looked at, not masked. The
container's own `sleep 10800` ceiling is never the thing that fires.

---

## 5. Sharding strategy

### 5.1 Directory-based sharding is the wrong axis

Directories are not units of work: `services` is 56 % of the suite and `services/system` alone (5906)
is bigger than any other whole suite; the four named suites today are 8398 / 2168 / 2175 / 2144. Any
directory split needs a human to re-balance it every time the suite grows, and the 2026-08 incident in
`ci_matrix_spec_coverage_spec.rb` (eight directories silently never run) shows what happens when the
directory list is the coverage contract.

### 5.2 File-level, deterministic, self-computed partition

Each shard job runs, in its own checkout:

1. `bundle exec rspec --dry-run --format json --out plan.json <every spec-bearing top-level dir>` —
   13.6 s locally (Rails boot dominates). The directory list is derived: `spec/*/` minus
   `factories fixtures support` (which carry no `*_spec.rb`; keep the existing coverage spec's
   `HELPER_DIRS` as the single source of that list).
2. `scripts/ci-spec-shard.rb plan.json --shards $CI_RSPEC_SHARDS --index $IDX` → a file list, computed
   as: group examples by **including spec file** (§5.4), sort files by (−count, path), assign each to the
   currently-lightest shard (LPT). Stable tie-breaks make the result a pure function of the file tree.
3. Run `bundle exec rspec --format progress --format json --out result.json $(cat shard.txt)`.
4. Assert `result.json` example_count == the planned count for this shard (a file that rspec silently
   skipped, or a load error that dropped a file, fails the shard right here).

No artifact, cache, or job output is needed for the partition: all six jobs compute the same answer
from the same commit. The gate job (§7.1) computes it a seventh time to check the union.

Measured balance at N=6: **2481 / 2481 / 2481 / 2481 / 2481 / 2480**. For comparison, stable-hash-mod-6
(the "no dry-run" alternative) gives 2469 / 2307 / 2461 / 2263 / 3271 / 2114 (max/mean 1.32) — the
13 s dry-run buys a 32 % shorter critical path and is worth it.

### 5.3 Staying balanced as the suite grows

- New files and new directories are included automatically (glob, not list). This preserves the
  guarantee the `misc` sweep was written for, without a `claimed=` list to keep in sync.
- Growth changes shard contents but not the algorithm; N only needs raising when a shard's estimated
  time approaches the budget. Make the shard step print its planned count and elapsed time so the
  number is visible every run.
- The script refuses to run if `CI_RSPEC_SHARDS` ≠ the matrix length (the gate passes the matrix
  list in; the shard passes its own idx; both must be < N).

### 5.4 Two correctness details the script must handle

- **Shared examples.** The JSON formatter reports `file_path` as the *shared-example* file for examples
  pulled in via `it_behaves_like` (173 examples today, e.g. `providers/shared_examples.rb` = 158, and
  `spec/support/shared_examples/api_controller_examples.rb`). Group by the path prefix of `id`
  (`./spec/requests/.../ingress_routes_spec.rb[1:1]`), which is always the including spec. Grouping by
  `file_path` would hand `shared_examples.rb` to a shard as a runnable file — rspec would load it, run
  0 examples, and the count assertion in 5.2(4) would catch it, but only after wasting the shard.
- **Count ≠ time.** `docs/module_docs_mcp_call_signatures_spec.rb` is 1092 trivially cheap examples;
  request specs are ~1 s each. Count-based LPT is expected to be off by tens of percent in wall time.
  Phase 2 (§6 step 5): commit `extensions/system/server/spec/ci/timings.json` (per-file seconds summed
  from a green run's `result.json`), weight by time when present, fall back to count for unknown files,
  refresh it by hand or from a scheduled run. Do not build phase 2 before phase 1 has produced the data.

### 5.5 Intra-job parallelism (later, not now)

Once shard jobs are stable, `CI_RSPEC_PROCS=k` can run k rspec processes inside one shard job: split the
shard's file list k ways with the same LPT, give each process `TEST_ENV_NUMBER=_pK` (postgres:
`createdb --template=powernode_test powernode_test_pK` after the migrate — seconds) and **its own redis
container** (§3.4). Host CPU on `fna` is unknown; three concurrent shard jobs × k processes must fit.
Measure a single `k=2` run before making it the default. `parallel_tests` is not in the bundle
(`Gemfile.lock` has only `parallel`) and adding it is a core-repo change; the plain-rspec approach above
needs no gem.

---

## 6. Schema-materialisation strategy

### 6.1 The defect, generalised

`db:schema:load` runs `assume_migrated_upto_version(schema_version)`: every migration file on the
migration path with version ≤ the schema's version is stamped as applied *without running*. Extension
migrations are on that path (`PowernodeSystem::Engine`, `engine.rb:76-78`). So:

| Extension migration vs core `schema.rb` | `schema:load` + stamp (today) | `schema:load` + `db:migrate` | `db:create` + `db:migrate` from zero |
|---|---|---|---|
| dumped into schema.rb (normal case) | ok | ok | ok |
| **newer** than schema version, not dumped (run 1762: `system_platform_health_snapshots`) | stamped, table missing → `PG::UndefinedTable` mid-suite | ok — pending, gets run | ok |
| **older** than schema version, not dumped (**live now**: `system_fleet_signal_states` 20260905061000 < local schema 20260905062000) | stamped, table missing | **assumed by `schema:load`, table missing, nothing pending** | ok |

The third row is not hypothetical — it is the state of the local `dev-loop/dev-improve` branch today
(§1.5), produced by the ordinary sequence "core runs a later migration and dumps while the submodule
pointer predates the extension migration". Two repos with independent timestamps will keep producing
it. Only building from migrations is correct in every row.

### 6.2 Recommendation: build the CI test DB from migrations

`Prepare test database` becomes:

```bash
bundle exec rails db:create
SCHEMA=/tmp/ci-schema.rb bundle exec rails db:migrate      # core + extension migrations, in order
bundle exec rails db:migrate:status | grep -c '^ *down' | grep -qx 0   # belt: nothing left down
```

- Cost: 104 migrations in **10.9 s** locally against the current 2 m 07 s prepare step in CI (most of
  which is Rails boot and loading a 12 400-line `schema.rb`); expect CI to be equal or faster.
- `SCHEMA=` redirects the post-migrate dump (Rails honours `ENV["SCHEMA"]` in
  `schema_dump_path`, activerecord 8.1.3 `database_tasks.rb:472`) so the checkout's `schema.rb` is
  never rewritten inside a job — and the redirected dump is the input to §6.3 for free.
- `rails_helper`'s `check_all_pending!` passes because everything really is applied (verified: the
  dry-run against the probe DB loaded all 14 885 examples). `ci-stamp-migration-versions.rb` becomes
  dead and is deleted, with its pinning spec `spec/scripts/ci_migration_stamping_spec.rb` rewritten to
  the new invariant ("no CI job runs `db:schema:load`; every job that runs specs runs `db:migrate`
  and asserts zero `down`") — that spec's first example (`finds the jobs that load the schema`) would
  otherwise fail by design, and `pattern-validation`/`Dead Reference Cleanup` require the script's
  references to go with it.

Hazards named in `rails_helper`, addressed:

- **Deadlock against concurrent rspec** — not applicable: the DB is created fresh by the only process
  connected to it, before any rspec starts. The deadlock concerns `db:test:prepare`'s *purge* on a
  shared long-lived DB, which never happens here.
- **Silently dropped private-extension tables** — not applicable in CI: the bundle is public-only
  (`extensions_loader_helper.rb` excludes `extensions/private` unless opted in) and nothing is loaded
  from `schema.rb`, so nothing is *assumed*. `scripts/prepare-extension-test-db.sh` stays the local
  path and is untouched by this design. Note its header claims `Migrator.migrations_paths` never absorbs
  the engine's path; the per-lane memory and today's probe (extension migrations ran under
  `db:migrate`) show that at least under `rails db:migrate` it does. Both are recorded; the CI step's
  `migrate:status` check makes the question moot for CI.
- **Migration rot** (an old migration breaking against newer app code — data migrations that touch
  models are the usual culprit): this is the one new exposure. It is a real defect in the migration
  when it happens, it surfaces on the first push after it is introduced, and §6.3 reports it on every
  run in a job that costs nothing when green. The core baseline was squashed on 2025-09-05
  (`db/migrate/README.md`), so the exposed history is one year deep, not the project's lifetime.

### 6.3 Skew detector job (`db-schema-skew`)

Same checkout/bundle as a shard; its own sidecar; runs `db:create`, `SCHEMA=/tmp/fresh.rb db:migrate`,
then compares `/tmp/fresh.rb` with `powernode-platform/server/db/schema.rb` on a normalised structural
view: sets of `create_table`, columns (`t.<type> "<name>"` lines under each table), `add_index`,
`add_foreign_key`, ignoring the `define(version:)` line and ordering. Differences are printed as
"tables/columns present in migrations but absent from schema.rb" (and the reverse). Today it would
report `system_platform_health_snapshots` and `system_fleet_signal_states` against origin/develop.

Advisory (`continue-on-error: true`, warning annotation) for the first weeks — develop is currently
skewed and a blocking job would be red on every push, which §8 of memory (`a-saturated-gate-reports-
nothing-new`) shows is worse than no job. Promote to blocking once develop is clean and the fix path is
documented: the remedy is always in **core** (bump the submodule pointer, `db:migrate`, commit
`schema.rb`), which this extension's CI can only report, not perform. `scripts/check-schema-fresh.sh`'s
header already says a from-zero migrate + diff "is a CI job, not this script"; this is that job.

---

## 7. What could make CI green while testing less — and the guards

### 7.1 Coverage guards (no unverified feature required)

- **Gate job** (`rspec-gate`, `needs: rspec`): runs the same dry-run and partition script for *every*
  index 0..N-1 and asserts (a) the union of shard file lists == the set of spec-bearing files under
  `spec/`, disjoint; (b) Σ planned counts == the dry-run's `example_count`; (c) N == matrix length. A
  bug in the glob, in LPT, or a stale N fails here. `needs:` without `if: always()` means a failed or
  cancelled shard skips the gate and the run is red — no `needs.<job>.result` or matrix-outputs
  feature is required.
- **Per-shard self-check** (§5.2 step 4): ran == planned. Catches a file rspec dropped (load error in
  another file, a `--pattern` mismatch, a file rspec deems empty). `errors_outside_of_examples_count`
  must be 0.
- **No `|| true`, no `continue-on-error` on shards.** The only advisory job is `db-schema-skew`.
- **Extension coverage spec** `spec/scripts/ci_matrix_spec_coverage_spec.rb` is rewritten, not
  deleted: its new invariants are "the shard script's directory glob excludes exactly `HELPER_DIRS`",
  "every spec-bearing dir has ≥ 1 file in the partition", "the workflow's matrix length equals
  `CI_RSPEC_SHARDS`". Its current assertions parse `for suite in` / `claimed=`, which will no longer
  exist; leaving it would fail loudly (good) but the replacement must land in the same commit.

### 7.2 Other risks

| Risk | Mitigation / disposition |
|---|---|
| Random example order (`config.order = :random`) plus new file groupings surfaces order-dependent flakes | Real defects; seeds are printed; do not add retries. Expect a handful in the first runs. |
| Six postgres containers on one host: RAM/IO | tmpfs + `fsync=off` (§3.3); confirm host RAM; fall back to disk with `fsync=off`. |
| Stacked runs (memory: image eviction mid-job when N runs queued) | Superseded same-branch runs must be cancelled — `concurrency:` is off the table (run 1675); use `platform_cancel_gitea_workflow_run` by hand for now; a hygiene step that cancels older in-progress runs of the same branch via the Gitea API is a follow-up, not part of this design. |
| Runner `v3.2.0` is not a version of upstream act_runner I can identify | Treat every YAML feature as unverified until the step-0 probe exercises it. |
| `docker run` from a job leaves a container if the job container is SIGKILLed before the cleanup step | Deadline-labelled reaper in `ci-hygiene` (§2.3). |
| Image pulls per job (`pgvector/pgvector:pg16`, `redis:7`) | Host daemon cache; same images as today; `docker run` pulls only when absent. |
| `GITHUB_ENV` not honoured | Probe; fallback is writing `ci-env.sh` in the workspace and `source`-ing it in each later step. |
| Gitea exposes fewer than 3 runners (one busy with a disk-image build) | Waves get longer; nothing breaks; the shard budget is per job, not per run. |
| Balance drifts as suites grow | The shard step prints planned count + elapsed; raise N when a shard passes ~60 min. |
| The migration-built DB differs from what developers test against locally (`schema.rb`-built) | That difference IS the defect being detected; §6.3 makes it visible instead of latent. |

---

## 8. Findings outside the brief (act on independently)

1. **`ci-hygiene` reaps every postgres/redis container on the host, not just port-holders — and it
   is a `needs:` prerequisite of every run.** The port match is only the first half; the second half
   is an image-wide catch-all with no port filter at all (`ci.yaml:52-53`):
   `docker rm -f $(docker ps -aq --filter "ancestor=redis:7")` and the same for
   `pgvector/pgvector:pg16`. With three runners a new push kills the previous run's sidecars mid-suite
   regardless of what port they publish. Check a "cancelled downstream job" run's rspec log for a
   mid-progress `PG::ConnectionBad`.
   - **The same catch-all exists in the parent repo**, `.gitea/workflows/extensions-bundle.yml:59-60`,
     on the same runner pool. Cross-*repo* pushes reap each other's sidecars, not only cross-run
     pushes within powernode-system. Both copies must be scoped, and the parent's is a core-repo
     change this extension's CI cannot make.
   - **Consequence for this design:** the kernel-allocated ports of §3.2 do *not* dodge this reaper —
     it matches on image, not port. Scoping the reaper (§2.3: label + deadline; a name/run-id filter
     is an acceptable alternative) is therefore a **prerequisite** of step 2 in §9, not a follow-up,
     and the parent's copy must be scoped in the same window or every shard remains one parent push
     away from destruction.
2. **`system_fleet_signal_states` is absent from `schema.rb` on origin/develop and on local
   `dev-loop/dev-improve`**, while extension migration `20260905061000` exists and is *below* the local
   schema version (`2026_09_05_062000`). Any DB materialised from this `schema.rb` by `schema:load`
   assumes the migration applied and lacks the table, and `schema:load`+`db:migrate` cannot repair it
   (nothing is pending). Verified state on dev-cell, 2026-09-05 (`pg_tables` + `schema_migrations`):
   `powernode_test_l1`, `_l2` **have** the table; `powernode_test_l3`, `_l6`, `_l7` and the shared
   `powernode_test` **lack it**. CI's `schema:load`-built DB lacks it. So the exposure is
   per-database, decided by how each was last built or migrated — not "every lane" and not "no
   lane". A lane running on l3/l6/l7 or the shared DB is exposed.
   - **This is a silent-pass risk, not a visible failure.** `System::Fleet::SignalState` rescues
     `StandardError` in every method — `setting` (`signal_state.rb:92`), `record_dedupe!` (:118),
     `claim_notification!` (:146), `record_escalation!` (:161), `record_decision!` (:170), `claim!`
     (:229) — and returns `nil` with a `Rails.logger.warn`. `PG::UndefinedTable` is a `StandardError`,
     so on a table-less DB the code path no-ops instead of raising; a spec asserting only on the
     caller's behaviour can go green with the table absent. Treat a green signal-state spec on one
     of the exposed DBs as unproven until the table is confirmed present.
   - **Remedy is a deliberate `schema.rb` regeneration in core**, not a re-run of anything: with the
     extension submodule pointer at (or past) `20260905061000`, run `rails db:migrate` against a
     development DB that does not already have the version stamped (or un-stamp it first), and commit
     the dumped `schema.rb`. The parent push earlier today fixed the sibling
     `system_platform_health_snapshots` because that migration was *above* the old schema version;
     this one sits *below* it, so nothing automatic will ever pick it up. The §6.3 skew job is the
     detector for the next instance.
3. **Local per-lane rspec shares redis db 15.** `TEST_DATABASE = 15` is a constant, not derived from
   `TEST_ENV_NUMBER`, and `rails_helper` flushes it in `before(:suite)`; concurrent lanes wipe each
   other. A core change deriving the db from `TEST_ENV_NUMBER` (or one redis per lane) closes it.

---

## 9. Migration path (one push per step, each verified by a run, each revertible)

**Step 0 — probe (`probe-ci-isolation.yaml`, `workflow_dispatch`, ~5 min).** Same shape as
`probe-matrix.yaml`. Jobs: (P1) `docker run -p $GW::5432 pgvector…`, `docker port`, connect from the
job with `pg_isready -h $GW -p $PORT`; two matrix entries at once to prove distinct ports; (P2)
`$GITHUB_ENV` propagation between steps; (P3) `${{ github.run_id }}` non-empty; (P4) a `sleep 300`
job with `timeout-minutes: 2` — is it killed?; (P5) `/proc/self/mountinfo` self-ID +
`--network container:` (optional path, §3.5); (P6) `needs.<job>.result` in an `if:`. Record outcomes
in the workflow's header comment the way ci.yaml records runs 1673–1676. Nothing below uses a feature
P1–P3 did not pass; P4–P6 only widen options.
*Verify:* run URL and per-probe pass/fail in the commit message.

**Step 0.5 — scope the reaper (PREREQUISITE for anything that starts a sidecar).** Rewrite
`ci-hygiene` to reap only `powernode.ci=sidecar`-labelled containers past their `deadline` label
(§2.3) and delete both the port match and the `ancestor=` image catch-all; land the identical change
in the parent repo's `.gitea/workflows/extensions-bundle.yml:59-60` (core commit) in the same window.
Until both copies are scoped, every sidecar on the host — today's `services:` ones and this design's
`docker run` ones alike — is destroyed by the next push to either repo (§8.1). This step is safe on its
own because the `if: always()` "Reap own sidecars" steps still clean up the normal path; the only
thing the old reaper did that the new one does not is kill live containers.
*Verify:* start a deliberately orphaned labelled container with a past deadline and one with a
future deadline in the step-0 probe; the next run's `ci-hygiene` removes the first and leaves the
second; a concurrent run's rspec log shows no mid-progress connection loss.

**Step 1 — schema.** In the existing single `rspec` job and `provider-specs`: replace
`db:schema:load` + stamp with `db:create` + `SCHEMA=… db:migrate` + `migrate:status` assert; delete
`ci-stamp-migration-versions.rb`; rewrite `ci_migration_stamping_spec.rb`; add `db-schema-skew`
(advisory).
*Verify:* prepare step ≤ 2 min; `health_spec.rb:201` passes; skew job lists exactly the two known
tables; no `Migrations are pending` anywhere. Topology unchanged, so the run is directly comparable
to 1762.

**Step 2 — isolation.** Remove `services:` from `rspec`, `provider-specs`, `worker-specs`; add the
sidecar start/cleanup steps; add `timeout-minutes` + `timeout(1)` wrappers; drop the `needs:` chain
so provider/worker run concurrently with rspec. Requires step 0.5 in both repos first — with the
image catch-all still live anywhere on the pool, concurrent jobs would lose their sidecars to the
next push and the "zero port collisions" verification below would be confounded by reaper kills.
*Verify:* three jobs hold three different published ports at once (`docker ps` output in each job's
log); zero "port is already allocated"; `ci-hygiene` reaps nothing on a clean host and reaps the
deliberately-orphaned probe container from step 0.

**Step 3 — sharding.** Add `scripts/ci-spec-shard.rb` (+ unit spec: LPT balance, shared-example
attribution, determinism); convert `rspec` to the 6-entry matrix; add `rspec-gate`; rewrite
`ci_matrix_spec_coverage_spec.rb`.
*Verify:* gate reports Σ planned == dry-run total (14 885 + whatever landed); every shard's ran ==
planned; longest shard < 60 min; whole workflow < 90 min. Compare failures against step 2's single-job
run — the set must be a superset (new order-dependent flakes) never a subset.

**Step 4 — observe for a week.** Collect per-shard elapsed from the logs; if max/min > 1.5, do
step 5; if a shard trends toward 60 min, raise N.

**Step 5 — refinements**, each independent: timing-weighted partition (`spec/ci/timings.json`);
`CI_RSPEC_PROCS=2` after measuring host cores; `--network container:` mode if P5 passed; promote
`db-schema-skew` to blocking once develop is clean.

Rollback at any step is `git revert` of that step's single commit; the workflow is valid at every
intermediate state, and until step 3 lands the single-job shape (today's) keeps running, so develop
never loses its only signal.

---

## 10. Unverified items, stated plainly

- `timeout-minutes`, `$GITHUB_ENV`, `github.run_id`, `needs.<job>.result`, matrix-job outputs — all
  unproven on this runner (§1.4); step 0 exists to close that.
- Host `fna` CPU count and RAM: unknown; §3.3's tmpfs size and §5.5's process count depend on it.
- Per-example timing beyond the controllers suite: unknown; every wall-time estimate assumes
  0.875 s/example, which is an upper bound for unit-heavy shards and might be exceeded only by a shard
  that is entirely request specs (impossible under LPT — 2144 request/controller examples are spread
  over six shards).
- Whether the runner's docker daemon uses the default bridge subnet: the gateway is discovered at
  runtime with `172.17.0.1` as fallback, so a non-default value is handled, but the discovery command
  itself (`docker network inspect bridge`) has not been run in a job here.
- The rot exposure of the 104 migrations against future code: known zero today (probe), unknowable
  ahead of time; §6.3 is the detector.
- `rubocop` failed on run 1762 for reasons unrelated to this design; not investigated.

## Appendix — commands used for the evidence

```bash
# suite shape (against a migration-built probe DB; the shared powernode_test aborts on a pending migration)
cd /home/pnadmin/work/server
TEST_ENV_NUMBER=_ciprobe RAILS_ENV=test SCHEMA=/tmp/…/probe-schema.rb bundle exec rails db:create db:migrate   # 10.9 s, 104 migrations
TEST_ENV_NUMBER=_ciprobe bundle exec rspec --dry-run --format json --out ext-dryrun.json ../extensions/system/server/spec/{controllers,requests,services,models,lib,integration,db,decorators,docs,lint,migrations,schema,scripts,seeds,serializers,system}   # 13.6 s, 14 885 examples
TEST_ENV_NUMBER=_ciprobe RAILS_ENV=test SCHEMA=/tmp/…/probe-schema.rb bundle exec rails db:schema:dump
comm -23 <(grep -o 'create_table "[a-z_]*"' probe-schema.rb | sort -u) <(git show origin/develop:server/db/schema.rb | grep -o 'create_table "[a-z_]*"' | sort -u)
# run 1762 via MCP: platform_get_gitea_workflow_run(run_id 1762); platform_get_gitea_job_logs(job 12508 / 12507)
```

The probe database `powernode_test_ciprobe` was left in place on dev-cell; drop it when convenient.
