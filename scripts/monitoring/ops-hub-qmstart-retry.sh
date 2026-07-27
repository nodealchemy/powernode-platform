#!/usr/bin/env bash
# ops-hub-qmstart-retry.sh — auto-retry a failed `qmstart` once storage is confirmed
# back online (RCP v2 campaign, P0-a). Companion to ops-hub-watchdog.sh, but this one
# runs on the Proxmox HYPERVISOR host (dna) itself -- not on the third-party watchdog
# host -- because it needs local `qm`/`pvesm` CLI access. It is the direct fix for the
# 2026-07-21->23 incident: a transient dna-data NFS blip failed a manual `qmstart 104`
# and nothing ever retried it, so ops-hub sat dead for ~2 days until a human noticed.
#
# THIS SCRIPT SHIPS PERMANENTLY DRY-RUN UNTIL AN OPERATOR EXPLICITLY ARMS IT.
# It will NEVER execute `qm start` unless BOTH of the following are true at once:
#   1. it is invoked with the --execute flag, AND
#   2. the marker file $ARM_MARKER_FILE (default /etc/powernode/qmstart-retry.armed)
#      exists.
# The systemd unit shipped alongside this script (ops-hub-qmstart-retry.service) does
# NOT pass --execute, so simply installing the unit is inert/safe -- it only ever logs
# what it would have done. See docs/operations/ops-hub-watchdog.md#arming-qmstart-retry
# for the exact two-step arm procedure. Per the task that produced this file: arming is
# an explicit human sign-off action, not something this increment performs.
#
# LOGIC (level-triggered, not edge-triggered -- see docs for why): on every run,
#   - if the VM is already running, do nothing.
#   - if the VM is stopped AND the configured storage is active, this is a retry
#     candidate. Rate-limited (max $MAX_ATTEMPTS_PER_WINDOW attempts per
#     $WINDOW_SECONDS) so a persistently-broken start doesn't hot-loop forever --
#     after the cap it logs "giving up, needs human" and stops attempting until the
#     window rolls over.
#   - if the VM is stopped and storage is NOT active, there is nothing useful to do
#     yet (storage still down); log and wait for the next run.
#
# Usage: ops-hub-qmstart-retry.sh [--execute] [--reset]
#   --execute  actually run `qm start` when conditions are met AND the arm marker
#              file is present. Without this flag the script only ever logs intent.
#   --reset    clear persisted rate-limit state.
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-/etc/powernode/ops-hub-qmstart-retry.conf}"
if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

# --- defaults (override via CONFIG_FILE) -----------------------------------------
# 600, not 104: ops-hub-A was migrated out of the hand-made 100-114 band, whose
# neighbour at 105 is the production firewall. See
# docs/operations/ops-hub-vmid-migration.md. The deployed unit on dna carries
# Environment=VMID=600; this default only governs a fresh deploy, and getting it
# wrong means this guard silently watches a VM that does not exist.
VMID="${VMID:-600}"
VM_NAME="${VM_NAME:-ops-hub}"
# STORAGE_NAME is the storage whose "active" state gates a retry. This MUST track
# where VM $VMID's disks actually live. It defaulted to dna-data (the NFS export
# implicated in the 2026-07-21 incident) until RCP v2 P0-c migrated ops-hub off NFS
# onto rna-local zfspool `local-data` for INV-6; verified live 2026-07-25 —
# `qm config 104` shows efidisk0/ide2/scsi0 all on local-data. Gating on the old
# NFS export would check a storage the VM no longer uses.
STORAGE_NAME="${STORAGE_NAME:-local-data}"
ARM_MARKER_FILE="${ARM_MARKER_FILE:-/etc/powernode/qmstart-retry.armed}"
STATE_DIR="${STATE_DIR:-/var/lib/powernode-watchdog}"
STATE_FILE="${STATE_DIR}/qmstart-retry.${VMID}.state"
MAX_ATTEMPTS_PER_WINDOW="${MAX_ATTEMPTS_PER_WINDOW:-3}"
WINDOW_SECONDS="${WINDOW_SECONDS:-3600}"
TEXTFILE_COLLECTOR_DIR="${TEXTFILE_COLLECTOR_DIR:-/var/lib/node_exporter/textfile_collector}"
METRIC_FILE="${TEXTFILE_COLLECTOR_DIR}/powernode_ops_hub_qmstart_retry.prom"
SYSLOG_TAG="${SYSLOG_TAG:-powernode-ops-hub-qmstart-retry}"

EXECUTE=0
RESET=0
for arg in "$@"; do
  case "$arg" in
    --execute) EXECUTE=1 ;;
    --reset) RESET=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 64 ;;
  esac
done

mkdir -p "${STATE_DIR}" 2>/dev/null || true

if [[ "${RESET}" -eq 1 ]]; then
  rm -f "${STATE_FILE}"
  echo "rate-limit state reset for vmid ${VMID}"
  exit 0
fi

log() {
  local level="$1"; shift
  logger -t "${SYSLOG_TAG}" -p "daemon.${level}" -- "$*" 2>/dev/null || true
  echo "[$(date -u +%FT%TZ)] ${level}: $*"
}

