#!/bin/bash
# BLOCKING hook (gate #9): enforces CLAUDE.md's isolation invariant — core never
# depends on an extension, and each extension is self-contained, so it may name
# ITS OWN extension and no other. Two scopes, one rule:
#   * a CORE source file (any path NOT under extensions/) may name no extension;
#   * an EXTENSION source file may name only its own slug.
# A *generic* reference to the extensions/ or extensions/private/ directory (the
# decoupling seam) is allowed; naming a specific extension is a leak — its Ruby
# namespace (e.g. `<Namespace>::`), its submodule path (`extensions/private/<slug>`)
# or its import alias (`@ext/<slug>/`, `@<slug>/`).
#
# The extension→extension half was added later (IMP-7beedfd810c4). Before it, this
# hook exited early on ANY path under extensions/, under a comment claiming only
# that "a file inside an extension may reference its own namespace" — so a PUBLIC,
# MIT, publicly-cloned extension naming a PRIVATE one (absent from public clones)
# was silently permitted. Measured on this tree when the half was turned on: 10
# pre-existing references — 2 in a public extension, 8 in a private one — all
# grandfathered, so no committer was wedged on an untriaged backlog. Only 1 of the
# 10 was public-safe enough for the tracked ledger; the other 9 name a private
# extension in one half or the other and live in the gitignored one. The
# model-agnostic mirror is scripts/checks/extension-cross-reference-check.sh, run
# by pattern-validation.sh; the two paths must agree file-for-file, which is what
# server/spec/scripts/core_purity_cross_extension_spec.rb pins.
#
# Private-extension names are derived dynamically from extensions/private/* on
# disk, so this public hook never hardcodes one. Fails OPEN (exit 0) on any
# uncertainty so it can never block an unrelated edit; exits 2 only on a clear,
# structural private-extension reference in a core source file.
#
# SCOPE / KNOWN LIMITATION (do not "fix" by widening the blocklist — it was tried and
# reverted): the namespace token is the extension SLUG, capitalized
# (extensions/private/<slug> -> `<Slug>::`). This intentionally does NOT enforce the
# extension's OWN Ruby namespaces (`Billing::`, `BaaS::`, `Mcp::`, `Marketplace::`, ...).
# A text-grep blocking gate cannot distinguish a real code dependency from a sanctioned
# textual mention: those namespaces legitimately appear in core comments, LLM-prompt
# strings, the blessed `defined?(Billing::X)` runtime guard (db/seeds.rb), the decoupling
# seam's own docs (powernode/billing_bridge.rb), and the purity specs that assert on them.
# Deriving + forbidding them here produced 23 false-positive blocks of legitimate core
# files (verified by adversarial review of the gate-#9 namespace-blindspot tasks). Such
# model-namespace leaks are caught instead by the NON-BLOCKING `improve_discovery` scan,
# whose AI judgment can tell code from comment/guard/spec. Keep this gate to structural
# slug/path/alias references only.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

[[ -z "$FILE_PATH" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

# Only source code can create a code-level dependency.
case "$FILE_PATH" in
  *.rb|*.ts|*.tsx|*.js|*.jsx) ;;
  *) exit 0 ;;
esac

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/opt/powernode}"

# --- Out-of-tree guard: the hook fires on EVERY Write/Edit in a session, including
# files that live OUTSIDE this repository (session-dir orchestration scripts,
# ~/.claude scratch files, other checkouts). Core-purity only constrains THIS
# repo's tree — resolve the git toplevel containing the written file and exit 0
# when it belongs to neither this repo nor one of its extension submodules (or is
# in no git repo at all).
#
# An extension is a SUBMODULE, so its files resolve to a DIFFERENT toplevel nested
# under the project toplevel. That branch used to be irrelevant because everything
# under extensions/ was exempted a few lines earlier; it no longer is (see the
# own-extension note below), so a nested extension toplevel is ACCEPTED and falls
# through to the checks.
FILE_TOPLEVEL=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)
PROJECT_TOPLEVEL=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$FILE_TOPLEVEL" || -z "$PROJECT_TOPLEVEL" ]] \
   || { [[ "$FILE_TOPLEVEL" != "$PROJECT_TOPLEVEL" ]] \
        && [[ "$FILE_TOPLEVEL" != "$PROJECT_TOPLEVEL"/extensions/* ]]; }; then
  # Fail-open ONLY for out-of-repo paths; if the project dir itself has no
  # toplevel (broken env) the mismatch branch also fails open, per the hook's
  # documented fail-open-on-uncertainty doctrine.
  exit 0
