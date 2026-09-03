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
SKIP_PRIVATE_PASS=false

# Test seam for scripts/checks/tests/validate-stale-ext-gate-check.sh: skips the
# real `bundle exec rspec` invocations below (platform alone is 1056 spec
# files; extensions/system ships 608 more) while leaving every decision and
# reporting branch around them — including the private-extension
# migration-staleness check (IMP-93291dfa635f) — real. Lets that test drive
# THIS script end-to-end without paying for a full backend-spec run or
# touching the shared test DB (memory: "TARGETED specs only ... nor bare
# validate.sh").
VALIDATE_SELFTEST_SKIP_RSPEC="${VALIDATE_SELFTEST_SKIP_RSPEC:-}"

# Test seams for scripts/checks/tests/validate-maintainer-bundle-pass-check.sh,
# both inert unless explicitly set:
#   *_PRIVATE_PASS_FAIL   — makes the STUBBED second pass (i.e. only when
#                           VALIDATE_SELFTEST_SKIP_RSPEC is on) report failure,
#                           so the divergence-must-fail branch is exercised
#                           without a real red suite.
#   *_PRIVATE_EXT_ROOT    — where to look for private extensions. Pointing it
#                           at an empty dir reproduces the public-clone shape
#                           on a maintainer checkout, without moving anything.
VALIDATE_SELFTEST_PRIVATE_PASS_FAIL="${VALIDATE_SELFTEST_PRIVATE_PASS_FAIL:-}"
PRIVATE_EXT_ROOT="${VALIDATE_SELFTEST_PRIVATE_EXT_ROOT:-$PROJECT_ROOT/extensions/private}"

