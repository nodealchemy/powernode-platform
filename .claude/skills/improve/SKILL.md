---
name: improve
description: Discover, offer, and triage code-quality improvements for the dev-improve loop
disable-model-invocation: true
argument-hint: [discover|review|approve <id>|delegate <id>|revert <id>|status|enable-autonomy <agent>|disable-autonomy] [repo]
---

# /improve — Discover & Offer Code-Quality Improvements

Surface code-quality improvements, **offer** them for human approval, and turn approved ones into `dev-improve` Ralph Loop tasks that `/dev-loop` (or a platform agent) acts on. Operator-driven (Tier-1). The platform `improvement` MCP tool is the dual surface — platform agents call the same actions, so this works for Powernode and any other indexed repo.

## Usage
```
/improve discover [repo]           # find + vet + offer improvements
/improve review                    # list pending offers
/improve approve <id>              # approve an offer -> creates a dev-improve task
/improve delegate <id>             # approve + hand the task to a platform agent
/improve revert <id>               # mark a promoted task reverted (ungameable metric signal)
/improve status                    # improvement scoreboard (velocity + revert_rate)
/improve enable-autonomy <agent>   # gated: run dev-improve unattended (off by default)
/improve disable-autonomy          # return dev-improve to operator-driven
```

## discover
1. **Analyze (MCP-first):** `platform.code_static_analysis`, then `scripts/pattern-validation.sh`; add `platform.code_dead_code` / `platform.code_find_duplicates` when asked.
2. **Verify-before-offer (scrutiny gate — mandatory):** for EACH candidate, confirm it still reproduces on HEAD. For `dead_code`/`code_duplication`, prove zero live callers with `platform.code_blast_radius` BEFORE proposing a deletion/extraction. Discard anything you cannot reproduce. Record the proof as `verifier_evidence`.
3. **Classify** each vetted finding: `code_lint | dead_code | code_duplication | convention_adherence | test_gap`.
4. **Core-purity (gate #9):** findings under `extensions/private/*` are auto-tagged to that extension by the tool — never offer them as core/global, and never propose a fix that makes a core file depend on an extension.
5. **Offer** each finding: `platform.improvement` action `create_improvement` with `recommendation_type`, `title`, `fingerprint` (`kind|file|rule`), `files`, `fix`, `verifier_evidence`, `confidence_score`. Idempotent on `fingerprint` — re-running `discover` updates, never duplicates.
6. Report a summary table (kind, title, file, confidence). Do **NOT** bulk-approve — offers await individual human review (CLAUDE.md bulk-op rule covers auto-discovered code changes).

## review
`platform.improvement` `list_improvements` (status: pending). Show the offers; the user decides.

## approve <id>
- Confirm with the user (never batch-approve auto-discovered code changes).
- `platform.improvement` `approve_improvement` (`recommendation_id`) → creates a `dev-improve` RalphTask back-linked to the recommendation; returns `task_key`.
- Tell the user to drain it: `/dev-loop dev-improve` (or `/improve delegate` to hand it to a platform agent).

## delegate <id>
Approve as above, then hand the task to a platform agent instead of running it in this session:
1. Pick a capable platform agent: `platform.list_agents`.
2. `platform.delegate_ralph_task(loop_id: "dev-improve", task_key: <key>, agent_id: <agent>, await: false)`.

Reuses the platform's capability-matrix + delegation-authority checks; `await: true` blocks until the agent finishes and records the outcome on the loop; it's a no-op when the kill switch is active. Either drain the queue yourself (`/dev-loop dev-improve`) or delegate — both act on the same `dev-improve` tasks.

## status
`platform.improvement` `scoreboard` — offer funnel (discovered / approved / applied / dismissed) plus the **ungameable metric**: revert-adjusted `net_improvement_velocity` and per-kind `revert_rate` (blast-radius weighted, per-kind capped). Computed from ground truth (`reverted_at` / task status), never self-reported checks.

## revert <id>
`platform.improvement` `revert_improvement` (`recommendation_id`, `reason`) — marks the dev-improve task promoted from that recommendation as reverted. This is the ground-truth signal the metric uses; it works even while the kill switch is active (undoing a bad change must always be possible).

## enable-autonomy / disable-autonomy (gated — off by default)
Tier-2 unattended mode. `enable_autonomy` (`agent_id`, `max_iterations_per_day`) flips the `dev-improve` loop to autonomous **push**, drained by a capability-matched platform agent on the `process_scheduled` cadence, with the daily cap and `ai_suspended?` kill switch enforced. Refused while the kill switch is active. `disable_autonomy` returns the loop to operator-driven pull execution. Leave this OFF until discovery noise/quality is proven.

## Guardrails
- Verify-before-offer is mandatory — no unverified finding reaches the queue.
- The human-approval gate is structural: a `dev-improve` task cannot exist until an offer is approved.
- Respect `emergency_halt` — `approve` is a no-op when the kill switch is active.
- One offer = one `fingerprint`.
