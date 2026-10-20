#!/usr/bin/env bash
#
# test-redis.sh — optional, unprivileged, test-ONLY Redis daemon for the parallel suite.
#
# Why: the shared Redis has 16 logical databases. The suite takes two per lane (main + worker) and
# worktrees hold lanes 1-5, so a parallel run has nowhere to put N more lanes there. This starts a
# SECOND daemon, loopback only, with 64 databases and no persistence. The shared daemon is never
# touched. Everything in it is rebuildable test state; it is not a cache of anything.
#
# Usage:
#   scripts/test-redis.sh start         # idempotent; writes a config under TEST_REDIS_DIR and daemonizes
#   scripts/test-redis.sh stop          # SIGTERM to the verified pid of the daemon this script started
#   scripts/test-redis.sh status        # exit 0 running, 3 stopped
#   scripts/test-redis.sh --print-conf  # print the config that start would write
#
# Environment:
#   TEST_REDIS_DIR        config/log/pid dir   (default /dev/shm/powernode-test-redis)
#   TEST_REDIS_PORT       loopback TCP port    (default 6380; 6379 is refused — that is the shared daemon)
#   TEST_REDIS_DATABASES  `databases` setting  (default 64, minimum 16)
#   TEST_REDIS_BIN        redis-server binary  (default: redis-server on PATH)
#   TEST_REDIS_CLI        redis-cli binary     (default: redis-cli on PATH)
#
# The suite reaches it through the same two variables (server/config/initializers/redis.rb):
# TEST_REDIS_PORT and TEST_REDIS_DATABASES. scripts/parallel-rspec.sh exports them.
#
# Command guard (Redis >= 7 ACL rules, not the deprecated rename-command): every lane of every concurrent
# run shares this one daemon, so the default user may not run anything that reaches past its own database
# or changes the daemon itself (FLUSHALL, CONFIG SET, DEBUG, MONITOR, SHUTDOWN, ACL, ...). FLUSHDB, SCAN,
# INFO, CONFIG GET, CLIENT (except KILL and PAUSE) and data commands stay allowed. There is no admin user and no password: `stop`
# sends SIGTERM to the pidfile's pid only after verify_pidfile proves it is the redis-server on this port.
set -euo pipefail

TEST_REDIS_DIR="${TEST_REDIS_DIR:-/dev/shm/powernode-test-redis}"
TEST_REDIS_PORT="${TEST_REDIS_PORT:-6380}"
TEST_REDIS_DATABASES="${TEST_REDIS_DATABASES:-64}"
TEST_REDIS_BIN="${TEST_REDIS_BIN:-redis-server}"
TEST_REDIS_CLI="${TEST_REDIS_CLI:-redis-cli}"

die() { echo "test-redis: $*" >&2; exit 1; }

[ "$TEST_REDIS_PORT" != "6379" ] || die "refusing to manage port 6379 (the shared Redis); set TEST_REDIS_PORT"
case "$TEST_REDIS_PORT" in ''|*[!0-9]*) die "TEST_REDIS_PORT must be a number, got: $TEST_REDIS_PORT" ;; esac
case "$TEST_REDIS_DATABASES" in ''|*[!0-9]*) die "TEST_REDIS_DATABASES must be a number, got: $TEST_REDIS_DATABASES" ;; esac
[ "$TEST_REDIS_DATABASES" -ge 16 ] || die "TEST_REDIS_DATABASES must be at least 16, got: $TEST_REDIS_DATABASES"

# maxmemory: TEST_REDIS_MAXMEMORY_MB, else ~10% of RAM (min 2048 MB). Embedding-cache SETEXs alone reach ~1.5 GB over a
# full run; noeviction stays so a capacity problem is loud (OOM errors), never silent key loss.
MAXMEM_MB="${TEST_REDIS_MAXMEMORY_MB:-$(awk '/^MemTotal:/ {m=int($2/1024/10); print (m<2048?2048:m)}' /proc/meminfo)}"

# The default user: everything, minus what one lane must never do to the others or to the daemon.
#   instance-wide data loss : flushall swapdb replicaof slaveof failover sync psync replconf cluster
#                             script|flush function|flush function|delete function|restore
#   writes into another db  : move migrate
#   reconfiguration         : config|set config|rewrite config|resetstat acl module
#   stop / disk / debugging : shutdown save bgsave bgrewriteaof debug monitor pfdebug pfselftest
#   other lanes' sessions   : client|kill client|pause script|kill function|kill function|load
ACL_DENY="flushall swapdb replicaof slaveof failover sync psync replconf cluster script|flush function|flush \
function|delete function|restore config|set config|rewrite config|resetstat acl module shutdown save bgsave \
bgrewriteaof debug monitor pfdebug pfselftest client|kill client|pause move migrate script|kill function|kill \
function|load"
ACL_RULE="user default on nopass ~* &* +@all$(for c in $ACL_DENY; do printf ' -%s' "$c"; done)"

conf() {
  cat <<CONF
# managed by scripts/test-redis.sh — rewritten on every start
port $TEST_REDIS_PORT
bind 127.0.0.1
protected-mode yes
daemonize yes
databases $TEST_REDIS_DATABASES
dir $TEST_REDIS_DIR
pidfile $TEST_REDIS_DIR/redis.pid
logfile $TEST_REDIS_DIR/redis.log
save ""
appendonly no
stop-writes-on-bgsave-error no
maxmemory ${MAXMEM_MB}mb
maxmemory-policy noeviction
$ACL_RULE
CONF
}

[ "${1:-}" != "--print-conf" ] || { conf; exit 0; }

