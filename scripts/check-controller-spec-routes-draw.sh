#!/bin/bash
# check-controller-spec-routes-draw.sh
#
# Fails when a NON-ANONYMOUS controller spec calls `routes.draw` without
# restoring the application's routes afterwards.
#
# WHY. In an rspec-rails controller spec, `routes` is `Rails.application.routes`
# unless the spec declares an anonymous controller — and
# ActionDispatch::Routing::RouteSet#draw calls `clear!` BEFORE evaluating its
# block. So `routes.draw` in a non-anonymous spec does not add test routes: it
# REPLACES the entire application route table with them, permanently, for the
# rest of the process.
#
# The damage lands on whatever runs later, never on the spec that caused it.
# spec/controllers/api/v1/mcp/hosting_controller_authorization_spec.rb did this
# and broke 32 examples across three unrelated files — git_controller_spec (18,
# ActionController::UrlGenerationError), onboarding_controller_spec (13) and
# users_controller_spec (1) — every one of which passed in isolation. A
# controller spec raises UrlGenerationError because it generates its own URL; a
# request spec walks a path that no longer routes and gets a plain 404, so the
# same cause presents two different ways and looks like two bugs.
#
# Two forms are safe:
#   1. An ANONYMOUS controller spec (`controller(ApplicationController) do`) —
#      rspec-rails gives those an isolated RouteSet, so the draw is contained.
#   2. Restoring afterwards with `Rails.application.reload_routes!`.
#
# Anonymous-vs-not is the distinction that matters, NOT the presence of
# routes.draw — which is why this check looks for the pair, not the call.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC_ROOTS=("$REPO_ROOT/server/spec" "$REPO_ROOT"/extensions/*/server/spec)

violations=0

for root in "${SPEC_ROOTS[@]}"; do
  [ -d "$root" ] || continue

  # Any spec that draws routes at all — the global form is always suspect, the
  # bare form only when the spec is not anonymous.
  while IFS= read -r file; do
    [ -n "$file" ] || continue

    # Safe form 2: restores the real routes.
    if grep -qE 'reload_routes!' "$file"; then
      continue
    fi

    # Safe form 1: anonymous controller spec (isolated RouteSet). Matches
    # `controller do` and `controller(SomeClass) do`.
    if grep -qE '^\s*controller[[:space:](]' "$file"; then
      # ...unless it reaches for the GLOBAL route set explicitly, which is not
      # isolated even in an anonymous spec.
      if grep -qE 'Rails\.application\.routes\.draw' "$file"; then
        echo "VIOLATION: ${file#$REPO_ROOT/} draws Rails.application.routes without reload_routes!"
        violations=$((violations + 1))
      fi
      continue
    fi

    echo "VIOLATION: ${file#$REPO_ROOT/} calls routes.draw in a non-anonymous controller spec without reload_routes!"
    violations=$((violations + 1))
  done < <(grep -rlE '(^|[^.[:alnum:]_])routes\.draw' "$root" --include='*_spec.rb' 2>/dev/null)
done

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "A non-anonymous controller spec's \`routes\` IS Rails.application.routes, and"
  echo "RouteSet#draw clears it first — the whole application route table is replaced"
  echo "for the rest of the process, breaking unrelated specs that run afterwards."
  echo "Fix: add \`after { Rails.application.reload_routes! }\`, or declare an"
  echo "anonymous controller (\`controller(ApplicationController) do\`)."
  exit 1
fi

exit 0
