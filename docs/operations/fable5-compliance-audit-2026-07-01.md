# Fable 5 Compliance Audit — 2026-07-01

Verification of the platform's Fable 5 rules and prompts against Anthropic's published
restrictions (per the `claude-api` reference current as of 2026-07-01), plus the
deprecated/obsolete-functionality cleanup performed in the same pass. Companion to
[conventions/fable5-compliance.md](../contributing/conventions/fable5-compliance.md)
(`guidance-fable5-compliance`).

## Verdict

**COMPLIANT.** Every published Fable 5 API restriction is enforced in code at the request-builder
layer in both apps, the prompting guidance matches the published behavioral guide, and routing
keeps Fable non-selectable until the operator flips `fable_routing_enabled`. The audit surfaced
no new violations; it surfaced deprecated/legacy provider-catalog content, which was removed in
this pass (below).

## Verification results (published restriction → enforcement)

| Published restriction | Enforcement | Status |
|---|---|---|
| Sampling params (`temperature`/`top_p`/`top_k`) 400 on Fable/Mythos/Opus 4.7+/Sonnet 5 | `Ai::Llm::ModelCapabilities.supports_sampling_params?` gates ALL body-builders: worker `build_anthropic_body`, `chat_fallback_providers_concern`, `chat_streaming_concern`; server `Adapters::Anthropic`, `provider_client_service` (send_message / generate_text / stream_text) | ✅ |
| `thinking` block (enabled/disabled/budget_tokens) 400 on Fable — omit or adaptive-only | Builders emit `{type:"adaptive",display:"summarized"}` only behind `opts[:surface_reasoning]` on `:adaptive_only` models; no `budget_tokens` path exists anywhere | ✅ |
| Depth via `output_config.effort` only (`low`→`max`) | `Ai::Routing::EffortMapper` (pin > complexity-derived > `high` default) merged into `output_config` so it composes with structured output; live for all effort-capable models | ✅ |
| No assistant prefill | Zero prefill call-sites in either app (verified by grep); `supports_prefill?` capability flag reserved for future callers | ✅ |
| `refusal` stop reason: branch before content, discard billed partials | Worker `parse_anthropic_response` + streaming path branch on `stop_reason` (never `stop_details`), nil out content/tool_calls on refusal, tag `pre_output`/`mid_stream` | ✅ |
| Refusal recovery | `Ai::Llm::RefusalHandler`: adapt (1 truthful reframe) → visible fallback (server-resolved non-Fable model, never the refuser) → respect a fallback refusal (no 3rd model); LOUD structured logging; `Ai::ModelRefusalEvent` + pre-route promotion server-side | ✅ |
| Exact model IDs (`claude-fable-5`, `claude-mythos-5`), no invented date suffixes | Only `claude-fable`/`claude-mythos` prefixes + exact `claude-fable-5` in code/seeds; Mythos never seeded as a default (recognized by prefix only — Project Glasswing gating respected) | ✅ |
| 30-day retention required (ZDR → 400) | Documented in convention doc + BASE_GUARDRAILS; **operator-parked**: confirm org retention before first live call (cannot be code-enforced) | ⚠️ parked |
| Minutes-long turns | 600s capability-aware request timeout (vs 120s legacy) aligned with server→worker envelope | ✅ |
| Prompting guide (over-prescription degrades output; `reasoning_extraction` refusals) | CoT/STAR scaffolds skipped for `refusal_capable?` models in `agent_tool_bridge_service`; Extended Thinking skill reworded off reasoning-as-output; `LoopGuardrails` TAIL carries autonomous-operation + progress-grounding lines; BASE_GUARDRAILS carries the refusal/goal-over-steps line | ✅ |
| Fable candidacy gating | `Ai::FableRouting` DEFAULT OFF (account → SiteSetting → false); selector + router exclude the family from candidates, drop Fable pins, and never fall back to it while off | ✅ |
| Worker/server duplication risk | The two `ModelCapabilities` copies are byte-identical except reciprocal path comments | ✅ |

## Deprecated/obsolete functionality removed in this pass

All changes verified: 276 targeted examples green (server + worker), `tsc --noEmit` clean,
pattern-validation scan clean for these files, gitleaks clean.

