#!/bin/bash
# Pre-push validation script for Powernode Platform
# Runs backend specs, TypeScript check, and pattern validation
# Usage: ./scripts/validate.sh [--skip-tests] [--skip-ts] [--skip-patterns] [--skip-secrets]

set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

SKIP_TESTS=false
SKIP_TS=false
SKIP_PATTERNS=false
SKIP_SECRETS=false
SKIP_EXT_SPECS=false

# Test seam for scripts/checks/tests/validate-stale-ext-gate-check.sh: skips the
# real `bundle exec rspec` invocations below (platform alone is 1056 spec
# files; extensions/system ships 608 more) while leaving every decision and
# reporting branch around them — including the private-extension
# migration-staleness check (IMP-93291dfa635f) — real. Lets that test drive
# THIS script end-to-end without paying for a full backend-spec run or
# touching the shared test DB (memory: "TARGETED specs only ... nor bare
# validate.sh").
VALIDATE_SELFTEST_SKIP_RSPEC="${VALIDATE_SELFTEST_SKIP_RSPEC:-}"

for arg in "$@"; do
  case "$arg" in
    --skip-tests)   SKIP_TESTS=true ;;
    --skip-ts)      SKIP_TS=true ;;
    --skip-patterns) SKIP_PATTERNS=true ;;
    --skip-secrets)  SKIP_SECRETS=true ;;
    --skip-extension-specs) SKIP_EXT_SPECS=true ;;
    --help)
      echo "Usage: ./scripts/validate.sh [--skip-tests] [--skip-ts] [--skip-patterns] [--skip-secrets] [--skip-extension-specs]"
      echo ""
      echo "Runs pre-push validation checks:"
      echo "  1. Backend RSpec tests (platform + every extension that ships specs)"
      echo "  2. Frontend TypeScript type check"
      echo "  3. Pattern validation audit"
      echo "  4. Secret scanning (gitleaks)"
      echo ""
      echo "Options:"
      echo "  --skip-tests             Skip ALL RSpec specs (platform and extensions)"
      echo "  --skip-extension-specs   Run platform specs only — prints a loud warning."
      echo "                           The extension suites are long (system alone is"
      echo "                           ~8000 examples); this exists so you can choose to"
      echo "                           defer them, not so they can be forgotten."
      echo "  --skip-ts                Skip TypeScript type check"
      echo "  --skip-patterns          Skip pattern validation"
      echo "  --skip-secrets           Skip gitleaks secret scanning"
      exit 0
      ;;
  esac
done

echo -e "${BLUE}=== Powernode Pre-Push Validation ===${NC}"
echo "Date: $(date)"
echo ""

RESULTS=()
OVERALL_EXIT=0

# 0. Preflight: gem pre-activation doctor (fail fast — a newer-than-locked orphan
# of a boot-critical gem (json, rdoc, ...) crashes boot with "already activated
# <gem>-X", so nothing after this can run reliably; see
# scripts/doctor-gem-preactivation.sh for remediation)
echo -e "${BLUE}[0/4] Gem pre-activation doctor...${NC}"
if "$SCRIPT_DIR/doctor-gem-preactivation.sh"; then
  echo ""
else
  echo ""
  echo -e "${RED}Gem pre-activation doctor FAILED — fix the orphan gem before validating.${NC}"
  exit 1
fi