fi

# Repo-relative path, used by the own-extension resolution and the baseline lookup.
REL_PATH="${FILE_PATH#$PROJECT_TOPLEVEL/}"
[[ "$REL_PATH" == "$FILE_PATH" ]] && exit 0   # couldn't relativise → fail open

# --- OWN extension ------------------------------------------------------------
# There used to be a wholesale `[[ "$FILE_PATH" == *"/extensions/"* ]] && exit 0`
# here, under a comment reading "a file inside an extension may reference its own
# namespace". The COMMENT stated a narrower rule than the CODE implemented: the
# code exempted every extension file from EVERY check, so the gate only ever
# enforced core → extension and had no opinion on one extension naming ANOTHER —
# including a PUBLIC, MIT, publicly-cloned extension naming a PRIVATE one that is
# absent from public clones. That is the same class of leak this gate blocks in
# core. OWN_EXT now implements the rule the comment always claimed: an extension
# file skips the checks for ITS OWN slug, and only its own.
OWN_EXT=""
case "$REL_PATH" in
  extensions/private/*/*) OWN_EXT="${REL_PATH#extensions/private/}"; OWN_EXT="${OWN_EXT%%/*}" ;;
  extensions/*/*)         OWN_EXT="${REL_PATH#extensions/}";         OWN_EXT="${OWN_EXT%%/*}" ;;
esac

# The grandfather ledgers, shared with scripts/checks/extension-cross-reference-check.sh
# and the pattern-validation mirror. Unreadable => the baseline-gated halves fail open.
#
# There are TWO because they have different publication rules. The tracked file is
# committed to core and published to the PUBLIC mirror, so no entry in it may name
# a private extension in EITHER half — not as a path inside extensions/private/
# (which discloses the name and the internal layout) and not as a slug after the
# `|` (which discloses the name outright). Those live in the gitignored sibling
# instead, which is also where they belong: a public clone has no private
# extension for them to describe.
BASELINE="$PROJECT_DIR/.claude/hooks/core-purity-baseline.txt"
LOCAL_BASELINE="$PROJECT_DIR/.claude/hooks/core-purity-baseline.local.txt"

# Is "<rel-path>|<slug>" grandfathered in either ledger?
is_grandfathered() {
  local entry="$1|$2" led
  for led in "$BASELINE" "$LOCAL_BASELINE"; do
    [[ -r "$led" ]] || continue
    grep -Fxq "$entry" "$led" && return 0
  done
  return 1
}

# Gitignore status, resolved ONCE in the file's OWN toplevel so it is correct
# inside an extension submodule too. Used exactly where the pre-existing gates
# used it — the placement gate and the baseline-backed halves — and NOT widened
# to the absolute core→private rule, which has never had a gitignore carve-out.
IS_IGNORED=0
git -C "$FILE_TOPLEVEL" check-ignore -q "$FILE_PATH" 2>/dev/null && IS_IGNORED=1

# --- Extension-isolation (placement gate): a CORE frontend/src file must not
# live inside a subtree named after an extension (e.g. features/<slug>/,
# shared/services/<slug>/). Such code belongs IN that extension's frontend tree,
# not core. 'system' is allowlisted: core legitimately hosts a distinct
# features/system/storage subfeature that merely shares the name of the public
# 'system' extension. Covers committed core frontend/src AND frontend/cypress;
# assembled extension e2e copies under cypress/ are gitignored and were already
# exempted by the check-ignore above.
#
# CORE ONLY (`-z "$OWN_EXT"`). This gate is about PLACEMENT, and an extension's
# own frontend tree is by definition `extensions/<slug>/frontend/src/...` — every
# path in it contains `/<slug>/`, so running it there would block an extension
# from editing its own UI. It never fired before because extension files exited
# the hook long before reaching it.
if [[ -z "$OWN_EXT" && "$IS_IGNORED" -eq 0 ]] \
   && [[ "$FILE_PATH" == *"/frontend/src/"* || "$FILE_PATH" == *"/frontend/cypress/"* ]]; then
  shopt -s nullglob
  iso_slugs=()
  for d in "$PROJECT_DIR"/extensions/*/; do
    b="$(basename "$d")"
    [[ "$b" == "private" || "$b" == "system" ]] && continue
    iso_slugs+=("$b")
  done
  for d in "$PROJECT_DIR"/extensions/private/*/; do
    iso_slugs+=("$(basename "$d")")
  done
  shopt -u nullglob
  for slug in "${iso_slugs[@]}"; do
    if [[ "$FILE_PATH" == *"/${slug}/"* ]]; then
      {
        echo "BLOCKED (core-purity / gate #9): $FILE_PATH is a CORE file in a '${slug}/' subtree."
        echo "  '${slug}' is an extension — this code belongs in that extension, not core."
        echo "  Move it under extensions/.../${slug}/frontend/ (commit inside the submodule)."
        echo "  Extension app code self-registers via the feature registry; e2e specs are"
        echo "  assembled into core cypress/ at test time by cypress/assemble-extensions.cjs."
      } >&2
      exit 2
    fi
  done
