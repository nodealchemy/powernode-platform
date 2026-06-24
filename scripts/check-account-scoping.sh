#!/bin/bash
#
# check-account-scoping.sh — Cross-tenant IDOR regression guard
# =============================================================================
# Flags the anti-pattern that produced 17 cross-tenant IDOR bugs: a user-facing
# api/v1 controller querying an account-scoped model through a BARE CONSTANT
# receiver with a user-supplied id, e.g.
#
#     SomeModel.find(params[:id])           # ← attacker passes any tenant's id
#     SomeModel.find_by(id: params[:id])
#     SomeModel.all                         # ← leaks every tenant's rows
#
# The fix is to scope through the current tenant's association:
#
#     current_account.some_models.find(params[:id])
#
# SCOPE
#   server/app/controllers/api/v1/**/*.rb  — user-facing, JWT/user-authed.
#   EXCLUDES api/v1/internal/**            — worker/server-authed (no tenant ctx).
#
# WHAT COUNTS AS SAFE (NOT flagged)
#   1. A scoped receiver immediately before the constant on the same line
#      (current_account. / current_user. / account. / @account. / scope.) —
#      these are already-scoped chains.
#   2. `Constant.all?` / `.any?` etc. (enumerable predicates) — the `.all`
#      match requires `.all` NOT be followed by an identifier char or `?`/`!`.
#
# BASELINE (avoid alert fatigue) — two complementary opt-outs:
#   (a) Inline annotation: any matched line ENDING with `# scoping-ok: <reason>`
#       is exempt. Use this for NEW, vetted by-design cases (global models,
#       admin-gated cross-account reads, post-find ownership checks). Deliberate
#       and self-documenting — the reason lives next to the code.
#   (b) Allowlist file: scripts/account-scoping-allowlist.txt holds
#       `<relpath>:<sha1-of-trimmed-line>` entries for the CURRENT known-good
#       set. Keyed by line CONTENT hash (not line number) so it survives
#       unrelated edits/line shifts, but any genuine change to a flagged line
#       drops out of the baseline and must be re-vetted.
#
#   Why both: the allowlist seeds a GREEN baseline over the existing vetted
#   tree without touching dozens of files; the annotation is the ergonomic
#   path for future intentional cases. New/unvetted hits match neither and FAIL.
#
# REGENERATE BASELINE (only when you've reviewed every current match):
#       bash scripts/check-account-scoping.sh --update-allowlist
#
# EXIT CODES
#   0  no non-baselined hits (CI-green; the vetted set is allowed)
#   1  one or more NEW/unvetted hits (CI gate trips on regressions only)
#
# Advisory-friendly: pass --warn to always exit 0 (report-only mode).
# =============================================================================

set -uo pipefail

# --- Locate repo root so the script works from any CWD ----------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

CONTROLLERS_DIR="server/app/controllers/api/v1"
ALLOWLIST="scripts/account-scoping-allowlist.txt"

# Color codes (match pattern-validation.sh)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

MODE="check"   # check | update
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

# --- The anti-pattern regexes -----------------------------------------------
# Constant-receiver finder on a user param.
RE_FINDER='\b[A-Z][A-Za-z0-9_:]*\.(find|find_by)\(\s*(params\[|id:\s*params\[)'
# Bare Constant.all — the (?![?!A-Za-z0-9_]) negative lookahead keeps `.all?`,
# `.allow`, `.all_x` etc. from matching; only a true `.all` collection read.
RE_ALL='\b[A-Z][A-Za-z0-9_:]*\.all(?![?!A-Za-z0-9_])'
# A scoped receiver appearing IMMEDIATELY before a capitalized token (the rare
# `current_account.SomeModel.find` shape) — treated as already-scoped.
RE_SCOPED_PREFIX='(current_account|current_user|account|@account|scope)\.[A-Z]'

# --- Collect candidate hits --------------------------------------------------
# Each hit line: <relpath>:<lineno>:<full-line-text>
collect_hits() {
    grep -rnP "${RE_FINDER}" "${CONTROLLERS_DIR}" --include='*.rb' 2>/dev/null
    grep -rnP "${RE_ALL}"    "${CONTROLLERS_DIR}" --include='*.rb' 2>/dev/null
}