for arg in "$@"; do
  case "$arg" in
    --skip-tests)   SKIP_TESTS=true ;;
    --skip-ts)      SKIP_TS=true ;;
    --skip-patterns) SKIP_PATTERNS=true ;;
    --skip-secrets)  SKIP_SECRETS=true ;;
    --skip-extension-specs) SKIP_EXT_SPECS=true ;;
    --skip-private-bundle-pass) SKIP_PRIVATE_PASS=true ;;
    --help)
      echo "Usage: ./scripts/validate.sh [--skip-tests] [--skip-ts] [--skip-patterns] [--skip-secrets] [--skip-extension-specs] [--skip-private-bundle-pass]"
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
      echo "  --skip-private-bundle-pass"
      echo "                           Skip the second pass that re-runs PUBLIC extension"
      echo "                           specs under server/Gemfile.private. That pass only"
      echo "                           happens on a maintainer checkout (extensions/private/*"
      echo "                           present) and roughly DOUBLES the public extension"
      echo "                           suites; skip it to defer that cost for one run."
      echo "                           Whenever there was a pass to skip, the skip is"
      echo "                           labelled in the summary."
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
    EXT_DIVERGE_NOTES=()
    # Public extensions this pass ACTUALLY ran, for the private-bundle second
    # pass below. Recorded here rather than re-globbed there on purpose: the
    # opt-out file, the "ships no specs" filter and the private/public split
    # are all decided once, in one place. An opt-out honored in one pass and
    # ignored in the other is not an opt-out.
    PUBLIC_EXT_SPECS_RUN=()
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

      # Only public extensions are eligible for the second pass — a private
      # extension already runs under the private bundle here, so re-running it
      # would just be the same configuration twice.
      if [[ -z "$ext_bundle" ]]; then
        PUBLIC_EXT_SPECS_RUN+=("$ext_spec")
      fi

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

    # ── Second pass: the SAME public-extension specs, under the PRIVATE bundle ──
    #
    # IMP-0bf0d8873023. TWO configurations ship and the loop above only ever
    # tests one of them. Its `case` selects Gemfile.private for private
    # extensions only; every public extension gets an EXPLICIT
    # BUNDLE_GEMFILE=$PROJECT_ROOT/server/Gemfile (explicit because it must
    # also override an inherited one), and that bundle never sets
    # POWERNODE_INCLUDE_PRIVATE_EXTENSIONS, so no private extension is on the
    # load path. (Precisely: selecting a Gemfile cannot CLEAR an inherited env
    # var — only Gemfile.private:12 ever sets the flag, and it does so with
    # `||=`. Hence the explicit pin on the pass-2 invocation below.)
    #
    # That is CORRECT for a public clone — there is no extensions/private/*
    # there and nothing else to test. It is incomplete for a maintainer or
    # deployed checkout, where a private extension's guards, decorators and
    # registered providers load IN FRONT OF public-extension code. Existence
    # proof: extensions/system's provisioning_service_spec.rb was 68 examples /
    # 0 failures under the public bundle and 68 / 47 under the private one
    # (IMP-4344d65ddf56), and the 47 included the RCP INV-2/INV-6 boot-path and
    # storage-locality invariants — permanently green here, red in the
    # configuration closer to a real deployment.
    #
    # So this pass is ADDITIVE: it never changes what pass 1 runs, and it does
    # not run at all without private extensions on disk. Its failures are HARD
    # (SPECS_OK=false), not advisory — a second pass that only reports would
    # reproduce the invisibility it exists to remove.
    #
    # Cost: it re-runs the same examples, so it roughly DOUBLES the public
    # extension spec phase, and only maintainers pay it. Measured 2026-08-30 on
    # dev-cell: a 125-file / 1970-example slice of extensions/system (16% of its
    # 779 spec files) took 36 min under the public bundle and 31 min under the
    # private one (~1 s/example either way), so full extensions/system is hours
    # in EACH configuration. That phase was already the long pole —
    # --skip-extension-specs exists for exactly that reason — and
    # --skip-private-bundle-pass defers just this half of it for one run.
    #
    # Same measurement on divergence, so the cost is bought with eyes open: of
    # those 1970 examples, ZERO failed in either configuration and exactly 2
    # (both in provisioning_service_spec.rb, both explicitly skipped when the
    # guard is absent) changed status. Divergence is not endemic today. What is
    # missing without this pass is any way to find out when it stops being rare.
    if [[ ${#PUBLIC_EXT_SPECS_RUN[@]} -gt 0 ]]; then
      if ! compgen -G "$PRIVATE_EXT_ROOT/*/server" >/dev/null 2>&1; then
        # Public clone: nothing is loaded differently, so there is no second
        # configuration to test. Silent by design — this is the normal case for
        # everyone without private extensions, not a gap.
        #
        # FIRST on purpose, ahead of the --skip flag: this branch means "there
        # is nothing here to skip". Checking the flag first made a public clone
        # print a coverage warning about a gap it does not have.
        :
      elif [[ "$SKIP_PRIVATE_PASS" == "true" ]]; then
        echo -e "${YELLOW}  └─ private-bundle second pass SKIPPED (--skip-private-bundle-pass)${NC}"
        EXT_SKIP_NOTES+=("private-bundle second pass SKIPPED (--skip-private-bundle-pass) — public extensions were tested in the public configuration ONLY")
      elif [[ ! -f "$PROJECT_ROOT/server/Gemfile.private" || ! -f "$PROJECT_ROOT/server/Gemfile.private.lock" ]]; then
        # Private extensions ARE on disk but their bundle was never installed —
        # same structural gap the loop above reports per private extension, and
        # reported the same way rather than silently passing.
        echo -e "${YELLOW}  └─ private-bundle second pass SKIPPED (private bundle not installed) — run 'cd server && BUNDLE_GEMFILE=Gemfile.private bundle install'${NC}"
        EXT_SKIP_NOTES+=("private-bundle second pass SKIPPED (private bundle not installed)")
      else
        # Same precondition as the private-extension branch above: a loadable
        # bundle whose migrations are NOT in the test DB produces a wall of
        # PG::UndefinedTable failures indistinguishable from a real regression.
        # Checked here for EVERY private extension on disk, including ones
        # opted out of their own spec run — the second pass loads them all.
        private_pass_blocked=""
        for private_ext in "$PRIVATE_EXT_ROOT"/*/server; do
          [[ -d "$private_ext" ]] || continue
          # `|| true`: the checker deliberately exit 1s on STALE, and a bare
          # `var="$(cmd)"` is not exempt from `set -e`.
          pp_status="$("$SCRIPT_DIR/check-extension-bundle-migrations.sh" "$private_ext/db/migrate" || true)"
          if [[ "$pp_status" != "OK" ]]; then
            private_pass_blocked="$(basename "$(dirname "$private_ext")") (${pp_status})"
            break
          fi
        done

        if [[ -n "$private_pass_blocked" ]]; then
          # Deliberately a FAIL, not a SKIP: like IMP-93291dfa635f's stale
          # bundle this is incidental and trivially fixable, and letting it
          # pass would hand back a green gate covering strictly less.
          echo -e "${RED}  └─ FAIL private-bundle second pass NOT RUN (private bundle not migrated: ${private_pass_blocked}) — run 'bash scripts/prepare-extension-test-db.sh'${NC}"
          EXT_FAIL_NOTES+=("private-bundle second pass NOT RUN — private bundle not migrated (${private_pass_blocked}); run scripts/prepare-extension-test-db.sh")
          SPECS_OK=false
        else
          echo -e "${BLUE}  └─ Re-running public extension specs under the private bundle (maintainer configuration)...${NC}"
          private_pass_bundle="$PROJECT_ROOT/server/Gemfile.private"
          for ext_spec in "${PUBLIC_EXT_SPECS_RUN[@]}"; do
            ext_slug="$(basename "$(dirname "$(dirname "$ext_spec")")")"
            echo -e "${BLUE}  └─ extensions/$ext_slug specs (private bundle)...${NC}"

            # ONE construction site AND, below, one execution site. An earlier
            # version had the stub echo a look-alike string on a branch of its
            # own: mutating the real branch's BUNDLE_GEMFILE to the PUBLIC
            # Gemfile then left the selftest fully green — the assertion that
            # this is a different configuration could not see the one change
            # that makes it the same one twice. The stub now WRAPS this array
            # rather than branching around it, so the selftest can only be
            # observing the argv that actually runs.
            #
            # The env pin is load-bearing, not belt-and-braces. Gemfile.private
            # sets the flag with `||=` (server/Gemfile.private:12) and
            # extensions_loader_helper.rb:44 compares `== "1"`, so an inherited
            # POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 survives selection of the
            # private bundle and loads ZERO private extensions — a second pass
            # byte-identical to the first, silently green, pure cost. Verified
            # in ruby. An inherited value is not theoretical: any exported
            # shell value, or a hand-written server/.env, reaches this pass.
            # (scripts/prepare-worktree.sh no longer writes the flag into a
            # worktree's server/.env — IMP-a31d6e31023e removed that write
            # because .env is on the WRONG side of Bundler; see the comment at
            # its server/.env branch.)
            private_pass_cmd=(env POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=1 \
              BUNDLE_GEMFILE="$private_pass_bundle" \
              bundle exec rspec "$ext_spec" --format progress)

            if [[ -n "$VALIDATE_SELFTEST_SKIP_RSPEC" ]]; then
              # Stubbed run: REPLACE the command with one that prints the real
              # argv and exits with the status the seam asks for. Wrapping
              # rather than branching is the point — there is a single
              # execution site below, so a change to what actually runs cannot
              # hide from the selftest. $1 is the fail seam, "${@:2}" the argv.
              private_pass_cmd=(bash -c \
                'echo "     [selftest] would run: ${*:2}"; [[ -z "$1" ]]' \
                _ "$VALIDATE_SELFTEST_PRIVATE_PASS_FAIL" "${private_pass_cmd[@]}")
            fi

            if (cd "$PROJECT_ROOT/server" && "${private_pass_cmd[@]}" 2>&1); then
              continue
            fi
            # Deliberately does NOT claim pass 1 was green — it may have failed
            # too, and this pass has no way to know. What it does know, and all
            # it asserts, is which configuration this failure came from.
            echo -e "${RED}     extensions/$ext_slug specs FAILED under the private bundle (private extensions loaded)${NC}"
            EXT_DIVERGE_NOTES+=("extensions/$ext_slug specs FAILED under the private bundle (maintainer/production configuration)")
            SPECS_OK=false
          done
        fi
      fi
    fi
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
  # Suites that DID run and failed in the PRIVATE-bundle configuration
  # (IMP-0bf0d8873023). Named separately from a plain spec failure because the
  # question they raise is different: the same code was just exercised in two
  # shipped configurations, so the first thing to establish is whether pass 1
  # was green — if it was, the disagreement itself is the finding.
  for note in "${EXT_DIVERGE_NOTES[@]:-}"; do
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
    # gitleaks absence here is INCIDENTAL, not structural: it's a public,
    # freely installable binary (https://github.com/gitleaks/gitleaks) with no
    # credential or submodule gate like server/Gemfile.private has — nothing
    # stops any machine from installing it. Silently downgrading to a
    # non-fatal SKIP let this gate report PASS having scanned nothing (found
    # by iteration 2433d0ebe0e7, same shape as IMP-93291dfa635f's stale
    # extension bundle: a routine, fixable environment gap must not coexist
    # with an unqualified "All checks passed"). If a machine genuinely cannot
    # install gitleaks, the operator must say so explicitly via
    # --skip-secrets (already a distinct, loud SKIP line below) rather than
    # have this branch infer it silently.
    echo -e "${RED}  └─ gitleaks not installed — secrets NOT SCANNED. Install it (https://github.com/gitleaks/gitleaks#installing) or re-run with --skip-secrets to explicitly accept the gap.${NC}"
    RESULTS+=("${RED}FAIL${NC} Secret scanning (gitleaks not installed — nothing was scanned; install gitleaks or pass --skip-secrets to accept this explicitly)")
    OVERALL_EXIT=1
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
