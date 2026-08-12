#!/bin/bash

# Pattern Validation Script for Powernode Platform
# Validates compliance with discovered architectural patterns

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Powernode Platform Pattern Compliance Audit ===${NC}"
echo "Date: $(date)"
echo "Platform Version: $(cat VERSION 2>/dev/null || echo 'Unknown')"
echo ""

# Initialize counters
total_checks=0
passed_checks=0
failed_checks=0
warnings=0
# Names of security-critical checks that FAILed (IDOR/account-scoping, zero-authz
# controllers, kill-switch compliance, private-schema/core-purity leaks). ANY entry
# here hard-blocks the gate (exit 2) regardless of overall compliance rate — see the
# exit-code policy at the bottom of this script.
security_critical_failed_checks=()

# Test seam: PATTERN_VALIDATION_SELFTEST lets scripts/checks/tests/pattern_validation_exit_test.sh
# exercise the exit-code policy below in isolation, without running (or faking results for)
# the full real audit. Fabricates counters/failure list, then falls straight through to the
# summary/exit-code block — the real checks are skipped entirely (see the matching `else` at
# the end of the real-audit body).
if [[ -z "${PATTERN_VALIDATION_SELFTEST:-}" ]]; then

# Function to check pattern compliance
check_pattern() {
    local description="$1"
    local command="$2"
    local expected="$3"
    local warning_threshold="$4"
    
    total_checks=$((total_checks + 1))
    echo -n "Checking: $description... "
    
    result=$(eval "$command" 2>/dev/null || echo "0")
    # Clean up result - remove newlines and get just the first number
    result=$(echo "$result" | tr -d '\n' | grep -o '[0-9]*' | head -1 | grep -v '^$' || echo "0")
    
    if [[ "$expected" == "empty" ]]; then
        if [[ -z "$result" || "$result" -eq 0 ]]; then
            echo -e "${GREEN}✓ PASS${NC}"
            passed_checks=$((passed_checks + 1))
        else
            echo -e "${RED}✗ FAIL${NC} (Found: $result)"
            failed_checks=$((failed_checks + 1))
        fi
    elif [[ "$expected" == "positive" ]]; then
        if [[ "$result" -gt 0 ]] 2>/dev/null; then
            if [[ -n "$warning_threshold" && "$result" -lt "$warning_threshold" ]] 2>/dev/null; then
                echo -e "${YELLOW}⚠ WARN${NC} (Found: $result, Expected: >=$warning_threshold)"
                warnings=$((warnings + 1))
            else
                echo -e "${GREEN}✓ PASS${NC} (Found: $result)"
                passed_checks=$((passed_checks + 1))
            fi
        else
            echo -e "${RED}✗ FAIL${NC} (Found: $result)"
            failed_checks=$((failed_checks + 1))
        fi
    else
        # Bare-numeric expected = a MAXIMUM ("should be minimal" checks): at-most semantics,
        # not exact equality — a count BELOW the ceiling is an improvement, not a warning
        # (strict -eq made the two minimal checks WARN forever once the codebase got better,
        # and would perversely re-green on a regression back to exactly the ceiling).
        if [[ "$result" -le "$expected" ]]; then
            echo -e "${GREEN}✓ PASS${NC} (Found: $result, Max: $expected)"
            passed_checks=$((passed_checks + 1))
        else
            echo -e "${YELLOW}⚠ WARN${NC} (Found: $result, Expected: <=$expected)"
            warnings=$((warnings + 1))
        fi
    fi
}

echo -e "${BLUE}## Backend Pattern Compliance${NC}"

# API Response Format Compliance
check_pattern "API response format compliance" \
    "grep -r 'render_success\\|render_error\\|render_created' server/app/controllers/ | wc -l" \
    "positive" "10"

check_pattern "Success response usage" \
    "grep -r 'render_success' server/app/controllers/ | wc -l" \
    "positive" "5"

check_pattern "Error response usage" \
    "grep -r 'render_error\\|render_validation_error\\|render_not_found' server/app/controllers/ | wc -l" \
    "positive" "5"

# Controller Pattern Compliance
check_pattern "Api::V1 namespace usage" \
    "find server/app/controllers/api/v1 -name '*.rb' | wc -l" \
    "positive" "5"

check_pattern "Controller serialization concerns" \
    "grep -r 'include.*Serialization' server/app/controllers/ | wc -l" \
    "positive" "3"

check_pattern "Permission-based authorization" \
    "grep -r 'require_permission' server/app/controllers/ | wc -l" \
    "positive" "10"