fi

# Derive private-extension names dynamically — never hardcode them here.
shopt -s nullglob
priv_names=()
for d in "$PROJECT_DIR"/extensions/private/*/; do
  [[ -d "$d" ]] || continue
  priv_names+=("$(basename "$d")")
done
shopt -u nullglob
# NO early exit on an empty private set. There used to be one here, and it made
# the PUBLIC block below unreachable on exactly the installs it was written for:
# private extensions are absent from public clones and core-mode installs by
# definition, so `exit 0` here meant the public gate never ran there. It was not
# caught by testing because this machine HAS private extensions, so the early
# exit never fired locally — a check that only works in the configuration it was
# tested in. An empty array simply skips the loop below; that is sufficient.
HITS=""
for name in "${priv_names[@]}"; do
  # A file inside a private extension may name ITS OWN extension, and only its own.
  [[ -n "$OWN_EXT" && "$name" == "$OWN_EXT" ]] && continue
  # An extension → private-extension reference already committed when this half was
  # turned on is grandfathered through the shared ledger. CORE files are NEVER
  # grandfathered against a private extension: that rule is absolute and predates
  # the baseline.
  if [[ -n "$OWN_EXT" ]]; then
    [[ "$IS_IGNORED" -eq 1 ]] && continue
    is_grandfathered "$REL_PATH" "$name" && continue
  fi
  # Kebab slug -> PascalCase namespace, the SAME derivation the public half and the
  # scan mirror use. This was `${name^}` (first letter only), which silently derived
  # `Supply-chain::` for a kebab-slugged private extension and so agreed with the
  # mirror's `SupplyChain::` on nothing.
  cap=""; IFS='-' read -ra _pp <<< "$name"
  for _seg in "${_pp[@]}"; do cap+="${_seg^}"; done
  # Structural references only: namespace ::, submodule path, import alias.
  pat="(\b${cap}::)|(extensions/private/${name}\b)|(@ext/${name}/)|(@${name}/)"
  m=$(grep -nE "$pat" "$FILE_PATH" 2>/dev/null)
  if [[ -n "$m" ]]; then
    HITS+="  [private extension: ${name}]"$'\n'"${m}"$'\n'
  fi
done

if [[ -n "$HITS" ]]; then
  {
    if [[ -n "$OWN_EXT" ]]; then
      echo "BLOCKED (core-purity / gate #9): $FILE_PATH is in the '${OWN_EXT}' extension but names a DIFFERENT, PRIVATE extension."
    else
      echo "BLOCKED (core-purity / gate #9): $FILE_PATH is a CORE file but names a private extension."
    fi
    echo "$HITS"
    echo "Extensions are self-contained: neither core nor another extension may depend on a"
    echo "private one — it is ABSENT from public clones, so naming it breaks them. Either move"
    echo "this logic into that extension, or route through a generic seam (e.g."
    echo "register_extension_tools / a provider) that does not name it."
    echo "Maintainer-only notes that must name a private extension belong in CLAUDE.local.md."
  } >&2
  exit 2
fi

# --- PUBLIC extensions (extensions/<slug>, excluding private/) -----------------
# CLAUDE.md's invariant is "core NEVER depends on extensions" — ALL of them, not
# just private ones. But public extensions cannot use the private rule verbatim:
# a private extension is ABSENT from public clones so naming one is always a leak,
# whereas a public extension is PRESENT, and core legitimately (a) documents the
# seams reaching it, (b) hosts core subtrees sharing its name, and (c) guards its
# constants with `defined?(::System::X)` to degrade gracefully without it.
# Measured 2026-08-12: `System::` was in 48 core files / 143 lines — 61 comment
# lines, 32 `defined?` guards, 14 quoted strings. Blocking that outright would
# reproduce the 23-false-positive revert documented in this file's header.
#
# So: block NEW references, grandfather COMMITTED ones via a baseline generated
# from HEAD (scripts/generate-core-purity-baseline.sh). Work in progress cannot
# grandfather itself, which is the point. Comment lines and `defined?` guards are
# never blocked for any extension — they are sanctioned forms, not dependencies.
# Fails OPEN whenever the baseline is unreadable, per this hook's doctrine.
# ($BASELINE, $REL_PATH and the gitignore exemption are resolved near the top.)
#
# The same rule now covers one extension naming ANOTHER public extension: an
# extension file skips only its OWN slug below.
[[ -r "$BASELINE" ]] || exit 0

# Gitignored files are exempt from this half. Load-bearing rather than cosmetic:
# the baseline is generated from committed state, so a gitignored file can NEVER
# appear in it and could therefore never be grandfathered — permanently blocking
# edits to e.g. the assembled extension e2e copies under frontend/cypress/ that
# the placement gate above deliberately exempts.
[[ "$IS_IGNORED" -eq 1 ]] && exit 0

shopt -s nullglob
pub_names=()
for d in "$PROJECT_DIR"/extensions/*/; do
  b="$(basename "$d")"
  [[ "$b" == "private" ]] && continue
  pub_names+=("$b")
