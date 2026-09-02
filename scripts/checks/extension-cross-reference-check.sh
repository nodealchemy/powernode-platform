#!/usr/bin/env bash
# extension-cross-reference-check.sh — gate #9, EXTENSION-to-EXTENSION half.
# =============================================================================
# WHAT THIS EXISTS FOR
#
# CLAUDE.md's isolation invariant is "each extensions/* is self-contained;
# extensions depend on core; core NEVER depends on extensions". The blocking hook
# (.claude/hooks/core-purity-check.sh) and its scan mirror in
# scripts/pattern-validation.sh enforced only the CORE half, because the hook
# carried a wholesale early exit:
#
#     # A file inside an extension may reference its own namespace.
#     [[ "$FILE_PATH" == *"/extensions/"* ]] && exit 0
#
# The comment stated a NARROWER rule than the code implemented. It sanctions a
# file naming its OWN extension; the code exempted every file under extensions/
# from every check, so nothing ever had an opinion on one extension naming
# ANOTHER — including a PUBLIC, MIT, publicly-cloned extension naming a PRIVATE
# one that is absent from public clones. That is the same class of leak the gate
# blocks in core, and it was silently permitted.
#
# This script is the model-agnostic half of the fix (non-Claude executors run the
# scan, not the hook). The hook applies the identical rule at edit time.
#
# THE RULE
#
#   A file inside an extension may name its OWN extension freely, and only its own.
#
#   * naming a DIFFERENT PRIVATE extension  -> always a hit (structural reference
#     in any position, comments included: the private slug is maintainer-private
#     detail that must not ship in a public clone, exactly as for core).
#   * naming a DIFFERENT PUBLIC extension   -> a hit on CODE lines only. A comment
#     or a `defined?(::Ns::Const)` graceful-degradation guard is a sanctioned form,
#     not a dependency — same carve-out the core->public half already makes.
#   * already-committed references are grandfathered, so turning this on does not
#     wedge a committer on a backlog nobody has triaged. TWO ledgers, because they
#     have different publication rules:
#       - .claude/hooks/core-purity-baseline.txt        (tracked) — the ledger the
#         core->public half already uses. Public-safe entries only.
#       - .claude/hooks/core-purity-baseline.local.txt  (gitignored) — every entry in
#         which EITHER half names a private extension: a PATH inside
#         extensions/private/, or a private SLUG after the `|`. The tracked file is
#         published to the PUBLIC mirror, where a private path discloses the
#         extension AND its internal layout and a private slug discloses it
#         outright — exactly the leak class this gate exists to prevent. It is also
#         the right scope, since private extensions are absent from public clones,
#         so those entries are meaningless there. scripts/generate-core-purity-baseline.sh
#         does the routing; this script simply reads both.
#     Shrinking both lists is real isolation-debt reduction.
#
# Names are derived DYNAMICALLY from extensions/* and extensions/private/* on
# disk — none is hardcoded (this script is core, so core-purity applies to it
# too). Core mode (no extensions checked out) is a no-op PASS.
#
# HONEST LIMIT — READ BEFORE TRUSTING A RESULT
#
# The token derived for an extension is its SLUG, PascalCased
# (extensions/private/business -> `Business::`), plus its submodule path and
# import aliases. It deliberately does NOT cover the Ruby namespaces an extension
# actually declares (`Billing::`, `Marketplace::`, ...). That widening was tried
# on the core half and reverted after 23 false-positive blocks, and this script
# inherits the same limitation on purpose: a text grep cannot tell a dependency
# from a prompt string. So a cross-extension coupling written against a
# non-slug namespace is NOT detected here. Those are the AI-judged
# `improve_discovery` scan's territory, not this gate's.
#
# Usage: bash scripts/checks/extension-cross-reference-check.sh [--list]
#   (no args) prints the COUNT of non-grandfathered cross-extension references
#   --list    prints them as "<repo-relative-path>|<other-extension-slug>"
#
# Env:
#   EXT_CROSS_ROOT             repo root to scan (default: this script's repo)
#   EXT_CROSS_IGNORE_BASELINE  set to 1 to report every reference, grandfathered
#                              or not — used by scripts/generate-core-purity-baseline.sh,
#                              which then routes each line to the ledger its PATH belongs in
set -uo pipefail

ROOT="${EXT_CROSS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MODE="${1:-}"
BASELINE=".claude/hooks/core-purity-baseline.txt"
LOCAL_BASELINE=".claude/hooks/core-purity-baseline.local.txt"

cd "$ROOT" 2>/dev/null || { [ "$MODE" = "--list" ] || echo 0; exit 0; }

