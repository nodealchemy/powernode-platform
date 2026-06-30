# CLAUDE.md Rules — Model-Agnostic Suitability Audit

**Status:** Report-only (do NOT migrate from this doc; it is an evaluation). Generated 2026-06-30.
**Question answered:** for every rule currently held in a Claude-specific `CLAUDE.md`, *should it instead
live in a home readable by ALL executors* (Claude Code / Grok / Codex / Gemini via the MCP-agnostic
dev-loop pull queue), which never read `CLAUDE.md`?

## Why this matters (framing)

`CLAUDE.md` is loaded **only by Claude**. The Powernode dev-loop drives **MCP-agnostic CLI executors**.
A rule that must bind *all* executors but lives only in `CLAUDE.md` is **mis-homed**. The model-agnostic
homes are:

- **Platform knowledge** (`create_knowledge`, tag `guidance-*`) — queryable by any agent via `search_knowledge`. Canonical home for cross-executor rules.
- **Agent system-prompts** — rules an agent must always carry without an MCP query (baseline guardrails).
- **Skills** (`.claude/skills/*` + platform skills) — procedural, invoke-when-relevant workflows.
- **Mechanical enforcement** — `scripts/pattern-validation.sh` + `scripts/validate.sh` + the **git `pre-commit` hook** installed by `scripts/install-git-hooks.sh`. *This* path is model-agnostic (fires for any committer). The `.claude/hooks/*.sh` are a **Claude-only** edit-time nudge layer on top — necessary but NOT sufficient for non-Claude executors.
- **Loop guardrails** (the Ralph-loop `guardrails` array, delivered in the `dev_next_task` payload) — per-iteration rules every loop executor receives regardless of model.
- **Stays in CLAUDE.md** — only if genuinely Claude/harness-specific, OR the deliberate outage-safe core that must hold even if MCP is down. For these, a model-agnostic **copy** may still be warranted.

> **Mechanical-enforcement nuance (used throughout):** "already enforced by a hook" is only *partly*
> model-agnostic. `.claude/hooks/*.sh` run for Claude Code only. The truly cross-executor enforcement is
> `scripts/pattern-validation.sh` (run by the git pre-commit hook from `install-git-hooks.sh`, by
> `scripts/validate.sh`, and by the loop verification gate). Where a rule is "hook + scan", the **scan**
> is the model-agnostic half; the hook is a Claude convenience.

---

## Executive Summary

- **Rules audited:** 53 distinct rules across `CLAUDE.md` (root), `server/CLAUDE.md`, `frontend/CLAUDE.md`, `worker/CLAUDE.md`, plus 2 personal rules in `~/.claude/CLAUDE.md`.
- **Already have a model-agnostic home (no migration needed):** ~30 — the mechanical scans (`pattern-validation.sh` + ruby/ts hooks), the `conventions/*.md` docs recalled via `search_knowledge` + SessionStart digest (MCP-first, knowledge-lifecycle, testing, service-ops), and the rules already baked into the loop `guardrails` arrays (test-first, 3-strikes, one-task, commit-to-branch, core-purity).
- **Recommend migrating to a model-agnostic home (action):** ~16 — of which **→ platform knowledge (`guidance-*`): ~12**, **→ agent system-prompt: 2**, **→ new `pattern-validation.sh` scan: 1 (kill-switch)**, **→ loop guardrail addition: 1 (never-batch-approve)**.
- **Stays in CLAUDE.md (Claude/harness-specific or outage-safe core):** 4, plus the 2 personal `~/.claude` rules.
- **Already migrated (DONE — do not re-recommend):** 2 — `guidance-secret-safety` ("never emit secrets in generated artifacts") and `guidance-agent-escalation` ("no permission laundering").

### Top 5 priority migrations (safety/governance currently binding only Claude)

