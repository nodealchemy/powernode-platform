#!/usr/bin/env bash
# test-pg.sh — sourced helpers shared by scripts/test-pg-tmpfs.sh, scripts/prepare-extension-test-db.sh
# and scripts/prepare-worktree.sh for the optional tmpfs test Postgres cluster. Source it; do not run it.

TEST_PG_DEFAULT_DIR="/dev/shm/powernode-test-pg16"
TEST_PG_MARKER=".test-pg-tmpfs"

# Last DATABASE_PORT=<digits> in a dotenv file, as dotenv itself would read it: tolerates a leading
# `export`, surrounding whitespace and single/double quotes; ignores commented-out lines. Empty if none.
test_pg_dotenv_port() {
  [ -f "${1:-}" ] || return 0
  sed -nE "s/^[[:space:]]*(export[[:space:]]+)?DATABASE_PORT[[:space:]]*=[[:space:]]*[\"']?([0-9]+)[\"']?[[:space:]]*(#.*)?\$/\\2/p" "$1" | tail -1
}

# True iff DIR holds a live-looking unix socket for exactly PORT (plain decimal, no leading zero/space).
test_pg_socket_up() {
  local dir="${1:-}" port="${2:-}"
  [[ "$port" =~ ^[1-9][0-9]*$ ]] || return 1
  [ -S "$dir/.s.PGSQL.$port" ]
}

# Decide which cluster this prep run talks to, from the port RAILS resolved (the source of truth)
# cross-checked against any DATABASE_PORT the shell/dotenv declared.
#   prints "shared" (Rails and the bare psql default agree) or "tmpfs" (socket for that port in DIR);
#   returns 2 on an env/Rails disagreement, 3 when Rails' port is neither.
test_pg_resolve_cluster() {
  local env_port="${1:-}" rails_port="${2:-}" dir="${3:-$TEST_PG_DEFAULT_DIR}"
  if [ -z "$rails_port" ] && [ -n "$env_port" ]; then
    echo "DATABASE_PORT=$env_port is declared but Rails reported no port (could not boot or connect on it?)" >&2; return 2
  fi
  [ -n "$rails_port" ] || rails_port="${PGPORT:-5432}"
  if [ -n "$env_port" ] && [ "$env_port" != "$rails_port" ]; then
    echo "DATABASE_PORT=$env_port but Rails resolved port $rails_port" >&2; return 2
  fi
  if [ "$rails_port" = "${PGPORT:-5432}" ]; then echo shared; return 0; fi
  if test_pg_socket_up "$dir" "$rails_port"; then echo tmpfs; return 0; fi
  echo "Rails resolved port $rails_port, which is not the tmpfs cluster (no socket $dir/.s.PGSQL.$rails_port) and not PGPORT=${PGPORT:-5432}" >&2
  return 3
}

