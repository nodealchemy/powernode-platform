# Self-Improvement Loop Evaluation — 2026-07-02

Evaluation of the `dev-improve` Ralph loop: are the improvements **meaningful**, and do **subsequent loops directly benefit** (i.e. does the loop *compound*)? Grounded in `platform_get_ralph_loop_statistics`, `platform_learning_metrics`, `platform_knowledge_health`, and the 5 drain rounds run on 2026-07-01/02.

## Verdict

- **Meaningful per loop: YES (mostly).** 30-day window: `net_improvement_velocity 21.93`, `total_durable 166`, **`total_reverted 0` (0% revert rate)**. The test-first + `/code-review` + verification gate is working — landed improvements stick, and this session's fixes were real (a recurring server→worker `NameError` bug class, the pipeline-sync chain, a security-gate under-block, genuine dedups) with only minor-value tail items (a 0.65 perf hoist).
- **Subsequent loops benefit: PARTIALLY — this is the weak point.** Knowledge transfers only through a shallow "last-N `recent_learnings`" window (visible in `dev_next_task` context) plus the orchestrator carrying context within a session. The durable, effectiveness-ranked compounding machinery is **not** functioning, and recurring bug *classes* are drained instance-by-instance instead of being eliminated.

## What's working (keep)

1. **Quality gate holds.** 0% revert across 166 durable improvements in 30 days. Test-first repro + adversarial `/code-review` caught real defects mid-flight this session (a security-gate `nil`-vs-fail-safe under-block; a sync-vs-fire-and-forget callback rollback risk).
2. **Discovery rigor.** The discovery pass re-verifies each finding on HEAD and rejects stale signals (it discarded a 56-item stale dead-code batch and known-fixed items), avoiding wasted drain cycles.
3. **Seam pattern reuse within a session.** The `WorkerJobService` HTTP-seam fix was reused across instances, and later learnings explicitly reference the earlier fix — so *some* cross-loop transfer happens via the recency window + orchestration.
4. **The correct compounding template already exists** but isn't being applied to new classes: the "migrate Claude-only rules" campaign encoded conventions as `guidance-*` knowledge + `pattern-validation.sh` scans + `BASE_GUARDRAILS`. That is exactly the mechanism the loop should use for every recurring class.

## Compounding gaps (the problem)

### Gap 1 — Recurring bug CLASSES are drained one instance at a time, never eliminated
The server→worker job-seam `NameError` class (Sidekiq-free `server/` referencing a worker-only job constant via `perform_async`/`perform_later`) was fixed as **separate** tasks across rounds: `IMP-876b1fae1e89` (4 sites), `IMP-7c70a08d5e59` (MCP monitoring), `IMP-cee9c190806e` (AgentExecution) — and the learnings note *"discovered a second/untracked instance of the same class."* The loop keeps **re-discovering instances of a class it already learned about**, because:
- No mechanical **guard** (a `pattern-validation.sh` scan and/or edit hook) was added to detect the *whole* class or *prevent* new instances.
- Discovery re-derives the class from generic static analysis each round rather than running a **targeted all-instances sweep** keyed on the known class.

Result: a class that a compounding loop would eliminate in one guarded pass instead trickled across ~4 rounds and remains open to regression.

### Gap 2 — dev-loop learnings are write-mostly, not injected (the core "no benefit" signal)
`platform_learning_metrics` shows **`avg_effectiveness 0.0474`** across 12,092 learnings. Every dev-loop learning created this session (the NameError seam, the crypto-gate false positive, the dedup, the gitleaks span) shares this shape:
- `title: null`, `importance_score: 0.3` (default), `tags: ["ralph_loop"]` only
- **`injection_count: 0`, `access_count: 0`, `last_injected_at: null`**

They are recorded but **not fed into the effectiveness-ranked injector** — subsequent loops see them only if they fall in the small recency window. The "most_effective" learnings are all *old trading-domain* entries with huge injection counts; the dev-loop's own learnings never enter that ranked pool. Learning is accumulating (6,198 active, 1,786 deprecated) without measurably improving future iterations.

### Gap 3 — Shared-knowledge pipeline is stale
`platform_knowledge_health`: shared_knowledge `stale_count 5,788 / 6,291` (~92% stale), only `102/6,291` rated. Matches the prior incident note (stalled knowledge feedback pipeline). Learnings/knowledge aren't being re-verified or rated, so effectiveness can't be measured or compound. This is a worker-side pipeline gap.

### Gap 4 — Recurring human-in-the-loop friction not being designed out
The crypto protected-path gate (`**/*credential*`) false-positived **twice** (a contract spec, then an accurately-named concern), each needing operator disposition. The gate matches on filename, not content; the fix (content/AST-aware distinction) is already a *blocked* task (core-purity hook AST blind-spot). Recurring friction that isn't being resolved is negative compounding.

## Recommendations (ranked by leverage)

1. **Convert recurring classes into guards.** Policy: when a bug class recurs ≥2 times (or its learning is reinforced), the *next* action is to add a `pattern-validation.sh` scan (+ optional PostToolUse hook) that (a) finds all current instances and (b) blocks new ones — not another per-instance fix. **Concrete now:** a scan asserting `server/**` must not `perform_async`/`perform_later` a job constant not defined under `server/app/jobs` (route via `WorkerJobService`). Turns the multi-round reactive drain into a one-time class elimination + regression backstop. *(This is the single highest-leverage change for "subsequent loops directly benefit.")*
2. **Fix learning feed-forward.** dev-loop learnings must be created with a title, a class/subsystem tag (not just `ralph_loop`), and a real importance score; high-value ones promoted to `guidance-*` shared knowledge so every executor can `search_knowledge` them. Make discovery `query_learnings` on the specific class tags before generic analysis. Without this, `avg_effectiveness 0.047` will persist and the loop won't compound.
3. **Add a targeted class-sweep discovery mode.** For each known recurring class, discovery runs an all-instances grep and queues them together (loop-until-dry on the class) rather than surfacing one per round.
4. **Unblock the crypto protected-path gate refinement** (content/AST-aware) to stop the recurring false-positive toil.
5. **Restore the knowledge/learning feedback pipeline** (92% stale) so effectiveness/rating signals actually update — prerequisite for measuring #2.
6. **Track a convergence metric:** *recurrence rate* = new instances of already-learned classes per round. A compounding loop drives this **down** (classes get guarded away). Today it is flat/rising for the NameError class — the objective proof the loop isn't yet compounding.

## Bottom line
The loop produces meaningful, durable, low-revert improvements — but it currently **compounds weakly**: it learns *narratively* (recency window) rather than *mechanically* (guards) or *durably* (injected/ranked learnings). The fix is to make each loop leave behind a **guard or an injected learning** that measurably reduces the next loop's work on the same class — starting with Recommendation #1.
