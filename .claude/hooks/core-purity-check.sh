#!/bin/bash
# BLOCKING hook (gate #9): bars a CORE source file from referencing a SPECIFIC
# private extension. Core = any path NOT under extensions/. A *generic* reference
# to the extensions/ or extensions/private/ directory (the decoupling seam) is
# allowed; naming a specific private extension is a leak — its Ruby namespace
# (e.g. `<Namespace>::`), its submodule path (`extensions/private/<slug>`) or its
# import alias (`@ext/<slug>/`, `@<slug>/`).
#
# Private-extension names are derived dynamically from extensions/private/* on
# disk, so this public hook never hardcodes one. Fails OPEN (exit 0) on any
# uncertainty so it can never block an unrelated edit; exits 2 only on a clear,
# structural private-extension reference in a core source file.
#
# SCOPE / KNOWN LIMITATION (do not "fix" by widening the blocklist — it was tried and
# reverted): the namespace token is the extension SLUG, capitalized
# (extensions/private/business -> `Business::`). This intentionally does NOT enforce the
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

# A file inside an extension may reference its own namespace.
[[ "$FILE_PATH" == *"/extensions/"* ]] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/opt/powernode}"

# --- Out-of-tree guard: the hook fires on EVERY Write/Edit in a session, including
# files that live OUTSIDE this repository (session-dir orchestration scripts,
# ~/.claude scratch files, other checkouts). Core-purity only constrains THIS
# repo's core tree — resolve the git toplevel containing the written file and
# exit 0 on a mismatch (or when the file isn't inside any git repo). Files inside
# an in-repo submodule were already exempted by the extensions/ check above, so
# a submodule's different toplevel can't weaken the gate here. Full strictness
# is preserved for every in-repo core path (toplevels match → fall through).
FILE_TOPLEVEL=$(git -C "$(dirname "$FILE_PATH")" rev-parse --show-toplevel 2>/dev/null)
PROJECT_TOPLEVEL=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$FILE_TOPLEVEL" || "$FILE_TOPLEVEL" != "$PROJECT_TOPLEVEL" ]]; then
  # Fail-open ONLY for out-of-repo paths; if the project dir itself has no
  # toplevel (broken env) the mismatch branch also fails open, per the hook's
  # documented fail-open-on-uncertainty doctrine.
  exit 0
fi

# --- Extension-isolation (placement gate): a CORE frontend/src file must not
# live inside a subtree named after an extension (e.g. features/<slug>/,
# shared/services/<slug>/). Such code belongs IN that extension's frontend tree,
# not core. Files under extensions/ were already exempted above. 'system' is
# allowlisted: core legitimately hosts a distinct features/system/storage
# subfeature that merely shares the name of the public 'system' extension.
# Covers committed core frontend/src AND frontend/cypress; assembled extension
# e2e copies under cypress/ are gitignored, so check-ignore exempts them.
if [[ "$FILE_PATH" == *"/frontend/src/"* || "$FILE_PATH" == *"/frontend/cypress/"* ]] \
   && ! git -C "$PROJECT_DIR" check-ignore -q "$FILE_PATH" 2>/dev/null; then
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
  cap="${name^}"
  # Structural references only: namespace ::, submodule path, import alias.
  pat="(\b${cap}::)|(extensions/private/${name}\b)|(@ext/${name}/)|(@${name}/)"
  m=$(grep -nE "$pat" "$FILE_PATH" 2>/dev/null)
  if [[ -n "$m" ]]; then
    HITS+="  [private extension: ${name}]"$'\n'"${m}"$'\n'
  fi
done

if [[ -n "$HITS" ]]; then
  {
    echo "BLOCKED (core-purity / gate #9): $FILE_PATH is a CORE file but names a private extension."
    echo "$HITS"
    echo "Core must never depend on a private extension. Either move this logic into the extension,"
    echo "or route through a generic seam (e.g. register_extension_tools / a provider) that does not name it."
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
BASELINE="$PROJECT_DIR/.claude/hooks/core-purity-baseline.txt"
[[ -r "$BASELINE" ]] || exit 0

REL_PATH="${FILE_PATH#$PROJECT_TOPLEVEL/}"
[[ "$REL_PATH" == "$FILE_PATH" ]] && exit 0   # couldn't relativise → fail open

# Gitignored files are exempt, matching the placement gate above and the
# pattern-validation mirror. Load-bearing rather than cosmetic: the baseline is
# generated with `git grep HEAD`, so a gitignored file can NEVER appear in it and
# could therefore never be grandfathered — permanently blocking edits to e.g. the
# assembled extension e2e copies under frontend/cypress/ that this same hook
# deliberately exempts a few lines earlier.
git -C "$PROJECT_DIR" check-ignore -q "$FILE_PATH" 2>/dev/null && exit 0

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
  # Grandfathered for this exact file? Then this slug is not enforced here.
  grep -Fxq "${REL_PATH}|${name}" "$BASELINE" && continue

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
    echo "BLOCKED (core-purity / gate #9): $FILE_PATH is a CORE file but names a PUBLIC extension."
    echo "$PUB_HITS"
    echo "Core must never depend on an extension — public ones included. Route through a generic"
    echo "seam (a registry entry, a provider, or data the extension already supplies) instead of"
    echo "naming it. Example: read a value off the signal/event the extension emits rather than"
    echo "querying its model directly."
    echo
    echo "Sanctioned forms are NOT blocked: comment/doc references to a seam, and"
    echo "\`defined?(::Namespace::Const)\` graceful-degradation guards."
    echo
    echo "If this reference is genuinely sanctioned and must persist, it belongs in the baseline —"
    echo "commit it, then run ./scripts/generate-core-purity-baseline.sh. Note the baseline is"
    echo "built from HEAD, so this is a deliberate, reviewable act, not an automatic exemption."
  } >&2
  exit 2
fi
exit 0