# sha1 of the trimmed line content (whitespace-stripped both ends)
content_hash() {
    local line="$1"
    printf '%s' "$line" \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | sha1sum | cut -d' ' -f1
}

# Build the set of currently-flagged hits, filtered for safe/annotated/internal.
# Emits TSV: relpath \t lineno \t hash \t linetext
filtered_hits() {
    collect_hits | sort -u | while IFS=: read -r file lineno rest; do
        # rest is the line text (may itself contain ':')
        local linetext="$rest"

        # Exclude internal/** and worker/** (service-token authed, not user-facing —
        # account context comes from the worker/service identity, scoped there).
        case "$file" in
            "${CONTROLLERS_DIR}/internal/"*) continue ;;
            "${CONTROLLERS_DIR}/worker/"*)   continue ;;
        esac

        # Safe chain: scoped receiver immediately before a constant on the line
        if printf '%s' "$linetext" | grep -qP "${RE_SCOPED_PREFIX}"; then
            continue
        fi

        # Inline opt-out annotation
        if printf '%s' "$linetext" | grep -qP '#\s*scoping-ok:'; then
            continue
        fi

        local h
        h="$(content_hash "$linetext")"
        printf '%s\t%s\t%s\t%s\n' "$file" "$lineno" "$h" "$linetext"
    done
}

# --- Update mode: regenerate the allowlist from the current tree -------------
if [[ "$MODE" == "update" ]]; then
    {
        echo "# Account-scoping IDOR guard — baseline allowlist"
        echo "# Format: <relpath>:<sha1-of-trimmed-line>"
        echo "# Generated by: scripts/check-account-scoping.sh --update-allowlist"
        echo "# These are the CURRENT known-acceptable matches (global models,"
        echo "# admin-gated cross-account, post-find ownership checks). Adding new"
        echo "# entries is deliberate: regenerate only after reviewing each match,"
        echo "# or prefer an inline '# scoping-ok: <reason>' annotation in code."
        filtered_hits | awk -F'\t' '{print $1":"$3}' | sort -u
    } > "${ALLOWLIST}"
    n=$(grep -cvE '^\s*(#|$)' "${ALLOWLIST}")
    echo -e "${GREEN}Wrote ${ALLOWLIST} with ${n} baselined entries.${NC}"
    exit 0
fi

# --- Check mode --------------------------------------------------------------
# Load allowlist (relpath:hash) into a lookup.
declare -A ALLOWED=()
if [[ -f "${ALLOWLIST}" ]]; then
    while IFS= read -r entry; do
        [[ "$entry" =~ ^[[:space:]]*(#|$) ]] && continue
        ALLOWED["$entry"]=1
    done < "${ALLOWLIST}"
fi

new_hits=0
baselined=0

echo -e "${BLUE}=== Cross-tenant account-scoping (IDOR) guard ===${NC}"
echo "Scanning ${CONTROLLERS_DIR} (excluding internal/)"
echo ""

while IFS=$'\t' read -r file lineno hash linetext; do
    [[ -z "$file" ]] && continue
    key="${file}:${hash}"
    if [[ -n "${ALLOWED[$key]:-}" ]]; then
        baselined=$((baselined + 1))
        continue
    fi
    new_hits=$((new_hits + 1))
    trimmed="$(printf '%s' "$linetext" | sed -e 's/^[[:space:]]*//')"
    echo -e "${RED}✗ ${file}:${lineno}${NC}"
    echo "    ${trimmed}"
    echo -e "    ${YELLOW}↳ scope to current_account.<assoc>.find(...) or annotate \`# scoping-ok: <reason>\`${NC}"
    echo ""
done < <(filtered_hits)

echo -e "${BLUE}--- Summary ---${NC}"
echo "Baselined (vetted) matches skipped: ${baselined}"
if [[ "$new_hits" -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS — no new/unvetted account-scoping issues.${NC}"
    exit 0
fi

echo -e "${RED}✗ FAIL — ${new_hits} new/unvetted account-scoping issue(s).${NC}"
echo "  Fix by scoping through the tenant association, or — if vetted —"
echo "  add an inline '# scoping-ok: <reason>' or run --update-allowlist."
if [[ "$WARN_ONLY" -eq 1 ]]; then
    echo -e "${YELLOW}(--warn: reporting only, exiting 0)${NC}"
    exit 0
fi
exit 1
