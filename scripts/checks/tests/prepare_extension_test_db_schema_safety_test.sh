#!/bin/bash
# Red/green test: scripts/prepare-extension-test-db.sh must never write the TRACKED
# server/db/schema.rb.
#
# IMP-01a08cc5: the script ended with `git -C "$REPO" checkout -- server/db/schema.rb`,
# justified as "db:migrate just re-dumped schema.rb in FULL (private) mode". It had not:
# config/initializers/schema_dump_isolation.rb has set
# ActiveRecord.dump_schema_after_migration = false everywhere since 2026-06-20, nine days
# BEFORE the checkout line landed (verified by execution: `SCHEMA=<tmp> RAILS_ENV=test
# bin/rails db:migrate` wrote 0 bytes and left schema.rb's sha unchanged). So the checkout
# restored nothing and did exactly one thing — discard any UNCOMMITTED schema.rb edits,
# which in a checkout shared by concurrent sessions is another session's in-flight
# migration work.
#
# The fix keeps schema.rb out of the script's hands entirely: db:migrate is pointed at a
# throwaway dump sink (SCHEMA=, honoured by ActiveRecord's schema_dump_path) so that even
# if the auto-dump is ever re-enabled, the dump lands in a temp file, and nothing restores
# the tracked file. A snapshot-and-restore was rejected: it races a peer editing schema.rb
# during a multi-minute migrate.
#
# Static by necessity: exercising the script for real drops and rebuilds a test database,
# which is unsafe in a checkout shared with other sessions' lanes.
#
# Usage: bash scripts/checks/tests/prepare_extension_test_db_schema_safety_test.sh
# Exits 0 if all assertions pass, 1 otherwise.

cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" || exit 1

SCRIPT="${PREPARE_SCRIPT_UNDER_TEST:-scripts/prepare-extension-test-db.sh}"
fail=0

# Executable lines only — the header discusses schema.rb and db:migrate at length.
code="$(grep -vE '^[[:space:]]*#' "$SCRIPT")"

echo "=== prepare-extension-test-db.sh never writes the tracked schema.rb ==="

# 1. No git verb that rewrites a working-tree file may name schema.rb.
hits="$(printf '%s\n' "$code" | grep -nE 'git\b.*\b(checkout|restore|reset|stash)\b.*schema\.rb' || true)"
if [[ -n "$hits" ]]; then
    echo "FAIL: a git command rewrites schema.rb (discards uncommitted edits):"
    printf '    %s\n' "$hits"
    fail=1
else
    echo "PASS: no git checkout/restore/reset/stash of schema.rb"
fi

# 2. Every db:migrate must send any schema dump to a sink, never the tracked file.
migrates="$(printf '%s\n' "$code" | grep -E 'bin/rails[^|;&]*\bdb:migrate\b' || true)"
if [[ -z "$migrates" ]]; then
    echo "FAIL: found no db:migrate invocation — the assertion below would be vacuous"
    fail=1
else
    unsunk="$(printf '%s\n' "$migrates" | grep -vE 'SCHEMA="?\$' || true)"
    if [[ -n "$unsunk" ]]; then
        echo "FAIL: db:migrate without a SCHEMA= dump sink:"
        printf '    %s\n' "$unsunk"
        fail=1
    else
        echo "PASS: every db:migrate dumps (if at all) to a SCHEMA= sink"
    fi
fi

echo ""
if [[ $fail -eq 0 ]]; then
    echo "ALL ASSERTIONS PASSED"
else
    echo "ASSERTIONS FAILED"
fi
exit $fail
