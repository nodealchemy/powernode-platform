#!/bin/bash
# PreToolUse (Bash) — makes platform-reviewer's "read-only" shell MECHANICAL.
#
# Wired in the reviewer's OWN frontmatter (`hooks:`; Claude Code scopes a
# subagent's frontmatter hooks to that subagent), never in settings.json, so it
# does not restrict the main session or any other agent. The roster renders it
# for every role that has a shell and no Edit/Write (role[:shell_guard]).
#
# Policy: an ALLOWLIST. A command is allowed only when it is provably read-only;
# anything else, and anything this script cannot parse, is denied (exit 2, the
# reason on stderr). Denied outright: shell metacharacters that chain, redirect,
# substitute or expand (; & > < ` $ ( ) { } \ and newlines), `||`, and any
# mention of ~/.config/powernode or the unit env files. A pipe is allowed only
# between allowed commands.
#
# Allowed first words:
#   git [-C dir]  log show diff status rev-parse ls-files ls-tree cat-file
#                 merge-base blame grep, and `branch --list`; never --output,
#                 --ext-diff, --textconv or -c
#   rg grep       (rg without --pre / --hostname-bin)
#   cat head tail ls wc sort uniq cut pwd stat file
#   sed -n <N,Mp> file     (a bare print script only)
#   find           without -delete -exec -execdir -ok -okdir -fprint* -fls
#   go vet | go test
#   rspec, bundle exec rspec, jest, npx jest — only when the test-DB guard
#                 applies: RAILS_ENV unset or test and no non-test DATABASE_NAME
#                 (an exported development environment let rspec's cleaner
#                 empty the development database once)
set -uo pipefail

deny() { echo "readonly-shell-guard: denied: $1" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || deny "jq is not installed, so the command cannot be checked"
payload="$(cat 2>/dev/null || true)"
cmd="$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)" || deny "unreadable payload"
[[ -n "$cmd" ]] || deny "no command to check"

# Never touch the platform's own configuration or secrets.
case "$cmd" in
  *".config/powernode"*|*"powernode.conf"*|*"backend-default"*|*"~/.config"*|*"/.ssh"*|*"id_rsa"*|*"id_ed25519"*) deny "mentions platform configuration or secrets" ;;
esac

# Metacharacters that chain, redirect, substitute or expand.
if [[ "$cmd" == *$'\n'* || "$cmd" =~ [\;\&\>\<\`\$\(\)\{\}\\] || "$cmd" == *"||"* ]]; then
  deny "uses shell chaining, redirection, substitution or expansion"
fi

test_db_guard() {
  [[ -z "${RAILS_ENV:-}" || "${RAILS_ENV}" == "test" ]] || return 1
  [[ -z "${DATABASE_NAME:-}" || "${DATABASE_NAME}" == *test* ]] || return 1
}

check_segment() {
  local seg="$1"
  # shellcheck disable=SC2206
  local -a t=($seg)
  [[ ${#t[@]} -gt 0 ]] || deny "empty command segment"
  local first="${t[0]}" i
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
        case "$tok" in --output*|--ext-diff|--textconv|-c|--exec-path*|--open-files-in-pager*) deny "git option $tok can write or run commands" ;; esac
      done ;;
    rg)
      for tok in "${t[@]:1}"; do
        case "$tok" in --pre|--pre=*|--hostname-bin|--hostname-bin=*) deny "rg $tok runs a command" ;; esac
      done ;;
    grep|cat|head|tail|ls|wc|sort|uniq|cut|pwd|stat|file) ;;
    sed)
      [[ "${t[1]:-}" == "-n" && "${t[2]:-}" =~ ^\'?[0-9]+(,[0-9$]+)?p\'?$ && ${#t[@]} -le 4 ]] || deny "sed is allowed only as: sed -n <N,Mp> file" ;;
    find)
      for tok in "${t[@]:1}"; do
        case "$tok" in -delete|-exec|-execdir|-ok|-okdir|-fprint|-fprint0|-fprintf|-fls) deny "find $tok can write or run commands" ;; esac
      done ;;
    go) [[ "${t[1]:-}" == "vet" || "${t[1]:-}" == "test" ]] || deny "go ${t[1]:-<none>} is not allowed (only vet and test)" ;;
    rspec|jest) test_db_guard || deny "$first is allowed only under the test-DB guard (RAILS_ENV unset/test, no non-test DATABASE_NAME)" ;;
    bundle) [[ "${t[1]:-}" == "exec" && "${t[2]:-}" == "rspec" ]] && { test_db_guard || deny "rspec is allowed only under the test-DB guard"; } || deny "bundle ${t[1]:-} is not allowed (only bundle exec rspec)" ;;
    npx) [[ "${t[1]:-}" == "jest" ]] && { test_db_guard || deny "jest is allowed only under the test-DB guard"; } || deny "npx ${t[1]:-} is not allowed (only npx jest)" ;;
    *) deny "$first is not on the read-only allowlist" ;;
  esac
}

IFS='|' read -r -a segments <<<"$cmd"
for seg in "${segments[@]}"; do check_segment "$seg"; done
exit 0