# 1. Backend RSpec tests
if [[ "$SKIP_TESTS" == "false" ]]; then
  echo -e "${BLUE}[1/4] Running backend specs...${NC}"
  SPECS_OK=true

  # Platform specs. `bundle exec rspec` uses RSpec's default pattern
  # spec/**/*_spec.rb RELATIVE TO THE CWD, so this covers server/spec ONLY.
  if [[ -n "$VALIDATE_SELFTEST_SKIP_RSPEC" ]] || (cd "$PROJECT_ROOT/server" && bundle exec rspec --format progress 2>&1); then
    :
  else
    echo -e "${RED}  └─ platform server/spec failed${NC}"
    SPECS_OK=false
  fi

  # Extension specs — the whole point of this block.
  #
  # They used to be invisible here. The platform run above covers 1056 spec
  # files; extensions/system alone ships 608 that were NEVER LOADED, so a green
  # gate said nothing about them. On 2026-08-05 this gate reported 21901
  # examples / 0 failures while CI was red with 43 extension failures. Both were
  # true — they were testing different things.
  #
  # Same shape as the tsc phase below: enumerate extension SPEC DIRS, not
  # configs, so a missing one is a failure rather than a silent skip. An
  # extension that ships specs is either run or named in the opt-out file.
  if [[ "$SKIP_EXT_SPECS" == "true" ]]; then
    echo -e "${YELLOW}  └─ SKIP all extension specs (--skip-extension-specs). Platform specs alone do NOT cover extensions.${NC}"
  else
    RSPEC_OPTOUT_FILE="$PROJECT_ROOT/scripts/rspec-check-optouts.txt"
    EXT_SKIP_NOTES=()
    EXT_FAIL_NOTES=()
    for ext_spec in "$PROJECT_ROOT"/extensions/*/server/spec "$PROJECT_ROOT"/extensions/private/*/server/spec; do
      [[ -d "$ext_spec" ]] || continue
      # No *_spec.rb means nothing to run; not a gap.
      [[ -n "$(find "$ext_spec" -name '*_spec.rb' -print -quit 2>/dev/null)" ]] || continue
      ext_slug="$(basename "$(dirname "$(dirname "$ext_spec")")")"

      # `|| true` is load-bearing under `set -eo pipefail`: a no-match grep
      # (exit 1) inside a command substitution would abort the whole gate
      # silently, mid-phase — the exact failure this check exists to remove.
      optout_reason="$(grep -E "^${ext_slug}[[:space:]]" "$RSPEC_OPTOUT_FILE" 2>/dev/null | head -1 | sed -E "s/^${ext_slug}[[:space:]]+//" || true)"
      if [[ -n "$optout_reason" ]]; then
        # Printed every run on purpose: an exemption nobody sees stops being a
        # decision and becomes an accident.
        echo -e "${YELLOW}  └─ SKIP extensions/$ext_slug — specs not run: ${optout_reason}${NC}"
        continue
      fi

      # PRIVATE extensions need the private bundle. Their code is loaded through
      # PATH gems declared in server/Gemfile.private; under the committed
      # public-only Gemfile the extension is simply absent, so every one of its
      # specs dies at load with `NameError: uninitialized constant <Namespace>`
      # — 95 load errors and "0 examples, 0 failures", which reads as green to
      # anything checking totals. Measured on the business extension.
      #
      # Gemfile.private.lock is gitignored and only exists for maintainers; a
      # public clone has no extensions/private/* at all, so this branch is
      # simply never taken there.
      ext_bundle=""
      case "$ext_spec" in
        "$PROJECT_ROOT"/extensions/private/*)
          if [[ -f "$PROJECT_ROOT/server/Gemfile.private" ]]; then
            ext_bundle="$PROJECT_ROOT/server/Gemfile.private"

            # A loadable bundle is necessary but NOT sufficient (IMP-d4583399ba5c):
            # db:schema:load/db:prepare load the core-only schema.rb and mark every
            # migration version <= the schema version as already-applied via
            # assume_migrated_upto_version, WITHOUT running this extension's own
            # engine migrations — so its tables are silently absent from a test DB
            # never built by scripts/prepare-extension-test-db.sh, even though the
            # bundle above loaded cleanly. Left unchecked, that produces hundreds of
            # PG::UndefinedTable failures indistinguishable from a real regression
            # (measured: 851 on the business extension). Check the real
            # precondition — are THIS extension's migrations actually recorded in
            # schema_migrations — instead of a wall of cascading spec failures.
            ext_migrate_dir="$(dirname "$ext_spec")/db/migrate"
            # `|| true` is load-bearing under `set -eo pipefail`: the checker
            # deliberately exit 1s on STALE, and a bare `var="$(cmd)"` assignment
            # is NOT exempt from `set -e` when cmd fails — without this, the one
            # case this whole feature exists to catch (stale private-extension
            # migrations) would abort the ENTIRE validate.sh run right here,
            # silently skipping TS/pattern/secrets checks too, instead of
            # gracefully skipping just this extension's specs.
            migration_status="$("$SCRIPT_DIR/check-extension-bundle-migrations.sh" "$ext_migrate_dir" || true)"
            if [[ "$migration_status" != "OK" ]]; then
              # Unlike a missing Gemfile.private (a genuine, unavoidable gap on
              # a public checkout — nothing to do about it, so it stays a
              # SKIP), a stale bundle is INCIDENTAL: it happens whenever
              # anyone adds a routine migration and hasn't re-run
              # prepare-extension-test-db.sh, and it is trivially fixable.
              # Reporting it as a SKIP that still lets the overall gate PASS
              # was IMP-93291dfa635f: a routine migration add earned a green
              # gate that covered strictly less than before, exactly when a
              # migration's blast radius matters most. Fail the gate instead
              # of just noting the gap — do NOT relax the check above to
              # tolerate new migrations, that would remove a real signal.
              echo -e "${RED}  └─ FAIL extensions/$ext_slug specs NOT RUN (private bundle not migrated: ${migration_status}) — run 'bash scripts/prepare-extension-test-db.sh'${NC}"
              EXT_FAIL_NOTES+=("extensions/$ext_slug specs NOT RUN — private bundle not migrated (${migration_status}); run scripts/prepare-extension-test-db.sh")
              SPECS_OK=false
              continue
            fi
          else
            echo -e "${YELLOW}  └─ SKIP extensions/$ext_slug specs SKIPPED (private bundle not loaded) — run 'cd server && BUNDLE_GEMFILE=Gemfile.private bundle install'${NC}"
            EXT_SKIP_NOTES+=("extensions/$ext_slug specs SKIPPED (private bundle not loaded)")
            continue
          fi
          ;;
      esac

      echo -e "${BLUE}  └─ extensions/$ext_slug specs...${NC}"
      # Run from the PLATFORM's server/ so rails_helper, factories and the
      # engine's autoload paths resolve exactly as they do in CI.
      if [[ -n "$VALIDATE_SELFTEST_SKIP_RSPEC" ]] || (cd "$PROJECT_ROOT/server" && BUNDLE_GEMFILE="${ext_bundle:-$PROJECT_ROOT/server/Gemfile}" \
            bundle exec rspec "$ext_spec" --format progress 2>&1); then
        :
      else
        echo -e "${RED}     extensions/$ext_slug specs failed${NC}"
        SPECS_OK=false
      fi
    done
  fi

  if [[ "$SPECS_OK" == "true" ]]; then
    RESULTS+=("${GREEN}PASS${NC} Backend specs")
  else
    RESULTS+=("${RED}FAIL${NC} Backend specs")
    OVERALL_EXIT=1
  fi
  # Surface any precondition-skipped private extension explicitly in the
  # summary, distinct from PASS/FAIL — a skip nobody sees in the final tally
  # stops being a decision and reads as an accidental pass (IMP-d4583399ba5c).
  for note in "${EXT_SKIP_NOTES[@]:-}"; do
    [[ -n "$note" ]] && RESULTS+=("${YELLOW}SKIP${NC} $note")
  done
  # Distinct from the SKIP notes above: these are suites that did NOT run and
  # for that reason alone must not coexist with an unqualified overall PASS
  # (IMP-93291dfa635f). SPECS_OK is already false whenever this array is
  # non-empty, so OVERALL_EXIT is already 1 by the time we get here.
  for note in "${EXT_FAIL_NOTES[@]:-}"; do
    [[ -n "$note" ]] && RESULTS+=("${RED}FAIL${NC} $note")
  done
  echo ""
else
  RESULTS+=("${YELLOW}SKIP${NC} Backend specs")
fi

# 2. TypeScript type check (platform + each extension that has tsconfig.check.json)
if [[ "$SKIP_TS" == "false" ]]; then
  echo -e "${BLUE}[2/4] Running TypeScript type check...${NC}"
  TS_OK=true
  if (cd "$PROJECT_ROOT/frontend" && npx tsc --noEmit 2>&1); then
    :
  else
    TS_OK=false
  fi
  # Each extensions/*/frontend/tsconfig.check.json is a tsc gate for that
  # extension's frontend tree (Vite resolves @<slug>/* aliases at runtime,
  # but the platform's main tsconfig.json only includes its own src). Without
  # this loop, runtime ReferenceErrors and TS1005 syntax errors in extension
  # components slip past the validation gate (see history: CanaryMarker +
  # ArchitectureList).
  # tsc needs to walk up from extension source files and find react etc. —
  # it walks up from the file location, so the platform's node_modules has
  # to be reachable from extensions/<slug>/frontend/. We ensure this by
  # symlinking; never commit the symlink (extension .gitignore handles that).
  # Enumerate extension FRONTEND DIRS, not tsconfig.check.json files. Globbing
  # the configs made a missing one a silent skip — which is precisely how
  # marketing and supply-chain stayed unchecked (380 source files) while the
  # gate reported green, and how a real regression (mainNav deleted from
  # PublicPageContainer under a "bump dependencies" commit) survived. An
  # extension frontend must now either ship a config or be named in
  # scripts/tsc-check-optouts.txt with a reason; anything else fails.
  OPTOUT_FILE="$PROJECT_ROOT/scripts/tsc-check-optouts.txt"
  for ext_dir in "$PROJECT_ROOT"/extensions/*/frontend "$PROJECT_ROOT"/extensions/private/*/frontend; do
    [[ -d "$ext_dir" ]] || continue
    ext_slug="$(basename "$(dirname "$ext_dir")")"
    ext_tsconfig="$ext_dir/tsconfig.check.json"

    if [[ ! -f "$ext_tsconfig" ]]; then
      # Opt-out lines are "<slug><whitespace><reason>"; comments start with #.
      # `|| true` is load-bearing: this script runs under `set -eo pipefail`, so
      # a no-match grep (exit 1) inside a command substitution aborts the whole
      # gate — silently, mid-phase, with no summary. That is the exact failure
      # mode this check exists to remove, so it must not introduce one.
      optout_reason="$(grep -E "^${ext_slug}[[:space:]]" "$OPTOUT_FILE" 2>/dev/null | head -1 | sed -E "s/^${ext_slug}[[:space:]]+//" || true)"
      if [[ -n "$optout_reason" ]]; then
        # Printed every run on purpose: an exemption that is invisible stops
        # being a decision and becomes an accident.
        echo -e "${YELLOW}  └─ SKIP extensions/$ext_slug/frontend — not type-checked: ${optout_reason}${NC}"
      else
        echo -e "${RED}  └─ extensions/$ext_slug/frontend has no tsconfig.check.json and no entry in scripts/tsc-check-optouts.txt${NC}"
        TS_OK=false
      fi
      continue
    fi

    if [[ ! -e "$ext_dir/node_modules" ]]; then
      ln -sf "$PROJECT_ROOT/frontend/node_modules" "$ext_dir/node_modules"
    fi
    if (cd "$PROJECT_ROOT/frontend" && npx tsc --noEmit -p "$ext_tsconfig" 2>&1); then
      :
    else
      echo -e "${RED}  └─ extensions/$ext_slug/frontend tsc failed${NC}"
      TS_OK=false
    fi
  done
  if [[ "$TS_OK" == "true" ]]; then
    RESULTS+=("${GREEN}PASS${NC} TypeScript types")
  else
    RESULTS+=("${RED}FAIL${NC} TypeScript types")
    OVERALL_EXIT=1
  fi
  echo ""
