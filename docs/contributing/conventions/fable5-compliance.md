# Fable 5 Compliance

Ground rules for working with **Claude Fable 5** (`claude-fable-5`; `claude-mythos-5` on Project
Glasswing) — Anthropic's most capable model, premium-priced ($10 input / $50 output per MTok).
These rules apply to every executor (Claude Code and non-Claude loop executors); they are enforced
in code (`Ai::Llm::ModelCapabilities`, `Ai::Llm::Adapters::Anthropic`, `Ai::Routing::EffortMapper`,
`Ai::FableRouting`), not something an executor hand-implements per call.

## API rules — enforced by the request builder, do not hand-set

| Rule | Detail |
|------|--------|
| Thinking | Always-on, adaptive-only. NEVER pass a `thinking` block or sampling params (temperature/top_p/top_k) — Fable 400s on either; the builder omits/strips them. |
| Depth | Controlled ONLY via `output_config.effort`, auto-derived from task complexity (`Ai::Routing::EffortMapper`) — do not try to tune depth another way. |
| Prefill | No assistant-prefill turns — Fable rejects a trailing prefilled assistant message. |
| Data retention | 30-day data retention is required for Fable/Mythos traffic. |

## Refusal handling — don't panic, don't manually retry

Fable's safety classifiers can decline benign security/infra work (`stop_reason: "refusal"`, HTTP
200 — not an error). This is already handled: the platform reframes once with truthful
authorized-context, then falls back to Opus, logging the event (`Ai::ModelRefusalEvent`) and
attributing served-by. Repeated refusals for an `(agent_type, category)` combo auto-pre-route away
from Fable going forward. Executors should NOT retry manually or treat a refusal as a failed task —
it is handled and surfaced.

## Routing

Fable is gated by `Account#settings["fable_routing_enabled"]` (`Ai::FableRouting`), **DEFAULT
OFF**. While off, Fable is excluded from the candidate set entirely — non-selectable, never chosen
by preference, UCB exploration, or a cost tie. When on, reasoning-tier allowlisted `agent_type`s get
a preference bonus toward Fable; repeat refusals still auto-pre-route away regardless of the
allowlist.

## Prompting Fable

Fable is tuned for long-horizon autonomous work, follows brief goal-level instructions
better than enumerated ones, and **degrades when over-prescribed**. So "optimize for Fable"
means *removing* scaffolding built for older models as much as adding rules: state the GOAL
plus constraints over step-by-step, and let it plan its own approach.

These patterns are already wired into the platform's executor prompts — `Ai::Agent::BASE_GUARDRAILS`
(every agent) and `Ai::DevLoop::LoopGuardrails` (the autonomous loops). Carry them yourself when
prompting Fable directly:

| Pattern | What to do |
|---------|-----------|
| Goal over steps | State the goal + constraints; don't enumerate a procedure Fable can plan itself — over-prescription measurably lowers output quality. |
| Act when ready | When you have enough to act, act. Don't re-derive settled facts, re-litigate decided calls, or survey options you won't pursue — give a recommendation, not a menu. |
| Checkpoint only when needed | Pause for the user ONLY for a destructive/irreversible action, a real scope change, or input only they can provide — not to narrate or ask permission for in-scope reversible work. |
| Ground progress claims | Audit every progress/completion claim against a real tool result before reporting it; say plainly when a step failed, was skipped, or is unverified. (Anthropic testing: nearly eliminates fabricated status reports.) |
| Don't over-refactor at high effort | Higher effort tempts unrequested tidying. A bug fix needs no surrounding cleanup; validate only at system boundaries; no abstractions/flags/back-compat shims for hypothetical futures. |
| Lead with the outcome | First sentence = the TLDR ("what happened" / "what I found"); detail after. Readable beats terse — no arrow-chains, jargon, or invented labels in user-facing text. |
| Give the reason | Include intent ("I'm doing X for Y; they need Z") — Fable connects the task to context better than inferring it. |
| Delegate readily | Fable dispatches parallel subagents well; hand off independent subtasks and keep working; prefer async over blocking. |
| Don't echo reasoning | **NEVER** instruct Fable to show, transcribe, or explain its internal reasoning as response text — it trips the `reasoning_extraction` refusal → Opus fallback. Adaptive thinking is always on; read the summarized `thinking` block if you need visibility. |

Effort is the depth control (auto-derived; do not hand-tune): `high` default, `xhigh` for the
hardest work, `low`/`medium` for routine — `Ai::Routing::EffortMapper`.