# Tenancy guard for the skill knowledge-graph reader. Ai::Skill#knowledge_graph_node
# is a bare has_one: the unique index is per [account_id, ai_skill_id] and
# sync_to_knowledge_graph gives a GLOBAL skill (account_id nil) one active node PER
# ACCOUNT by design, so for a global skill the association returns an ARBITRARY
# tenant's node. Callers holding an account must use #knowledge_graph_node_for.
# 019fedd4 / 019ff1eb converted 15 app call sites across 11 files; this keeps the
# 16th from appearing.
#
# app/ only — specs legitimately exercise the association itself (its active-only
# scoping is IMP-8eb424f427bc's coverage), so they are deliberately not scanned.
# `ds.` is excluded: Ai::DataSource has its OWN knowledge_graph_node association
# with a different (non-unique) index and its own tenancy question — see 019ff1eb.
check_pattern "Skill KG-node reads are account-scoped (no bare has_one in app/)" \
    "grep -rn '\.knowledge_graph_node\b' server/app/ --include=*.rb | grep -v 'knowledge_graph_node_for\|knowledge_graph_nodes' | grep -v 'ds\.knowledge_graph_node' | wc -l" \
    "empty" "0"

# Cross-tenant IDOR guard: api/v1 controllers must not query account-scoped
# models through a bare-constant receiver on a user param (Model.find(params[..]),
# Model.find_by(id: params[..]), Model.all). The check-account-scoping.sh guard
# baselines the current vetted set (allowlist + inline `# scoping-ok:`), so this
# FAILS only on NEW/unvetted occurrences (a real regression). Run the guard
# directly for per-file detail; here we surface PASS/FAIL into the audit.
total_checks=$((total_checks + 1))
echo -n "Checking: No new cross-tenant IDOR (account-scoping guard)... "
# Guard exits 1 on new hits; swallow under set -e and branch on the code.
if bash scripts/check-account-scoping.sh >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (New unbaselined account-scoping hit(s); run: bash scripts/check-account-scoping.sh)"
    failed_checks=$((failed_checks + 1))
    security_critical_failed_checks+=("No new cross-tenant IDOR (account-scoping guard)")
fi

# Missing-authorization guard: a user-facing api/v1 controller (excl internal/
# and worker/, which are service-token authed) must not ship a state-changing
# action with NO authorization mechanism at all (require_permission / a gate /
# authorize* before_action). check-authz-coverage.sh baselines the current
# vetted set (allowlist + inline `# authz-ok:`), so this FAILS only on a NEW
# zero-authz controller. Run the guard directly for per-file detail.
total_checks=$((total_checks + 1))
echo -n "Checking: No new zero-authz controllers (authorization-coverage guard)... "
# Guard exits 1 on new zero-authz controllers; swallow under set -e, branch on the code.
if bash scripts/check-authz-coverage.sh >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (New zero-authz controller(s); run: bash scripts/check-authz-coverage.sh)"
    failed_checks=$((failed_checks + 1))
    security_critical_failed_checks+=("No new zero-authz controllers (authorization-coverage guard)")
fi

# MCP catalog freshness guard: docs/reference/auto/mcp-tools.md is generated
# FROM Ai::Tools::PlatformApiToolRegistry::TOOLS action_definitions (rails
# mcp:generate_tool_catalog). A commit that adds/changes an MCP tool action's
# params/description without regenerating this doc leaves it silently stale —
# check-mcp-catalog-fresh.sh regenerates into the real output path and diffs
# against the committed content (ignoring the timestamp line) to catch drift,
# then restores the file so this check has no side effects of its own.
total_checks=$((total_checks + 1))
echo -n "Checking: MCP tool catalog is up to date (rails mcp:generate_tool_catalog)... "
if bash scripts/check-mcp-catalog-fresh.sh >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (Catalog stale; run: cd server && bundle exec rails mcp:generate_tool_catalog)"
    failed_checks=$((failed_checks + 1))
fi

# Inline-permission-check guard: require_permission* now raise + self-halt, but
# an inline check in an action body still runs after preceding side effects. The
# correct usage is a before_action gate. check-inline-require-permission.sh flags
# a require_permission* statement in a PUBLIC action body (excludes before_action
# lambdas, private helpers, and the `return require_permission` dispatch pattern).
total_checks=$((total_checks + 1))
echo -n "Checking: No inline require_permission in action bodies... "
if bash scripts/check-inline-require-permission.sh >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (Inline require_permission in an action body; run: bash scripts/check-inline-require-permission.sh)"
    failed_checks=$((failed_checks + 1))
fi

# In a NON-anonymous controller spec, `routes` IS Rails.application.routes and
# RouteSet#draw clears it first — so routes.draw there replaces the entire
# application route table for the rest of the process. The damage lands on
# whatever runs later, never on the spec that caused it: one such spec broke 32
# examples across three unrelated files, each of which passed in isolation.
# Mechanically checkable, so it belongs here rather than in a convention doc.
total_checks=$((total_checks + 1))
echo -n "Checking: No unrestored routes.draw in controller specs... "
if bash scripts/check-controller-spec-routes-draw.sh >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (routes.draw wipes the app route table; run: bash scripts/check-controller-spec-routes-draw.sh)"
    failed_checks=$((failed_checks + 1))
