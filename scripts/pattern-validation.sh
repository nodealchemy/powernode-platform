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

# System::NodeModule#current_version_id is the FLEET ACTUATOR — every instance
# carrying the module converges on whatever it points at. The guards that decide
# whether a version may become that pointer live in ModulePublicationProcessor
# (the auto_promote opt-out, the non-empty artifact floor from the 2026-08-07
# empty-erofs incident, the core-provenance verdict, the batch-atomic hold from
# the core/extension promote-skew outage), NOT in the writer — so a write that
# reaches the column by any other route gets none of them.
#
# A comment on #promote_to_version! USED TO claim it was "the platform's ONLY
# choke point" for that (deleted by IMP-9a5e40a21d70 increment 2, which is why
# this is past tense). It never was: SIX sites write the column, and a
# re-derivation from the column found the 5th and 6th that five separate readers
# of that comment had not.
#
# This is the model-agnostic twin of
# extensions/system/server/spec/lint/node_module_current_version_write_seam_spec.rb
# — which is the precise check (path#receiver equality, both directions, each
# exemption carrying its rationale and the guards it skips). This one is COARSER
# (whole-file exclusions, no receiver resolution) but has the one thing the spec
# cannot have: it runs from the repo root, so it also covers `server/` and
# `extensions/private/*`, where a writer would be invisible to an extension spec
# in a public clone.
#
# LIMIT, stated so a pass is not over-read: source scan only. A runtime-built
# attribute hash, `send(:update!, attrs)`, raw SQL, or `execute("UPDATE ...")`
# are all invisible to it. The wall is a model-layer runtime guard; this is a
# tripwire on the AUTHORED shapes. Verified to fire on all four real mechanisms
# (single-line kwarg, multi-line kwarg, in-place assign, update_all), and
# verified NOT to fire on `current_version_number:` — the benign denormalized
# column — because the regex requires the colon immediately after the name.
#
# THE TWO TWINS ARE NOT SUPERSETS OF EACH OTHER; each catches what the other
# misses, which is why both exist:
#   * this one catches a call whose earlier arguments contain a `)` inside a
#     STRING LITERAL — the spec's bracket-depth walker stops early there.
#   * the spec catches a keyword on the 3rd/4th line of a call; `-A2` here
#     reaches only the 2nd.
#
# KNOWN FALSE-POSITIVE MODE (noisy, never silent): the second grep filters the
# whole `-A2` stream, so a pure READ of the column sitting within two lines
# AFTER any update-verb call is counted. That is the same context-bleed the
# spec's walker was written to fix, and it is left here because grep cannot
# bound a call. It can only produce a spurious FAIL, never a miss. If this check
# fails on a line that is plainly a read, confirm against the spec — which
# resolves receivers and call extents — before touching the exclusion list.
#
# Two exclusion groups, and they mean DIFFERENT things:
#   extensions/system/... — the censused NodeModule writers. Adding a path here
#     is a policy decision about the fleet; make it in the spec's CENSUS first,
#     where it must name the guards it skips.
#   extensions/private/business/.../mcp/ — NOT NodeModule. Mcp::HostedServer and
#     Mcp::ServerDeployment have their own unrelated `current_version` columns;
#     the shell rule cannot resolve receivers, so they are excluded by path.
check_pattern "NodeModule#current_version_id written only by the censused seam" \
    '( grep -rn -A2 -E "(\.|^[[:space:]]*)(update!?|update_columns?|update_all|assign_attributes)\(" --include=*.rb server/app server/lib extensions/*/server/app extensions/*/server/lib extensions/*/server/db/seeds extensions/private/*/server/app extensions/private/*/server/lib 2>/dev/null | grep -E "current_version(_id)?:" ; grep -rnE "\.current_version(_id)?[[:space:]]*(\|\|)?=[^=~]|^[[:space:]]*self\.current_version(_id)?[[:space:]]*(\|\|)?=[^=~]|=[[:space:]]*\{[[:space:]]*current_version(_id)?:" --include=*.rb server/app server/lib extensions/*/server/app extensions/*/server/lib extensions/*/server/db/seeds extensions/private/*/server/app extensions/private/*/server/lib 2>/dev/null ) | grep -vE "^extensions/system/server/(app/models/system/node_module|app/services/system/(account_bootstrap_service|manifest_import_service|package_build_webhook_service)|db/seeds/cutover_renamed_modules)\.rb[:-]" | grep -vE "^extensions/private/business/server/app/models/mcp/(hosted_server|server_deployment)\.rb[:-]" | wc -l' \
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
# FROM Ai::Tools::PlatformApiToolRegistry.all_tools action_definitions (rails
# mcp:generate_tool_catalog). A commit that adds/changes an MCP tool action's
# params/description without regenerating this doc leaves it silently stale —
# check-mcp-catalog-fresh.sh regenerates into the real output path and diffs
# against the committed content (ignoring the timestamp line) to catch drift,
# then restores the file so this check has no side effects of its own. It pins
# the generation environment to the PUBLIC bundle, because `.all_tools` merges
# in whatever the loaded extension engines registered — see that script.
total_checks=$((total_checks + 1))
echo -n "Checking: MCP tool catalog is up to date (rails mcp:generate_tool_catalog)... "
if bash scripts/check-mcp-catalog-fresh.sh >/dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (Catalog stale; run: cd server && env -u BUNDLE_GEMFILE POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 POWERNODE_DEPLOYED=0 bundle exec rails mcp:generate_tool_catalog)"
    failed_checks=$((failed_checks + 1))
