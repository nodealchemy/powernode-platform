# Memory System Architecture

**Multi-tier memory with working memory, short-term, long-term, and shared tiers**

**Version**: 1.0 | **Last Updated**: February 2026

---

## Overview

The Memory System provides agents with persistent, searchable memory across multiple tiers. Working memory lives in Redis for fast access, short-term memory has TTL-based expiration, long-term memory uses pgvector for semantic search, and shared memory enables cross-agent knowledge exchange.

### Memory Tiers

```
┌─────────────────────────────────────────────────────────┐
│                    Memory Router                         │
│         Ai::Memory::RouterService                        │
└────────────┬──────────┬──────────┬──────────┬───────────┘
             │          │          │          │
       ┌─────▼────┐ ┌───▼──────┐ ┌▼────────┐ ┌▼─────────┐
       │ Working  │ │ Short-   │ │ Long-   │ │ Shared   │
       │ Memory   │ │ Term     │ │ Term    │ │ Memory   │
       │ (Redis)  │ │ (DB+TTL) │ │ (pgvec) │ │ (Pools)  │
       └──────────┘ └──────────┘ └─────────┘ └──────────┘
       TTL: mins     TTL: hours   Permanent    Cross-agent
       Key-value     Structured   Embeddings   Collaborative
```

---

## Models

### Ai::AgentShortTermMemory

TTL-based short-term memory entries per agent session.

```ruby
MEMORY_TYPES = %w[task_context conversation tool_result reflection observation]
DEFAULT_TTL = 3600  # 1 hour

belongs_to :account
belongs_to :agent, class_name: "Ai::Agent"
```

**Key fields:** `session_id`, `memory_key`, `memory_value` (JSON), `memory_type`, `ttl_seconds`, `expires_at`, `access_count`, `last_accessed_at`

**Key methods:**
- `expired?` — checks if `expires_at` has passed
- `touch_access!` — increments `access_count`, updates `last_accessed_at`
- `refresh_ttl!` — extends expiration by `ttl_seconds`
- `self.cleanup_expired!` — bulk deletes expired entries

### Ai::MemoryPool

Shared memory pools for cross-agent collaboration.

```ruby
POOL_TYPES = %w[shared agent_private team_shared task_scoped]
SCOPES = %w[global account team agent task]

belongs_to :account
```

**Key fields:** `pool_id` (unique), `pool_type`, `scope`, `data` (JSON), `access_control` (JSON), `version`, `expires_at`

**Key methods:**
- `read_data` / `write_data` / `merge_data` — data access with access control
- `accessible_by?(agent)` — checks access control rules
- `grant_access(agent_id, level)` / `revoke_access(agent_id)` — permission management
- `statistics` — entry count, size, access metrics

### Ai::PersistentContext

Long-lived context containers for agents and knowledge bases.

```ruby
CONTEXT_TYPES = %w[agent_memory knowledge_base shared_context tool_cache project_context]
SCOPES = %w[agent account team global]

belongs_to :account
belongs_to :agent, optional: true
has_many :context_entries, dependent: :destroy
has_many :context_access_logs, dependent: :destroy
```

**Key methods:**
- `create_snapshot` / `restore_from_snapshot` — point-in-time backup and recovery
- `archive!` / `unarchive!` — lifecycle management
- `grant_access(agent_id, level)` — fine-grained access control

### Ai::ContextEntry

Individual entries within a PersistentContext, with pgvector embeddings for semantic search.

```ruby
ENTRY_TYPES = %w[fact observation reflection decision plan tool_output conversation_summary]
SOURCE_TYPES = %w[agent user system tool workflow]
MEMORY_TYPES = %w[factual experiential working]

has_neighbors :embedding  # pgvector integration

belongs_to :persistent_context
belongs_to :previous_version, optional: true
has_many :newer_versions
```

**Key methods:**
- `semantic_search(query_embedding, limit)` — nearest neighbor search via pgvector
- `update_content(new_content, editor)` — versioned content updates
- `boost_importance!` / `reduce_importance!` — importance score adjustment
- `effective_relevance_score` — combines importance, confidence, and recency

### Ai::SharedContextPool

Workflow-scoped shared memory for multi-node data exchange.

```ruby
# Pool types: shared_memory, tool_cache, blackboard
belongs_to :workflow_run
```

Used within workflow executions for nodes to share state via a common data pool.

---

## Services

### Ai::Memory::RouterService

Routes memory operations to the appropriate tier.