fi

# A spec that `require`s a file living inside an AUTOLOAD root bypasses Zeitwerk
# and REOPENS whatever constant that file defines, for the rest of the process.
# When two files define the same constant, the autoload path decides which one
# production sees (app/services precedes lib/), and the loser is inert — until a
# spec requires it by path. That happened: a naive duplicate of
# System::CveOps::VersionMatcher under lib/ was Zeitwerk-shadowed and unreachable
# in production, but one spec's `require Rails.root.join(...lib/...)` overwrote
# the real .vulnerable? suite-wide. RSpec loads EVERY spec file before running
# any example, so command-line order was irrelevant — merely INCLUDING that spec
# poisoned the run, which is why six examples failed in CI and passed in every
# isolation that omitted spec/lib. Fixed in extensions/system 16a636b6; this is
# the recurrence guard (IMP-fa6577beed89).
#
# Deliberately scoped to app/ and lib/ (the autoload roots). Requiring from
# config/ or db/migrate/ is legitimate and common — migrations are not
# autoloaded and must be required to be tested — so those are not matched.
# require_relative is excluded: spec support files use it and resolve
# relatively, never re-entering an autoload root by absolute path.
check_pattern "No spec requires a file inside an autoload root (Zeitwerk shadow vector)" \
    "grep -rnE '^[[:space:]]*require[[:space:]]+.*(Rails\\.root\\.join\\([^)]*[\"'\\'']((app)|(lib))[\"'\\'']|/((app)|(lib))/)' server/spec extensions/*/server/spec --include='*_spec.rb' --include='rails_helper.rb' --include='spec_helper.rb' 2>/dev/null | grep -v 'require_relative' | wc -l" \
    "empty"

# Model Structure Compliance
# Post-0.4.0 convention: native `id: :uuid` PKs with the `uuidv7()` DB default
# (the old `string :id, limit: 36` string-PK form was eliminated in the squash —
# decision #8 fixed the mis-set primary_key_type: :string).
# Agent host-path safety: a /persist-backed path declared as an unexported const
# cannot be redirected by a test seam, so any test reaching it mutates LIVE node
# state. This is not hypothetical — PendingComposePath was such a const, and the
# agent suite called os.Remove on the real staged boot composition of whatever
# host ran `go test`. The safe idiom is a `Default*` const paired with a
# redirectable var (or a config field), which this check allows.
check_pattern "Agent /persist paths are redirectable (no unexported consts)" \
    "grep -rnE '^[[:space:]]*const[[:space:]]+[a-z][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*\"/persist' extensions/system/agent --include='*.go' 2>/dev/null | grep -v '_test\.go:' | wc -l" \
    "empty"

check_pattern "UUID primary key usage (native :uuid + uuidv7 default)" \
    "grep -rh 'id: :uuid' server/db/migrate/ | wc -l" \
    "positive" "50"

check_pattern "Model frozen_string_literal pragma" \
    "find server/app/models -name '*.rb' -exec grep -L 'frozen_string_literal' {} \; | wc -l" \
    "empty"

check_pattern "Permission method implementation" \
    "grep -r 'def has_permission?' server/app/models/ | wc -l" \
    "positive" "1"

# Access control uses PERMISSIONS, never roles (model-agnostic promotion of the
# advisory hook permission-not-roles-check.sh; recall knowledge guidance-permissions-not-roles).
# The genuine silent-auth bug is calling `.include?` on the `permissions` HAS_MANY
# association, which returns Permission OBJECTS — so a name-STRING test is always
# false (e.g. `current_user.permissions.include?('x')`). The correct call is
# `current_user.has_permission?('x')`. We match the association-access form
# (`<receiver>.permissions.include?(`) rather than the hook's bare `permissions.include?(`
# regex, because the bare form has many LEGITIMATE uses that test membership in a
# name-STRING array (user_permissions / valid_permissions / effective_permissions /
# allowed_permissions / current_permissions locals, ApiKey scope arrays) — those are
# not bugs and must not fail the gate.
check_pattern "Forbidden permissions-association include? (use has_permission?)" \
    "grep -rnE '\.permissions\.include\?\(' server/app --include='*.rb' 2>/dev/null | grep -v '_spec\.rb' | wc -l" \
    "empty"

check_pattern "Model concern usage" \
    "grep -r 'include.*\\(PasswordSecurity\\|Auditable\\)' server/app/models/ | wc -l" \
    "positive" "2"

echo ""
echo -e "${BLUE}## Frontend Pattern Compliance${NC}"