1. **Worker kill-switch compliance** — *"All AI execution jobs MUST include `AiSuspensionCheckConcern`"* (`worker/CLAUDE.md`) → **new `pattern-validation.sh` scan** (+ `guidance-kill-switch-compliance`). It is a core *safety* invariant, mechanically checkable, and has **zero enforcement today** — it lives only in a file non-Claude executors never read. Highest value: a non-Claude executor can add an AI job that silently bypasses the kill switch.
2. **Cryptographic Material Safety — full 7-rule table** (`CLAUDE.md` §Crypto) → **`guidance-crypto-material-safety`** + agent system-prompt. Only the "no-secrets-in-artifacts" subset is migrated (`guidance-secret-safety`); the other six (no CLI key-gen, Vault-only storage, audit all key ops, no key args in logs, no keys in code, guide-don't-handle) still bind Claude only.
3. **Bulk-operation safety / never batch-approve** (`CLAUDE.md` §Bulk) → **agent system-prompt + loop guardrail** (`guidance-bulk-op-safety`). Autonomous loop executors draining a queue are exactly the actors that batch-approve permission grants / financial ops / auto-discovered code changes — the rule must reach them.
4. **Reuse First** — discover skills/knowledge before greenfield (`CLAUDE.md` §Design) → **`guidance-reuse-first`** + agent prompt. Directly governs what a dev-loop executor builds; today only Claude is told to query first.
5. **Permission-based access control (permissions, never roles)** (`CLAUDE.md` §Permission) → **strengthen `pattern-validation.sh`** (promote `permission-not-roles-check.sh` from advisory to a scan check) + `guidance-permissions-not-roles`. Security boundary; the model-agnostic scan exists only as an advisory Claude hook today.

### Genuinely Claude-only — must NOT move

- **Auto-memory consult** (`MEMORY.md`) — a Claude Code harness feature (relevance-injected); no analog for other executors.
- **"Where guidance lives" routing table** and **"Specialists & Documentation" table** — meta-navigation telling *Claude* how its own homes/hooks are wired. Non-Claude executors reach the same content directly via `search_knowledge`; a copy would be noise.
- **CWD verification before `git add`/`commit`** — guards a Claude tool-drift failure mode (subdir/worktree CWD); keep in core (a loop-guardrail copy is optional, see toss-ups).
- The 2 personal `~/.claude/CLAUDE.md` rules — personal harness prefs (see Group G).

### Judgment toss-ups worth user input

- **Terminology table** — migrate to `guidance-terminology` (helps any executor write correct commit/PR prose) or leave as low-stakes core? Leaning: low-value migrate.
- **Git branch-flow / no-"v"-prefix / staged-commits** — loop executors commit only to loop branches and never push, so branch-flow barely binds them; the "no AI attribution" + "staged by concern" parts do. Migrate the latter two; leave branch-flow as core?
- **CWD-verification** — copy into loop guardrails for non-Claude executors that also operate in worktrees, or treat as Claude-only?

---

## Group A — → Platform knowledge (`guidance-*`)  *[primary home; cross-executor recall via `search_knowledge`]*

| # | Rule (short) | Source:section | Nature | Already model-agnostic? | Recommended home(s) | Keep CLAUDE.md ref? | Rationale |
|---|---|---|---|---|---|---|---|
| 1 | **Crypto material safety — full 7-rule table** (no key output, no keys in code, no CLI key-gen, Vault-only, audit all key ops, no key args in logs, guide-don't-handle) | CLAUDE.md §Cryptographic Material Safety | safety | Partial — only `guidance-secret-safety` (artifact subset) migrated | **`guidance-crypto-material-safety`** + agent system-prompt | Yes (canonical, outage-safe) | Any executor can generate/log key material; binds all. **PRIORITY #2** |
| 2 | **Reuse First** — discover_skills + search_knowledge + code_semantic_search before greenfield | CLAUDE.md §Design Principles | governance | Partial (mcp-first-workflow.md covers querying, not the "don't greenfield" mandate) | **`guidance-reuse-first`** + agent prompt | Brief ref | Governs what a dev-loop executor builds. **PRIORITY #4** |
| 3 | Audit = report only (save findings to docs/, don't implement unless told) | CLAUDE.md §Design | governance | No | `guidance-audit-report-only` (+ reflected in audit/improve skills) | Brief ref | An executor told to "audit" must not start editing — binds all |
| 4 | Surface Assumptions before ambiguous implementation | CLAUDE.md §Design | governance/behavioral | No | `guidance-surface-assumptions` + agent prompt | Brief ref | Behavioral guardrail every autonomous executor needs |
| 5 | Trace Changes to Request — revert adjacent "improvements" (scope creep) | CLAUDE.md §Design | convention | Partial — loop guardrail "minimal change tracing to the task" | `guidance-trace-to-request` (loop guardrail already partial) | Brief ref | Reinforces a rule loops already carry; generalize to all agents |
| 6 | Plan Before Multi-File (3+ files → outline + approval) | CLAUDE.md §Design | convention | No | `guidance-plan-before-multifile` | Brief ref | Workflow discipline for any executor doing wide changes |
| 7 | Dead Reference Cleanup after deleting a file | CLAUDE.md §Design | convention | No | `guidance-dead-reference-cleanup` | Brief ref | Hygiene rule applicable to all executors |
| 8 | Pull, Never Push (downstream pulls; ask if unsure of data-flow direction) | CLAUDE.md §Architecture | architecture | No | `guidance-pull-never-push` | Brief ref | Architecture invariant binding any code-writing executor |
| 9 | Service Boundaries — cross-namespace via service interfaces, never direct model access | CLAUDE.md §Architecture | architecture | Partial — core-purity-check.sh covers extension refs only | `guidance-service-boundaries` | Brief ref | Design invariant; not fully mechanically caught |
| 10 | Git: branch flow `develop→feature→release→master`; no "v" prefix on tags/release branches; staged commits by concern | CLAUDE.md §Git | convention | No | `guidance-git-conventions` | Yes (core) | Any committing executor should follow; see toss-up on branch-flow relevance to loops |
| 11 | Git: no **AI** attribution in commits (generalize from "Claude attribution") | CLAUDE.md §Git | convention | No | `guidance-git-conventions` + loop guardrail | Yes (core) | Other executors add *their own* attribution; rule must generalize |
| 12 | Submodule safety — no `submodule sync` on public subs; survey both statuses; commit inside submodule first; never commit ext files from parent | CLAUDE.md §Submodule Safety | safety/convention | Partial — `submodule-boundary-check.sh` (Claude hook) | `guidance-submodule-safety` + `pattern-validation.sh` check | Yes (core) | Any executor touching submodules can corrupt the private remote |
| 13 | File Organization — NEVER save files to project root; use `docs/{...}` | CLAUDE.md §File Organization | convention | No | `guidance-file-organization` + new `pattern-validation.sh` check (flag new root files) | Brief ref | Binds any executor that writes docs/artifacts |
| 14 | Terminology table (server/ vs "backend dir", etc.) | CLAUDE.md §Terminology | informational | No | `guidance-terminology` (low priority) | Optional | Helps prose accuracy; low stakes — **toss-up** |
| 15 | MCP-first workflow (4 phases, session-start queries) | CLAUDE.md §Memory; server/frontend/worker CLAUDE.md | convention | **Yes** — `conventions/mcp-first-workflow.md`, tag `guidance-mcp-first-workflow`, SessionStart digest | Already correct (knowledge) | Yes (pointer) | Note: non-Claude executors do NOT get the SessionStart digest — ensure they query the tag |
| 16 | Knowledge contribution lifecycle (create_learning/knowledge after work) | CLAUDE.md §Memory; nested "After Work" tables | convention | **Yes** — `conventions/knowledge-lifecycle.md`, tag `guidance-knowledge-lifecycle` | Already correct (knowledge) | Yes (pointer) | Already model-agnostic; nested per-subsystem tables duplicate it |

## Group B — → Agent system-prompt  *[baseline guardrails carried without an MCP query]*

| # | Rule (short) | Source:section | Nature | Already model-agnostic? | Recommended home(s) | Keep CLAUDE.md ref? | Rationale |
|---|---|---|---|---|---|---|---|
| 17 | **Bulk-operation safety** — state count before bulk; >5 items need explicit confirmation (show first 3 + last 1); **never batch-approve** training/permission/financial/auto-discovered changes | CLAUDE.md §Bulk Operation Safety | governance/safety | Partial — autonomous-campaigns.md says "approve offers individually, never batch" | **agent system-prompt** + loop guardrail (`guidance-bulk-op-safety`) | Yes (core) | Loop executors draining a queue are the actors that batch-approve. **PRIORITY #3** |
| 18 | Stop & Ask (HARD) — after 3 failed attempts, STOP and ask; no 4th approach | CLAUDE.md §Design | safety/behavioral | **Yes** — already in every loop `guardrails` array ("After 3 failed attempts… stop") | agent system-prompt (for non-loop agents); loop guardrail already covers loops | Yes (core) | Migrate to prompt so non-loop agents also carry it |
| 19 | Crypto-safety **baseline** (always-carry summary) | CLAUDE.md §Crypto | safety | Partial — `guidance-secret-safety` | agent system-prompt (secondary to #1) | Yes (core) | A baseline secrets guardrail must hold even without a `search_knowledge` call |

## Group C — → Skill (`.claude/skills/*` + platform skills)  *[procedural, invoke-when-relevant]*

| # | Rule (short) | Source:section | Nature | Already model-agnostic? | Recommended home(s) | Keep CLAUDE.md ref? | Rationale |
|---|---|---|---|---|---|---|---|
| 20 | Quality Gates — `npx tsc --noEmit` after TS; Ruby syntax + related spec after `.rb`; `rails db:seed` after seeds | CLAUDE.md §Design | procedural | Partial — `scripts/validate.sh` + git pre-commit run these | platform skill / loop verification gate; reference `scripts/validate.sh` | Brief ref | Procedural check; make the *gate* the home, not prose |
| 21 | Completion Gate — run `/verify` on changed files before reporting done | CLAUDE.md §Design | procedural | No (`/verify` is a Claude skill) | Generalize to "run the verification gate" → loop guardrail + skill | Brief ref | Non-Claude executors have no `/verify`; bind via the gate |
| 22 | Test execution commands + multi-agent test DB rules | server/CLAUDE.md; testing-patterns.md | procedural | **Yes** — `conventions/testing-patterns.md`, tag `guidance-testing-patterns` | Already correct (knowledge/skill) | Yes (pointer) | Already model-agnostic |
| 23 | Service management & ops (systemd-only; restart matrix) | service-and-ops.md | procedural | **Yes** — `conventions/service-and-ops.md`, tag `guidance-service-and-ops` | Already correct (knowledge) | Yes (pointer) | Already model-agnostic |

## Group D — → Mechanical (`pattern-validation.sh` + git pre-commit)  *[model-agnostic scan is the real home; `.claude/hooks` is a Claude-only nudge]*

| # | Rule (short) | Source:section | Nature | Already model-agnostic? | Recommended home(s) | Keep CLAUDE.md ref? | Rationale |
|---|---|---|---|---|---|---|---|
| 24 | **AI execution jobs MUST include `AiSuspensionCheckConcern`** (kill-switch compliance) | worker/CLAUDE.md §Critical Rules | **safety** | **NO — zero enforcement; Claude-only file** | **new `pattern-validation.sh` check** (grep AI job classes for the concern) + `guidance-kill-switch-compliance` | Yes (core) | A non-Claude executor can add an AI job that bypasses the kill switch. **PRIORITY #1** |
| 25 | `# frozen_string_literal: true` in every `.rb` | server/worker CLAUDE.md; backend-patterns.md | mechanical | **Yes** — `ruby-syntax-check.sh` + scan | Already correct | Nested nudge | Fully caught by scan |
| 26 | `Rails.logger` only — no `puts`/`print` | server/worker CLAUDE.md; backend-patterns.md | mechanical | **Yes** — `pattern-validation.sh` | Already correct | Nested nudge | Caught by scan |
| 27 | Always use `render_success()` / `render_error()` | server/CLAUDE.md; backend-patterns.md | mechanical | **Yes** — `pattern-validation.sh` | Already correct | Nested nudge | Caught by scan |
| 28 | Migrations: index in `t.references` declaration, never separate `add_index` | server/CLAUDE.md; backend-patterns.md | mechanical | **Yes** — `ruby-convention-check.sh` | Already correct | Nested nudge | Caught by hook |
| 29 | Namespaced models use `::` in `class_name:` | backend-patterns.md | mechanical | **Yes** — `ruby-convention-check.sh` | Already correct | Doc | Caught by hook |
| 30 | Namespaced FK prefixes (`Ai::`→`ai_`, etc.) | backend-patterns.md | mechanical | **Yes** — `ruby-convention-check.sh` | Already correct | Doc | Caught by hook |
| 31 | Pair `class_name:` with `foreign_key:` | backend-patterns.md | mechanical | **Yes** — `ruby-convention-check.sh` | Already correct | Doc | Caught by hook |
| 32 | JSON columns: lambda defaults `-> { {} }` | backend-patterns.md | mechanical | **Yes** — `ruby-convention-check.sh` | Already correct | Doc | Caught by hook |
| 33 | Controllers under 300 lines | backend-patterns.md | mechanical | **Yes** — `controller-size-check.sh` | Already correct | Doc | Caught by hook |
| 34 | Theme classes only (`bg-theme-*`); no hardcoded colors | frontend CLAUDE.md; frontend-patterns.md | mechanical | **Yes** — `hardcoded-color-check.sh` + scan | Already correct | Nested nudge | Caught by hook+scan |
| 35 | No `console.log` in production | frontend CLAUDE.md; frontend-patterns.md | mechanical | **Yes** — `console-log-check.sh` + scan | Already correct | Nested nudge | Caught by hook+scan |
| 36 | No `any` types | frontend CLAUDE.md; frontend-patterns.md | mechanical | **Yes** — `no-any-type-check.sh` + scan | Already correct | Nested nudge | Caught (advisory; 347 baseline backlog) |
| 37 | Flat navigation — no submenus | frontend CLAUDE.md; frontend-patterns.md | mechanical | **Yes** — `pattern-validation.sh` | Already correct | Doc | Caught by scan |
| 38 | Imports: `@/shared/`, `@/features/` cross-feature aliases | frontend CLAUDE.md; frontend-patterns.md | mechanical | **Yes** — `convert-relative-imports.sh` | Already correct | Doc | Caught/auto-fixed |
| 39 | Eager loading — `.includes()` when iterating associations | CLAUDE.md §Backend; backend-patterns.md | high-stakes | Partial — `n-plus-one-check.sh` is **advisory nudge** only | core (stays) + strengthen scan if feasible | Yes (core) | No full mechanical catch — deliberately kept in core |
| 40 | Webhook receivers return 200/202, never 500 | CLAUDE.md §Backend; backend-patterns.md | high-stakes | Partial — `webhook-500-check.sh` is **advisory nudge** only | core (stays) + scan backstop | Yes (core) | Provider retry-storm risk; kept in core |
| 41 | Worker invariants — no job classes in `server/app/jobs/`; no Sidekiq gems in `server/Gemfile` | CLAUDE.md §Worker; server/CLAUDE.md | mechanical | **Yes** — `pattern-validation.sh` (per MANIFEST) | Already correct | Yes (core) | Caught by scan; boundary is high-stakes so core ref stays |
| 42 | Extension isolation — core source must not reference a private extension | CLAUDE.md §Architecture | architecture/safety | Partial — `core-purity-check.sh` (**blocking** Claude hook) + loop guardrail | Already strong; add `pattern-validation.sh` mirror for CI/non-Claude | Yes (core) | Blocking hook is Claude-only; loop guardrail covers loops; add scan for full coverage |

## Group E — → Loop guardrails  *[per-iteration, delivered in `dev_next_task` payload to every loop executor]*  — mostly ALREADY there

| # | Rule (short) | Source:section | Nature | Already model-agnostic? | Recommended home(s) | Keep CLAUDE.md ref? | Rationale |
|---|---|---|---|---|---|---|---|
| 43 | One task per iteration | CLAUDE.md (implicit); autonomous-campaigns.md | convention | **Yes** — in `DEFAULT_GUARDRAILS`/`GUARDRAILS` arrays | Already correct (guardrail) | — | Confirmed present in campaign_driver/audit_backlog/improvement_promotion |
| 44 | Test-First Bug Reproduction — failing test before fix | CLAUDE.md §Design; testing-patterns.md | convention | **Yes** — guardrail + `guidance-testing-patterns` | Already correct (guardrail) + `guidance` for non-loop | Yes (core) | Migrate the general statement to knowledge too |
| 45 | 3-strikes → stop (loop form: "report outcome=failed and stop") | CLAUDE.md §Design | safety | **Yes** — in every guardrail array | Already correct (guardrail) | Yes (core) | Same rule as #18; loops covered |
| 46 | Independent review of the diff before committing | CLAUDE.md (implicit /code-review gate) | convention | **Yes** — guardrail ("run /code-review on the diff BEFORE committing") | Already correct (guardrail) | — | Already enforced per-iteration |
| 47 | Commit only to the loop/campaign branch — never develop/master, never push | CLAUDE.md §Git | safety | **Yes** — in every guardrail array | Already correct (guardrail) | Yes (core) | Already enforced per-iteration |

## Group F — Stays in CLAUDE.md  *[Claude/harness-specific OR outage-safe core; copy noted where useful]*

| # | Rule (short) | Source:section | Nature | Already model-agnostic? | Recommended home(s) | Keep CLAUDE.md ref? | Rationale |
|---|---|---|---|---|---|---|---|
| 48 | Consult auto-memory (`MEMORY.md`) | CLAUDE.md §Memory | harness-specific | N/A | **Stays** — Claude Code feature | Yes | Relevance-injection is a CC harness capability; no analog elsewhere |
| 49 | "Where guidance lives" routing table | CLAUDE.md §Where guidance lives | harness-specific (meta) | N/A | **Stays** | Yes | Tells *Claude* how its hooks/homes wire; other executors use `search_knowledge` directly |
| 50 | "Specialists & Documentation" table | CLAUDE.md §Specialists | harness-specific (meta) | N/A | **Stays** | Yes | Meta-navigation; a copy would be noise |
| 51 | CWD verification before `git add`/`commit` (run `git rev-parse --show-toplevel`) | CLAUDE.md §Submodule Safety | harness-specific | No | **Stays** (optional loop-guardrail copy) | Yes | Guards a Claude tool-CWD-drift failure mode — **toss-up** whether to copy to loops |

## Group G — Personal config (`~/.claude/CLAUDE.md`)  *[classify as personal; do not platform-migrate]*

| # | Rule (short) | Source:section | Nature | Already model-agnostic? | Recommended home(s) | Keep CLAUDE.md ref? | Rationale |
|---|---|---|---|---|---|---|---|
| 52 | git commit should not include "Generated with"/"Co-Authored-By" notes | ~/.claude/CLAUDE.md | personal pref | N/A | **Stays (personal)** | Personal | Personal harness pref; overlaps repo rule #11 — the *platform* generalization ("no AI attribution") is what migrates, not this personal copy |
| 53 | Always use absolute paths in shell/tool commands | ~/.claude/CLAUDE.md | personal/harness | N/A | **Stays (personal)** | Personal | Guards CWD-drift in the user's CC harness; not a platform rule |

## Already migrated (DONE — do not re-recommend)

| Rule | Home | Note |
|---|---|---|
| "Never emit secrets/keys in generated artifacts" | `guidance-secret-safety` | Worked pattern; subset of audit row #1 (the remaining 6 crypto rules still need migration) |
| "No permission laundering" (escalation governance) | `guidance-agent-escalation` | Worked pattern; relates to Permission/escalation governance |

---

## Notes & caveats

- **Counts are by *primary* home.** Several rules have a legitimate secondary home (e.g. crypto → knowledge *and* agent prompt); only the primary is counted in the summary.
- **"Already model-agnostic" ≠ "no work."** For mechanical rules it means a *scan* exists; but verify the loop verification gate actually runs `scripts/pattern-validation.sh` so non-Claude executors are gated, not just nudged by `.claude/hooks`.
- **SessionStart digest is Claude-only.** `session-guidance-inject.sh` injects the `guidance-*` pointer list at the start of *Claude* sessions. Non-Claude loop executors must be made to query `search_knowledge tag:guidance-*` (e.g. via the task payload or agent prompt) to receive the same conventions — otherwise migrating a rule to a `guidance-*` tag still doesn't reach them.
- **The nested `server//frontend//worker/ CLAUDE.md` files are ~80% MCP-tool catalogs and MCP-first query tables**, which duplicate `mcp-first-workflow.md` + the auto-generated `reference/auto/mcp-tools.md`. Their only *unique, binding* rule not already covered model-agnostically is the **kill-switch concern (#24)**. The catalogs themselves are Claude-navigation aids and can stay.
- This document is **report-only**. No `guidance-*` entries were created, no `CLAUDE.md` edited, nothing committed.
