#!/bin/bash
# PreToolUse (Bash) — makes a "read-only" shell MECHANICAL for a roster role that
# has a shell and no Edit/Write (role[:shell_guard], rendered into that role's OWN
# frontmatter `hooks:`; Claude Code scopes a subagent's frontmatter hooks to that
# subagent). Never wired in settings.json, so it never restricts the main session.
#
# NOT A BOUNDARY ON ITS OWN: a frontmatter hook needs workspace trust, and an
# unset $CLAUDE_PROJECT_DIR makes the hook path fail with exit 127, which Claude
# Code treats as NON-blocking. So in phase 1 no role relies on it — the reviewer
# has no shell at all (Ai::Agents::CanonicalRoster). It stays, hardened, for a
# future shell role, covered by server/spec/hooks/readonly_shell_guard_spec.rb.
#
# Policy: an ALLOWLIST. A command is allowed only when it is provably read-only;
# anything else, and anything this script cannot parse, is denied (exit 2, the
# reason on stderr). Denied outright, anywhere in the command:
#   * shell metacharacters that chain, redirect, substitute or expand
#     (; & > < ` $ ( ) { } \ and newlines), and `||`;
#   * quotes (' "), glob characters (* ? [ ]) and a leading ~ on any word: each
#     makes what bash runs differ from the words checked here ("-delete" in
#     quotes is still -delete; .c*nfig still reaches .config);
#   * a `..` path segment, any /proc path, .config, the unit env files, SSH keys
#     (after collapsing // and /./);
#   * an absolute path that is /, $HOME or an ancestor of $HOME (a whole-home scan).
# A pipe is allowed only between allowed commands.
#
# Allowed first words (each with its own option checks below):
#   git [-C dir]  log show diff status rev-parse ls-files ls-tree cat-file
#                 merge-base blame grep, and `branch --list`; never -c, --output,
#                 --ext-diff, --textconv, --filters, --no-index, --exec-path or
#                 grep's -O / --open-files-in-pager (git accepts an abbreviated
#                 long option, so every prefix of those is denied too)
#   rg grep       (rg without --pre / --pre-glob / --hostname-bin)
#   cat head tail ls wc cut pwd stat
#   sort          without -o / --output / --compress-program
#   uniq          with at most one file operand (a second one is its OUTPUT)
#   file          without -C / --compile
#   sed -n <N,Mp> file     (a bare print script only)
#   find          without -delete -exec -execdir -ok -okdir -fprint* -fls
#   go vet | go test       only GO_FLAGS / GO_VALUE (so no -c -o -exec -toolexec
#                 -vettool, no profile output, no -args)
#   rspec, bundle exec rspec  only RSPEC_FLAGS / RSPEC_VALUE and spec paths (so
#                 no --init -r -O -o -I), and only under the test-DB guard
#   jest, npx jest only JEST_FLAGS / JEST_VALUE and plain paths (so no --config,
#                 --outputFile, -u, setup files), and only under the test-DB guard
# The test-DB guard: RAILS_ENV unset or test and no non-test DATABASE_NAME (an
# exported development environment let rspec's cleaner empty the development
# database once).
set -uo pipefail