fi

# Claude Code agent skeleton freshness guard: .claude/agents/powernode/*.md is
# generated FROM the canonical (global, seeded) Ai::Agent rows by
# `rails claude:sync_agents` (Ai::ClaudeExport::AgentSkeletonSync) and COMMITTED
# so any checkout can Agent(subagent_type: "<slug>") a platform agent. A seed
# change that adds/renames/retiers a canonical agent — or a renderer change —
# leaves the files silently stale; check-claude-agents-fresh.sh regenerates into
# a temp dir with the PUBLIC bundle and diffs. It reads the development database,
# so on an install whose agent seeds never ran it cannot produce the set at all:
# that is exit 2 and reported as a WARN here (an empty regeneration is neither
# fresh nor stale — never a PASS), exit 1 is a real FAIL. Exit 3 is a FAILED
# generator and is scored a FAIL with its own message: a crash writes zero files
# too, so folding it into the exit-2 WARN would hide it behind this cell's
# steady state.
total_checks=$((total_checks + 1))
echo -n "Checking: Claude Code agent skeletons are up to date (rails claude:sync_agents)... "
# `|| status=$?` rather than a bare call: this script runs under `set -e`, and a
# bare non-zero exit here would abort the whole audit instead of scoring a check.
claude_agents_status=0
bash scripts/check-claude-agents-fresh.sh >/dev/null 2>&1 || claude_agents_status=$?
if [[ $claude_agents_status -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
elif [[ $claude_agents_status -eq 2 ]]; then
    echo -e "${YELLOW}⚠ WARN${NC} (Unverifiable: the dev DB holds no canonical agent; regenerate on a seeded install: cd server && env -u BUNDLE_GEMFILE POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 POWERNODE_DEPLOYED=0 bundle exec rails claude:sync_agents)"
    warnings=$((warnings + 1))
elif [[ $claude_agents_status -eq 3 ]]; then
    echo -e "${RED}✗ FAIL${NC} (The export itself FAILED — a broken renderer/migration/bundle, NOT an unseeded checkout. Run it for the error: cd server && env -u BUNDLE_GEMFILE POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 POWERNODE_DEPLOYED=0 bundle exec rails claude:sync_agents)"
    failed_checks=$((failed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (Skeletons stale; run: cd server && env -u BUNDLE_GEMFILE POWERNODE_INCLUDE_PRIVATE_EXTENSIONS=0 POWERNODE_DEPLOYED=0 bundle exec rails claude:sync_agents, then commit .claude/agents/powernode/)"
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

# Frontend console output (IMP-1f4b84af602c). This check used to match only
# console.log/debug/info, and the edit hook carried its own copy of that same
# narrow pattern — so console.warn and console.error accumulated for the life of
# the tree, unseen by either guard, and the scan reported a clean 0 on a tree
# holding 36 of them. Both guards now call scripts/list-console-sites.sh, so
# there is one definition of what counts and it cannot drift again.
#
# Pre-existing sites are grandfathered in two ledgers (regenerate with
# scripts/generate-console-log-baseline.sh): the tracked
# .claude/hooks/console-log-baseline.txt for core and public extensions, and the
# gitignored .local.txt for private-extension paths, which must never reach the
# public mirror. So this FAILS only on a NEW console call.
#
# Compared as MULTISETS via `comm`, not membership: a file legitimately holding
# two identical console.error lines has two ledger entries, and a third copy is
# a new site rather than a free ride on the first two.
#
# FAILS LOUD in two directions, because this guard exists precisely because its
# predecessor reported a clean 0 on a dirty tree: a missing ledger means every
# site reads as new, and a lister that returns nothing while the ledger holds
# entries is treated as a broken matcher, not as a clean tree.
total_checks=$((total_checks + 1))
echo -n "Checking: No new frontend console output (use @/shared/utils/logger)... "
console_tmp=$(mktemp -d)
bash scripts/list-console-sites.sh 2>/dev/null | cut -d'|' -f1,3- | sed '/^$/d' | sort > "$console_tmp/found" || true
cat .claude/hooks/console-log-baseline.txt .claude/hooks/console-log-baseline.local.txt 2>/dev/null \
    | grep -v '^#' | sed '/^$/d' | sort > "$console_tmp/baseline" || true
console_found=$(wc -l < "$console_tmp/found" | tr -d ' ')
console_baseline=$(wc -l < "$console_tmp/baseline" | tr -d ' ')
console_new=$(comm -23 "$console_tmp/found" "$console_tmp/baseline")
console_hits=$(printf '%s\n' "$console_new" | grep -cv '^$' || true)
if [ "${console_found:-0}" -eq 0 ] && [ "${console_baseline:-0}" -gt 0 ]; then
    echo -e "${RED}✗ FAIL${NC} (console site lister returned NOTHING while the baseline holds ${console_baseline} entries — broken matcher, not a clean tree; run: bash scripts/list-console-sites.sh)"
    failed_checks=$((failed_checks + 1))
elif [ "${console_hits:-0}" -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (${console_hits} new console call(s) — use @/shared/utils/logger)"
    printf '%s\n' "$console_new" | grep -v '^$' | sed 's/^/    /'
    failed_checks=$((failed_checks + 1))
fi
rm -rf "$console_tmp"

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
echo -e "${BLUE}## Inert Declarations${NC}"
# A symbol declared in a registry and referenced nowhere else has no other end —
# it is inert by construction. This codebase's dominant defect class is the
# mechanism that exists, passes review, and never fires (the build skip, the
# task reaper, the worker-scoped dispatch chain — all month-scale, all found by
# a person looking rather than by a test). This is the structural half of the
# answer: the cheap mechanical cases fail at merge instead of being rediscovered
# later as an improvement offer.
#
# RATCHET. Today's known-unconsumed set is a debt ledger inside the script, so
# this passes on a clean tree and fails only on a NEW inert declaration. Clear
# ledger entries by building the producer or deleting the declaration — never by
# adding to the list to make a build green.
check_pattern "Inert declarations (declared, referenced nowhere)" \
    "bash scripts/checks/declared-but-unconsumed.sh" \
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

# core-purity gate (#9), EXTENSION-to-EXTENSION half. The two checks above cover only
# CORE source, and the blocking hook used to exit early on ANY path under extensions/ —
# under a comment ("a file inside an extension may reference its own namespace") that
# stated a narrower rule than the code implemented. So nothing ever had an opinion on one
# extension naming ANOTHER, including a PUBLIC MIT extension naming a PRIVATE one that is
# absent from public clones. Same rule, same baseline ledger, same sanctioned forms —
# see scripts/checks/extension-cross-reference-check.sh for the full contract and its
# honest limits. Core mode (no extensions checked out) is a no-op PASS.
total_checks=$((total_checks + 1))
echo -n "Checking: Extension source references no OTHER extension (core-purity mirror)... "
# FAIL CLOSED. A security-critical gate must not turn "the check script is gone,
# renamed, or errored" into "0 hits" — that reads as a green gate for a tree nobody
# checked. So: absence is its own FAIL, and a non-numeric result (a stderr leak, an
# empty result, a crash) is a FAIL too, not a silent 0.
if [ ! -r scripts/checks/extension-cross-reference-check.sh ]; then
    echo -e "${RED}✗ FAIL${NC} (core-purity mirror script MISSING: scripts/checks/extension-cross-reference-check.sh)"
    failed_checks=$((failed_checks + 1))
    security_critical_failed_checks+=("Extension source references no OTHER extension (core-purity mirror)")
else
xext_hits=$(bash scripts/checks/extension-cross-reference-check.sh 2>/dev/null || true)
case "$xext_hits" in
    ''|*[!0-9]*)
        echo -e "${RED}✗ FAIL${NC} (core-purity mirror script MISSING a usable result: produced '"'"'$xext_hits'"'"')"
        failed_checks=$((failed_checks + 1))
        security_critical_failed_checks+=("Extension source references no OTHER extension (core-purity mirror)")
        xext_hits=""
        ;;
esac
if [ -z "$xext_hits" ]; then
    : # already reported above
elif [ "$xext_hits" -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (Found $xext_hits extension file(s) naming ANOTHER extension: $(bash scripts/checks/extension-cross-reference-check.sh --list 2>/dev/null | tr '\n' ' '))"
    failed_checks=$((failed_checks + 1))
    security_critical_failed_checks+=("Extension source references no OTHER extension (core-purity mirror)")
fi
fi

# Deployment-identifier leak guard. Powernode is a platform OTHER people deploy: THIS
# deployment's hostnames, internal IP ranges, VM ids and operator details are irrelevant
# to every other deployment and a gratuitous disclosure on the public mirror. Their home
# is the deployment's own platform knowledge (tag deployment-*), never a tracked file —
# docs/contributing/conventions/deployment-knowledge.md. The identifier patterns live in
# the GITIGNORED .claude/hooks/deployment-identifiers.local.txt: a guard against name
# leakage must not itself contain the names, so no list => no-op PASS (a public clone
# has no deployment to protect yet). Scans every file git would publish — tracked
# PLUS untracked-not-ignored, so a brand-new file is checked by the author who is
# running the gate rather than by whoever runs it next — in core and in each
# PUBLIC extension submodule (each publishes on its own); private extensions and
# gitignored files are out of scope by construction. The edit-time hook
# .claude/hooks/deployment-identifier-check.sh runs the same script per file.
total_checks=$((total_checks + 1))
echo -n "Checking: No deployment-local identifiers in tracked or new files (leak guard)... "
# FAIL CLOSED on a missing/broken script, same doctrine as the core-purity mirror above.
if [ ! -r scripts/checks/deployment-identifier-check.sh ]; then
    echo -e "${RED}✗ FAIL${NC} (leak-guard script MISSING: scripts/checks/deployment-identifier-check.sh)"
    failed_checks=$((failed_checks + 1))
    security_critical_failed_checks+=("No deployment-local identifiers in tracked or new files (leak guard)")
else
depl_hits=$(bash scripts/checks/deployment-identifier-check.sh 2>/dev/null || true)
case "$depl_hits" in
    ''|*[!0-9]*)
        echo -e "${RED}✗ FAIL${NC} (leak-guard script produced no usable result: '"'"'$depl_hits'"'"')"
        failed_checks=$((failed_checks + 1))
        security_critical_failed_checks+=("No deployment-local identifiers in tracked or new files (leak guard)")
        depl_hits=""
        ;;
esac
if [ -z "$depl_hits" ]; then
    : # already reported above
elif [ "$depl_hits" -eq 0 ]; then
    if [ -r .claude/hooks/deployment-identifiers.local.txt ]; then
        echo -e "${GREEN}✓ PASS${NC}"
    else
        echo -e "${GREEN}✓ PASS${NC} (no deployment identifier list on this checkout — nothing to guard)"
    fi
    passed_checks=$((passed_checks + 1))
else
    echo -e "${RED}✗ FAIL${NC} (Found $depl_hits file(s) naming a deployment-local identifier: $(bash scripts/checks/deployment-identifier-check.sh --list 2>/dev/null | cut -d: -f1 | sort -u | tr '\n' ' '))"
    echo "    Run 'bash scripts/checks/deployment-identifier-check.sh --list' for the matching lines."
    echo "    Remedy: docs/contributing/conventions/deployment-knowledge.md (genericize the text; keep the real value in platform knowledge or docs/operations/local/)." 
    failed_checks=$((failed_checks + 1))
    security_critical_failed_checks+=("No deployment-local identifiers in tracked or new files (leak guard)")
fi
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
echo -e "${BLUE}## Frontend Conventions${NC}"
# Native browser dialogs (window.confirm / window.prompt) in frontend source. They are
# unthemed and unstyleable, block the JS thread, are silently suppressed in sandboxed
# iframes and by browsers that throttle repeated dialogs, render a `\n`-formatted warning
# as flat text, and carry no loading state — so a destructive action gated on one has no
# way to show that it is in flight. The shared ConfirmationModal / useConfirmation hook
# (frontend/src/shared/components/ui/ConfirmationModal.tsx) is the replacement, with
# useReasonConfirm for the reason-carrying variant. NEW call sites FAIL; sites already
# committed when this landed are grandfathered per-file WITH A COUNT in
# .claude/hooks/native-dialog-baseline.txt, so a baselined file cannot quietly grow more.
# Comment lines are never counted (a convention doc quoting `window.prompt(...)` is a
# sanctioned form, not a dependency) — same rule as the core-purity mirror above.
#
# FAIL CLOSED on a missing baseline. The baseline file is this check's ONLY input, so
# "no baseline => PASS" would let deleting one tracked file turn the guard into a
# permanently-green no-op that scans nothing — the shape a gate must never have.
#
# Only the `window.`-qualified forms are matched, deliberately: `confirm({ ... })` with no
# receiver is the shared hook's OWN call, so matching the bare global would flag every
# correct migration. A future evasion via bare `confirm(` is a known, accepted gap.
nd_baseline=".claude/hooks/native-dialog-baseline.txt"
total_checks=$((total_checks + 1))
echo -n "Checking: No new native browser dialogs in frontend source (window.confirm/prompt)... "
nd_offenders=""
if [ ! -r "$nd_baseline" ]; then
    echo -e "${RED}✗ FAIL${NC} (baseline ledger MISSING or unreadable: $nd_baseline)"
    failed_checks=$((failed_checks + 1))
else
    # Public extensions sit at extensions/<slug>/frontend/src; private ones are one level
    # deeper at extensions/private/<slug>/frontend/src. Both are scanned; an unmatched
    # glob leaves the literal string, which `[ -d ]` rejects (core mode is a clean no-op).
    nd_roots="frontend/src"
    for ext_fe in extensions/*/frontend/src extensions/private/*/frontend/src; do
        [ -d "$ext_fe" ] && nd_roots+=" $ext_fe"
    done
    while IFS= read -r ndf; do
        [ -n "$ndf" ] || continue
        # Code lines only — drop comment lines (`#`, `//`, ` * `), tab-indented included.
        # `|| true` is load-bearing under `set -e`: grep -c exits 1 when it counts zero,
        # and an assignment takes its pipeline's status, so a comment-only file would
        # abort the WHOLE gate here and silently skip every check after it.
        nd_count=$(grep -nE 'window\.(confirm|prompt)\(' "$ndf" 2>/dev/null \
                     | grep -vcE '^[0-9]+:[[:space:]]*(#|//|\*)' || true)
        [ "${nd_count:-0}" -gt 0 ] || continue
        nd_allowed=$(grep -E "^${ndf}\|" "$nd_baseline" 2>/dev/null | head -1 | cut -d'|' -f2 || true)
        # A non-numeric allowance (a typo, a trailing space, a CRLF line ending) must not
        # make `[ N -gt "$nd_allowed" ]` error out INSIDE an `if` — that returns non-zero,
        # skips the append, and silently EXEMPTS the file. Anything unparseable is 0.
        case "$nd_allowed" in
            ''|*[!0-9]*) nd_allowed=0 ;;
        esac
        if [ "$nd_count" -gt "$nd_allowed" ]; then
            nd_offenders+="${ndf}(${nd_count}>${nd_allowed}) "
        fi
    done < <(grep -rlE 'window\.(confirm|prompt)\(' $nd_roots \
                --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
                2>/dev/null || true)
    if [ -z "$nd_offenders" ]; then
        echo -e "${GREEN}✓ PASS${NC}"
        passed_checks=$((passed_checks + 1))
    else
        echo -e "${RED}✗ FAIL${NC} (Use useConfirmation from @/shared/components/ui/ConfirmationModal instead: $nd_offenders)"
        failed_checks=$((failed_checks + 1))
    fi
fi

# ---------------------------------------------------------------------------
# Deep relative imports in a public extension frontend (IMP-003653cb5634).
#
# An extension's own tree is reachable two ways: `@system/features/...` and a
# stack of `../`. The alias is stable under a move; the relative form re-points
# every climb the moment a component changes directory, and it does so silently
# — tsc resolves the NEW path if one happens to exist there, so a file dragged
# one level up can start importing a different module that still type-checks.
#
# Three climbs is the threshold, not two: `../../types` stays inside a feature
# and reads as local, while `../../../` has already left it. That is exactly the
# 61 sites this check was written against, all converted in the same change.
#
# Public AND private extension trees, like the native-dialog guard above. An
# earlier draft of this check scanned public trees only, justified by the rule
# that a tracked core file may not name a private extension — which is true, and
# which the SPLIT LEDGER already solves: private paths go in the gitignored
# .local.txt sibling, exactly as the console-log and core-purity baselines do.
# Excluding them would have left 125 of the 128 offending files fleet-wide
# unguarded on a reason that does not hold.
#
# Grandfathered per file WITH A COUNT, and it is a RATCHET in both directions: a
# listed file that grows fails, and a listed file that shrinks, is fixed or is
# deleted ALSO fails, so the ledger cannot outlive the debt it describes. FAIL
# CLOSED on a missing tracked baseline — it is this check's only way to tell
# known debt from new, so "no baseline => PASS" would turn a deleted file into a
# permanently-green no-op.
#
# Single-quoted `from '...'` only. A double-quoted or dynamic `import('...')`
# form is invisible here; none exists in any extension frontend today, and this
# is a known, accepted gap of the same kind the native-dialog guard records.
#
# The convention this enforces is documented in
# docs/contributing/conventions/frontend-patterns.md, whose Enforcement column
# named scripts/convert-relative-imports.sh. That script is real, but it never
# enforced anything, for three independent reasons: no hook, gate or CI step runs
# it (its only caller is the /cleanup all skill, invoked by hand); it hardcodes
# SRC_ROOT="frontend/src", so it cannot see an extension tree; and its output
# alphabet is @/shared/ and @/features/ only, so it could never emit @system/
# even if it reached these files. A rule whose only enforcement is an on-demand
# fixer that cannot produce the required alias is not enforced, which is how 61
# sites accumulated while the doc read as covered.
dri_baseline=".claude/hooks/deep-relative-import-baseline.txt"
total_checks=$((total_checks + 1))
echo -n "Checking: Extension frontends use path aliases, not deep relative imports... "
dri_offenders=""
if [ ! -r "$dri_baseline" ]; then
    echo -e "${RED}✗ FAIL${NC} (baseline ledger MISSING or unreadable: $dri_baseline)"
    failed_checks=$((failed_checks + 1))
else
    dri_roots=""
    for ext_fe in extensions/*/frontend/src extensions/private/*/frontend/src; do
        [ -d "$ext_fe" ] && dri_roots+=" $ext_fe"
    done
    # Every ledger entry whose tree IS present, tracked plus the gitignored
    # private half.
    dri_entries=$(cat "$dri_baseline" .claude/hooks/deep-relative-import-baseline.local.txt 2>/dev/null \
                    | grep -cE '^extensions/[^|]+\|' || true)
    if [ -z "$dri_roots" ] && [ "${dri_entries:-0}" -gt 0 ]; then
        # A lister that returns nothing while the ledger holds entries is a
        # broken matcher, not a clean tree — the same reasoning the console-log
        # check applies. Core mode with an EMPTY ledger is the clean case below.
        echo -e "${RED}✗ FAIL${NC} (no extension frontend trees found, but the ledger holds ${dri_entries} entr(y/ies) — submodules uninitialised?)"
        failed_checks=$((failed_checks + 1))
    elif [ -z "$dri_roots" ]; then
        # Core mode, or a clone with no extension checked out, and nothing
        # claimed. A clean pass, not a silent skip of a check that had input.
        echo -e "${GREEN}✓ PASS${NC} (no extension frontend trees present)"
        passed_checks=$((passed_checks + 1))
    else
        while IFS= read -r drif; do
            [ -n "$drif" ] || continue
            # Comment lines are never counted: a header or a convention doc
            # quoting the bad form is describing it, not depending on it. The
            # `|| true` keeps a zero count from aborting the gate under `set -e`.
            dri_count=$(grep -nE "from '(\.\./){3,}" "$drif" 2>/dev/null \
                          | grep -vcE '^[0-9]+:[[:space:]]*(#|//|\*|/\*)' || true)
            [ "${dri_count:-0}" -gt 0 ] || continue
            dri_allowed=$(cat "$dri_baseline" .claude/hooks/deep-relative-import-baseline.local.txt 2>/dev/null \
                            | grep -E "^${drif}\|" | head -1 | cut -d'|' -f2 || true)
            case "$dri_allowed" in
                ''|*[!0-9]*) dri_allowed=0 ;;
            esac
            if [ "$dri_count" -gt "$dri_allowed" ]; then
                dri_offenders+="${drif}(${dri_count}>${dri_allowed}) "
            fi
        done < <(grep -rlE "from '(\.\./){3,}" $dri_roots \
                    --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
                    2>/dev/null || true)
        # The other half of the ratchet: an entry that outlived its debt. Without
        # this the ledger is only a floor, and "can only shrink" is a claim the
        # check does not make true.
        dri_stale=""
        while IFS='|' read -r dri_path dri_want; do
            case "$dri_path" in ''|\#*) continue ;; esac
            case "$dri_want" in ''|*[!0-9]*) continue ;; esac
            # Only judge entries whose tree is on disk; an absent submodule is
            # not evidence its files were fixed.
            dri_tree="${dri_path%%/frontend/*}/frontend/src"
            [ -d "$dri_tree" ] || continue
            if [ ! -f "$dri_path" ]; then
                dri_stale+="${dri_path}(file gone) "
                continue
            fi
            dri_now=$(grep -nE "from '(\.\./){3,}" "$dri_path" 2>/dev/null \
                        | grep -vcE '^[0-9]+:[[:space:]]*(#|//|\*|/\*)' || true)
            [ "${dri_now:-0}" -lt "$dri_want" ] && dri_stale+="${dri_path}(${dri_now}<${dri_want}) "
        done < <(cat "$dri_baseline" .claude/hooks/deep-relative-import-baseline.local.txt 2>/dev/null || true)

        if [ -z "$dri_offenders" ] && [ -z "$dri_stale" ]; then
            echo -e "${GREEN}✓ PASS${NC}"
            passed_checks=$((passed_checks + 1))
        elif [ -n "$dri_offenders" ]; then
            echo -e "${RED}✗ FAIL${NC} (use the extension's own path alias, e.g. @system/: $dri_offenders)"
            failed_checks=$((failed_checks + 1))
        else
            echo -e "${RED}✗ FAIL${NC} (ledger entries outlived their debt — lower or delete them: $dri_stale)"
            failed_checks=$((failed_checks + 1))
        fi
    fi
fi

# ---------------------------------------------------------------------------
# ResponsiveListContainer adoption (IMP-91dab7a7dfb0) — WARNING level.
#
# The container absorbs the list chrome — initial-load spinner, empty state,
# filter row with refresh, count summary, desktop/mobile split — that every
# list component used to re-implement. A .tsx that renders a <table> without
# IMPORTING it is re-implementing that chrome again, so the empty and error
# copy drifts between hubs and each chrome fix has to be made once per file.
#
# WARNING, not FAIL, and deliberately so: some tables legitimately live inside
# a modal, inside a composite tab, or in a presentational sub-table that takes
# its rows as a prop. Those, plus the files still owing the conversion, are
# listed in the baseline below and subtracted here, so this WARN fires ONLY on
# debt that is new — a warning that can never go green is one a reader learns
# to scroll past, which costs the warnings that do matter.
#
# Matches an IMPORT, not a mention: keying on containment would let a single
# comment naming the container remove a file from this scan for good. Comment
# lines are not counted on the <table side either, matching the guards above.
#
# FAIL CLOSED on a missing baseline, for the same reason as the native-dialog
# ledger: the baseline is this check's only way to tell known debt from new, so
# "no baseline => PASS" would turn deleting one file into a silent no-op.
rlc_baseline=".claude/hooks/responsive-list-container-baseline.txt"
total_checks=$((total_checks + 1))
echo -n "Checking: Extension tables route their list chrome through ResponsiveListContainer... "
if [ ! -r "$rlc_baseline" ]; then
    echo -e "${RED}✗ FAIL${NC} (baseline ledger MISSING or unreadable: $rlc_baseline)"
    failed_checks=$((failed_checks + 1))
else
    rlc_offenders=""
    rlc_roots=""
    # Scope to extension trees that actually DEFINE a ResponsiveListContainer.
    # An extension without one has nothing to adopt. Private extensions are
    # included, matching the other frontend guards in this script.
    for rlc_root in extensions/*/frontend/src extensions/private/*/frontend/src; do
        [ -d "$rlc_root" ] || continue
        find "$rlc_root" -name 'ResponsiveListContainer.tsx' -print -quit 2>/dev/null | grep -q . \
            && rlc_roots="$rlc_roots $rlc_root"
    done
    if [ -z "$rlc_roots" ]; then
        # No extension defines the container in this checkout (core-mode clone,
        # or public extensions only). Nothing to scan is not the same as
        # nothing to find, so say which it is.
        echo -e "${GREEN}✓ PASS${NC} (no extension frontend defines ResponsiveListContainer)"
        passed_checks=$((passed_checks + 1))
    else
        while IFS= read -r rlcf; do
            case "$rlcf" in *.test.tsx) continue ;; esac
            rlc_hits=$(grep -nE '<table' "$rlcf" 2>/dev/null \
                         | grep -vcE '^[0-9]+:[[:space:]]*(#|//|\*)' || true)
            [ "${rlc_hits:-0}" -gt 0 ] || continue
            grep -qE '^[[:space:]]*import[[:space:]].*ResponsiveListContainer' "$rlcf" && continue
            # Known debt (exempt or still-owed) is listed in the baseline.
            grep -qxF "$rlcf" "$rlc_baseline" && continue
            rlc_offenders+="${rlcf} "
        done < <(grep -rlE '<table' $rlc_roots --include='*.tsx' 2>/dev/null || true)
        if [ -z "$rlc_offenders" ]; then
            echo -e "${GREEN}✓ PASS${NC}"
            passed_checks=$((passed_checks + 1))
        else
            rlc_count=$(printf '%s' "$rlc_offenders" | wc -w | tr -d ' ')
            echo -e "${YELLOW}⚠ WARN${NC} (${rlc_count} NEW table component(s) outside the container; adopt it or add a reasoned entry to $rlc_baseline: $rlc_offenders)"
            warnings=$((warnings + 1))
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Shared error / loading feedback (IMP-fb105f6edaa3) — WARNING level.
#
# Core ships ui/ErrorAlert and ui/LoadingSpinner. A hand-rolled
# `bg-theme-danger-bg text-theme-danger-fg` banner has no icon and no dismiss
# affordance unless its own site adds them, and a `p-8 text-center
# text-theme-secondary` "Loading X…" div looks different from the spinner every
# neighbouring surface uses. Both are duplication with a visible cost.
#
# WARNING, not FAIL, for the same reason as the container scan above: a few
# sites legitimately keep their own markup — a banner carrying rich JSX that
# ErrorAlert's `message: string` would flatten, a permission-denial notice that
# is not a failed operation, an EMPTY-state box that happens to wear the same
# three classes as the loading block. Those live in the baseline and are
# subtracted, so this fires only on NEW debt.
#
# The baseline is keyed `error:<path>` / `loading:<path>`, NOT by path alone.
# A file excused for its empty-state box must not thereby be excused for an
# error banner someone hand-rolls into it later.
#
# Matching is scoped to a double-quoted className, so a `hover:` in a sibling
# attribute cannot suppress a real finding. Within a className, `hover:`
# excludes only the DANGER pair: a banner has no hover state, so that token
# marks a destructive BUTTON wearing the danger colours. The loading trio
# carries no such exclusion — it is a layout, not a colour.
#
# This mirrors extensions/system's sharedFeedback.contract.test.ts, which is
# the stricter of the two: its regex can span newlines, so a className broken
# across lines is caught there and not here. That asymmetry is deliberate —
# jest red / gate green is the safe direction — but it means the jest ratchet,
# not this scan, is the authority inside extensions/system.
#
# FAIL CLOSED on a missing baseline, like the two ledgers above.
sf_baseline=".claude/hooks/shared-feedback-baseline.txt"
total_checks=$((total_checks + 1))
echo -n "Checking: Extension error/loading states use shared ErrorAlert + LoadingSpinner... "
if [ ! -r "$sf_baseline" ]; then
    echo -e "${RED}✗ FAIL${NC} (baseline ledger MISSING or unreadable: $sf_baseline)"
    failed_checks=$((failed_checks + 1))
