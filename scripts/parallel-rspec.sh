#!/usr/bin/env bash
#
# parallel-rspec.sh — run the server RSpec suite (server/spec + the public extensions' specs) in N
# parallel processes, each on its OWN Postgres database and its OWN Redis lane. Opt-in: nothing else
# in the repo calls this unless VALIDATE_PARALLEL is set (scripts/validate.sh), and a plain
# `bundle exec rspec` is untouched.
#
#   1. guard   refuse anything but the tmpfs Postgres cluster (the shared 5432 cluster holds the
#              worktrees' lanes; a parallel run recreates N databases)
#   2. redis   start/verify the dedicated test daemon (scripts/test-redis.sh: 64 databases)
#   3. size    N = min(cores, memory, free redis lanes, postgres connection headroom), live — see below
#   4. prep    scripts/prepare-extension-test-db.sh --lanes "<prefix>1 .. <prefix>N" (golden template, N clones)
#   5. run     parallel_rspec -n N, files balanced by recorded runtimes; each process is renamed onto its
#              lane by spec/parallel_lane_env.rb (TEST_ENV_NUMBER=<prefix>K, TEST_REDIS_LANE=TEST_REDIS_LANE_BASE+K-1)
#   6. tail    specs that cannot share a filesystem/process neighbourhood (scripts/parallel-serial-tail.txt)
#              run afterwards, one process, on lane ${LANE_PREFIX}1
#   exit status is non-zero when either phase failed.
#
# Usage:
#   DATABASE_PORT=5433 scripts/parallel-rspec.sh [options] [-- <spec dirs/files>]
#     -n N, PARALLEL_N=N   use exactly N processes (still capped by the free Redis lanes)
#     --check              run the guard and print the plan (N and its limiting factor); change nothing
#     --dry-run            print the commands instead of running them (after prep is skipped)
#     --no-tail            skip the serial tail (measurement runs of the parallel phase alone)
#   With no paths: server/spec plus extensions/{system,marketing,supply-chain}/server/spec.
#
# Sizing inputs (all overridable; defaults are MEASURED figures, see docs/guides/testing.md):
#   PARALLEL_RSS_MB          resident memory per rspec process                  (default 2000)
#   PARALLEL_DB_MB           tmpfs bytes per lane database                      (default 80)
#   PARALLEL_MEM_RESERVE_MB  memory left for the OS, Postgres, the shell (default 2048; the effective reserve is
#                            at least 7000 + the test Redis maxmemory: one process's observed spike plus Redis)
#   PARALLEL_PG_CONNS        Postgres connections per process; capped by the AR pool (default 4)
#   MemAvailable is read live from /proc/meminfo; nothing assumes a machine size.
#
# Worktrees: each checkout has its own lane namespace (databases powernode_test<prefix>K) and claims a
# contiguous range of the test Redis lanes from a ledger (<TEST_REDIS_DIR>/lanes.ledger, released on exit).
# The main checkout uses `__p`; any other git worktree `__w<6 hex of sha1(path)>p`; PARALLEL_LANE_PREFIX
# overrides (only those two shapes are accepted). A 64-database Redis has 30 lanes, so concurrent runs
# SHARE them: a second run is sized to the lanes still free (N shrinks, "redis" becomes the limit) and
# refuses to start at 0. One prefix runs once at a time. --check prints the namespace and the range.
#
# Other environment:
#   DATABASE_PORT (or server/.env.test.local)  the tmpfs cluster's port, REQUIRED (default cluster is refused)
#   TEST_PG_DIR     tmpfs cluster socket dir     (default /dev/shm/powernode-test-pg16)
#   TEST_ENV_LOCAL_FILE  file read for DATABASE_PORT when unset (default server/.env.test.local)
#   TEST_REDIS_DIR  test Redis dir, also holds the lane ledger (default /dev/shm/powernode-test-redis)
#   TEST_REDIS_PORT / TEST_REDIS_DATABASES       dedicated Redis (default 6380 / 64)
#   PARALLEL_KILL_AFTER=SECONDS  how long a signalled process group may ignore TERM before it is KILLed (default 30)
#   PARALLEL_STATS=FILE   sample per-process RSS, MemAvailable and PG connections every 5 s into FILE
#   PARALLEL_TEST_OPTIONS extra rspec options for every process (e.g. a json formatter)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$REPO/server"
# shellcheck source=lib/test-pg.sh
. "$REPO/scripts/lib/test-pg.sh"

