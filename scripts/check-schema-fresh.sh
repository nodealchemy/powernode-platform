#!/usr/bin/env bash
# Guard: server/db/schema.rb must reflect the migrations that exist on disk.
#
# WHY A VERSION CHECK IS NOT ENOUGH (IMP-706bda46952c / IMP-fcc896c4c4e8).
# On 2026-08-05 schema.rb declared version 2026_08_05_000000 — NEWER than every
# migration in the tree — while containing NONE of the effects of the three
# 20260804* migrations. A guard comparing only max(version) would have passed:
# the version was ahead, the content was behind. That happened because an
# earlier migration (20260720180000) had its effect applied but its version
# unrecorded, so `db:migrate` cancelled it AND every later migration, and a
# subsequent targeted `db:migrate:up` bumped the dumped version without
# bringing the skipped ones along.
#
# WHAT THIS CHECKS (cheap, read-only, non-circular):
#   1. every migration version on disk (core + extensions) is recorded in
#      schema_migrations of the target database, and
#   2. schema.rb's declared version equals the highest version on disk.
# (1) is the root-cause check: it fires on an unapplied/unrecorded migration
# BEFORE the divergence can reach schema.rb, and it is exactly what would have
# caught this incident. (2) catches a dump taken from a database that is behind.
#
# WHAT THIS CANNOT CHECK, stated plainly so nobody assumes more:
#   - schema.rb being stale while every migration IS applied (a hand-edit, or
#     migrating without dumping). Detecting that requires migrating a scratch
#     database from zero and diffing a fresh dump — a CI job, not this script.
#   - It CANNOT be turned into an rspec spec against the TEST database. That DB
#     is built by prepare-extension-test-db.sh via drop/create/schema:load —
#     loaded FROM schema.rb — so dumping it and comparing to schema.rb is
#     circular and always green. Any future "schema freshness spec" that
#     compares those two is measuring nothing.
#
# Read-only: issues one SELECT, mutates nothing, dumps nothing.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

SCHEMA="server/db/schema.rb"
[ -f "$SCHEMA" ] || { echo "error: $SCHEMA not found" >&2; exit 1; }

# Every migration on disk: core + every extension (public and private).
mapfile -t disk_versions < <(
  find server/db/migrate extensions/*/server/db/migrate -name '[0-9]*_*.rb' 2>/dev/null |
    xargs -r -n1 basename |
    sed -E 's/^([0-9]+)_.*/\1/' |
    sort -u
)

if [ "${#disk_versions[@]}" -eq 0 ]; then
  echo "error: no migrations found on disk — wrong working directory?" >&2
  exit 1
fi

# schema.rb declares define(version: 2026_08_05_000000) — strip the underscores.
declared="$(grep -oE 'define\(version: [0-9_]+\)' "$SCHEMA" | grep -oE '[0-9_]+' | tr -d '_')"
max_disk="${disk_versions[-1]}"

status=0

if [ "$declared" != "$max_disk" ]; then
  echo "schema.rb declares version $declared but the newest migration on disk is $max_disk." >&2
  echo "  A dump taken from a database that has not applied every migration." >&2
  echo "  Fix: run 'bin/rails db:migrate' to completion, then 'bin/rails db:schema:dump'." >&2
  status=1
fi

# Which of those versions the database has actually recorded. Skipped (with a
# clear note) when no database is reachable, so this stays usable in a
# checkout-only context rather than failing for the wrong reason.
recorded="$(cd server && bundle exec rails runner \
  'puts ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations").join("\n")' \
  2>/dev/null || true)"

if [ -z "$recorded" ]; then
  echo "note: no database reachable — checked schema.rb's declared version only." >&2
  exit "$status"
fi

missing=()
for v in "${disk_versions[@]}"; do
  grep -qx "$v" <<<"$recorded" || missing+=("$v")
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Migrations present on disk but NOT recorded in schema_migrations:" >&2
  for v in "${missing[@]}"; do
    file="$(find server/db/migrate extensions/*/server/db/migrate -name "${v}_*.rb" 2>/dev/null | head -1)"
    echo "  $v  ${file:-<file not found>}" >&2
  done
  echo "  'db:migrate' cancels the failing migration AND every later one, so this" >&2
  echo "  is what silently strands newer migrations. Confirm whether each effect is" >&2
  echo "  already present before recording a version — never blanket-insert." >&2
  status=1
fi

exit "$status"