else
    sf_offenders=""
    sf_roots=""
    # Only trees that have ALREADY adopted ui/ErrorAlert. A tree that has not
    # migrated at all is not carrying "new" debt — every one of its banners
    # predates the shared component there, and warning on all of them at every
    # gate run is noise an unrelated extension cannot act on. It joins this
    # ledger by adopting ErrorAlert once, which is the same shape as the
    # container scan's "trees that define a container".
    for sf_root in extensions/*/frontend/src extensions/private/*/frontend/src; do
        [ -d "$sf_root" ] || continue
        grep -rql "ui/ErrorAlert" "$sf_root" 2>/dev/null || continue
        sf_roots="$sf_roots $sf_root"
    done
    if [ -z "$sf_roots" ]; then
        echo -e "${GREEN}✓ PASS${NC} (no extension frontend tree has adopted ErrorAlert)"
        passed_checks=$((passed_checks + 1))
    else
        while IFS= read -r sff; do
            case "$sff" in *.test.tsx) continue ;; esac
            sf_classes=$(grep -oE 'className="[^"]*"' "$sff" 2>/dev/null || true)
            if printf '%s\n' "$sf_classes" \
                 | grep -F 'bg-theme-danger-bg text-theme-danger-fg' \
                 | grep -qv 'hover:'; then
                grep -qxF "error:$sff" "$sf_baseline" || sf_offenders+="error:${sff} "
            fi
            if printf '%s\n' "$sf_classes" \
                 | grep -qF 'p-8 text-center text-theme-secondary'; then
                grep -qxF "loading:$sff" "$sf_baseline" || sf_offenders+="loading:${sff} "
            fi
        done < <(grep -rlE 'bg-theme-danger-bg text-theme-danger-fg|p-8 text-center text-theme-secondary' \
                    $sf_roots --include='*.tsx' 2>/dev/null || true)
        if [ -z "$sf_offenders" ]; then
            echo -e "${GREEN}✓ PASS${NC}"
            passed_checks=$((passed_checks + 1))
        else
            sf_count=$(printf '%s' "$sf_offenders" | wc -w | tr -d ' ')
            echo -e "${YELLOW}⚠ WARN${NC} (${sf_count} NEW hand-rolled error/loading block(s); use ErrorAlert / LoadingSpinner, or add a reasoned entry to $sf_baseline: $sf_offenders)"
            warnings=$((warnings + 1))
        fi
    fi
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