die() { echo "parallel-rspec: $*" >&2; exit 1; }

CHECK="" DRY="" NO_TAIL="" N_REQUESTED="${PARALLEL_N:-}" PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --dry-run) DRY=1 ;;
    --no-tail) NO_TAIL=1 ;;
    -n) shift; N_REQUESTED="${1:-}" ;;
    --) shift; PATHS=("$@"); break ;;
    -h|--help) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done
if [ -n "$N_REQUESTED" ]; then
  [[ "$N_REQUESTED" =~ ^[1-9][0-9]*$ ]] || die "process count must be a positive integer, got: $N_REQUESTED"
fi

# ---- 1. guard: tmpfs cluster only ------------------------------------------------------------------
command -v setsid >/dev/null 2>&1 || die "setsid (util-linux) is required: each phase runs as its own process group"
TEST_PG_DIR="${TEST_PG_DIR:-$TEST_PG_DEFAULT_DIR}"
DB_PORT="${DATABASE_PORT:-}"
[ -n "$DB_PORT" ] || DB_PORT="$(test_pg_dotenv_port "${TEST_ENV_LOCAL_FILE:-$SERVER/.env.test.local}")"
test_pg_parallel_guard "$DB_PORT" "$TEST_PG_DIR" || exit 1
export DATABASE_PORT="$DB_PORT"
export TEST_REDIS_PORT="${TEST_REDIS_PORT:-6380}" TEST_REDIS_DATABASES="${TEST_REDIS_DATABASES:-64}"
# The shim assigns both per process; an inherited lane from the invoking shell must not leak in.
unset TEST_ENV_NUMBER TEST_REDIS_LANE TEST_REDIS_LANE_BASE
# Namespace of this checkout: database lanes ${PREFIX}1..N and a claimed range of redis lanes, so a second
# worktree running at the same moment shares neither (see the ledger below).
LANE_PREFIX="$(test_pg_lane_prefix "$REPO")"
[[ "$LANE_PREFIX" =~ ^__(p|w[0-9a-f]{6}p)$ ]] || die "PARALLEL_LANE_PREFIX must be __p or __w<6 hex>p, got: $LANE_PREFIX"
export PARALLEL_LANE_PREFIX="$LANE_PREFIX"
REDIS_LEDGER="${TEST_REDIS_DIR:-/dev/shm/powernode-test-redis}/lanes.ledger"
mkdir -p "$(dirname "$REDIS_LEDGER")"

# ---- 2. redis ----------------------------------------------------------------------------------------
if [ -z "$CHECK" ] && [ -z "$DRY" ]; then
  "$REPO/scripts/test-redis.sh" start >/dev/null || die "could not start the dedicated test Redis (scripts/test-redis.sh)"
elif ! "$REPO/scripts/test-redis.sh" status >/dev/null 2>&1; then
  echo "parallel-rspec: note: the dedicated test Redis is not running; a real run starts it" >&2
fi

# ---- 3. size -----------------------------------------------------------------------------------------
psql_tmpfs() { PGHOST="$TEST_PG_DIR" PGPORT="$DB_PORT" PGUSER="${DATABASE_USER:-powernode}" psql -qtAX -d postgres "$@"; }
CORES="$(nproc)"
MEM_AVAIL_KB="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
# Reserve (OS, Postgres, shell) must also cover the test Redis at its maxmemory ceiling and one process's
# observed transient spike (~7 GB, seen once per full run): max(PARALLEL_MEM_RESERVE_MB or 2048, 7000 + redis).
REDIS_MAX_MB="$(awk -v v="$("$REPO/scripts/test-redis.sh" --print-conf 2>/dev/null | awk '/^maxmemory /{gsub(/mb/,"",$2); print $2}')" 'BEGIN{print (v==""?2048:v)}')"
RESERVE_MB=$(( 7000 + REDIS_MAX_MB ))
[ "$RESERVE_MB" -ge "${PARALLEL_MEM_RESERVE_MB:-2048}" ] || RESERVE_MB="$PARALLEL_MEM_RESERVE_MB"
RESERVE_KB=$(( RESERVE_MB * 1024 ))
PER_PROCESS_KB=$(( (${PARALLEL_RSS_MB:-2000} + ${PARALLEL_DB_MB:-80}) * 1024 ))
REDIS_TOTAL="$(test_pg_redis_lanes "$TEST_REDIS_DATABASES")"
# Free lanes = the largest contiguous range no other live run holds (peek only; the claim happens below).
claim_out="$(test_pg_redis_claim "$REDIS_LEDGER" "$REDIS_TOTAL" "$REDIS_TOTAL" "$LANE_PREFIX" "$$" peek)" \
  || die "cannot take redis lanes for namespace $LANE_PREFIX (see message above)"
