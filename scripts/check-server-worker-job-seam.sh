#!/bin/bash
#
# check-server-worker-job-seam.sh — server→worker job-seam NameError guard
# =============================================================================
# The server (server/) is a Sidekiq-FREE Rails API; background jobs live in the
# standalone worker (worker/) and are reached ONLY through the HTTP API seam
# (WorkerJobService). A recurring bug class is server code enqueueing a job
# CONSTANT that is not defined anywhere in the server's load path:
#
#     WebhookRetryJob.perform_later(delivery.id)        # ← defined only in worker/
#     DataManagement::ExportProcessingJob.perform_later  # ← defined nowhere
#
# The constant resolves at RUNTIME, so this passes boot/specs that never hit the
# line and then raises NameError in production. The fix is to route through
# WorkerJobService (or another HTTP seam) — never a bare job constant.
#
# WHAT IS FLAGGED
#   A `Const.perform_async|perform_later|perform_at|perform_in(...)` call in
#   server/app/**/*.rb where Const's class/module is NOT defined anywhere on the
#   server's load path (server/app, server/lib, extensions/*/server/app,
#   extensions/private/*/server/app).
#
# WHAT IS SAFE (NOT flagged)
#   1. Whole-line comments (first non-space char is '#').
#   2. Lines self-guarded with `defined?(Const)` on the same line.
#   3. Constants genuinely defined on the server load path (e.g. a mounted
#      engine's ActiveJob) — those cannot NameError.
#
# BASELINE (avoid alert fatigue) — two complementary opt-outs, mirroring
# check-account-scoping.sh:
#   (a) Inline annotation: a matched line containing `# job-seam-ok: <reason>`
#       is exempt (deliberate, self-documenting).
#   (b) Allowlist file: scripts/job-seam-allowlist.txt holds
#       `<relpath>:<sha1-of-trimmed-line>` entries for the CURRENT known set
#       (each is a real latent NameError tracked by its own improvement task).
#       Keyed by line CONTENT hash so it survives line shifts, but any edit to
#       a flagged line drops out of the baseline and must be re-vetted.
#
# REGENERATE BASELINE (only after reviewing every current match):
#       bash scripts/check-server-worker-job-seam.sh --update-allowlist
#
# EXIT CODES
#   0  no non-baselined hits
#   1  one or more NEW/unvetted hits (regression gate)
#
# Advisory-friendly: pass --warn to always exit 0 (report-only mode).
# Overridable for the guard's own tests: JOB_SEAM_SCAN_DIR, JOB_SEAM_DEF_DIRS
# (space-separated definition dirs), JOB_SEAM_ALLOWLIST.
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

SCAN_DIR="${JOB_SEAM_SCAN_DIR:-server/app}"
DEF_DIRS="${JOB_SEAM_DEF_DIRS:-server/app server/lib}"
# Extension engines are on the server load path — their dirs are globbed in
# unless the caller overrode DEF_DIRS (test isolation).
if [[ -z "${JOB_SEAM_DEF_DIRS:-}" ]]; then
    for d in extensions/*/server/app extensions/private/*/server/app; do
        [[ -d "$d" ]] && DEF_DIRS+=" $d"
    done
fi
ALLOWLIST="${JOB_SEAM_ALLOWLIST:-scripts/job-seam-allowlist.txt}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MODE="check"
WARN_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --update-allowlist) MODE="update" ;;
        --warn)             WARN_ONLY=1 ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown arg: $arg" >&2; exit 2 ;;
    esac
done

RE_ENQUEUE='\b[A-Z][A-Za-z0-9_:]*\.(perform_async|perform_later|perform_at|perform_in)\b'

content_hash() {
    printf '%s' "$1" \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | sha1sum | cut -d' ' -f1
}

# Definition lookup with a cache: is <Const> (by its LAST segment) defined as a
# class/module anywhere on the server load path? Matching only the demodulized
# segment is deliberately fail-SAFE for false alarms (any same-named server
# class suppresses the hit) — the gate exists for constants with NO server-side
# definition at all, which is the NameError class.
declare -A DEF_CACHE=()
const_defined_server_side() {
    local const="$1"
    local last="${const##*::}"
    if [[ -n "${DEF_CACHE[$last]:-}" ]]; then
        [[ "${DEF_CACHE[$last]}" == "yes" ]]
        return
    fi
    # shellcheck disable=SC2086
    if grep -rqE "^[[:space:]]*(class|module)[[:space:]]+([A-Za-z0-9_]+::)*${last}\b" ${DEF_DIRS} --include='*.rb' 2>/dev/null; then
        DEF_CACHE[$last]="yes"; return 0
    fi
    DEF_CACHE[$last]="no"; return 1
}

