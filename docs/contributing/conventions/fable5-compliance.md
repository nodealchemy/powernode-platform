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

Prefer stating the GOAL plus constraints over prescriptive step-by-step instructions —
over-prescription measurably reduces Fable's output quality. Let it plan its own approach.
