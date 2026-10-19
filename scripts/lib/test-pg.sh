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