# Emits TSV: relpath \t lineno \t hash \t constant \t linetext
filtered_hits() {
    grep -rnPH "${RE_ENQUEUE}" "${SCAN_DIR}" --include='*.rb' 2>/dev/null | sort -u \
    | while IFS=: read -r file lineno rest; do
        local linetext="$rest"

        # Whole-line comment → not live code.
        local trimmed="${linetext#"${linetext%%[![:space:]]*}"}"
        [[ "$trimmed" == "#"* ]] && continue

        # Inline opt-out annotation.
        printf '%s' "$linetext" | grep -q '#[[:space:]]*job-seam-ok:' && continue

        local const
        const=$(printf '%s' "$linetext" \
            | grep -oP '\b[A-Z][A-Za-z0-9_:]*(?=\.(perform_async|perform_later|perform_at|perform_in)\b)' \
            | head -1)
        [[ -z "$const" ]] && continue
        const="${const#::}"

        # Self-guarded call sites (`X.perform_later if defined?(X)`) are safe.
        printf '%s' "$linetext" | grep -qF "defined?(${const}" && continue
        printf '%s' "$linetext" | grep -qF "defined?(::${const}" && continue

        const_defined_server_side "$const" && continue

        local h
        h="$(content_hash "$linetext")"
        printf '%s\t%s\t%s\t%s\t%s\n' "$file" "$lineno" "$h" "$const" "$linetext"
    done
}

if [[ "$MODE" == "update" ]]; then
    {
        echo "# Server→worker job-seam guard — baseline allowlist"
        echo "# Format: <relpath>:<sha1-of-trimmed-line>"
        echo "# Generated by: scripts/check-server-worker-job-seam.sh --update-allowlist"
        echo "# Each entry is a KNOWN latent NameError (server enqueueing a constant"
        echo "# undefined on its load path), baselined so the gate trips only on NEW"
        echo "# regressions. Fixing a baselined line (route through WorkerJobService)"
        echo "# removes it here on the next --update-allowlist run."
        filtered_hits | awk -F'\t' '{print $1":"$3}' | sort -u
    } > "${ALLOWLIST}"
    n=$(grep -cvE '^\s*(#|$)' "${ALLOWLIST}")
    echo -e "${GREEN}Wrote ${ALLOWLIST} with ${n} baselined entries.${NC}"
    exit 0
fi

declare -A ALLOWED=()
if [[ -f "${ALLOWLIST}" ]]; then
    while IFS= read -r entry; do
        [[ "$entry" =~ ^[[:space:]]*(#|$) ]] && continue
        ALLOWED["$entry"]=1
    done < "${ALLOWLIST}"
fi

new_hits=0
baselined=0

echo -e "${BLUE}=== Server→worker job-seam (NameError) guard ===${NC}"
echo "Scanning ${SCAN_DIR} for bare job-constant enqueues undefined on the server load path"
echo ""

while IFS=$'\t' read -r file lineno hash const linetext; do
    [[ -z "$file" ]] && continue
    key="${file}:${hash}"
    if [[ -n "${ALLOWED[$key]:-}" ]]; then
        baselined=$((baselined + 1))
        continue
    fi
    new_hits=$((new_hits + 1))
    trimmed="$(printf '%s' "$linetext" | sed -e 's/^[[:space:]]*//')"
    echo -e "${RED}✗ ${file}:${lineno}${NC}  (undefined constant: ${const})"
    echo "    ${trimmed}"
    echo -e "    ${YELLOW}↳ ${const} is not defined on the server load path — this raises NameError at"
    echo -e "      runtime. Route through WorkerJobService (HTTP seam), or annotate a vetted"
    echo -e "      case with \`# job-seam-ok: <reason>\`.${NC}"
    echo ""
done < <(filtered_hits)

echo -e "${BLUE}--- Summary ---${NC}"
echo "Baselined (known, improvement-tracked) matches skipped: ${baselined}"
if [[ "$new_hits" -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS — no new server→worker job-seam violations.${NC}"
    exit 0
fi

echo -e "${RED}✗ FAIL — ${new_hits} new server→worker job-seam violation(s).${NC}"
echo "  The server is Sidekiq-free: enqueue via WorkerJobService, never a bare job"
echo "  constant. If vetted, annotate '# job-seam-ok: <reason>' or run --update-allowlist."
if [[ "$WARN_ONLY" -eq 1 ]]; then
    echo -e "${YELLOW}(--warn: reporting only, exiting 0)${NC}"
    exit 0
fi
exit 1