REDIS_BASE="${claim_out% *}" REDIS_LANES="${claim_out#* }"
PG_MAX="$(psql_tmpfs -c 'show max_connections' 2>/dev/null || true)"
[[ "$PG_MAX" =~ ^[1-9][0-9]*$ ]] || die "cannot read max_connections from the tmpfs cluster on port $DB_PORT (is it running? scripts/test-pg-tmpfs.sh start)"
PG_USED="$(psql_tmpfs -c 'select count(*) from pg_stat_activity' 2>/dev/null || true)"; PG_USED="${PG_USED:-0}"
POOL="${RAILS_MAX_THREADS:-30}"
CONNS="${PARALLEL_PG_CONNS:-4}"; [ "$CONNS" -le "$POOL" ] || CONNS="$POOL"
SIZE="$(test_pg_parallel_n "$CORES" "$MEM_AVAIL_KB" "$RESERVE_KB" "$PER_PROCESS_KB" "$REDIS_LANES" "$PG_MAX" "$PG_USED" "$CONNS")" \
  || die "refusing to run (see above)"
N_COMPUTED="${SIZE%%$'\t'*}" LIMIT="${SIZE#*$'\t'}"
N="$N_COMPUTED"
if [ -n "$N_REQUESTED" ]; then
  N="$N_REQUESTED"
  [ "$N" -le "$REDIS_LANES" ] || die "N=$N exceeds the $REDIS_LANES redis lanes of a $TEST_REDIS_DATABASES-database daemon"
  [ "$N" -le "$N_COMPUTED" ] || echo "parallel-rspec: warning: N=$N is above the computed $N_COMPUTED (limited by $LIMIT)" >&2
fi
echo "parallel-rspec: namespace $LANE_PREFIX: databases powernode_test${LANE_PREFIX}1..$N, redis lanes $REDIS_BASE..$((REDIS_BASE + N - 1)) of $REDIS_TOTAL (ledger $REDIS_LEDGER)"
echo "parallel-rspec: N=$N (computed $N_COMPUTED, limited by $LIMIT; cores=$CORES mem_avail=$((MEM_AVAIL_KB / 1024))MB per_process=$((PER_PROCESS_KB / 1024))MB redis_lanes=$REDIS_LANES pg=${PG_USED}/${PG_MAX} x${CONNS})"
[ -z "$CHECK" ] || { echo "parallel-rspec: --check ok (tmpfs cluster on port $DB_PORT)"; exit 0; }

# ---- file selection ----------------------------------------------------------------------------------
PATHS_EXPLICIT=0; [ "${#PATHS[@]}" -eq 0 ] || PATHS_EXPLICIT=1
if [ "${#PATHS[@]}" -eq 0 ]; then
  PATHS=(spec)
  for ext in system marketing supply-chain; do
    d="$REPO/extensions/$ext/server/spec"
    [ -n "$(find "$d" -name '*_spec.rb' -print -quit 2>/dev/null)" ] && PATHS+=("../extensions/$ext/server/spec")
  done
fi