write_metric() {
  local armed="$1" vm_running="$2" storage_active="$3" attempts_in_window="$4"
  [[ -d "${TEXTFILE_COLLECTOR_DIR}" ]] || return 0
  local tmp="${METRIC_FILE}.tmp.$$"
  {
    echo "# HELP powernode_ops_hub_qmstart_retry_armed Whether the retry is armed to actually execute (1) or dry-run only (0)"
    echo "# TYPE powernode_ops_hub_qmstart_retry_armed gauge"
    echo "powernode_ops_hub_qmstart_retry_armed{vmid=\"${VMID}\"} ${armed}"
    echo "# HELP powernode_ops_hub_vm_running Last-observed qm status (1=running, 0=not running)"
    echo "# TYPE powernode_ops_hub_vm_running gauge"
    echo "powernode_ops_hub_vm_running{vmid=\"${VMID}\"} ${vm_running}"
    echo "# HELP powernode_ops_hub_storage_active Last-observed storage status (1=active, 0=not active)"
    echo "# TYPE powernode_ops_hub_storage_active gauge"
    echo "powernode_ops_hub_storage_active{storage=\"${STORAGE_NAME}\"} ${storage_active}"
    echo "# HELP powernode_ops_hub_qmstart_retry_attempts_in_window Retry attempts in the current rate-limit window"
    echo "# TYPE powernode_ops_hub_qmstart_retry_attempts_in_window gauge"
    echo "powernode_ops_hub_qmstart_retry_attempts_in_window{vmid=\"${VMID}\"} ${attempts_in_window}"
  } > "${tmp}"
  mv -f "${tmp}" "${METRIC_FILE}"
}

# --- load rate-limit state ---------------------------------------------------------
window_start_epoch=0
attempts_in_window=0
if [[ -f "${STATE_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
fi
now_epoch="$(date +%s)"
if (( now_epoch - window_start_epoch > WINDOW_SECONDS )); then
  window_start_epoch="${now_epoch}"
  attempts_in_window=0
fi

# --- determine armed state (both gates required) ------------------------------------
armed=0
if [[ "${EXECUTE}" -eq 1 && -f "${ARM_MARKER_FILE}" ]]; then
  armed=1
fi

# --- query current VM status --------------------------------------------------------
# `qm status <vmid>` prints a line like "status: running" or "status: stopped".
vm_running=0
qm_status_output=""
if command -v qm >/dev/null 2>&1; then
  qm_status_output="$(qm status "${VMID}" 2>&1 || true)"
  [[ "${qm_status_output}" == *"running"* ]] && vm_running=1
else
  log err "qm CLI not found -- this script must run on the Proxmox hypervisor host (dna), not a generic host. Aborting this check cycle."
  write_metric "${armed}" 0 0 "${attempts_in_window}"
  exit 0
fi

if [[ "${vm_running}" -eq 1 ]]; then
  log info "vmid ${VMID} (${VM_NAME}) is already running -- nothing to do"
  write_metric "${armed}" 1 1 "${attempts_in_window}"
  exit 0
fi

# --- query storage status ------------------------------------------------------------
# `pvesm status` prints a table; column 2 is Status (active/inactive/unknown) for the
# row whose first column matches STORAGE_NAME.
storage_active=0
if command -v pvesm >/dev/null 2>&1; then
  storage_line="$(pvesm status 2>/dev/null | awk -v s="${STORAGE_NAME}" '$1==s {print}')"
  if [[ "${storage_line}" == *" active "* ]] || [[ "${storage_line}" =~ [[:space:]]active[[:space:]] ]]; then
    storage_active=1
  fi
else
  log err "pvesm CLI not found -- this script must run on the Proxmox hypervisor host (dna). Aborting this check cycle."
  write_metric "${armed}" 0 0 "${attempts_in_window}"
  exit 0
fi

if [[ "${storage_active}" -eq 0 ]]; then
  log info "vmid ${VMID} (${VM_NAME}) is stopped and storage '${STORAGE_NAME}' is not active yet -- waiting for storage to recover before retrying"
  write_metric "${armed}" 0 0 "${attempts_in_window}"
  exit 0
fi

# --- VM stopped + storage active: this is a retry candidate --------------------------
if (( attempts_in_window >= MAX_ATTEMPTS_PER_WINDOW )); then
  log crit "vmid ${VMID} (${VM_NAME}) is stopped, storage '${STORAGE_NAME}' is active, but ${attempts_in_window} retry attempt(s) already made in this ${WINDOW_SECONDS}s window -- giving up automatically, THIS NEEDS A HUMAN. Not retrying again until the window rolls over."
  write_metric "${armed}" 0 1 "${attempts_in_window}"
  exit 0
fi

if [[ "${armed}" -eq 1 ]]; then
  log crit "ARMED RETRY: vmid ${VMID} (${VM_NAME}) is stopped, storage '${STORAGE_NAME}' is active -- executing: qm start ${VMID}"
  if qm start "${VMID}"; then
    log notice "qm start ${VMID} succeeded (attempt $((attempts_in_window + 1))/${MAX_ATTEMPTS_PER_WINDOW} this window)"
  else
    log err "qm start ${VMID} FAILED (attempt $((attempts_in_window + 1))/${MAX_ATTEMPTS_PER_WINDOW} this window) -- see qm/journal output above"
  fi
  attempts_in_window=$((attempts_in_window + 1))
else
  log warning "DRY-RUN (not armed): would run 'qm start ${VMID}' -- vmid ${VMID} (${VM_NAME}) is stopped and storage '${STORAGE_NAME}' is active. To arm, see docs/operations/ops-hub-watchdog.md#arming-qmstart-retry. (attempt would be $((attempts_in_window + 1))/${MAX_ATTEMPTS_PER_WINDOW} this window)"
  attempts_in_window=$((attempts_in_window + 1))
fi

write_metric "${armed}" 0 1 "${attempts_in_window}"

cat > "${STATE_FILE}" <<EOF
window_start_epoch=${window_start_epoch}
attempts_in_window=${attempts_in_window}
EOF

exit 0
