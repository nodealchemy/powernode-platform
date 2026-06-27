# Autonomous Improvement Campaigns

A **campaign** is a durable, named, repeatable improvement run. It is the first-class platform
wrapper around the `dev-improve` Ralph loop — it replaces the hand-authored standing prompt plus
the `~/.claude` markdown plan files that earlier drove long autonomous improvement sessions. A run
becomes `start(config)`: the campaign persists its own scope, posture, decision-authority, and
stop-conditions, the loop(s) it drives, a decision log, an async parked-questions queue, and a
progress ledger.

Surfaces (all four are the same feature):
- **Slash command** — `/campaign` (alias `/autodev`): `start | run | status | answer | stop`.
- **MCP tool** — `campaign` (`campaign_start`, `campaign_status`, `campaign_answer_question`,
  `campaign_stop`) so platform agents drive campaigns the same way.
- **Dashboard panel** — AI → Campaigns (`/app/ai/campaigns`), gated by `ai.campaigns.read`.
- **This convention** — the rationale + reference (tag `guidance-autonomous-campaigns`).

## When to use one

Reach for a campaign when the work is **open-ended, repeatable, and self-refilling** — drain a
backlog, sweep a tree for a class of defect, raise coverage, remove dead code — rather than a
single discrete change. For a one-off task, use `/dev-loop` (one task) or a Mission. A campaign is
the right home when you would otherwise hand-author a standing prompt and babysit a `/loop`.

## Model

Sibling to the multipurpose `Ai::RalphLoop` (a campaign *drives* loops; it does not extend one):

- `Ai::Campaign` — lifecycle (`created → active → paused → completed → archived`), denormalized
  counters, `decision_authority`, `configuration` (scope/posture/ordering), `stop_conditions`,
  and the roll-up/snapshot logic. `has_many :ralph_loops` via `campaign_id`.
- `Ai::CampaignDecision` — the decision log (`unblock | skip | build | remove | defer | policy |
  escalate | other`): what the agent decided and why, so the operator reviews reasoning, not just diffs.
- `Ai::ParkedQuestion` — the async queue (`open → answered | dismissed`). The agent parks a blocking
  question and keeps moving or stops; the operator answers later via `/campaign answer` or the panel.
- `Ai::ProgressEntry` — the ledger (task counts + completion % + per-loop summary), one row per snapshot.

`Ai::DevLoop::CampaignDriver` is the service seam: `start` (creates the campaign + a dedicated
campaign-scoped loop on branch `campaign/<id>`, then snapshots), `status`, `answer_question`, `stop`
(pauses the loop schedules + completes the campaign). The slash command, MCP tool, and REST
controller (`Api::V1::Ai::CampaignsController`) all delegate to this one driver.

## Decision authority

Encodes how much the loop decides itself versus parks for the operator — the same spectrum that
governs operator-granted decision authority during a session:

| Level | Decides | Parks |
|-------|---------|-------|
| `supervised` | almost nothing | every non-trivial fork |
| `monitored` | low-risk, reversible items | anything ambiguous |
| `trusted` (default) | design/architecture per best practice; implements test-first/staged, mocks externals | only irreversible-external / live-credential / business-policy-value |
| `autonomous` | everything reversible | only live-credential / irreversible-external |

## Parked questions, not stalls

The core operating rule: **never guess on a genuine fork, never stall the run.** When blocked above
the campaign's authority (a live credential, an irreversible external action, a business-policy or
pricing value), the agent `park_question!`s it on the campaign and continues other in-scope work or
stops cleanly. Parked questions are answered asynchronously; the answer unblocks the next `run` for
that area. This is what lets a long run stay productive without a human in the loop for every fork.

## Posture (inherited from the loop body)

A `/campaign run` is a `/dev-loop` iteration with campaign context — every loop-body rule still holds:

- **STAGE-only** — commit on the campaign branch; never push/land unless the operator says so.
- **Test-first** reproduction; minimal change tracing to the task; revert scope creep.
- **One improvement per `run`**; refill via scoped `/improve discover` when the queue is dry;
  approve offers individually (never batch — the bulk-operation rule covers auto-discovered changes).
- **Core-purity** — a campaign over an extension keeps findings extension-scoped; never make a core
  file depend on a private extension.
- **Crypto-material safety absolute**; **3-strikes → stop & ask**; honour `emergency_halt` / kill-switch.

## Deploy notes

The `ai.campaigns.read` / `ai.campaigns.manage` permissions are code-defined in the catalog — a
server restart picks them up; grant them to the roles that should see/drive campaigns. The
`ai_campaigns` tables ship in a migration that must be applied before the feature is usable.