TAIL_LIST="$REPO/scripts/parallel-serial-tail.txt"
TAIL_FILES=() TAIL_REGEX=""
if [ -z "$NO_TAIL" ] && [ -f "$TAIL_LIST" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -n "$line" ] || continue
    case "$line" in
      server/*) rel="${line#server/}"; rx="^$(printf '%s' "$rel" | sed 's/[][\.*^$+?(){}|/]/\\&/g')" ;;
      *)        rel="../$line";        rx="$(printf '%s' "$line" | sed 's/[][\.*^$+?(){}|/]/\\&/g')" ;;
    esac
    # Only entries inside the selected paths belong to this run's tail.
    inside=""
    for p in "${PATHS[@]}"; do
      p="${p%/}"
      if [ "$rel" = "$p" ] || [[ "$rel" == "$p"/* ]]; then inside=1; break; fi
    done
    [ -n "$inside" ] || continue
    # Checked only for entries this run selects: an uninitialised extension submodule must not kill a core-only run.
    [ -e "$REPO/$line" ] || die "serial-tail entry does not exist: $line (fix scripts/parallel-serial-tail.txt)"
    TAIL_FILES+=("$rel")
    TAIL_REGEX="${TAIL_REGEX:+$TAIL_REGEX|}$rx"
  done < "$TAIL_LIST"
fi

BUNDLE_MODE="$(test_pg_bundle_mode "$REPO")" || die "cannot pick the bundle (see above)"
[ "$BUNDLE_MODE" != private ] || [ -n "${BUNDLE_GEMFILE:-}" ] || export BUNDLE_GEMFILE="$SERVER/Gemfile.private"

# Claim the redis range for real (re-checked under the lock) and give it back however this script ends.
claim_out="$(test_pg_redis_claim "$REDIS_LEDGER" "$REDIS_TOTAL" "$N" "$LANE_PREFIX" "$$" claim)" \
  || die "cannot claim $N redis lanes for $LANE_PREFIX"
[ "${claim_out#* }" -ge "$N" ] || { test_pg_redis_release "$REDIS_LEDGER" "$$"; die "only ${claim_out#* } redis lanes were free when claiming (wanted $N); another run started"; }
REDIS_BASE="${claim_out% *}"
SAMPLER_PID="" RUNTIME_LOG="$SERVER/tmp/parallel_runtime_rspec.log"
cleanup() {
  [ -z "$SAMPLER_PID" ] || kill "$SAMPLER_PID" 2>/dev/null || true
  [ ! -f "$RUNTIME_LOG.full" ] || mv -f "$RUNTIME_LOG.full" "$RUNTIME_LOG"
  test_pg_redis_release "$REDIS_LEDGER" "$$"
}
trap cleanup EXIT
export TEST_REDIS_LANE_BASE="$REDIS_BASE"
LANES="$(test_pg_parallel_lanes "$N" "$LANE_PREFIX")"
PAR_CMD=(bundle exec parallel_rspec -n "$N")
# Balance by recorded runtimes once a run has left a log (the RuntimeLogger in .rspec_parallel writes it);
# the first ever run has none and balances by file size.
if [ -s "$SERVER/tmp/parallel_runtime_rspec.log" ]; then
  # --allowed-missing 100: a log from an earlier subset (or before new spec files) must degrade, not abort.
  PAR_CMD+=(--group-by runtime --runtime-log tmp/parallel_runtime_rspec.log --allowed-missing 100)
fi
[ -z "$TAIL_REGEX" ] || PAR_CMD+=(--exclude-pattern "($TAIL_REGEX)")
[ -z "${PARALLEL_TEST_OPTIONS:-}" ] || PAR_CMD+=(--test-options "$PARALLEL_TEST_OPTIONS")
# parallel_tests applies --exclude-pattern to directory arguments only, so a tail file named explicitly on the
# command line would also run in the parallel phase: take those out of the parallel arguments here.
PAR_PATHS=()
for p in "${PATHS[@]}"; do
  skip=""
  for t in "${TAIL_FILES[@]+"${TAIL_FILES[@]}"}"; do [ "${p%/}" != "$t" ] || { skip=1; break; }; done
  [ -n "$skip" ] || PAR_PATHS+=("$p")
done
PAR_CMD+=("${PAR_PATHS[@]+"${PAR_PATHS[@]}"}")
TAIL_CMD=(env TEST_ENV_NUMBER="${LANE_PREFIX}1" TEST_REDIS_LANE="$REDIS_BASE" bundle exec rspec --require parallel_tests/rspec/failures_logger --format progress --format ParallelTests::RSpec::FailuresLogger --out tmp/serial_tail_failures.log ${PARALLEL_TEST_OPTIONS:-} "${TAIL_FILES[@]+"${TAIL_FILES[@]}"}")

if [ -n "$DRY" ]; then
  echo "prep : $REPO/scripts/prepare-extension-test-db.sh --lanes \"$LANES\""
  echo "run  : (cd server && ${PAR_CMD[*]})"
  [ "${#TAIL_FILES[@]}" -eq 0 ] || echo "tail : (cd server && ${TAIL_CMD[*]})"
  exit 0
fi

# ---- 4. prep -----------------------------------------------------------------------------------------
echo "parallel-rspec: preparing lanes $LANES"
prep_start=$SECONDS
TEST_REDIS_LANE="$REDIS_BASE" "$REPO/scripts/prepare-extension-test-db.sh" --lanes "$LANES" >/dev/null || die "lane preparation failed"
echo "parallel-rspec: lanes ready in $((SECONDS - prep_start))s"

# ---- 5. run ------------------------------------------------------------------------------------------
cd "$SERVER"
mkdir -p tmp
rm -f tmp/parallel_failures.log tmp/serial_tail_failures.log
if [ -n "${PARALLEL_STATS:-}" ]; then
  : > "$PARALLEL_STATS"
  ( while :; do
      printf '%s\tmem_avail_mb=%s\tpg_conns=%s\trss_kb=%s\n' "$(date +%s)" \
        "$(awk '/^MemAvailable:/ {print int($2/1024)}' /proc/meminfo)" \
        "$(psql_tmpfs -c 'select count(*) from pg_stat_activity' 2>/dev/null || echo '?')" \
        "$(ps -eo rss,args | awk '/[r]spec|[p]arallel_rspec/ && !/parallel-rspec.sh/ {printf "%s,", $1}')" >> "$PARALLEL_STATS"
      sleep 5
    done ) &
  SAMPLER_PID=$!
fi

trap test_pg_on_signal INT TERM HUP QUIT   # stop the process group, wait for it, THEN the EXIT trap releases the ledger
# A subset run (explicit paths) rewrites the runtime log with only its own files: keep the full-suite one.
# A .full left by a run that was SIGKILLed: newer than the live log means the live one is a clobbered subset
# log (restore the full one); older means it is stale (drop it).
if [ -f "$RUNTIME_LOG.full" ]; then
  if [ "$RUNTIME_LOG.full" -nt "$RUNTIME_LOG" ]; then mv -f "$RUNTIME_LOG.full" "$RUNTIME_LOG"; else rm -f "$RUNTIME_LOG.full"; fi
fi
if [ "$PATHS_EXPLICIT" = 1 ] && [ -s "$RUNTIME_LOG" ]; then cp -f "$RUNTIME_LOG" "$RUNTIME_LOG.full"; fi
par_start=$SECONDS
par_rc=0
if [ "${#PAR_PATHS[@]}" -gt 0 ]; then
  test_pg_run_group "${PAR_CMD[@]}" || par_rc=$?
else
  echo "parallel-rspec: every selected file is in the serial tail; no parallel phase"
fi
echo "parallel-rspec: parallel phase finished in $((SECONDS - par_start))s (exit $par_rc)"

tail_rc=0
if [ "${#TAIL_FILES[@]}" -gt 0 ]; then
  tail_start=$SECONDS
  echo "parallel-rspec: serial tail (${#TAIL_FILES[@]} files) on lane ${LANE_PREFIX}1"
  [ -n "$TEST_PG_SIGNALLED" ] || test_pg_run_group "${TAIL_CMD[@]}" || tail_rc=$?
  echo "parallel-rspec: serial tail finished in $((SECONDS - tail_start))s (exit $tail_rc)"
fi
[ -z "$TEST_PG_SIGNALLED" ] || { echo "parallel-rspec: interrupted" >&2; exit 143; }
[ "$par_rc" -eq 0 ] && [ "$tail_rc" -eq 0 ] || exit 1