# Permission-Based Access Control (CRITICAL)
check_pattern "Permission-based access control usage" \
    "grep -r 'hasPermission\|permissions.*includes' frontend/src/ | wc -l" \
    "positive" "20"

check_pattern "Forbidden role-based access (should be empty)" \
    "grep -rn 'if.*roles.*includes\|roles.*includes.*return\|canAccess.*roles\|hasRole.*roles\|checkRole.*roles' frontend/src/ | grep -v 'display\|format\|badge\|map\|filter\|length\|\.some\|admin.*components\|account.*components\|UserRolesModal\|TeamMembersManagement\|PermissionSelector\|InviteTeamMember\|SystemUserManagement' | wc -l" \
    "empty"

check_pattern "Forbidden user role access (should be empty)" \
    "grep -rn 'currentUser.*roles\?\.' frontend/src/ | grep -v 'display\|format\|badge\|member\.roles\|user\.roles.*map\|hasAdminAccess\|permissionUtils\|ProtectedRoute\|SystemUserManagement\|Header\.tsx\|PermissionsDebug' | wc -l" \
    "empty"

# Theme System Compliance
check_pattern "Theme-aware CSS classes usage" \
    "grep -r 'bg-theme-\|text-theme-\|border-theme' frontend/src/ | wc -l" \
    "positive" "50"

check_pattern "Forbidden hardcoded colors (should be minimal)" \
    "grep -r 'bg-red-\|bg-white\|text-black\|border-gray-' frontend/src/ | grep -v 'text-white' | wc -l" \
    "5"

# Color-on-color anti-pattern: text-theme-<c> on bg-theme-<c> of the SAME full
# color renders the text invisible on its own background. The fix is the fg/bg
# triad: bg-theme-<c>-bg text-theme-<c>-fg.
# IMPORTANT: the (?![-a-z]) lookahead is REQUIRED. A plain \b word-boundary also
# matches the position before -bg/-fg, so `bg-theme-<c>\b.*text-theme-<c>\b` wrongly
# flags the CORRECT triad bg-theme-<c>-bg / text-theme-<c>-fg — which produced a wave
# of false-positive "badge standardization" findings (true count is 0). Scan core +
# extension frontends.
check_pattern "Forbidden color-on-color badges (should be empty)" \
    "grep -rlP 'bg-theme-(success|error|warning|info|danger)(?![-a-z])[^\"]*text-theme-\\1(?![-a-z])' frontend/src/ extensions/*/frontend/src extensions/private/*/frontend/src 2>/dev/null | wc -l" \
    "empty"

# theme-{primary,secondary,tertiary,quaternary} are TEXT tokens; using one as a solid
# BACKGROUND paints a text color as a surface (white-on-white in dark mode). Opacity tints
# (/N), the -fg/-bg/-border triad, and comment lines are excluded. border-/ring- with these
# text tokens render high-contrast (not invisibility bugs) so are not flagged. See
# docs/reference/theme-system.md ("The #1 footgun").
check_pattern "Forbidden text-token-as-background (should be empty)" \
    "grep -rnP 'bg-theme-(primary|secondary|tertiary|quaternary)(?![\\w/-])' frontend/src/ extensions/*/frontend/src extensions/private/*/frontend/src 2>/dev/null | grep -vP ':\\s*(\\*|//|/\\*)' | wc -l" \
    "empty"

# Component Structure
check_pattern "React component forwardRef usage" \
    "grep -r 'forwardRef' frontend/src/ | wc -l" \
    "positive" "10"

check_pattern "Component displayName usage" \
    "grep -r '\.displayName' frontend/src/ | wc -l" \
    "positive" "10"

echo ""
echo -e "${BLUE}## Worker Pattern Compliance${NC}"

# BaseJob Pattern Compliance
check_pattern "BaseJob inheritance" \
    "grep -r '< BaseJob' worker/app/jobs/ | wc -l" \
    "positive" "5"

check_pattern "Forbidden ApplicationJob inheritance (should be empty)" \
    "grep -r '< ApplicationJob' worker/app/jobs/ | wc -l" \
    "empty"

check_pattern "Execute method usage" \
    "grep -r 'def execute' worker/app/jobs/ | wc -l" \
    "positive" "5"

check_pattern "Forbidden perform method overrides (should be empty)" \
    "find worker/app/jobs -name '*.rb' -exec grep -l 'def perform[^_]' {} \\; | grep -v base_job.rb | wc -l" \
    "empty"

check_pattern "Forbidden ActiveRecord usage (should be empty)" \
    "grep -rn 'ActiveRecord' worker/app/ | grep -v '# .*ActiveRecord\|health_controller\|connection_pool' | wc -l" \
    "empty"

