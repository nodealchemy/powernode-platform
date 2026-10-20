#!/bin/bash
# Red/green test: scripts/prepare-extension-test-db.sh --lanes (IMP-7e1c8b0f4849).
#
# The parallel suite needs N private databases, powernode_test__p1..__pN, on the tmpfs cluster. The
# script's contract for that, checked here:
#   1. --lanes exists, validates every lane name against ^__(p|w<6 hex>p)<N>$ BEFORE anything reaches dropdb
#      (so a worktree lane — 2/3/4, _tmpfs, _<slug>, never containing __ — can never be named), and exits 2 on a bad one;
#   2. it resolves the cluster from Rails ONCE (not once per lane: a Rails boot per lane is most of the
#      cost of preparing N lanes), and the other lanes are CREATE DATABASE ... TEMPLATE clones;
#   3. it refuses any cluster but the tmpfs one;
#   4. the serial core-mode default is untouched (drop/create/schema:load, no golden); only --lanes in
#      core mode uses a golden of its own (powernode_test_golden_core), apart from the private-mode one.
#
# Static plus argument-level checks only: a real multi-lane prep drops and recreates databases, so it is
# opt-in (PREPARE_LIVE_TEST=1, tmpfs cluster running, DATABASE_PORT=5433) and prints the wall time.
#
# Usage: bash scripts/checks/tests/prepare_multi_lane_test.sh
# Exits 0 if all assertions pass, 1 otherwise.

cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" || exit 1

SCRIPT="${PREPARE_SCRIPT_UNDER_TEST:-scripts/prepare-extension-test-db.sh}"
fail=0
code="$(grep -vE '^[[:space:]]*#' "$SCRIPT")"
check() { # check NAME CONDITION-EXIT-CODE
    if [[ "$2" -eq 0 ]]; then echo "PASS: $1"; else echo "FAIL: $1"; fail=1; fi
}

echo "=== prepare-extension-test-db.sh --lanes ==="

printf '%s\n' "$code" | grep -qE -- '--lanes\)'
supports=$?
check "--lanes is a recognised argument" "$supports"

printf '%s\n' "$code" | grep -qF '^__(p|w[0-9a-f]{6}p)[1-9][0-9]*$'
check "lane names are validated against ^__(p|w<6 hex>p)[1-9][0-9]*\$" $?

# Validation must come before the first thing that can reach dropdb/createdb/rails.
val_line="$(printf '%s\n' "$code" | grep -nF '^__(p|w[0-9a-f]{6}p)' | head -1 | cut -d: -f1)"
first_db_line="$(printf '%s\n' "$code" | grep -nE '\b(dropdb|createdb|bin/rails)\b' | head -1 | cut -d: -f1)"
[[ -n "$val_line" && -n "$first_db_line" && "$val_line" -lt "$first_db_line" ]]
check "validation precedes every dropdb/createdb/rails call" $?

runners="$(printf '%s\n' "$code" | grep -c 'PNTESTDB\\t#{c.database}')"
[[ "$runners" -eq 1 ]]
check "the cluster is resolved from Rails exactly once (found $runners resolver call(s))" $?

loop="$(printf '%s\n' "$code" | sed -n '/^for lane in "\${LANES\[@\]}"; do/,/^done/p')"
printf '%s\n' "$loop" | grep -q 'clone_from_golden' && ! printf '%s\n' "$loop" | grep -qE 'bin/rails|schema:load|db:migrate'
check "each lane is a golden-template clone, never a rebuild" $?

printf '%s\n' "$code" | grep -qE 'CLUSTER" != tmpfs' && printf '%s\n' "$code" | grep -q -- '--lanes only runs against the tmpfs'
check "--lanes refuses any cluster but tmpfs" $?

printf '%s\n' "$code" | grep -q 'powernode_test_golden_core'
check "core mode has its own golden template" $?

