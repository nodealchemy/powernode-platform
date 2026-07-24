#!/usr/bin/env bash
# ops-hub-watchdog.sh — external dead-node probe for ops-hub (RCP v2 campaign, P0-a).
#
# WHY THIS EXISTS (see /home/rett/.claude/plans/campaign-reciprocal-control-plane.md
# and platform memory ops-hub-unmonitored-after-self-repoint / ops-hub-lkg-self-pointed-dns-brick-risk):
# since ops-hub (VM104) was repointed to its own platform_url, it heartbeats ONLY to
# itself. Dev's own NodeInstance table for ops-hub is stale/terminated and alerts
# nothing. The 2026-07-21->23 incident (dna-data NFS blip failed a manual `qmstart 104`,
# nothing retried, node down ~2 days unnoticed) happened precisely because no
# INDEPENDENT third party was watching. This script is that third party: it must run
# on a host that is NOT ops-hub itself (self-monitoring is the exact anti-pattern this
# campaign exists to eliminate) and ideally not on dna either (dna dying takes ops-hub
# down WITH it, so a dna-local monitor can't see a whole-host failure — though it CAN
# still catch the actual 2026-07-21 scenario, where dna/storage were fine and only the
# VM was down; see docs/operations/ops-hub-watchdog.md for the placement discussion).
#
# WHAT IT DOES: polls ops-hub's /up endpoint (falls back to ICMP ping to distinguish
# "host unreachable" from "host up, app down") on a short interval via the companion
# systemd timer. Requires N consecutive failures before alerting (debounces a single
# transient blip -- the same kind of blip that triggered the real incident's storage
# hiccup, so we don't want to page on a single dropped packet). Alerts through three
# channels that degrade gracefully if the operator hasn't wired up the fancier ones:
#   1. journald/syslog CRITICAL line (always works, zero dependencies)
#   2. Prometheus textfile-collector metric (if the collector dir exists) so
#      Grafana/Prometheus alerting -- the platform's documented alerting layer,
#      see docs/operations/observability.md -- can page on it once a rule is added
#   3. optional HTTP webhook callback (operator-provisioned URL/token; no-op if unset)
#
# Exit code is always 0 (this runs from a timer; a nonzero exit would just show up as
# a failed systemd unit, which is a weaker signal than the alert channels above).
#
# Usage: ops-hub-watchdog.sh [--once] [--reset]
#   --once   run a single check cycle (default; the timer calls it this way)
#   --reset  clear persisted state (consecutive-failure count, alert-sent flag)
#
# Config: sourced from $CONFIG_FILE if present (systemd passes
# EnvironmentFile=-/etc/powernode/ops-hub-watchdog.conf so absence is not an error).
# All variables below can be overridden there.
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/powernode/ops-hub-watchdog.conf}"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

# --- defaults (override via CONFIG_FILE) -----------------------------------------
TARGET_NAME="${TARGET_NAME:-ops-hub}"
TARGET_URL="${TARGET_URL:-https://ops-hub.ipnode.us/up}"
TARGET_PING_HOST="${TARGET_PING_HOST:-ops-hub.ipnode.us}"
# 3s: tight enough that 3 consecutive failures at a 15s timer cadence (see the
# companion .timer unit) stays comfortably under the 2-minute detection SLA even in
# the worst case where every check times out fully -- see docs/operations/ops-hub-watchdog.md#detection-timing-budget.
CONNECT_TIMEOUT_SECONDS="${CONNECT_TIMEOUT_SECONDS:-3}"
FAILURE_THRESHOLD="${FAILURE_THRESHOLD:-3}"
STATE_DIR="${STATE_DIR:-/var/lib/powernode-watchdog}"
TEXTFILE_COLLECTOR_DIR="${TEXTFILE_COLLECTOR_DIR:-/var/lib/node_exporter/textfile_collector}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
ALERT_WEBHOOK_TOKEN="${ALERT_WEBHOOK_TOKEN:-}"
SYSLOG_TAG="${SYSLOG_TAG:-powernode-ops-hub-watchdog}"

STATE_FILE="${STATE_DIR}/${TARGET_NAME}.state"
# Parameterized by TARGET_NAME (matching STATE_FILE above) so a second concurrent
# instance monitoring a different target (e.g. TARGET_NAME=ops-hub-b once P1-a stands
# it up) writes its own file instead of clobbering this one on every run. node_exporter's
# textfile collector scrapes every *.prom file in the directory, so multiple files is
# the supported, correct pattern -- not a workaround.
METRIC_FILE="${TEXTFILE_COLLECTOR_DIR}/powernode_ops_hub_watchdog_${TARGET_NAME}.prom"

# --- arg parsing -------------------------------------------------------------------
RESET=0
for arg in "$@"; do
  case "$arg" in
    --reset) RESET=1 ;;
    --once) : ;; # default behavior, accepted for clarity/documentation
    *) echo "unknown argument: $arg" >&2; exit 64 ;;
  esac
done

mkdir -p "${STATE_DIR}" 2>/dev/null || true

if [[ "${RESET}" -eq 1 ]]; then
  rm -f "${STATE_FILE}"
  echo "state reset for ${TARGET_NAME}"
  exit 0
fi