else
  RESULTS+=("${YELLOW}SKIP${NC} TypeScript types")
fi

# 3. Pattern validation
if [[ "$SKIP_PATTERNS" == "false" ]]; then
  echo -e "${BLUE}[3/4] Running pattern validation...${NC}"
  if (cd "$PROJECT_ROOT" && ./scripts/pattern-validation.sh 2>&1); then
    RESULTS+=("${GREEN}PASS${NC} Pattern validation")
  else
    PATTERN_EXIT=$?
    if [[ $PATTERN_EXIT -eq 1 ]]; then
      RESULTS+=("${YELLOW}WARN${NC} Pattern validation (non-critical failures — see scripts/pattern-validation.sh)")
    else
      RESULTS+=("${RED}FAIL${NC} Pattern validation")
      OVERALL_EXIT=1
    fi
  fi
  echo ""
else
  RESULTS+=("${YELLOW}SKIP${NC} Pattern validation")
fi

# 4. Secret scanning (gitleaks)
if [[ "$SKIP_SECRETS" == "false" ]]; then
  echo -e "${BLUE}[4/4] Running secret scanning (gitleaks)...${NC}"
  if command -v gitleaks &> /dev/null; then
    GITLEAKS_CONFIG=""
    if [[ -f "$PROJECT_ROOT/.gitleaks.toml" ]]; then
      GITLEAKS_CONFIG="--config=$PROJECT_ROOT/.gitleaks.toml"
    fi

    # Scan current working tree (not full history — that's the quarterly audit)
    if gitleaks detect --source="$PROJECT_ROOT" $GITLEAKS_CONFIG --no-git 2>&1; then
      RESULTS+=("${GREEN}PASS${NC} Secret scanning")
    else
      RESULTS+=("${RED}FAIL${NC} Secret scanning (secrets detected!)")
      OVERALL_EXIT=1
    fi
  else
    RESULTS+=("${YELLOW}SKIP${NC} Secret scanning (gitleaks not installed)")
  fi
  echo ""
else
  RESULTS+=("${YELLOW}SKIP${NC} Secret scanning")
fi

# Summary
echo -e "${BLUE}=== Validation Summary ===${NC}"
for result in "${RESULTS[@]}"; do
  echo -e "  $result"
done
echo ""

if [[ $OVERALL_EXIT -eq 0 ]]; then
  echo -e "${GREEN}All checks passed — safe to push.${NC}"
else
  echo -e "${RED}Some checks failed — fix issues before pushing.${NC}"
fi

exit $OVERALL_EXIT