# Is DIR something `destroy` may rm -rf? Canonical path strictly under /dev/shm or /tmp (never those
# roots themselves, never via ..), and carrying the marker written when this script initialised it.
# On success prints the canonical path: callers must remove exactly that value.
test_pg_safe_to_destroy() {
  local real
  real="$(realpath -m -- "${1:-}")" || return 1
  case "$real" in
    /dev/shm|/tmp|/) return 1 ;;
    /dev/shm/*|/tmp/*) ;;
    *) return 1 ;;
  esac
  [ -f "$real/$TEST_PG_MARKER" ] && printf '%s\n' "$real"
}

# Opt a checkout in: write DATABASE_PORT into an env file iff the tmpfs cluster is running.
# Returns 0 written, 1 cluster not running. Replaces any earlier DATABASE_PORT line (incl. `export`).
test_pg_env_opt_in() {
  local file="$1" port="${TEST_PG_PORT:-5433}" here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  TEST_PG_PORT="$port" "$here/test-pg-tmpfs.sh" status >/dev/null 2>&1 || return 1
  sed -i -E '/^[[:space:]]*(export[[:space:]]+)?DATABASE_PORT[[:space:]]*=/d' "$file"
  printf 'DATABASE_PORT=%s\n' "$port" >> "$file"
}

# Which bundle does a test-DB prep run under? Private mode is in effect iff at least one private
# extension is on disk (extensions/private/<slug>/extension.json, the same notion
# extensions_loader_helper.rb uses). server/Gemfile.private is TRACKED, so its mere presence says nothing.
#   prints "core"    when no private extension is on disk (the default Gemfile is correct);
#   prints "private" when one is and the private bundle resolves (`bundle check` under Gemfile.private);
#   returns 1 with a message when private extensions are on disk but Gemfile.private is missing or its
#   bundle is not installed: silently falling back to core would build a wrong (private-table-less) DB.
test_pg_bundle_mode() {
  local repo="${1:?repo root}" ext
  ext="$(find "$repo/extensions/private" -mindepth 2 -maxdepth 2 -name extension.json -print -quit 2>/dev/null || true)"
  if [ -z "$ext" ]; then echo core; return 0; fi
  if [ ! -f "$repo/server/Gemfile.private" ]; then
    echo "private extensions are present under extensions/private but server/Gemfile.private is missing" >&2; return 1
  fi
  if ! (cd "$repo/server" && BUNDLE_GEMFILE="$repo/server/Gemfile.private" bundle check >/dev/null 2>&1); then
    echo "private extensions are present under extensions/private but the private bundle is not installed;" >&2
    echo "  run: cd server && BUNDLE_GEMFILE=Gemfile.private bundle install" >&2
    return 1
  fi
  echo private
}

# ---------------------------------------------------------------------------------------------------
# Parallel RSpec (scripts/parallel-rspec.sh). Pure helpers: no cluster is touched here.
# ---------------------------------------------------------------------------------------------------

# Space-separated lane suffixes PREFIX1..PREFIXN (PREFIX defaults to __p). A namespace of its own on
# purpose: parallel_tests' native numbering ("", 2, 3 ...) would land on the live worktree databases
# powernode_test2/3/4.
test_pg_parallel_lanes() {
  local n="${1:-}" prefix="${2:-__p}" i out=""
  [[ "$n" =~ ^[1-9][0-9]*$ ]] || { echo "lane count must be a positive integer, got: ${n:-<empty>}" >&2; return 1; }
  [[ "$prefix" =~ ^__(p|w[0-9a-f]{6}p)$ ]] || { echo "lane prefix must be __p or __w<6 hex>p, got: $prefix" >&2; return 1; }
  for ((i = 1; i <= n; i++)); do out="$out${out:+ }$prefix$i"; done
  printf '%s\n' "$out"
}

# The lane prefix of a checkout: PARALLEL_LANE_PREFIX if set, else `__p` for the main checkout and
# `__w<6 hex of sha1(path)>p` for any other git worktree (deterministic, so a worktree always reuses its
# own databases). Two checkouts never share a prefix, hence never a lane database.
test_pg_lane_prefix() {
  local repo="${1:-}" gd cd
  if [ -n "${PARALLEL_LANE_PREFIX:-}" ]; then printf '%s\n' "$PARALLEL_LANE_PREFIX"; return 0; fi
  gd="$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null || true)"
  cd="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -z "$gd" ] || [ "$gd" = "$cd" ]; then echo __p; return 0; fi
  printf '__w%sp\n' "$(printf '%s' "$repo" | sha1sum | cut -c1-6)"
}

# Redis lane ledger: concurrent parallel runs (one per worktree) must hold DISJOINT ranges of the test
# daemon's lanes, and one prefix may run once at a time (its databases are dropped and rebuilt).
# Lines are "<pid> <prefix> <base> <count>"; dead pids are pruned on every call; flock serializes.
#   usage: test_pg_redis_claim LEDGER TOTAL_LANES WANT PREFIX PID claim|peek
#   prints "<base> <count>" (count = the largest free contiguous range, at most WANT). claim records it.
#   returns 3 when PREFIX is already running, 4 when no lane is free.
test_pg_redis_claim() {
  local ledger="$1" total="$2" want="$3" prefix="$4" pid="$5" mode="${6:-claim}"
  [[ "$total" =~ ^[0-9]+$ && "$want" =~ ^[1-9][0-9]*$ && "$pid" =~ ^[0-9]+$ ]] || { echo "test_pg_redis_claim: bad arguments" >&2; return 1; }
  (
    flock -w 30 7 || { echo "test_pg_redis_claim: ledger lock timeout" >&2; exit 1; }
    [ -e "$ledger" ] || : > "$ledger"
    live=""
    while read -r p pf b c; do
      [ -n "${p:-}" ] && kill -0 "$p" 2>/dev/null && live="$live$p $pf $b $c"$'\n'
    done < "$ledger" 2>/dev/null || true
    printf '%s' "$live" > "$ledger"
    if printf '%s' "$live" | awk -v pf="$prefix" '$2 == pf { f = 1 } END { exit !f }'; then
      echo "test_pg_redis_claim: prefix $prefix already has a live parallel run (see $ledger)" >&2; exit 3
    fi
    out="$(printf '%s' "$live" | awk -v total="$total" -v want="$want" '
      { for (i = $3; i < $3 + $4; i++) used[i] = 1 }
      END {
        best = 0; bstart = 0; i = 0
        while (i < total) {
          if (used[i]) { i++; continue }
          s = i; while (i < total && !used[i]) i++
          if (i - s > best) { best = i - s; bstart = s }
        }
        n = (best < want) ? best : want
        print bstart, n
      }')"
    [ "${out#* }" -ge 1 ] || { echo "test_pg_redis_claim: no free redis lane (all $total are held; see $ledger)" >&2; exit 4; }
    [ "$mode" = peek ] || printf '%s %s %s %s\n' "$pid" "$prefix" "${out% *}" "${out#* }" >> "$ledger"
    echo "$out"
  ) 7>"$ledger.lock"
}

test_pg_redis_release() {
  local ledger="$1" pid="$2"
  [ -f "$ledger" ] || return 0
  ( flock -w 30 7 && awk -v pid="$pid" '$1 != pid' "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger" ) 7>"$ledger.lock"
}

# Refuse anything but the tmpfs cluster. PORT is the port Rails resolved for the test database
# ("" = the shared default). A parallel run purges and recreates N databases and would otherwise be
# one mistyped DATABASE_PORT away from doing that on the cluster that holds the worktrees' lanes.
test_pg_parallel_guard() {
  local port="${1:-}" dir="${2:-$TEST_PG_DEFAULT_DIR}" kind
  # By number, whatever PGPORT says: 5432 is the shared cluster. And a socket alone does not make a tmpfs
  # cluster: the directory must carry the marker scripts/test-pg-tmpfs.sh writes when it initialises one.
  if [ "$port" = 5432 ]; then
    echo "parallel run refused: port 5432 is the shared cluster; its powernode_test2/3/4 lanes belong to live worktrees." >&2
    return 1
  fi
  kind="$(test_pg_resolve_cluster "" "$port" "$dir")" || return 1
  if [ "$kind" = shared ]; then
    echo "parallel run refused: the test database resolves to the shared cluster (port ${port:-${PGPORT:-5432}}); its powernode_test2/3/4 lanes belong to live worktrees. Start the tmpfs cluster (scripts/test-pg-tmpfs.sh start) and set DATABASE_PORT=5433." >&2
    return 1
  fi
  if [ ! -f "$dir/$TEST_PG_MARKER" ]; then
    echo "parallel run refused: $dir has no $TEST_PG_MARKER marker, so it is not a cluster scripts/test-pg-tmpfs.sh created." >&2
    return 1
  fi
  return 0
}

# Redis lanes a daemon with DBS logical databases affords. Mirrors Powernode::Redis.max_test_lanes
# (server/config/initializers/redis.rb): lane k takes (DBS-1-2k, DBS-2-2k) and the floor is 3.
test_pg_redis_lanes() {
  local dbs="${1:-16}"
  [[ "$dbs" =~ ^[0-9]+$ ]] && [ "$dbs" -ge 16 ] || { echo "databases must be an integer >= 16, got: $dbs" >&2; return 1; }
  echo $(( ((14 + dbs - 16 - 3) / 2) + 1 ))
}

# How many parallel processes to run, from what the machine can carry RIGHT NOW. No fixed cap: the
# result is the smallest of four bounds, and the one that bit is named so a short run is explainable.
#   usage: test_pg_parallel_n CORES MEM_AVAIL_KB RESERVE_KB PER_PROCESS_KB REDIS_LANES PG_MAX PG_USED CONNS_PER_PROCESS
#   prints "<N>\t<limit>" where limit is cores|memory|redis|postgres. Returns 2 (nothing printed) when a bound is 0.
test_pg_parallel_n() {
  local cores="$1" mem="$2" reserve="$3" per="$4" lanes="$5" pgmax="$6" pgused="$7" conns="$8"
  local a
  for a in "$cores" "$mem" "$reserve" "$per" "$lanes" "$pgmax" "$pgused" "$conns"; do
    [[ "$a" =~ ^[0-9]+$ ]] || { echo "test_pg_parallel_n: not a non-negative integer: ${a:-<empty>}" >&2; return 1; }
  done
  [ "$per" -gt 0 ] && [ "$conns" -gt 0 ] || { echo "test_pg_parallel_n: per-process memory and connections must be > 0" >&2; return 1; }
  local by_mem=0 by_pg=0
  [ "$mem" -gt "$reserve" ] && by_mem=$(( (mem - reserve) / per ))
  # 3 = superuser_reserved_connections' default; the rest of max_connections is shared with whatever is already connected.
  [ "$pgmax" -gt $(( 3 + pgused )) ] && by_pg=$(( (pgmax - 3 - pgused) / conns ))
  local n="$cores" limit=cores
  [ "$by_mem" -lt "$n" ] && { n="$by_mem"; limit=memory; }
  [ "$lanes" -lt "$n" ] && { n="$lanes"; limit=redis; }
  [ "$by_pg" -lt "$n" ] && { n="$by_pg"; limit=postgres; }
  # A bound of zero is a refusal, never "one process anyway": the run would start on a machine that cannot carry it.
  if [ "$n" -lt 1 ]; then
    echo "test_pg_parallel_n: refused: the $limit bound computes to 0 (cores=$cores mem_avail_kb=$mem reserve_kb=$reserve redis_lanes=$lanes pg_max=$pgmax pg_used=$pgused). Free memory, fix Postgres access, or lower the reserve." >&2
    return 2
  fi
  printf '%s\t%s\n' "$n" "$limit"
}

# Run a command as its own process group and wait for it, so a SIGINT/SIGTERM sent to the wrapper can stop
# the WHOLE group (parallel_rspec plus its N rspec children) before the wrapper releases what it holds.
# The caller installs: trap test_pg_on_signal INT TERM HUP QUIT (setsid moves the group out of the terminal session, so HUP never reaches it on its own)
TEST_PG_CHILD="" TEST_PG_SIGNALLED=""
test_pg_on_signal() {
  TEST_PG_SIGNALLED=1
  [ -z "$TEST_PG_CHILD" ] || kill -TERM -- "-$TEST_PG_CHILD" 2>/dev/null || true
}
#   usage: test_pg_run_group CMD [ARGS...]; returns the command's status (143 when signalled)
#   PARALLEL_KILL_AFTER (default 30): seconds a signalled group may ignore TERM before it is KILLed.
test_pg_run_group() {
  local rc waited=0 limit="${PARALLEL_KILL_AFTER:-30}"
  command -v setsid >/dev/null 2>&1 || { echo "test_pg_run_group: setsid (util-linux) is required" >&2; return 1; }
  [ -z "$TEST_PG_SIGNALLED" ] || return 143   # a signal landed before the phase started: do not launch it
  setsid "$@" &
  TEST_PG_CHILD=$!
  # Poll, never a bare `wait`: a blocking wait cannot escalate to KILL. A trapped signal TERMs the group
  # (test_pg_on_signal); a group that ignores TERM is KILLed once it has been signalled for $limit seconds.
  while kill -0 "$TEST_PG_CHILD" 2>/dev/null; do
    sleep 1
    if [ -n "$TEST_PG_SIGNALLED" ]; then
      waited=$((waited + 1))
      [ "$waited" -lt "$limit" ] || { kill -KILL -- "-$TEST_PG_CHILD" 2>/dev/null || true; waited=0; }
    fi
  done
  wait "$TEST_PG_CHILD" 2>/dev/null; rc=$?
  kill -KILL -- "-$TEST_PG_CHILD" 2>/dev/null || true   # stragglers of the group
  TEST_PG_CHILD=""
  [ -z "$TEST_PG_SIGNALLED" ] || rc=143
  return "$rc"
}
