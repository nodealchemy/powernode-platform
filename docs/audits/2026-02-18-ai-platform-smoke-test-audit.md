# AI Platform — End-to-End Smoke Test Audit

**Date**: 2026-02-18
**Scope**: Skills, Skill Graph, Agent Execution, Conversations, Missions, Team Execution, Knowledge Graph
**Environment**: Development (localhost:3000/3001/4567)

---

## Executive Summary

Executed a progressive 10-stage smoke test across the AI platform. **Core functionality works** — agents execute against all 4 providers, conversations maintain context, skill graph discovery returns relevant results, and the mission pipeline transitions through all phases. However, **19 bugs** were found across 6 subsystems, including 3 critical issues.

| Severity | Count |
|----------|-------|
| Critical | 3 |
| High | 3 |
| Medium | 6 |
| Low | 7 |

---

## Bug #1 — Agent execution `output_data.response` always nil

**Severity**: Critical
**Subsystem**: Agent Executor
**Impact**: AI response text is never stored in execution records — only metadata (tokens, duration) is persisted

### Root Cause

Content extraction in `execute_with_provider` doesn't handle OpenAI's `choices` response format.

**File**: `server/app/services/ai/mcp_agent_executor/provider_execution.rb`, lines 75-84

```ruby
content_text = if response_data["content"].is_a?(Array)
                 # Only matches Anthropic: {"content": [{"text": "..."}]}
                 response_data["content"].map { |block| block.is_a?(Hash) ? block["text"] : block.to_s }.join
               elsif raw_data.is_a?(String)
                 raw_data
               else
                 # Tries keys that DON'T EXIST in OpenAI responses
                 response_data["content"] || response_data["text"] || result[:content] || result[:text]
               end
```

OpenAI/Grok returns: `{"choices": [{"message": {"content": "The AI text"}}], "usage": {...}}`
The actual text lives at `choices[0].message.content` — a path never tried.

The Anthropic branch (Array check) works for Anthropic but the else branch fails for OpenAI because it looks for flat `content`/`text` keys, not the nested `choices` structure.

Ollama works via its adapter (`ollama_adapter.rb` lines 27-43) which adds explicit `content:`/`text:` keys at the top level. OpenAI/Anthropic adapters use the generic `handle_response` which doesn't add these keys.

### Fix

Add OpenAI `choices` branch before the else:

```ruby
elsif response_data.dig("choices", 0, "message", "content").present?
  response_data.dig("choices", 0, "message", "content")
```

### Impact chain
- `provider_execution.rb:84` → `content_text = nil`
- `provider_execution.rb:94` → `{"output" => nil, ...}`
- `context_and_formatting.rb:82` → `{"result" => {"output" => nil}}`
- `execution.rb:53` → `output["response"] = result.dig("result", "output")` → `nil`

---

## Bug #2 — Token counting returns 0 for Anthropic and Ollama

**Severity**: Medium
**Subsystem**: Agent Executor
**Impact**: Billing/usage tracking shows 0 tokens for 2 of 4 providers

### Root Cause

Token extraction assumes all providers use OpenAI's `usage.total_tokens` format.

**File**: `server/app/services/ai/mcp_agent_executor/provider_execution.rb`, line 97

```ruby
"tokens_used" => response_data.dig("usage", "total_tokens") || response_data[:tokens_used] || result[:tokens_used]
```

| Provider | Token location | Extraction result |
|----------|---------------|-------------------|
| OpenAI/Grok | `usage.total_tokens` | **Works** |
| Anthropic | `usage.input_tokens` + `usage.output_tokens` (no `total_tokens`) | **nil** → 0 |
| Ollama | `prompt_eval_count` + `eval_count` (no `usage` key) | **nil** → 0 |

Note: `response_handling.rb` lines 113-127 has a correct `extract_usage` method that handles all three formats, but it's only called in `send_message`, not `generate_text`.

### Fix

```ruby
"tokens_used" => response_data.dig("usage", "total_tokens") ||
  (response_data.dig("usage", "input_tokens").to_i + response_data.dig("usage", "output_tokens").to_i).then { |t| t > 0 ? t : nil } ||
  (response_data["prompt_eval_count"].to_i + response_data["eval_count"].to_i).then { |t| t > 0 ? t : nil } ||
  0
```