done
shopt -u nullglob

PUB_HITS=""
for name in "${pub_names[@]}"; do
  # A file inside a public extension may name ITS OWN extension, and only its own.
  [[ -n "$OWN_EXT" && "$name" == "$OWN_EXT" ]] && continue
  # Grandfathered for this exact file, in either ledger? Then this slug is not
  # enforced here.
  is_grandfathered "$REL_PATH" "$name" && continue

  # Kebab slug -> PascalCase namespace (supply-chain -> SupplyChain).
  ns=""; IFS='-' read -ra _p <<< "$name"
  for _seg in "${_p[@]}"; do ns+="${_seg^}"; done

  pat="(\b${ns}::)|(extensions/${name}\b)|(@ext/${name}/)|(@${name}/)"
  # Code lines only: never a comment, never a `defined?` guard.
  #
  # NOTE the anchor: grepping ONE file emits "LINE:content" (no path prefix), so
  # this anchors at ^[0-9]+: — not the ":[0-9]+:" form the baseline generator
  # needs for git grep's "path:line:content". Getting that wrong makes the gate
  # block every doc comment; it did once, which is why both forms are tested.
  #
  # The sed STRIPS trailing comments before matching, rather than only skipping
  # whole-line ones. A reference living in `x = y  # see extensions/system` is a
  # doc mention, not a dependency, and blocking it reproduces the false-positive
  # class this file's header records having reverted once. Whole-line forms also
  # allow tabs and the `/*` JSDoc opener, neither of which the old filter matched.
  m=$(grep -nE "$pat" "$FILE_PATH" 2>/dev/null \
        | sed -E 's@(#|//|/\*).*$@@' \
        | grep -vE '^[0-9]+:[[:space:]]*$' \
        | grep -vE '^[0-9]+:[[:space:]]*(#|//|\*|/\*)' \
        | grep -v 'defined?' \
        | grep -E "$pat")
  if [[ -n "$m" ]]; then
    PUB_HITS+="  [public extension: ${name}]"$'\n'"${m}"$'\n'
  fi
done

if [[ -n "$PUB_HITS" ]]; then
  {
    if [[ -n "$OWN_EXT" ]]; then
      echo "BLOCKED (core-purity / gate #9): $FILE_PATH is in the '${OWN_EXT}' extension but names a DIFFERENT public extension."
    else
      echo "BLOCKED (core-purity / gate #9): $FILE_PATH is a CORE file but names a PUBLIC extension."
    fi
    echo "$PUB_HITS"
    echo "Extensions are self-contained — no extension may depend on another, and core must"
    echo "never depend on one either, public ones included. Route through a generic"
    echo "seam (a registry entry, a provider, or data the extension already supplies) instead of"
    echo "naming it. Example: read a value off the signal/event the extension emits rather than"
    echo "querying its model directly."
    echo
    echo "Sanctioned forms are NOT blocked: comment/doc references to a seam, and"
    echo "\`defined?(::Namespace::Const)\` graceful-degradation guards."
    echo
    echo "If this reference is genuinely sanctioned and must persist, it belongs in the baseline —"
    echo "commit it, then run ./scripts/generate-core-purity-baseline.sh. Note the baseline is"
    echo "built from committed state, so this is a deliberate, reviewable act, not an automatic"
    echo "exemption. A file under extensions/private/ is routed by that script to the gitignored"
    echo ".claude/hooks/core-purity-baseline.local.txt — its path must never reach the tracked one."
  } >&2
  exit 2
fi
exit 0