# Server→worker job-seam guard: the server is Sidekiq-FREE, so server/app must
# never enqueue via a bare job constant (Const.perform_async/perform_later/...)
# that is undefined on the server load path — it resolves at runtime and raises
# NameError in production (the WebhookRetryJob class of bug). The dedicated
# guard verifies each enqueued constant is actually defined server-side, skips
# comments and defined?()-guarded lines, and baselines the current
# improvement-tracked set (allowlist + inline `# job-seam-ok:`), so this FAILS
# only on NEW violations. Run the guard directly for per-file detail.
total_checks=$((total_checks + 1))
echo -n "Checking: No new server→worker job-seam NameErrors (bare job-constant enqueues)... "
if bash scripts/check-server-worker-job-seam.sh >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (New bare job-constant enqueue(s) in server/app; run: bash scripts/check-server-worker-job-seam.sh)"
    failed_checks=$((failed_checks + 1))
fi

# Untracked LLM clients (IMP 019fe1da). WorkerLlmClient.for_account returns a
# client that creates NO Ai::AgentExecution — so its calls are invisible to the
# routing/cost/context oracles, and because WorkerLlmClient#track_llm_usage!
# bails without an @agent_id, they cannot debit an Ai::AgentBudget either. The
# whole provisioning pipeline was built this way and nobody noticed until a live
# dry-run measured zeros across every oracle. App services must hand the result
# to AgentBackedService#tracked_client_for (or use #build_agent_client).
#
# Counts for_account call sites in app/services that are NOT wrapped: a file is
# considered compliant when it also mentions tracked_client_for or
# build_agent_client. worker_llm_client.rb itself is excluded (it's the class),
# as is the tracked decorator.
total_checks=$((total_checks + 1))
echo -n "Checking: No untracked WorkerLlmClient.for_account in app services... "
untracked_llm=0
while IFS= read -r f; do
    case "$f" in
        */worker_llm_client.rb|*/tracked_worker_llm_client.rb|*/concerns/agent_backed_service.rb) continue ;;
    esac
    if ! grep -qE 'tracked_client_for|build_agent_client' "$f"; then
        untracked_llm=$((untracked_llm + 1))
    fi
