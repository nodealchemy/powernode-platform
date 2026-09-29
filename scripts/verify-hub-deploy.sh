#!/usr/bin/env bash
#
# verify-hub-deploy.sh — one remote call that answers "is the hub running what we just landed?"
#
# Replaces the four hand-run checks (rails ActiveEnterTimestamp vs boot time, /up, /etc/passwd,
# is-the-sha-deployed) with a single small JSON document, and exits non-zero when any check fails.
#
# Usage:
#   scripts/verify-hub-deploy.sh <core_sha> [ext_sha] [--since <epoch|date-string>]
#   scripts/verify-hub-deploy.sh --help
#
# Output (stdout, one JSON object, no secrets, a few hundred bytes):
#   { rails_unit, rails_active_enter, host_boot, rails_restarted_after_boot, up_status,
#     passwd_lines, core_present, ext_present, failed_units, checks:{...}, ok }
#   *_active_enter / host_boot are epoch seconds. core_present / ext_present are null when the
#   corresponding sha was not asked for.
#
# Checks (all must hold; failing ones are listed on stderr, exit 1):
#   rails_active        the rails unit is active
#   restarted_after_boot rails ActiveEnterTimestamp is later than host boot — a rails that has not
#                       restarted since boot cannot be running code delivered after boot. With
#                       --since it must also be at or after that moment (the deploy). Do NOT
#                       substitute NRestarts: a manual restart resets it.
#   up_ok               GET <up url> answers 200 (rails returns 502 for ~30s after a restart)
#   passwd_ok           /etc/passwd has at least HUB_PASSWD_MIN_LINES lines (an empty render
#                       once left the hub unable to start rails)
#   core_present / ext_present   the deployed sha matches (prefix compare either way)
#   no_failed_units     no failed powernode-* systemd unit
# Exit: 0 all green, 1 a check failed, 2 configuration / usage problem, 3 the hub could not be asked
# (transport failure, timeout, unparseable answer: nothing was verified, retrying is sensible).
# A sha must be 12-40 hex characters, and the hub's answer is only its first token of that shape.
# HUB_EXEC_CMD and HUB_*_SHA_CMD run verbatim: they are trusted operator configuration.
#
# Access and deployment facts come from local configuration, never from this file
# (see scripts/lib/landing-common.sh and scripts/landing.env.example):
#   HUB_EXEC_CMD           REQUIRED. A command that runs the bash script it reads on STDIN on the
#                          hub with the privilege needed to read the unit state, and prints that
#                          script's stdout (e.g. an ssh invocation of `bash -s`).
#   HUB_EXEC_UNWRAP        optional: `qga-json` when the transport wraps stdout in the guest-agent
#                          JSON envelope ({"out-data": "..."}); default: none.
#   HUB_RAILS_UNIT         optional: exact rails unit. Default: discovered from
#                          `powernode-*-rails.service` on the hub (never guess a unit name).
#   HUB_UP_URL             optional, default http://127.0.0.1:3000/up (as seen ON the hub).
#   HUB_CORE_SHA_CMD       command run on the hub that prints the deployed core sha.  Required
#   HUB_EXT_SHA_CMD        ...and the extension sha, when that sha is asked for. Not faked: with no
#                          command configured the run stops with exit 2.
#   HUB_PASSWD_FILE / HUB_PASSWD_MIN_LINES   default /etc/passwd / 10.
#   HUB_EXEC_TIMEOUT       seconds for the whole remote call, default 90.

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/landing-common.sh
. "$SELF_DIR/lib/landing-common.sh"

case "${1:-}" in -h|--help|"") sed -n '2,/^set -euo/{/^set -euo/!p}' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

CORE_SHA=""; EXT_SHA=""; SINCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="${2:-}"; [ -n "$SINCE" ] || LC_DIE_CODE=2 lc_die "--since needs a value"; shift 2 ;;
    -*) LC_DIE_CODE=2 lc_die "unknown option: $1" ;;
    *) if [ -z "$CORE_SHA" ]; then CORE_SHA="$1"; elif [ -z "$EXT_SHA" ]; then EXT_SHA="$1"; else LC_DIE_CODE=2 lc_die "unexpected argument: $1"; fi; shift ;;
  esac
done
[[ "$CORE_SHA" =~ ^[0-9a-fA-F]{12,40}$ ]] || LC_DIE_CODE=2 lc_die "core_sha must be 12-40 hex characters (a shorter one would match too much)"
[ -z "$EXT_SHA" ] || [[ "$EXT_SHA" =~ ^[0-9a-fA-F]{12,40}$ ]] || LC_DIE_CODE=2 lc_die "ext_sha must be 12-40 hex characters"
CORE_SHA="${CORE_SHA,,}"; EXT_SHA="${EXT_SHA,,}"

lc_load_config "$(lc_repo_root)"
lc_require HUB_EXEC_CMD HUB_CORE_SHA_CMD
[ -z "$EXT_SHA" ] || lc_require HUB_EXT_SHA_CMD

SINCE_EPOCH=""
if [ -n "$SINCE" ]; then
  if [[ "$SINCE" =~ ^[0-9]+$ ]]; then SINCE_EPOCH="$SINCE"; else SINCE_EPOCH="$(date -d "$SINCE" +%s 2>/dev/null)" || LC_DIE_CODE=2 lc_die "--since is neither an epoch nor a date: $SINCE"; fi
fi

