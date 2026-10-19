#!/usr/bin/env bash
#
# test-pg-tmpfs.sh — optional, unprivileged, test-ONLY Postgres cluster on tmpfs.
#
# Why: the shared system cluster fsyncs every commit, and many worktrees' test DBs contend
# on one disk. A throwaway cluster whose data dir lives in RAM (fsync/synchronous_commit/
# full_page_writes off) makes prep and suites much faster. It is crash-unsafe BY DESIGN and
# is lost on reboot — never put anything but rebuildable test databases in it.
#
# Usage:
#   scripts/test-pg-tmpfs.sh start        # initdb if needed, create role, start (idempotent)
#   scripts/test-pg-tmpfs.sh stop         # fast stop; data dir is kept (--force: ignore prep locks)
#   scripts/test-pg-tmpfs.sh status       # exit 0 running, 3 stopped
#   scripts/test-pg-tmpfs.sh destroy      # stop and delete the data dir
#   scripts/test-pg-tmpfs.sh --print-conf # print the managed postgresql.conf block
#
# Environment:
#   TEST_PG_DIR   data dir          (default /dev/shm/powernode-test-pg16; the unix socket lives in it)
#   TEST_PG_PORT  TCP port          (default 5433; 5432 is refused — that is the shared cluster)
#   TEST_PG_BIN   PG16 bin dir      (default /usr/lib/postgresql/16/bin)
#   POWERNODE_DATABASE_PASSWORD     password for role "powernode" (default powernode_dev, as database.yml)
#
# Opt a checkout in with `scripts/prepare-worktree.sh <path> --tmpfs-pg`, or by hand:
# DATABASE_PORT=5433 in server/.env.test.local. See docs/guides/testing.md.
set -euo pipefail

# shellcheck source=lib/test-pg.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/test-pg.sh"

TEST_PG_DIR="${TEST_PG_DIR:-$TEST_PG_DEFAULT_DIR}"
TEST_PG_PORT="${TEST_PG_PORT:-5433}"
TEST_PG_BIN="${TEST_PG_BIN:-/usr/lib/postgresql/16/bin}"
MIN_FREE_KB="${TEST_PG_MIN_FREE_KB:-$((3 * 1024 * 1024))}"
MARK_BEGIN="# >>> test-pg-tmpfs managed >>>"
MARK_END="# <<< test-pg-tmpfs managed <<<"

die() { echo "test-pg-tmpfs: $*" >&2; exit 1; }

[ "$TEST_PG_PORT" != "5432" ] || die "refusing to manage port 5432 (the shared system cluster); set TEST_PG_PORT"
case "$TEST_PG_PORT" in ''|*[!0-9]*) die "TEST_PG_PORT must be a number, got: $TEST_PG_PORT" ;; esac

conf_block() {
  cat <<CONF
$MARK_BEGIN
fsync = off
synchronous_commit = off
full_page_writes = off
listen_addresses = '127.0.0.1,::1'
port = $TEST_PG_PORT
unix_socket_directories = '$TEST_PG_DIR'
shared_buffers = 256MB
max_connections = 200
max_locks_per_transaction = 256
max_wal_size = 2GB
min_wal_size = 512MB
checkpoint_timeout = 30min
autovacuum = off
log_min_messages = warning
$MARK_END
CONF
}

[ "${1:-}" != "--print-conf" ] || { conf_block; exit 0; }

pg_bin() { echo "$TEST_PG_BIN/$1"; }
is_running() {
  [ -f "$TEST_PG_DIR/PG_VERSION" ] || return 1
  "$(pg_bin pg_ctl)" -D "$TEST_PG_DIR" status >/dev/null 2>&1
}
port_in_use() {
  (exec 3<>"/dev/tcp/127.0.0.1/$TEST_PG_PORT") 2>/dev/null
}
psql_local() { "$(pg_bin psql)" -qX -h "$TEST_PG_DIR" -p "$TEST_PG_PORT" -d postgres "$@"; }

cmd_status() {
  if is_running; then
    echo "running: $TEST_PG_DIR (port $TEST_PG_PORT, socket dir $TEST_PG_DIR)"
  else
    echo "stopped: $TEST_PG_DIR (port $TEST_PG_PORT)"
    return 3
  fi
}