rcli() { "$TEST_REDIS_CLI" -h 127.0.0.1 -p "$TEST_REDIS_PORT" "$@"; }
is_running() { [ "$(rcli ping 2>/dev/null || true)" = "PONG" ]; }
running_databases() { rcli config get databases 2>/dev/null | sed -n 2p; }

# The pidfile must name the process that really answers on this port (a stale file, or another daemon that
# took the port, is not "ours"). Prints the verified pid; dies otherwise, with $1 describing what was about to happen.
verify_pidfile() {
  local pid served
  pid="$(tr -dc '0-9' < "$TEST_REDIS_DIR/redis.pid")"
  served="$(rcli info server 2>/dev/null | tr -d '\r' | sed -n 's/^process_id://p')"
  [ -n "$pid" ] && [ "$pid" = "$served" ] && grep -q '^redis-server' "/proc/$pid/comm" 2>/dev/null \
    || die "pidfile ($TEST_REDIS_DIR/redis.pid: ${pid:-empty}) is not the redis-server serving port $TEST_REDIS_PORT (pid ${served:-unknown}); $1"
  echo "$pid"
}

cmd_status() {
  if is_running; then
    echo "running: 127.0.0.1:$TEST_REDIS_PORT ($(running_databases) databases, dir $TEST_REDIS_DIR)"
  else
    echo "stopped: 127.0.0.1:$TEST_REDIS_PORT"
    return 3
  fi
}

cmd_start() {
  command -v "$TEST_REDIS_BIN" >/dev/null 2>&1 || die "redis-server not found (set TEST_REDIS_BIN)"
  command -v "$TEST_REDIS_CLI" >/dev/null 2>&1 || die "redis-cli not found (set TEST_REDIS_CLI)"
  local major; major="$("$TEST_REDIS_BIN" --version | sed -n 's/.* v=\([0-9]*\)\..*/\1/p')"
  [ "${major:-0}" -ge 7 ] || die "redis-server ${major:-unknown}.x is too old: the command-guard ACL rules need Redis >= 7"
  mkdir -p "$TEST_REDIS_DIR"
  chmod 700 "$TEST_REDIS_DIR"
  exec 7>"$TEST_REDIS_DIR/.start.lock"
  flock -w 60 7 || die "another start is still running (lock held > 60s)"

  if is_running; then
    [ -f "$TEST_REDIS_DIR/redis.pid" ] || die "port $TEST_REDIS_PORT answers PING but was not started by this script (no $TEST_REDIS_DIR/redis.pid); pick another TEST_REDIS_PORT"
    verify_pidfile "not reusing it" >/dev/null
    local have; have="$(running_databases)"
    [ "$have" = "$TEST_REDIS_DATABASES" ] \
      || die "already running with $have databases, not $TEST_REDIS_DATABASES; run 'stop' first"
    # A daemon started before the guard existed (or with an older rule) keeps its config until it restarts.
    # The ACL itself cannot be read back (ACL is denied), so the config it was started from is the evidence.
    if ! grep -qxF -- "$ACL_RULE" "$TEST_REDIS_DIR/redis.conf" 2>/dev/null; then
      if grep -q '^user default ' "$TEST_REDIS_DIR/redis.conf" 2>/dev/null; then
        echo "test-redis: WARNING: port $TEST_REDIS_PORT is running an OLDER command guard; run 'stop' then 'start'" >&2
      else
        echo "test-redis: WARNING: port $TEST_REDIS_PORT is running WITHOUT the command guard (FLUSHALL, CONFIG SET, SHUTDOWN are open); run 'stop' then 'start'" >&2
      fi
    fi
    echo "already running on port $TEST_REDIS_PORT ($have databases)"; return 0
  fi
  if (exec 3<>"/dev/tcp/127.0.0.1/$TEST_REDIS_PORT") 2>/dev/null; then
    die "port $TEST_REDIS_PORT is already taken by something that is not answering PING"
  fi

  conf > "$TEST_REDIS_DIR/redis.conf"
  "$TEST_REDIS_BIN" "$TEST_REDIS_DIR/redis.conf" 7>&- >/dev/null \
    || { tail -n 20 "$TEST_REDIS_DIR/redis.log" >&2 2>/dev/null || true; die "redis-server failed to start"; }
  local i
  for i in $(seq 1 50); do is_running && break; sleep 0.1; done
  is_running || { tail -n 20 "$TEST_REDIS_DIR/redis.log" >&2 2>/dev/null || true; die "redis-server did not answer PING"; }
  echo "started: 127.0.0.1:$TEST_REDIS_PORT, $(running_databases) databases, no persistence"
}

cmd_stop() {
  if is_running; then
    [ -f "$TEST_REDIS_DIR/redis.pid" ] || die "port $TEST_REDIS_PORT is not a daemon this script started (no $TEST_REDIS_DIR/redis.pid); not stopping it"
    local pid; pid="$(verify_pidfile "not stopping it")" || exit 1
    # SIGTERM, not SHUTDOWN (which the ACL denies to clients). With `save ""` redis exits without writing.
    grep -q '^redis-server' "/proc/$pid/comm" 2>/dev/null || die "pid $pid is no longer a redis-server; not signalling it"
    kill -TERM "$pid" 2>/dev/null || true
    local i
    for i in $(seq 1 50); do is_running || break; sleep 0.1; done
    is_running && die "daemon on $TEST_REDIS_PORT did not stop"
    echo "stopped"
  else
    echo "not running"
  fi
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  -h|--help|"") sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $1 (start|stop|status|--print-conf)" ;;
esac
