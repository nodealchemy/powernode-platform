---
name: campaign
description: Start, drive, monitor, and stop an Autonomous Improvement Campaign — a durable, repeatable wrapper around the dev-improve loop
disable-model-invocation: true
argument-hint: [start <name> | run <id> | status [id] | answer <id> | stop <id>]
---

# /campaign — Autonomous Improvement Campaigns

A **campaign** is a durable, named, repeatable improvement run. It replaces the hand-authored
standing prompt + `~/.claude` plan files: a run becomes `start(config)`. The campaign owns its
scope/posture/decision-authority/stop-conditions, the Ralph loop(s) it drives, a decision log, an
async parked-questions queue, and a progress ledger. `/campaign run` is the Ralph-pattern loop
body — drive it repeatedly with `/loop /campaign run <id>`.

Aliases: `/campaign` and `/autodev` are the same skill. Dual surface — platform agents call the
same actions via the `campaign` MCP tool (`campaign_start/status/answer_question/stop`).

## Usage
```
/campaign start <name>     # create a campaign + its dedicated loop (interactive config)
/campaign run [<id>]       # drive ONE improvement iteration for the campaign (loop body)
/campaign status [<id>]    # progress + open questions + recent decisions (all, or one)
/campaign answer <id>      # answer a parked question to unblock the campaign
/campaign stop <id>        # stop the campaign + pause its loops + record a summary
```

## start <name>
Surface the config, then create. Confirm these with the operator if not given:
- **scope** — which tree/area (e.g. a private extension, `server/`, `worker/`); stays in `configuration`.
- **posture/ordering** — bugs-first, dead-code, test-gaps, quality; free text in `configuration`.
- **decision_authority** — how much the loop decides vs parks (see table below). Default `trusted`.
- **stop_conditions** — e.g. `{ "max_failed": 3, "completion_pct": 100 }`. Optional.

Call `platform.campaign_start(name:, description:, decision_authority:, configuration:, stop_conditions:)`.
It creates the `Ai::Campaign` **and** a dedicated campaign-scoped Ralph loop (branch `campaign/<id>`),
starts the campaign, and snapshots initial progress. Report the campaign id + loop branch.

## run [<id>]
One in-scope improvement, end to end — this is the loop body (compose, don't reinvent):
1. **Read the campaign**: `platform.campaign_status(<id>)` (or the most recent active campaign if id omitted).
   Honour `decision_authority`, `configuration` scope/posture, and `stop_conditions`.
2. **Stop conditions / halt**: if the campaign is terminal, `should_stop?` is met, or an
   `emergency_halt` / kill-switch is active → report and STOP (end `/loop` if active).
3. **Refill if dry**: if the campaign loop has no queued task, discover within scope —
   `/improve discover <scope>` (verify-before-offer gate), approve the next in-scope offer
   (individually, never batch — CLAUDE.md bulk rule), which promotes a task onto the campaign loop.
   If discovery is dry and nothing is pending → snapshot + report queue-empty + STOP.
4. **Drive one task**: run the `/dev-loop <campaign-loop>` iteration body on the campaign's loop
   (pull → re-verify claim → branch `campaign/<id>` → **test-first** red → minimal fix → verify →
   commit on the loop branch, STAGE-only, no push, no Claude attribution → report).
5. **Record the decision**: log what was decided (unblock/skip/build/remove/defer/policy) to the
   campaign so the operator sees the reasoning, not just the diff.
6. **Park, don't stall**: when blocked on something above your `decision_authority` (live-credential,
   irreversible external, business-policy/pricing value), `park_question!` on the campaign and move
   on or stop — never guess. Parked questions are answered async via `/campaign answer`.
7. **Snapshot progress** so the ledger + dashboard reflect the new state.

## status [<id>]
`platform.campaign_status(<id>)` (or list active campaigns). Show completion %, task counts,
open questions, and the recent decision log. Read-only.

## answer <id>
List the campaign's open questions (`status`), then `platform.campaign_answer_question(<id>,
question_id:, answer:)`. The answer unblocks the next `/campaign run` for that area.

## stop <id>
`platform.campaign_stop(<id>, summary:)` — pauses the campaign's loop schedules and marks the
campaign completed with your summary. Use when scope is drained or the operator calls it.

## Decision authority
| Level | The loop decides… | It parks… |
|-------|-------------------|-----------|
| `supervised` | almost nothing | every non-trivial fork |
| `monitored` | low-risk, reversible items | anything ambiguous |
| `trusted` (default) | design/architecture per best practice; implements test-first/staged, mocks externals | only irreversible-external / live-credential / business-policy-value |
| `autonomous` | everything reversible | only live-credential / irreversible-external |

## Posture (inherits the loop body's rules)
- **STAGE-only** during a run — commit on the campaign branch, never push/land unless the operator says so.
- **Test-first** bug reproduction; minimal change tracing to the task; no scope creep.
- **Core-purity**: never make a core file depend on a private extension; extension findings stay extension-scoped.
- **Crypto-material safety absolute**; **bulk-op confirmation** for >5 items; **3-strikes → stop & ask**.
- One improvement per `run`. Park genuine forks rather than guessing.

See [autonomous-campaigns convention](../../docs/contributing/conventions/autonomous-campaigns.md)
(tag `guidance-autonomous-campaigns`) for the model/driver/tool reference and the rationale.