cmd_start() {
  [ -x "$(pg_bin initdb)" ] || die "PG binaries not found in $TEST_PG_BIN (set TEST_PG_BIN)"
  mkdir -p "$(dirname "$TEST_PG_DIR")"
  # one start at a time: a second caller must not see (and delete) the first one's fresh postmaster.pid
  exec 7>"$(dirname "$TEST_PG_DIR")/.$(basename "$TEST_PG_DIR").start.lock"
  flock -w 120 7 || die "another start is still running (lock held > 120s)"
  if is_running; then
    [ -f "$TEST_PG_DIR/$TEST_PG_MARKER" ] || : > "$TEST_PG_DIR/$TEST_PG_MARKER"
    echo "already running on port $TEST_PG_PORT"; return 0
  fi

  if [ ! -f "$TEST_PG_DIR/PG_VERSION" ]; then
    mkdir -p "$(dirname "$TEST_PG_DIR")"
    local avail_kb
    avail_kb=$(df -Pk "$(dirname "$TEST_PG_DIR")" | awk 'NR==2{print $4}')
    [ "$avail_kb" -ge "$MIN_FREE_KB" ] || die "less than 3GB free under $(dirname "$TEST_PG_DIR")"
    echo "initdb $TEST_PG_DIR"
    "$(pg_bin initdb)" -D "$TEST_PG_DIR" -U "$(id -un)" -E UTF8 \
      --auth-local=trust --auth-host=scram-sha-256 >/dev/null
    chmod 700 "$TEST_PG_DIR"
  fi
  : > "$TEST_PG_DIR/$TEST_PG_MARKER"   # lets `destroy` recognise a directory this script made

  # stale pid file from a crashed/cleaned run: pg_ctl said not running, so it is safe to drop
  [ ! -f "$TEST_PG_DIR/postmaster.pid" ] || { echo "removing stale postmaster.pid"; rm -f "$TEST_PG_DIR/postmaster.pid"; }
  port_in_use && die "port $TEST_PG_PORT is already taken by another process"

  # rewrite the managed block (port / dir may have changed) — idempotent
  sed -i "/$MARK_BEGIN/,/$MARK_END/d" "$TEST_PG_DIR/postgresql.conf"
  conf_block >> "$TEST_PG_DIR/postgresql.conf"

  "$(pg_bin pg_ctl)" -D "$TEST_PG_DIR" -l "$TEST_PG_DIR/server.log" -w start >/dev/null 7>&- \
    || { tail -n 20 "$TEST_PG_DIR/server.log" >&2 || true; die "pg_ctl start failed"; }

  # Role the Rails config logs in as: a superuser, matching the shared cluster. The suite needs it
  # (session_replication_role / DISABLE TRIGGER ALL in DatabaseCleaner and some specs).
  local pw="${POWERNODE_DATABASE_PASSWORD:-powernode_dev}"
  pw="${pw//\'/\'\'}"
  if [ "$(psql_local -tA -c "SELECT 1 FROM pg_roles WHERE rolname='powernode'")" = "1" ]; then
    psql_local -c "ALTER ROLE powernode WITH SUPERUSER LOGIN PASSWORD '$pw'" >/dev/null
  else
    psql_local -c "CREATE ROLE powernode WITH SUPERUSER LOGIN PASSWORD '$pw'" >/dev/null
  fi
  echo "started: port $TEST_PG_PORT, socket dir $TEST_PG_DIR"
  echo "next: DATABASE_PORT=$TEST_PG_PORT in server/.env.test.local (prepare-worktree.sh --tmpfs-pg), then scripts/prepare-extension-test-db.sh"
}

cmd_stop() {
  local force=0; [ "${1:-}" != "--force" ] || force=1
  if [ "$force" = 0 ]; then
    local f
    for f in "${TMPDIR:-/tmp}"/prepare-extension-test-db.*.lock; do
      [ -e "$f" ] || continue
      if ! flock -n "$f" true 2>/dev/null; then
        die "a prepare-extension-test-db.sh run holds $f; wait for it or pass --force"
      fi
    done
  fi
  if is_running; then
    "$(pg_bin pg_ctl)" -D "$TEST_PG_DIR" -m fast -w stop >/dev/null
    echo "stopped (data dir kept: $TEST_PG_DIR)"
  else
    echo "not running"
  fi
}

cmd_destroy() {
  # Check BEFORE stopping or removing anything: canonical path under /dev/shm or /tmp (never the root
  # itself, never via ..) AND the marker written at initdb.
  local real
  real="$(test_pg_safe_to_destroy "$TEST_PG_DIR")" \
    || die "refusing to destroy $TEST_PG_DIR (must be a directory under /dev/shm or /tmp created by this script)"
  TEST_PG_DIR="$real"   # stop and remove exactly the path that was validated
  cmd_stop "${1:-}"
  rm -rf -- "$real"
  echo "destroyed $real"
}

case "${1:-}" in
  start) cmd_start ;;
  stop) shift; cmd_stop "${1:-}" ;;
  status) cmd_status ;;
  destroy) shift; cmd_destroy "${1:-}" ;;
  -h|--help|"") sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $1 (start|stop|status|destroy|--print-conf)" ;;
esac