# --- load persisted state (consecutive failures, whether we've already alerted) ---
consecutive_failures=0
already_alerted=0
if [[ -f "${STATE_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
fi

log() {
  local level="$1"; shift
  logger -t "${SYSLOG_TAG}" -p "daemon.${level}" -- "$*" 2>/dev/null || true
  echo "[$(date -u +%FT%TZ)] ${level}: $*"
}

write_metric() {
  # Prometheus textfile-collector format. Only written if the collector dir already
  # exists -- we do not create Prometheus/node_exporter's directory tree ourselves,
  # that is the operator's deploy (docs/operations/observability.md).
  local up_value="$1" failures="$2"
  [[ -d "${TEXTFILE_COLLECTOR_DIR}" ]] || return 0
  local tmp="${METRIC_FILE}.tmp.$$"
  {
    echo "# HELP powernode_ops_hub_up External watchdog view of ops-hub reachability (1=up, 0=down)"
    echo "# TYPE powernode_ops_hub_up gauge"
    echo "powernode_ops_hub_up{target=\"${TARGET_NAME}\"} ${up_value}"
    echo "# HELP powernode_ops_hub_watchdog_consecutive_failures Consecutive failed checks"
    echo "# TYPE powernode_ops_hub_watchdog_consecutive_failures gauge"
    echo "powernode_ops_hub_watchdog_consecutive_failures{target=\"${TARGET_NAME}\"} ${failures}"
    echo "# HELP powernode_ops_hub_watchdog_last_check_timestamp_seconds Unix time of last check"
    echo "# TYPE powernode_ops_hub_watchdog_last_check_timestamp_seconds gauge"
    echo "powernode_ops_hub_watchdog_last_check_timestamp_seconds $(date +%s)"
  } > "${tmp}"
  mv -f "${tmp}" "${METRIC_FILE}"
}

send_webhook() {
  # Best-effort, optional third alert channel. No-op unless the operator has set
  # ALERT_WEBHOOK_URL in CONFIG_FILE. Deliberately generic (any JSON-accepting
  # webhook receiver) rather than assuming a specific external alerting service --
  # see docs/operations/ops-hub-watchdog.md for the platform-notification-API
  # integration option that was investigated but needs an operator-provisioned
  # service credential to wire up safely.
  local message="$1"
  [[ -n "${ALERT_WEBHOOK_URL}" ]] || return 0
  local auth_header=()
  [[ -n "${ALERT_WEBHOOK_TOKEN}" ]] && auth_header=(-H "Authorization: Bearer ${ALERT_WEBHOOK_TOKEN}")
  curl -fsS -m 10 -X POST "${ALERT_WEBHOOK_URL}" \
    -H "Content-Type: application/json" \
    "${auth_header[@]}" \
    -d "{\"text\":\"${message}\"}" \
    >/dev/null 2>&1 || log warning "webhook delivery failed (non-fatal, other alert channels still fired)"
}

# --- the actual check ---------------------------------------------------------------
http_code="000"
http_code="$(curl -s -o /dev/null -w '%{http_code}' -k \
  --connect-timeout "${CONNECT_TIMEOUT_SECONDS}" --max-time "${CONNECT_TIMEOUT_SECONDS}" \
  "${TARGET_URL}" 2>/dev/null || echo "000")"

ping_ok=0
if ping -c1 -W"${CONNECT_TIMEOUT_SECONDS}" "${TARGET_PING_HOST}" >/dev/null 2>&1; then
  ping_ok=1
fi

if [[ "${http_code}" =~ ^2 ]]; then
  # --- healthy ---
  if [[ "${already_alerted}" -eq 1 ]]; then
    log notice "RECOVERED: ${TARGET_NAME} ${TARGET_URL} is back (http ${http_code}) after ${consecutive_failures} failed check(s)"
    send_webhook "RECOVERED: ${TARGET_NAME} is back (http ${http_code})"
  fi
  consecutive_failures=0
  already_alerted=0
  write_metric 1 0
else
  # --- failed check ---
  consecutive_failures=$((consecutive_failures + 1))
  reachability="host unreachable (no ping response either)"
  [[ "${ping_ok}" -eq 1 ]] && reachability="host answers ping but /up returned http=${http_code} (app-level failure, not a dead VM)"

  if [[ "${consecutive_failures}" -ge "${FAILURE_THRESHOLD}" ]]; then
    if [[ "${already_alerted}" -eq 0 ]]; then
      log crit "ALERT: ${TARGET_NAME} DOWN -- ${consecutive_failures} consecutive failed checks, ${reachability}. Investigate via dna's Proxmox provider (qm status 104) before any action -- see docs/operations/ops-hub-watchdog.md."
      send_webhook "ALERT: ${TARGET_NAME} DOWN (${consecutive_failures} consecutive failures) -- ${reachability}"
      already_alerted=1
    else
      log warning "still down: ${TARGET_NAME} (${consecutive_failures} consecutive failures) -- ${reachability}"
    fi
  else
    log info "check failed (${consecutive_failures}/${FAILURE_THRESHOLD}, not yet alerting): ${reachability}"
  fi
  write_metric 0 "${consecutive_failures}"
fi

cat > "${STATE_FILE}" <<EOF
consecutive_failures=${consecutive_failures}
already_alerted=${already_alerted}
EOF

exit 0