done < <(grep -rlE 'WorkerLlmClient\.for_account' server/app 2>/dev/null)
if [[ "$untracked_llm" -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} ($untracked_llm file(s) call WorkerLlmClient.for_account without tracked_client_for/build_agent_client — their LLM calls record nothing and cannot debit a budget)"
    failed_checks=$((failed_checks + 1))
fi

echo ""
echo -e "${BLUE}## Code Quality Patterns${NC}"

# Frozen String Literal
check_pattern "Backend frozen_string_literal compliance" \
    "find server/app -name '*.rb' -exec grep -L 'frozen_string_literal' {} \; | wc -l" \
    "empty"

check_pattern "Worker frozen_string_literal compliance" \
    "find worker/app -name '*.rb' -exec grep -L 'frozen_string_literal' {} \; | wc -l" \
    "empty"

# Debug Code (should be empty)
check_pattern "Backend debug code (should be empty)" \
    "grep -rn '^[[:space:]]*\\(puts \\|puts(\\|binding\\.pry\\|byebug\\|debugger\\)' server/app/ --include='*.rb' | grep -v storage_providers | wc -l" \
    "empty"

check_pattern "Frontend debug code (should be empty)" \
    "grep -rP '^\\s*console\\.(log|debug|info)\\s*\\(' frontend/src/ --include='*.ts' --include='*.tsx' | grep -v 'logger\\.ts\\|CodeSamples\\|\\.test\\.\\|\\.spec\\.' | wc -l" \
    "empty"

check_pattern "TypeScript any types (should be minimal)" \
    "grep -r ': any' frontend/src/ | grep -v 'node_modules' | wc -l" \
    "5"

echo ""
echo -e "${BLUE}## Architecture Patterns${NC}"

# Service Architecture
check_pattern "Service object usage" \
    "find server/app/services -name '*.rb' | wc -l" \
    "positive" "5"

check_pattern "Job service integration" \
    "grep -r 'WorkerJobService' server/app/ | wc -l" \
    "positive" "3"

# Navigation Structure (should be flat, no children). The nav tree is declared in
# shared/utils/navigation.tsx (the old frontend/src/config/navigation.tsx is gone — this
# check silently passed against the missing file for months). Anti-vacuous guard: if the
# target file ever moves again, the check FAILS loudly (999) instead of passing on a
# grep error, so a relocation can't quietly disarm the rule.
check_pattern "Forbidden submenu navigation (should be empty)" \
    "if [ -f frontend/src/shared/utils/navigation.tsx ]; then grep -c 'children:' frontend/src/shared/utils/navigation.tsx; else echo 999; fi" \
    "empty"

echo ""
echo -e "${BLUE}## Schema Isolation${NC}"
# Leak guard: the committed PUBLIC db/schema.rb must contain NO table owned by a
# PRIVATE extension. Forbidden prefixes are derived dynamically from
# extensions/private/* (no slug hardcoded — generic, mirrors core-purity-check.sh).
# The enforcement is the SchemaDumper prepend (config/initializers/schema_dump_isolation.rb);
# this is the belt-and-suspenders scan backstop.
priv_prefixes=$(ls -d extensions/private/*/ 2>/dev/null | xargs -r -n1 basename | paste -sd'|')
total_checks=$((total_checks + 1))
echo -n "Checking: No private-extension table refs in public schema.rb (leak guard)... "
if [ -z "$priv_prefixes" ]; then
    leak_count=0
else
    # Any quoted private-table reference (create_table, add_foreign_key both args, add_index).
    # Safe: core has no private-extension-prefixed COLUMNS (FK columns are publisher_id, etc.).
    # NOTE: `grep -c` prints the count AND exits 1 on zero matches; under `set -e` we must
    # swallow that exit with `|| true` (NOT `|| echo 0`, which double-emits "0" -> a
    # multiline value that breaks the `-eq` test and falsely trips the FAIL branch).
    leak_count=$(grep -cE "\"(${priv_prefixes})_" server/db/schema.rb 2>/dev/null || true)
    leak_count=${leak_count:-0}
fi
if [ "$leak_count" -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (Found $leak_count private-table refs in public schema.rb: $(grep -oE "\"(${priv_prefixes})_[a-z0-9_]*\"" server/db/schema.rb 2>/dev/null | sort -u | tr '\n' ' '))"
    failed_checks=$((failed_checks + 1))
    security_critical_failed_checks+=("No private-extension table refs in public schema.rb (leak guard)")
fi

# Extension-isolation reference guard: model-agnostic mirror of the BLOCKING
# core-purity-check.sh REFERENCE gate (#9). CORE source (server/app, frontend/src —
# anything NOT under extensions/) must never reference a PRIVATE extension by name:
# its Ruby namespace (`<Cap>::`), submodule path (extensions/private/<slug>), or import
# alias (@ext/<slug>/, @<slug>/). Private-extension slugs are derived DYNAMICALLY from
# extensions/private/* — none is hardcoded (this script is core, so core-purity applies
# to it too), mirroring the hook + the schema-leak block above. Core mode (no
# extensions/private/*) => no-op PASS. Git-ignored files are excluded (mirrors the hook).
# This is the scan backstop for the blocking hook so the rule reaches non-Claude executors.
priv_iso_slugs=$(ls -d extensions/private/*/ 2>/dev/null | xargs -r -n1 basename)
total_checks=$((total_checks + 1))
echo -n "Checking: Core source references no private extension (core-purity mirror)... "
iso_files=""
for slug in $priv_iso_slugs; do
    cap="${slug^}"
    iso_pat="(\b${cap}::)|(extensions/private/${slug}\b)|(@ext/${slug}/)|(@${slug}/)"
    iso_match=$(grep -rlE "$iso_pat" server/app frontend/src \
        --include='*.rb' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
        2>/dev/null || true)
    if [ -n "$iso_match" ]; then iso_files+="${iso_match}"$'\n'; fi
done
iso_hits=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if ! git check-ignore -q "$f" 2>/dev/null; then
        iso_hits=$((iso_hits + 1))
    fi
done < <(printf '%s\n' "$iso_files" | sort -u)
if [ "$iso_hits" -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (Found $iso_hits core file(s) naming a private extension: $(printf '%s\n' "$iso_files" | sort -u | grep -v '^$' | tr '\n' ' '))"
    failed_checks=$((failed_checks + 1))
    security_critical_failed_checks+=("Core source references no private extension (core-purity mirror)")
fi

# core-purity gate (#9), PUBLIC half. CLAUDE.md's invariant is "core NEVER depends on
# extensions" — all of them. Public extensions cannot reuse the private rule verbatim:
# a private extension is ABSENT from public clones so naming one is always a leak, but a
# public one is PRESENT and core legitimately documents the seams reaching it and guards
# its constants with `defined?(...)` to degrade gracefully. So NEW references fail while
# references already committed at the time of baselining are grandfathered via
# .claude/hooks/core-purity-baseline.txt (regenerate: scripts/generate-core-purity-baseline.sh).
# Comment lines and `defined?` guards are never counted — they are sanctioned forms, not
# dependencies. Mirrors the blocking hook so the rule reaches non-Claude executors.
# No baseline file => no-op PASS (fail-open, matching the hook's doctrine).
pub_baseline=".claude/hooks/core-purity-baseline.txt"
# `|| true` is load-bearing under `set -e`: grep exits 1 on empty input, and an
# assignment takes its pipeline's status — so with no extensions/ dir (source
# tarball, git archive), or only private/ present, this line would abort the
# WHOLE gate silently before even printing its check name, skipping every
# subsequent check. A gate that dies quietly is worse than no gate.
pub_iso_slugs=$(ls -d extensions/*/ 2>/dev/null | xargs -r -n1 basename | grep -v '^private$' || true)
total_checks=$((total_checks + 1))
echo -n "Checking: Core source adds no NEW public-extension reference (core-purity mirror)... "
pub_files=""
if [ -r "$pub_baseline" ]; then
    for slug in $pub_iso_slugs; do
        pub_ns=""
        for seg in $(printf '%s\n' "$slug" | tr '-' ' '); do pub_ns+="${seg^}"; done
        pub_pat="(\b${pub_ns}::)|(extensions/${slug}\b)|(@ext/${slug}/)|(@${slug}/)"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            grep -Fxq "${f}|${slug}" "$pub_baseline" && continue          # grandfathered
            git check-ignore -q "$f" 2>/dev/null && continue
            # Code lines only — drop comment lines and defined?() guards.
            if grep -nE "$pub_pat" "$f" 2>/dev/null \
                 | grep -vE '^[0-9]+: *(#|//|\*)' | grep -qv 'defined?'; then
                pub_files+="${f}"$'\n'
            fi
        done < <(grep -rlE "$pub_pat" server/app frontend/src \
                    --include='*.rb' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
                    2>/dev/null || true)
    done
fi
pub_hits=$(printf '%s\n' "$pub_files" | sort -u | grep -cv '^$' || true)
if [ "${pub_hits:-0}" -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (Found $pub_hits core file(s) with a NEW public-extension reference: $(printf '%s\n' "$pub_files" | sort -u | grep -v '^$' | tr '\n' ' '))"
    failed_checks=$((failed_checks + 1))
    security_critical_failed_checks+=("Core source adds no NEW public-extension reference (core-purity mirror)")
fi

echo ""
echo -e "${BLUE}## Migration Version Uniqueness${NC}"
# Duplicate-migration-version guard: schema_migrations is keyed by VERSION, so if two
# migrations anywhere on the migration path (core server/ + public AND private extension
# engines) share a leading timestamp, only ONE ever runs — the other is silently treated
# as already-applied and its schema changes are never made (in test OR production).
# prepare-extension-test-db.sh WARNS at test-DB build time; this is the durable gate.
# The version is the leading numeric stamp of the filename; migration dirs are globbed so
# core mode (no extensions/private/*) and partial checkouts degrade gracefully.
total_checks=$((total_checks + 1))
echo -n "Checking: No duplicate migration versions across core + extensions... "
dup_migration_versions=$(find server/db/migrate extensions/*/server/db/migrate extensions/private/*/server/db/migrate \
    -name '[0-9]*_*.rb' 2>/dev/null | xargs -r -n1 basename | sed 's/_.*//' | sort | uniq -d)
if [ -z "$dup_migration_versions" ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (Colliding migration version(s) — only one per version will ever run; re-timestamp the newer one:)"
    while IFS= read -r v; do
        [ -n "$v" ] || continue
        echo "    version $v is used by:"
        find server/db/migrate extensions/*/server/db/migrate extensions/private/*/server/db/migrate \
            -name "${v}_*.rb" 2>/dev/null | sed 's/^/      /'
    done <<< "$dup_migration_versions"
    failed_checks=$((failed_checks + 1))
fi

echo ""
echo -e "${BLUE}## Kill-Switch Compliance (Worker)${NC}"
# Model-agnostic enforcement of worker/CLAUDE.md L11 (recall guidance-kill-switch-compliance):
# every AI-execution worker job MUST `include AiSuspensionCheckConcern` AND call
# `bail_if_ai_suspended!` so the global emergency_halt / per-account kill switch stops it.
# Delegated to the dedicated guard so the authoritative required-job list stays next to the
# logic; the guard mirrors the regression specs and does a marker sweep for new jobs.
total_checks=$((total_checks + 1))
echo -n "Checking: AI-execution worker jobs honor the kill switch (AiSuspensionCheckConcern)... "
if ks_out=$(./scripts/checks/kill-switch-compliance-check.sh 2>&1); then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "$ks_out" | sed 's/^/    /'
    failed_checks=$((failed_checks + 1))
    security_critical_failed_checks+=("AI-execution worker jobs honor the kill switch (AiSuspensionCheckConcern)")
fi

echo ""
echo -e "${BLUE}## File Organization${NC}"
# Model-agnostic enforcement of the "NEVER save files to project root" rule
# (recall knowledge guidance-file-organization). Loose docs/reports/scratch files must
# live under docs/{getting-started,concepts,guides,reference,operations,contributing}/,
# NEVER at the repo root. This scans ROOT ONLY (no recursion, -maxdepth 1) for REGULAR
# FILES not in the allowlist of legitimate top-level files below (project docs like
# README/LICENSE, build/config manifests, and dotfiles like .gitignore/.gitmodules).
# Directories are never flagged. A genuinely-new legitimate root file must be added to
# root_file_allowlist (deliberate vetting, mirroring the other baseline-style guards); a
# stray report/scratch file at root FAILS here. CLAUDE.local.md and a file-form `.git`
# (worktree checkout) are allowlisted for live/worktree parity.
root_file_allowlist=" \
  CHANGELOG.md CLAUDE.md CLAUDE.local.md CODE_OF_CONDUCT.md CONTRIBUTING.md \
  GOVERNANCE.md LICENSE Makefile README.md ROADMAP.md SECURITY.md VERSION \
  extensions_loader_helper.rb package.json package-lock.json playwright.config.ts \
  .commitlintrc.json .env.example .git .gitflow .gitignore .gitleaks.toml \
  .gitmessage .gitmodules .releaserc.json "
total_checks=$((total_checks + 1))
echo -n "Checking: No stray files at repo root (file-organization guard)... "
stray_root_files=""
while IFS= read -r rf; do
    base=$(basename "$rf")
    case " $root_file_allowlist " in
        *" $base "*) : ;;                     # allowlisted legitimate root file
        *) stray_root_files+="$base " ;;      # not vetted -> stray
    esac
done < <(find . -maxdepth 1 -type f 2>/dev/null)
stray_root_files=$(echo "$stray_root_files" | xargs 2>/dev/null || echo "")
if [ -z "$stray_root_files" ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (Stray root file(s) — move under docs/ or allowlist if legitimate: $stray_root_files)"
    failed_checks=$((failed_checks + 1))
fi

else
    case "$PATTERN_VALIDATION_SELFTEST" in
        security_critical_fail)
            total_checks=1; passed_checks=0; failed_checks=1; warnings=0
            security_critical_failed_checks+=("TEST: fabricated security-critical failure")
            ;;
        nonsecurity_fail)
            total_checks=20; passed_checks=19; failed_checks=1; warnings=0
            ;;
        *)
            echo "Unknown PATTERN_VALIDATION_SELFTEST value: $PATTERN_VALIDATION_SELFTEST (expected: security_critical_fail|nonsecurity_fail)" >&2
            exit 64
            ;;
    esac