---

## Bug #3 — `ai_messages.ai_agent_id` NOT NULL blocks mission milestone messages

**Severity**: Critical
**Subsystem**: Mission Pipeline
**Impact**: Mission milestones fail to post, `start!` raises 500

### Root Cause

Schema-model mismatch. The model declares `optional: true` but the DB column has `null: false`.

**Database** (`server/db/schema.rb`, line 2233):
```ruby
t.uuid "ai_agent_id", null: false
```

**Model** (`server/app/models/ai/message.rb`, line 13):
```ruby
belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true
```

**Trigger path**:
1. `OrchestratorService#start!` → `create_conversation!` (no agent set)
2. `transition_to_phase!` → `mission.update!(current_phase: ...)` → triggers `after_save :post_milestone_to_conversation`
3. `post_milestone_to_conversation` → `conversation.add_system_message(...)` → `messages.build(ai_agent_id: nil)` → `PG::NotNullViolation`

### Fix

Migration to allow null:
```ruby
change_column_null :ai_messages, :ai_agent_id, true
```

---

## Bug #4 — Skill graph edges missing `source_label`/`target_label` in API response

**Severity**: Medium
**Subsystem**: Skill Graph
**Impact**: Frontend visualization silently drops ALL edges (they don't render)

### Root Cause

`serialize_skill_edge` returns `source_node_id`/`target_node_id` but the frontend type expects `source_skill_id`/`target_skill_id` and optional name fields.

**Backend** (`server/app/services/ai/skill_graph/bridge_service.rb`, lines 204-213):
```ruby
def serialize_skill_edge(edge)
  {
    id: edge.id,
    source_node_id: edge.source_node_id,    # Frontend expects source_skill_id
    target_node_id: edge.target_node_id,    # Frontend expects target_skill_id
    relation_type: edge.relation_type,
    weight: edge.weight, confidence: edge.confidence
  }
end
```

**Frontend** (`frontend/src/features/ai/knowledge-graph/types/skillGraph.ts`, lines 21-30):
```typescript
export interface SkillGraphEdge {
  source_skill_id: string;    // Used for edge routing
  target_skill_id: string;
  source_skill_name?: string; // Used for labels
  target_skill_name?: string;
  ...
}
```

**SkillGraphVisualization.tsx** line 166 filters with `nodeIdSet.has(edge.source_skill_id)` — since `source_skill_id` is undefined, ALL edges are filtered out.

### Fix

1. Add `.includes(:source_node, :target_node)` to edge query (line 132)
2. Add to serializer:
```ruby
source_skill_id: edge.source_node_id,
target_skill_id: edge.target_node_id,
source_skill_name: edge.source_node&.name,
target_skill_name: edge.target_node&.name,
```

---

## Bug #5 — Knowledge graph embeddings never generated in production

**Severity**: Critical
**Subsystem**: Knowledge Graph / Embedding Service
**Impact**: Vector search always returns 0 results; `nodes_with_embeddings: 0` after sync

### Root Cause

`EmbeddingService#build_client` has a **constructor signature mismatch** with `ProviderClientService` AND calls a non-existent method.

**File**: `server/app/services/ai/memory/embedding_service.rb`, lines 193-199

```ruby
def build_client
  return nil unless @provider
  Ai::ProviderClientService.new(
    provider: @provider,      # Wrong: expects positional arg (credential), not kwargs
    account: @account
  ).build_client              # Wrong: no such method exists
end
```

`ProviderClientService.new` expects a single positional `Ai::ProviderCredential` argument (line 22 of provider_client_service.rb):
```ruby
def initialize(ai_provider_credential)
```

The `ArgumentError` is caught by `generate_from_provider`'s `rescue StandardError` (line 170), which returns `nil`. The nil propagates through `sync_skill` which guards with `if embedding`, so nodes are created without embeddings.

**Why tests pass**: Line 157 returns mock embeddings in test environment before ever reaching `build_client`:
```ruby
return generate_mock_embedding(text) if Rails.env.test?
```

### Fix

```ruby
def build_client
  return nil unless @provider
  credential = @account.ai_provider_credentials
    .where(ai_provider_id: @provider.id, is_active: true).first
  return nil unless credential
  Ai::ProviderClientService.new(credential)
end
```

---

## Bug #6 — No transaction around phase change + worker dispatch (mission stuck in limbo)

**Severity**: Critical (data integrity)
**Subsystem**: Mission Pipeline
**Impact**: When worker is down, mission is left in inconsistent state — phase updated but no job queued

### Root Cause

`OrchestratorService#start!` (and `advance!`, `resume!`, `retry_phase!`) commit phase changes to DB via individual `update!` calls, then dispatch a worker job via HTTP. When the HTTP call fails, the phase change is already committed.

**File**: `server/app/services/ai/missions/orchestrator_service.rb`, lines 27-40

```ruby
def start!
  # ...
  transition_to_phase!(first_phase)   # COMMITS to DB
  mission.update!(status: "active")   # COMMITS to DB
  dispatch_phase_job!                 # HTTP call — can raise WorkerServiceError
end
```

No `ActiveRecord::Base.transaction` wrapping. Same pattern in `advance!` (line 60-61), `resume!` (line 111), `retry_phase!` (line 118).

---

## Bug #7 — `WorkerServiceError` not caught by controller — 500 leaks to client

**Severity**: High
**Subsystem**: Mission Pipeline
**Impact**: Client sees 500 error but DB state is already modified

### Root Cause

Controller actions only rescue `OrchestrationError`, not `WorkerJobService::WorkerServiceError`.

**File**: `server/app/controllers/api/v1/ai/missions_controller.rb`

```ruby
rescue ::Ai::Missions::OrchestratorService::OrchestrationError => e
  render_error(e.message, :unprocessable_content)
# Missing: rescue WorkerJobService::WorkerServiceError
```

Affected actions: `start` (line 80), `approve` (line 99), `reject` (line 116), `resume` (line 140), `retry_phase` (line 162), `advance` (line 227).

---

## Bug #8 — `handle_approval!` ignores the `gate:` parameter

**Severity**: High
**Subsystem**: Mission Pipeline
**Impact**: Latent bug — `gate:` param is accepted but silently ignored

**File**: `server/app/services/ai/missions/orchestrator_service.rb`, line 71

```ruby
def handle_approval!(gate:, user:, decision:, ...)
  approval = mission.approvals.create!(
    gate: gate_for_phase(mission.current_phase),  # Ignores the gate: parameter!
    ...
  )
```

Should use `gate_for_phase(gate)` not `gate_for_phase(mission.current_phase)`.

---

## Bug #9 — `handle_rejection!` missing "previewing" gate case

**Severity**: High
**Subsystem**: Mission Pipeline
**Impact**: Rejecting at merge approval is a no-op — mission stays stuck

**File**: `server/app/services/ai/missions/orchestrator_service.rb`, lines 202-213

The `case` statement handles 3 of 4 gates (`awaiting_feature_approval`, `awaiting_prd_approval`, `awaiting_code_approval`) but NOT `previewing`. The `APPROVAL_GATES` constant includes all 4.

---

## Bug #10 — Double WebSocket broadcast on every phase transition

**Severity**: Medium
**Subsystem**: Mission Pipeline
**Impact**: Frontend receives duplicate "phase_changed" events

**File**: `server/app/services/ai/missions/orchestrator_service.rb`, line 129 AND `server/app/models/ai/mission.rb`, line 61

`transition_to_phase!` does:
1. `mission.update!(current_phase: phase)` → triggers `after_save :broadcast_phase_update` → broadcast #1
2. `MissionChannel.broadcast_mission_event(...)` → broadcast #2

---

## Bug #11 — Anthropic provider stale `default_model: claude-instant-1`

**Severity**: Medium
**Subsystem**: Provider Configuration
**Impact**: PRD generation and any service using `credential.provider.default_model` fails with 404

**File**: `server/app/models/concerns/ai/provider/configurable.rb`, line 164-165

```ruby
"models" => %w[claude-instant-1 claude-2],
"default_model" => "claude-instant-1",
```

These models are deprecated. The seeded provider data in the DB carries this stale default. Fixed manually during smoke test to `claude-haiku-4-5-20251001`.

---

## Bug #12 — `deploy` action response omits mission phase state

**Severity**: Medium
**Subsystem**: Mission Pipeline
**Impact**: Frontend can't know the phase advanced without refetching

**File**: `server/app/controllers/api/v1/ai/missions_controller.rb`, lines 317-319

```ruby
orchestrator.advance!(result: { deployed_url: url, stub: true })
render_success(deployment: { port: port, url: url, status: "stub", note: e.message })
# Missing: mission.reload.mission_details
```

---

## Bug #13 — Mission `base_branch` defaults to "main" instead of repo's actual default

**Severity**: Medium
**Subsystem**: Mission Pipeline
**Impact**: Branch creation fails for repos with `master` as default branch

**File**: `server/app/controllers/api/v1/ai/missions_controller.rb`, line 237

```ruby
base = params[:base_branch] || mission.base_branch || "main"
```

And `mission.rb` defaults `base_branch` to `"main"` when creating. Should look up the repository's `default_branch` instead.

---

## Bug #14 — Execution serializer never includes AI response output

**Severity**: Medium
**Subsystem**: Agent API
**Impact**: Execution list/detail API has no output field — consumers can't retrieve what the AI said

The `serialize_execution` method in `agents_controller.rb` returns metadata (tokens, duration, status) but no output field. Even if Bug #1 is fixed to store the response, there's no API path to retrieve it from execution records.

---

## Bug #15 — `update_column` for phase_history bypasses callbacks/validations

**Severity**: Low
**Subsystem**: Mission Pipeline
**Impact**: No audit trail, stale `updated_at`, potential race condition

**File**: `server/app/services/ai/missions/orchestrator_service.rb`, lines 139, 148

`record_phase_entry` and `record_phase_exit` use `update_column` which bypasses the `Auditable` concern.

---

## Bug #16 — `start!` sets phase before status — brief inconsistent window

**Severity**: Low
**Subsystem**: Mission Pipeline
**Impact**: WebSocket broadcast shows phase change while status is still "draft"

**File**: `server/app/services/ai/missions/orchestrator_service.rb`, lines 33-35

```ruby
transition_to_phase!(first_phase)   # phase = "analyzing", status still "draft"
mission.update!(status: "active")   # now status = "active"
```

---

## Bug #17 — Skill discovery returns all skills with flat scores regardless of context

**Severity**: Low
**Subsystem**: Skill Graph
**Impact**: Discovery always returns similar scores (0.66-0.8 range), limited usefulness

Observed during smoke test: "review my PR and write tests" returned Code Review (0.8), Compliance Review (0.8), Test Writing (0.78), API Design (0.78), Performance Tuning (0.78), Technical Writing (0.66). The spread is narrow and "Compliance Review" scored the same as "Code Review" despite being irrelevant to code PRs. Likely due to missing embeddings (Bug #5) falling back to keyword matching.

---

## Bug #18 — Team execution task distribution never fires

**Severity**: Low
**Subsystem**: Team Execution
**Impact**: Team executions stay at 0 tasks/0 messages indefinitely

During smoke test, team execution was created (`status: running`) but after 30+ seconds, `tasks_total: 0, messages_exchanged: 0`. The worker didn't process it. May be missing a worker job for team task distribution, or the job class name doesn't match.

---

## Bug #19 — Grok provider resolves to wrong model (`grok-2-vision-1212` instead of `grok-3`)

**Severity**: Low
**Subsystem**: Provider Client
**Impact**: Agent configured for `grok-3` may execute on a different model

Observed in execution `output_data.metadata.model_used: "grok-2-vision-1212"` when agent.model was `grok-3`. The X.AI API may be aliasing/redirecting, or the model ID resolution in the client is incorrect.

---

## Priority Fix Order

| Priority | Bugs | Rationale |
|----------|------|-----------|
| **P0** | #1, #3, #5 | Data integrity (limbo state), blocking feature (milestones), search completely broken |
| **P1** | #4, #7, #8, #9 | Edge rendering invisible, 500 errors leaking, approval logic incorrect |
| **P2** | #2, #6, #11, #12, #13, #14 | Token tracking, duplicate events, stale config, incomplete responses |
| **P3** | #10, #15, #16, #17, #18, #19 | Minor issues, cosmetic, or require deeper investigation |