# The remote program. Everything it prints is a fixed-shape JSON line built from numbers, booleans and
# unit names filtered to [A-Za-z0-9_.@-]; it never echoes environment, files or command output verbatim.
build_remote() {
  cat <<REMOTE
set +e
unit=$(printf '%q' "${HUB_RAILS_UNIT:-}")
if [ -z "\$unit" ]; then
  unit=\$(systemctl list-units 'powernode-*-rails.service' --no-legend --plain 2>/dev/null | awk 'NR==1{print \$1}')
fi
unit=\$(printf '%s' "\$unit" | tr -cd 'A-Za-z0-9_.@-')
active=false
[ -n "\$unit" ] && [ "\$(systemctl is-active "\$unit" 2>/dev/null)" = active ] && active=true
enter_ts=\$(systemctl show -p ActiveEnterTimestamp --value "\$unit" 2>/dev/null)
enter=0; [ -n "\$enter_ts" ] && enter=\$(date -d "\$enter_ts" +%s 2>/dev/null); enter=\${enter:-0}
boot=\$(date -d "\$(uptime -s 2>/dev/null)" +%s 2>/dev/null); boot=\${boot:-0}
up=\$(curl -s -o /dev/null -m 10 -w '%{http_code}' $(printf '%q' "${HUB_UP_URL:-http://127.0.0.1:3000/up}") 2>/dev/null); up=\${up:-0}
passwd=\$(wc -l < $(printf '%q' "${HUB_PASSWD_FILE:-/etc/passwd}") 2>/dev/null | tr -d ' '); passwd=\${passwd:-0}
core_out=\$( ( ${HUB_CORE_SHA_CMD} ) 2>/dev/null | head -n 1 | awk '{print \$1}' | tr 'A-F' 'a-f' | grep -E '^[0-9a-f]{12,40}\$')
ext_out=\$( ( ${HUB_EXT_SHA_CMD:-true} ) 2>/dev/null | head -n 1 | awk '{print \$1}' | tr 'A-F' 'a-f' | grep -E '^[0-9a-f]{12,40}\$')
failed=\$(systemctl list-units 'powernode-*' --state=failed --no-legend --plain 2>/dev/null | awk '{print \$1}' | tr -cd 'A-Za-z0-9_.@\n-' | head -n 20)
fj=""
for u in \$failed; do fj="\${fj:+\$fj,}\"\$u\""; done
printf '{"rails_unit":"%s","rails_active":%s,"rails_active_enter":%s,"host_boot":%s,"up_status":%s,"passwd_lines":%s,"core_sha":"%s","ext_sha":"%s","failed_units":[%s]}\n' \
  "\$unit" "\$active" "\$enter" "\$boot" "\$up" "\$passwd" "\$core_out" "\$ext_out" "\$fj"
REMOTE
}

raw="$(mktemp)"; trap 'rm -f "$raw"' EXIT
# shellcheck disable=SC2086
if ! build_remote | timeout "${HUB_EXEC_TIMEOUT:-90}" bash -c "$HUB_EXEC_CMD" >"$raw" 2>/dev/null; then
  LC_DIE_CODE=3 lc_die "the hub call failed (transport error or timeout); nothing was verified"
fi

case "${HUB_EXEC_UNWRAP:-}" in
  qga-json) payload="$(jq -r '."out-data" // empty' <"$raw" 2>/dev/null || true)" ;;
  ""|none)  payload="$(cat "$raw")" ;;
  *) LC_DIE_CODE=2 lc_die "unknown HUB_EXEC_UNWRAP: $HUB_EXEC_UNWRAP" ;;
esac
line="$(printf '%s\n' "$payload" | command grep -E '^\{"rails_unit"' | tail -n 1 || true)"
[ -n "$line" ] && printf '%s' "$line" | jq -e . >/dev/null 2>&1 || LC_DIE_CODE=3 lc_die "the hub returned no parseable result; nothing was verified"

result="$(printf '%s' "$line" | jq -c \
  --arg core "$CORE_SHA" --arg ext "$EXT_SHA" --arg since "$SINCE_EPOCH" \
  --argjson min "${HUB_PASSWD_MIN_LINES:-10}" '
  # Both sides are full or >= 12-character hex; the shorter must prefix the longer. The hub side is
  # already filtered to that shape, so garbled or short output is "" and matches nothing.
  def matches($want; $have): ($want | length) >= 12 and ($have | length) >= 12 and
    ((($have | length) >= ($want | length) and ($have | startswith($want))) or
     (($want | length) > ($have | length) and ($want | startswith($have))));
  . as $r
  | ($r.rails_active_enter > $r.host_boot and $r.rails_active_enter > 0
     and (($since == "") or ($r.rails_active_enter >= ($since | tonumber)))) as $restarted
  | {
      rails_unit: $r.rails_unit,
      rails_active_enter: $r.rails_active_enter,
      host_boot: $r.host_boot,
      rails_restarted_after_boot: $restarted,
      up_status: $r.up_status,
      passwd_lines: $r.passwd_lines,
      core_present: (if $core == "" then null else matches($core; $r.core_sha) end),
      ext_present: (if $ext == "" then null else matches($ext; $r.ext_sha) end),
      failed_units: $r.failed_units
    }
  | .checks = {
      rails_active: ($r.rails_active),
      restarted_after_boot: .rails_restarted_after_boot,
      up_ok: (.up_status == 200),
      passwd_ok: (.passwd_lines >= $min),
      core_present: (.core_present != false),
      ext_present: (.ext_present != false),
      no_failed_units: (.failed_units | length == 0)
    }
  | .ok = (.checks | all(.))')"

printf '%s\n' "$result"
if [ "$(printf '%s' "$result" | jq -r .ok)" != "true" ]; then
  failing="$(printf '%s' "$result" | jq -r '[.checks | to_entries[] | select(.value != true) | .key] | join(", ")')"
  lc_info "verification FAILED: $failing"
  exit 1
fi
lc_info "verification passed"