# Kebab slug -> PascalCase Ruby namespace (supply-chain -> SupplyChain).
pascal() {
  local s="$1" out="" part parts
  IFS='-' read -ra parts <<< "$s"
  for part in "${parts[@]}"; do out+="${part^}"; done
  printf '%s' "$out"
}

# Owning extension slug of a repo-relative path ("" for a core file).
owner_of() {
  local p="$1" s
  case "$p" in
    extensions/private/*/*) s="${p#extensions/private/}"; printf '%s' "${s%%/*}" ;;
    extensions/*/*)         s="${p#extensions/}";         printf '%s' "${s%%/*}" ;;
    *)                      printf '' ;;
  esac
}

# Gitignore status, resolved in the file's OWN git toplevel — exactly as the
# blocking hook resolves it (core-purity-check.sh). Resolving it in the PARENT
# repo instead is wrong twice over, and both ways silently: every extension is a
# SUBMODULE, so `git check-ignore` run at the parent root FATALS on a public
# extension's path ("Pathspec ... is in submodule 'extensions/system'"), and it
# matches the parent's own `/extensions/private/` rule for EVERY private-extension
# file, dropping that entire tree from the scan. That divergence let the scan
# report 0 for files the hook hard-blocks.
is_ignored() {
  local f="$1" abs top
  abs="$ROOT/$f"
  top=$(git -C "$(dirname "$abs")" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$top" ] || return 1
  git -C "$top" check-ignore -q "$abs" 2>/dev/null
}

grandfathered() {
  [ "${EXT_CROSS_IGNORE_BASELINE:-0}" = "1" ] && return 1
  local entry="${1}|${2}" led
  for led in "$BASELINE" "$LOCAL_BASELINE"; do
    [ -r "$led" ] || continue
    grep -Fxq "$entry" "$led" && return 0
  done
  return 1
}

shopt -s nullglob
priv_slugs=()
for d in extensions/private/*/; do priv_slugs+=("$(basename "$d")"); done
pub_slugs=()
for d in extensions/*/; do
  b="$(basename "$d")"
  [ "$b" = "private" ] && continue
  pub_slugs+=("$b")
done
shopt -u nullglob

# No extensions checked out (core mode, source tarball) => nothing to judge.
if [ ${#priv_slugs[@]} -eq 0 ] && [ ${#pub_slugs[@]} -eq 0 ]; then
  [ "$MODE" = "--list" ] || echo 0
  exit 0
fi

SRC_GLOBS=(--include='*.rb' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx')
SKIP_DIRS=(--exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git --exclude-dir=tmp)

findings=""

candidates() {  # $1 = regex — extension source files matching it
  grep -rlE "$1" extensions "${SRC_GLOBS[@]}" "${SKIP_DIRS[@]}" 2>/dev/null || true
}

# --- PRIVATE half: any structural reference counts, comments included. ---------
for slug in "${priv_slugs[@]}"; do
  ns="$(pascal "$slug")"
  pat="(\b${ns}::)|(extensions/private/${slug}\b)|(@ext/${slug}/)|(@${slug}/)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$(owner_of "$f")" = "$slug" ] && continue
    is_ignored "$f" && continue
    grandfathered "$f" "$slug" && continue
    findings+="${f}|${slug}"$'\n'
  done < <(candidates "$pat")
done

# --- PUBLIC half: CODE lines only (comments and `defined?` guards are sanctioned).
for slug in "${pub_slugs[@]}"; do
  ns="$(pascal "$slug")"
  pat="(\b${ns}::)|(extensions/${slug}\b)|(@ext/${slug}/)|(@${slug}/)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$(owner_of "$f")" = "$slug" ] && continue
    is_ignored "$f" && continue
    grandfathered "$f" "$slug" && continue
    # Strip trailing comments, drop whole-line comments and `defined?` guards,
    # then re-match. Mirrors the filter the hook applies to the same half.
    if grep -nE "$pat" "$f" 2>/dev/null \
         | sed -E 's@(#|//|/\*).*$@@' \
         | grep -vE '^[0-9]+:[[:space:]]*$' \
         | grep -vE '^[0-9]+:[[:space:]]*(#|//|\*|/\*)' \
         | grep -v 'defined?' \
         | grep -qE "$pat"; then
      findings+="${f}|${slug}"$'\n'
    fi
  done < <(candidates "$pat")
done

findings=$(printf '%s' "$findings" | grep -v '^$' | sort -u || true)

if [ "$MODE" = "--list" ]; then
  [ -n "$findings" ] && printf '%s\n' "$findings"
  exit 0
fi
[ -z "$findings" ] && echo 0 || printf '%s\n' "$findings" | wc -l
exit 0