```ruby
router = Ai::Memory::RouterService.new(account: account, agent: agent)

# Read from specific tier (auto-routes if tier not specified)
value = router.read("session_context", session_id: "sess-123")

# Write to specific tier
router.write("task_result", { output: "..." }, tier: :short_term, session_id: "sess-123")

# Semantic search across long-term memory
results = router.semantic_search(query_embedding, limit: 10)

# Consolidate short-term → long-term (access_count >= 3)
router.consolidate!(session_id: "sess-123")

# Get stats across all tiers
stats = router.stats
# => { working_memory: {...}, short_term: {...}, long_term: {...}, shared: {...} }
```

### Ai::Memory::WorkingMemoryService

Redis-backed fast key-value store for active agent sessions.

```ruby
wm = Ai::Memory::WorkingMemoryService.new(agent: agent, account: account, task: task)

# Basic operations
wm.store("key", value, ttl: 300)
wm.retrieve("key")
wm.exists?("key")
wm.remove("key")
wm.keys  # List all keys
wm.clear # Remove all

# Specialized storage
wm.store_task_state(state_hash)
wm.store_intermediate_result(step_name, result)
wm.store_conversation_context(messages)
wm.append_to_conversation(message)
wm.store_tool_state(tool_name, state)
wm.store_scratch_pad(content)
wm.append_to_scratch_pad(content)

# Cross-agent sharing
wm.share_with_agent(target_agent_id, key, value)
shared_value = wm.retrieve_shared(source_agent_id, key)

# Workflow integration
wm.workflow_memory  # Returns workflow-scoped memory accessor

# Persistence (save Redis state to database)
wm.persist_to_database
wm.load_from_database
```

### Ai::Memory::StorageService

Backend storage with specialized concerns for different memory types.

**Included concerns:**
- `Experiential` — episodic memory from agent experiences
- `Factual` — structured facts and knowledge
- `SharedLearning` — learnings shared across agents
- `MemoryPool` — pool management operations

### Memory Maintenance

Automated maintenance runs via background jobs:

| Job | Schedule | Action |
|-----|----------|--------|
| Memory consolidation | 4:00 AM daily | Promotes STM entries with `access_count >= 3` to long-term |
| Deduplication | 4:00 AM daily | Merges entries with similarity >= 0.92 |
| Expired cleanup | Continuous | Deletes entries past `expires_at` |
| Context rot detection | 4:00 AM daily | Archives context entries with staleness >= 0.9 |

---

## Consolidation Pipeline

```
Short-Term Memory              Long-Term Memory
(DB with TTL)                  (pgvector embeddings)

  ┌──────────────┐              ┌──────────────┐
  │ Entry A      │              │              │
  │ access: 5    │──────────────▶  Promoted    │
  │ ttl: expired │  access >= 3 │  (embedded)  │
  └──────────────┘              └──────────────┘

  ┌──────────────┐
  │ Entry B      │
  │ access: 1    │──── Deleted (expired, low access)
  │ ttl: expired │
  └──────────────┘

  ┌──────────────┐     ┌──────────────┐
  │ Entry C      │     │ Entry D      │
  │ sim: 0.95    │─────│ sim: 0.95    │──── Merged (deduplicated)
  └──────────────┘     └──────────────┘
```

---

## Access Control

Memory access is controlled at multiple levels:

1. **Account scope** — all memory is scoped to an account
2. **Agent scope** — private memory is only accessible to the owning agent
3. **Pool access control** — JSONB `access_control` field with read/write permissions
4. **Context access control** — per-agent grants on PersistentContext

```ruby
# Pool access control structure
{
  "read" => ["agent-uuid-1", "agent-uuid-2"],
  "write" => ["agent-uuid-1"],
  "public_read" => false
}

# Grant/revoke
pool.grant_access("agent-uuid-3", :read)
pool.revoke_access("agent-uuid-3")
pool.accessible_by?(agent)  # => true/false
```

---

## Key Files

| File | Path |
|------|------|
| Short-Term Memory Model | `server/app/models/ai/agent_short_term_memory.rb` |
| Memory Pool Model | `server/app/models/ai/memory_pool.rb` |
| Persistent Context Model | `server/app/models/ai/persistent_context.rb` |
| Context Entry Model | `server/app/models/ai/context_entry.rb` |
| Context Access Log Model | `server/app/models/ai/context_access_log.rb` |
| Shared Context Pool Model | `server/app/models/ai/shared_context_pool.rb` |
| Router Service | `server/app/services/ai/memory/router_service.rb` |
| Working Memory Service | `server/app/services/ai/memory/working_memory_service.rb` |
| Storage Service | `server/app/services/ai/memory/storage_service.rb` |
| Maintenance Service | `server/app/services/ai/memory/maintenance_service.rb` |
| Embedding Service | `server/app/services/ai/memory/embedding_service.rb` |