# The serial core default stays exactly the develop behaviour: an exit-0 drop/create/schema:load block
# that runs only when no lanes were given, before the golden path.
printf '%s\n' "$code" | grep -q 'PRIVATE_VERSIONS\[@\]}" -eq 0 \] && \[ "${#LANES\[@\]}" -eq 0'
check "serial core mode is guarded to the no-lanes case" $?
core_block="$(printf '%s\n' "$code" | sed -n '/-eq 0 \] && \[ "${#LANES/,/^fi/p')"
printf '%s\n' "$core_block" | grep -q 'bin/rails db:drop db:create db:schema:load' && printf '%s\n' "$core_block" | grep -q 'exit 0' && ! printf '%s\n' "$core_block" | grep -qE 'golden|clone_from'
check "serial core mode is drop/create/schema:load with no golden" $?

# TARGET_DB must be exactly the first lane's name (a bare powernode_test via DATABASE_URL must fail).
printf '%s\n' "$code" | grep -qF '[ "$TARGET_DB" = "powernode_test${LANES[0]}" ]'
check "lane 0 is checked by exact name" $?

# Argument-level behaviour. Only run against a script that parses --lanes at all: an older script would
# ignore the flag and go on to drop the live test database.
if [[ "$supports" -eq 0 ]]; then
    # Run a COPY of the script inside a throwaway skeleton whose bin/rails only records that it was
    # reached. If a bad argument were ever accepted, the script would call that stub, never a real
    # database — an earlier version of this test ran the real script with `--lanes ""`, which fell through
    # to a default prep and started a db:drop against a live test database.
    skel="$(mktemp -d "${TMPDIR:-/tmp}/prep-lanes-test.XXXXXX")"
    mkdir -p "$skel/scripts/lib" "$skel/server/bin" "$skel/server/db"
    cp "$SCRIPT" "$skel/scripts/prepare-extension-test-db.sh"
    cp scripts/lib/test-pg.sh "$skel/scripts/lib/test-pg.sh"
    : > "$skel/server/db/schema.rb"
    printf '#!/bin/sh\necho REACHED-RAILS >> "%s/reached"\nexit 99\n' "$skel" > "$skel/server/bin/rails"
    chmod +x "$skel/server/bin/rails"
    run_skel() { (cd "$skel" && env -u TEST_ENV_NUMBER -u DATABASE_PORT -u TEST_REDIS_LANE bash scripts/prepare-extension-test-db.sh "$@" >/dev/null 2>&1); }
    for bad in "_tmpfs" "2" "__p0" "__p1;x" "__p1 _tmpfs" "" " "; do
        run_skel --lanes "$bad"; rc=$?
        [[ "$rc" -eq 2 && ! -e "$skel/reached" ]]
        check "--lanes '$bad' is refused with exit 2 before Rails is touched (rc=$rc)" $?
    done
    run_skel --lanes; rc=$?
    [[ "$rc" -eq 2 && ! -e "$skel/reached" ]]
    check "--lanes with no value is refused (rc=$rc)" $?
    run_skel --bogus; rc=$?
    [[ "$rc" -eq 2 && ! -e "$skel/reached" ]]
    check "an unknown argument is refused with exit 2 (rc=$rc)" $?
    run_skel --lanes "__p1 __p2"; rc=$?
    [[ -e "$skel/reached" ]]
    check "a valid lane list gets past validation (control: the stub rails was reached)" $?
    rm -rf -- "${skel:?}"
else
    echo "FAIL: argument-level checks skipped — the script has no --lanes support to exercise"
    fail=1
fi

if [[ -n "${PREPARE_LIVE_TEST:-}" && "$supports" -eq 0 ]]; then
    echo "=== live: 3 lanes on the tmpfs cluster ==="
    start=$SECONDS
    bash "$SCRIPT" --lanes "__p1 __p2 __p3" >/dev/null 2>&1; rc=$?
    echo "wall: $((SECONDS - start))s"
    [[ "$rc" -eq 0 ]]
    check "live multi-lane prep exits 0" $?
    for l in __p1 __p2 __p3; do
        n="$(psql -h "${TEST_PG_DIR:-/dev/shm/powernode-test-pg16}" -p "${DATABASE_PORT:-5433}" -U "${DATABASE_USER:-powernode}" -d "powernode_test$l" -tAc "select count(*) from information_schema.tables where table_schema='public'" 2>/dev/null)"
        [[ "${n:-0}" -gt 100 ]]
        check "powernode_test$l exists with a full schema (${n:-0} tables)" $?
    done
fi

echo
if [[ "$fail" -eq 0 ]]; then echo "ALL ASSERTIONS PASSED"; else echo "SOME ASSERTIONS FAILED"; fi
exit "$fail"