| Item | Change |
|---|---|
| `Ai::KnowledgeGraph::ExtractionService#default_model_for` | Dead code (zero callers) — removed |
| `WorkerLlmClient#execute_tool_loop` dropped `:effort` | Added to the opts slice; worker `jobs_controller#llm_execute_tool_loop` now also forwards `effort` + `max_tokens` (endpoint chain already supported them) |
| `Ai::Learning::LlmJudgeService` default evaluator `claude-sonnet-4-5-20250929` | → `claude-sonnet-5` |
| `providers/sync/anthropic.rb` sort branches for retired Claude-3-era ids (`sonnet-3`, `haiku-3-5`, `haiku-3`) | Removed; ladder now covers Fable → Opus 4.8/4.7/4.6/4.5 → Sonnet 5/4.6/4.5 → Haiku 4.5 (previously `claude-sonnet-5`/`claude-haiku-4-5` sorted last at priority 0) |
| `providers/sync/anthropic.rb` stale 200K/32K/8K fallbacks | Current generation (Fable/Mythos, Opus 4.6+, Sonnet 4.6/5) now 1M context / 128K output; Haiku 4.5 + Sonnet 4.5 64K output |
| `Ai::Providers::DefaultConfig` | Anthropic: dropped deprecated `claude-opus-4-1-20250805` (retires 2026-08-05) + date-suffixed ids → `%w[claude-opus-4-8 claude-sonnet-5 claude-sonnet-4-6 claude-haiku-4-5]`, default `claude-haiku-4-5`. OpenAI: dropped `gpt-4-turbo`/`gpt-3.5-turbo` |
| `Ai::Provider` concerns (`configurable`, `provider_setup`) | Replaced **invalid dot-form ids** (`claude-opus-4.5`, `claude-sonnet-4.5` — would 404 as API model ids) and `gpt-3.5-turbo`/`gpt-4` era defaults with the current lineup + correct 1M/128K envelopes and current pricing |
| `provider_testing/provider_adapters.rb` | Connection-test fallbacks → `claude-haiku-4-5`, `gpt-4.1-mini` |
| `db/seeds/comprehensive_ai_providers_seed.rb` | `claude-opus-4-1-20250805` → `claude-opus-4-8`; dated Sonnet 4.5 entry → `claude-sonnet-5`; Sonnet 4.6 envelope corrected to 1M/128K; Haiku → bare alias; default → `claude-haiku-4-5` |
| `Ai::ProviderManagementService::MODEL_PRICING` | Added missing `claude-sonnet-5` + `claude-sonnet-4-6` rows (Sonnet 5 previously resolved to **no pricing** — exact+prefix lookup both missed) |
| `frontend WorkflowTab.tsx` | Placeholder workflow model → `claude-sonnet-5` |
| `default_config_spec` | Fixed stale pre-existing failure (`types.size == 8` vs actual 10 — runway/elevenlabs) |
| `sync/anthropic_spec` | Updated stale output expectations; added current-generation coverage (1M/128K envelope + Fable-first sort) |

Kept deliberately: legacy pricing rows (historical cost attribution for existing usage records);
still-active legacy ids (`claude-opus-4-5`, `claude-sonnet-4-5`) in the pricing/tier tables;
API-fixture date-suffixed ids in sync specs (that is what the live API returns for legacy models).

## Known-open items (queued, not new)

- **Unify the 7 Anthropic body-builders** behind one gated builder so the `ModelCapabilities`
  gate cannot be bypassed by a future builder — queued as improvement `019f1cb6`. Every existing
  builder is individually gated today (verified above); this is structural hardening.
- **Streaming refusal adapt/fallback** — streaming surfaces refusals loudly but does not
  reframe/fall back mid-stream (TODO in worker `client.rb`).
- **Cross-provider refusal fallback** — same-provider only today.
- Pre-existing pattern-validation failure: stray git-ignored `test-credentials.json` at repo root
  (dated 2026-06-28, another session's artifact — surfaced, not deleted; owner should move or
  remove it).

## Operator-parked (Fable activation runbook)

1. Confirm anthropic org ≥30-day retention + limited-release `claude-fable-5` key access.
2. Run the isolated live smoke test when Fable is available.
3. Run provider/pricing/governance seeds, then flip `Account#settings["fable_routing_enabled"]`.