fi

echo ""
echo -e "${BLUE}=== AUDIT SUMMARY ===${NC}"
echo "Total Checks: $total_checks"
echo -e "Passed: ${GREEN}$passed_checks${NC}"
echo -e "Failed: ${RED}$failed_checks${NC}"
echo -e "Warnings: ${YELLOW}$warnings${NC}"

# Calculate compliance percentage
if [[ $total_checks -gt 0 ]]; then
    compliance_rate=$(( (passed_checks * 100) / total_checks ))
    echo "Compliance Rate: $compliance_rate%"
    
    if [[ $compliance_rate -ge 95 ]]; then
        echo -e "${GREEN}🎉 EXCELLENT: Platform shows excellent pattern compliance!${NC}"
        exit_code=0
    elif [[ $compliance_rate -ge 85 ]]; then
        echo -e "${YELLOW}⚠️ GOOD: Platform shows good compliance with minor issues${NC}"
        exit_code=1
    else
        echo -e "${RED}❌ NEEDS WORK: Platform needs significant pattern improvements${NC}"
        exit_code=2
    fi
else
    echo -e "${RED}❌ ERROR: No checks were performed${NC}"
    exit_code=3
fi

# Exit-code policy: compliance percentage alone can dilute a hard FAIL into a
# passing rate (a single failure among ~30 checks reads as ~97%). Two overrides
# on top of the compliance-based exit_code above:
#   - ANY security-critical check FAIL (IDOR/account-scoping, zero-authz
#     controllers, kill-switch compliance, private-schema/core-purity leaks)
#     hard-blocks with exit 2, regardless of compliance rate.
#   - ANY other FAIL (failed_checks > 0) is never reported as exit 0 — it is
#     bumped to at least exit 1 so scripts/validate.sh surfaces a WARN instead
#     of silently passing.
if [[ ${#security_critical_failed_checks[@]} -gt 0 ]]; then
    echo -e "${RED}🚨 SECURITY-CRITICAL CHECK(S) FAILED — hard block regardless of compliance rate:${NC}"
    for c in "${security_critical_failed_checks[@]}"; do
        echo -e "  ${RED}✗${NC} $c"
    done
    exit_code=2
elif [[ $failed_checks -gt 0 && $exit_code -eq 0 ]]; then
    exit_code=1
fi

echo ""
echo "For detailed pattern documentation, see:"
echo "- docs/concepts/architecture.md"
echo "- docs/guides/backend.md"
echo "- docs/guides/frontend.md"
echo "- docs/guides/testing.md"

exit $exit_code