deny() { echo "readonly-shell-guard: denied: $1" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || deny "jq is not installed, so the command cannot be checked"
payload="$(cat 2>/dev/null || true)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)" || deny "unreadable payload"
[[ -n "$cmd" ]] || deny "no command to check"

# Metacharacters that chain, redirect, substitute or expand.
if [[ "$cmd" == *$'\n'* || "$cmd" =~ [\;\&\>\<\`\$\(\)\{\}\\] || "$cmd" == *"||"* ]]; then
  deny "uses shell chaining, redirection, substitution or expansion"
fi
# Quotes and globs: what bash runs would differ from the words checked here.
case "$cmd" in
  *\'*|*\"*|*\**|*\?*|*\[*|*\]*) deny "uses quotes or glob characters" ;;
esac

# Never touch the platform's configuration, secrets or a process environment.
# Collapse // and /./ first so a doubled slash cannot split a protected name.
norm="$cmd"
while [[ "$norm" == *"//"* ]]; do norm="${norm//\/\//\/}"; done
while [[ "$norm" == *"/./"* ]]; do norm="${norm//\/.\//\/}"; done
case "$norm" in
  *".config"*|*"powernode.conf"*|*"backend-default"*|*".ssh"*|*"id_rsa"*|*"id_ed25519"*|*"/proc"*)
    deny "mentions platform configuration, secrets or /proc" ;;
esac

home="${HOME%/}"

# check_path_token WORD — the path rules every word of every command obeys.
check_path_token() {
  local tok="$1" path
  [[ "$tok" == "~"* ]] && deny "a leading ~ expands to a home directory"
  for path in "$tok" "${tok#*=}"; do
    [[ "$path" =~ (^|/)\.\.(/|$) ]] && deny "a .. path segment ($tok)"
    if [[ "$path" == /* ]]; then
      path="${path%/}"
      [[ -z "$path" ]] && deny "scans the filesystem root"
      if [[ -n "$home" && ( "$home" == "$path" || "$home" == "$path"/* ) ]]; then
        deny "scans the home directory or above ($tok)"
      fi
    fi
  done
  return 0
}

# abbrev_of WORD LONGOPT... — true when WORD (minus any =value) is LONGOPT or a
# prefix of it: getopt_long, git and Ruby's OptionParser all accept abbreviations.
abbrev_of() {
  local name="${1%%=*}" opt
  shift
  [[ "$name" == --?* ]] || return 1
  for opt in "$@"; do [[ "$opt" == "$name"* ]] && return 0; done
  return 1
}

test_db_guard() {
  [[ -z "${RAILS_ENV:-}" || "${RAILS_ENV}" == "test" ]] || return 1
  [[ -z "${DATABASE_NAME:-}" || "${DATABASE_NAME}" == *test* ]] || return 1
}

# *_FLAGS stand alone; *_VALUE flags take their value as the next word or as =value.
GO_FLAGS=" -v -short -race -cover -json -failfast -benchmem -x -n "
GO_VALUE=" -run -skip -count -timeout -p -tags -bench -benchtime -list -shuffle -parallel -cpu -covermode "
RSPEC_FLAGS=" --fail-fast --no-color --force-color --dry-run -b --backtrace --only-failures --next-failure -w --warnings "
RSPEC_VALUE=" -f --format -e --example -t --tag --seed --order -p --profile "
JEST_FLAGS=" --ci --runInBand -i --verbose --silent --bail --passWithNoTests --listTests --watchAll=false --no-watchman --colors --json "
JEST_VALUE=" -t --testNamePattern --testPathPattern --maxWorkers "

SPEC_PATH_RE='^([A-Za-z0-9_.-]+/)*spec(/[A-Za-z0-9_.-]+)*(:[0-9]+)*$'
PLAIN_PATH_RE='^[A-Za-z0-9_./-]+$'

# check_runner_args KIND FLAGS VALUE_FLAGS OPERAND_RE WORDS... — every flag is on
# the allowlist (rspec's joined -fd form included), and every operand matches.
check_runner_args() {
  local kind="$1" flags="$2" values="$3" operand_re="$4" skip=0 tok
  shift 4
  for tok in "$@"; do
    if [[ "$skip" -eq 1 ]]; then skip=0; continue; fi
    if [[ "$tok" == -* ]]; then
      [[ "$flags" == *" $tok "* ]] && continue
      if [[ "$values" == *" $tok "* ]]; then skip=1; continue; fi
      [[ "$tok" == *=* && "$values" == *" ${tok%%=*} "* ]] && continue
      [[ "$kind" == rspec && "$tok" =~ ^-f[a-z]+$ ]] && continue
      deny "$kind option $tok is not on the read-only allowlist"
    fi
    [[ "$tok" =~ $operand_re ]] || deny "$kind operand $tok is not allowed"
  done
  return 0
}

check_segment() {
  local seg="$1"
  # shellcheck disable=SC2206
  local -a t=($seg)
  [[ ${#t[@]} -gt 0 ]] || deny "empty command segment"
  local first="${t[0]}" i tok
  for tok in "${t[@]}"; do check_path_token "$tok"; done
  case "$first" in
    git)
      i=1
      while [[ "${t[$i]:-}" == "-C" ]]; do i=$((i + 2)); done
      local sub="${t[$i]:-}"
      case "$sub" in
        log|show|diff|status|rev-parse|ls-files|ls-tree|cat-file|merge-base|blame|grep) ;;
        branch) [[ "${t[$((i + 1))]:-}" == "--list" || "${t[$((i + 1))]:-}" == "-l" ]] || deny "git branch is allowed only with --list" ;;
        *) deny "git ${sub:-<none>} is not read-only" ;;
      esac
      for tok in "${t[@]:$i}"; do
        [[ "$tok" == "-c" ]] && deny "git -c can set a command to run"
        if abbrev_of "$tok" --output --ext-diff --textconv --filters --no-index --exec-path --open-files-in-pager; then
          deny "git option $tok can write, run commands or read outside the repository"
        fi
        [[ "$sub" == grep && "$tok" =~ ^-[A-Za-z]*O ]] && deny "git grep -O runs a pager command"
      done ;;
    rg)
      for tok in "${t[@]:1}"; do
        case "$tok" in --pre|--pre=*|--pre-glob*|--hostname-bin|--hostname-bin=*) deny "rg $tok runs a command" ;; esac
      done ;;
    grep|cat|head|tail|ls|wc|cut|pwd|stat) ;;
    sort)
      for tok in "${t[@]:1}"; do
        abbrev_of "$tok" --output --compress-program && deny "sort $tok writes a file or runs a program"
        [[ "$tok" =~ ^-[A-Za-z]*o ]] && deny "sort -o writes a file"
      done ;;
    uniq)
      # uniq [OPTION]... [INPUT [OUTPUT]]: a second operand is a file it WRITES.
      local operands=0 skip=0
      for tok in "${t[@]:1}"; do
        if [[ "$skip" -eq 1 ]]; then skip=0; continue; fi
        case "$tok" in
          --) deny "uniq -- would hide an output operand" ;;
          -f|-s|-w|--skip-fields|--skip-chars|--check-chars) skip=1 ;;
          -*) ;;
          *) operands=$((operands + 1)) ;;
        esac
      done
      [[ "$operands" -le 1 ]] || deny "uniq with a second operand writes it" ;;
    file)
      for tok in "${t[@]:1}"; do
        abbrev_of "$tok" --compile && deny "file --compile writes a magic file"
        [[ "$tok" =~ ^-[A-Za-z]*C ]] && deny "file -C writes a magic file"
      done ;;
    sed)
      [[ "${t[1]:-}" == "-n" && "${t[2]:-}" =~ ^[0-9]+(,[0-9]+)?p$ && ${#t[@]} -le 4 ]] || deny "sed is allowed only as: sed -n <N,Mp> file" ;;
    find)
      for tok in "${t[@]:1}"; do
        case "$tok" in -delete|-exec|-execdir|-ok|-okdir|-fprint*|-fls) deny "find $tok can write or run commands" ;; esac
      done ;;
    go)
      [[ "${t[1]:-}" == "vet" || "${t[1]:-}" == "test" ]] || deny "go ${t[1]:-<none>} is not allowed (only vet and test)"
      check_runner_args go "$GO_FLAGS" "$GO_VALUE" "$PLAIN_PATH_RE" "${t[@]:2}" ;;
    rspec)
      test_db_guard || deny "rspec is allowed only under the test-DB guard (RAILS_ENV unset/test, no non-test DATABASE_NAME)"
      check_runner_args rspec "$RSPEC_FLAGS" "$RSPEC_VALUE" "$SPEC_PATH_RE" "${t[@]:1}" ;;
    bundle)
      [[ "${t[1]:-}" == "exec" && "${t[2]:-}" == "rspec" ]] || deny "bundle ${t[1]:-} is not allowed (only bundle exec rspec)"
      test_db_guard || deny "rspec is allowed only under the test-DB guard"
      check_runner_args rspec "$RSPEC_FLAGS" "$RSPEC_VALUE" "$SPEC_PATH_RE" "${t[@]:3}" ;;
    jest)
      test_db_guard || deny "jest is allowed only under the test-DB guard"
      check_runner_args jest "$JEST_FLAGS" "$JEST_VALUE" "$PLAIN_PATH_RE" "${t[@]:1}" ;;
    npx)
      [[ "${t[1]:-}" == "jest" ]] || deny "npx ${t[1]:-} is not allowed (only npx jest)"
      test_db_guard || deny "jest is allowed only under the test-DB guard"
      check_runner_args jest "$JEST_FLAGS" "$JEST_VALUE" "$PLAIN_PATH_RE" "${t[@]:2}" ;;
    *) deny "$first is not on the read-only allowlist" ;;
  esac
}

IFS='|' read -r -a segments <<<"$cmd"
for seg in "${segments[@]}"; do check_segment "$seg"; done
exit 0
