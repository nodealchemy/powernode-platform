# frozen_string_literal: true

# AI Orchestration Advanced Articles - Priority 3
# Creates comprehensive documentation for advanced AI Orchestration features
# Continues from ai_orchestration_articles.rb (Articles 15-27)

puts "  🤖 Creating AI Orchestration Advanced articles..."

ai_cat = KnowledgeBase::Category.find_by!(slug: "ai-orchestration")
author = User.find_by!(email: "admin@powernode.org")

# Article 28: A2A Protocol
a2a_protocol_content = <<~MARKDOWN
  # A2A Protocol: Agent-to-Agent Communication

  The Agent-to-Agent (A2A) protocol enables structured inter-agent communication within Powernode's AI orchestration platform. Built on the JSON-RPC 2.0 specification, A2A provides a standardized way for agents to discover each other, exchange tasks, and coordinate work across team and account boundaries.

  ## Overview

  A2A addresses the fundamental challenge of multi-agent systems: how do independent agents communicate reliably? Rather than building point-to-point integrations, A2A provides a protocol layer that handles discovery, task routing, and lifecycle management.

  ### Key Capabilities

  | Capability | Description |
  |------------|-------------|
  | **Agent Discovery** | Find available agents and their capabilities |
  | **Task Lifecycle** | Send, monitor, and cancel tasks between agents |
  | **JSON-RPC Dispatch** | Standardized request/response format |
  | **Federation** | Connect with external agent systems |
  | **Push Notifications** | Real-time async task updates |
  | **Security** | JWT auth with account scoping and permission checks |

  ## Agent Cards and Discovery

  Every agent in the system publishes an **Agent Card** — a structured description of its capabilities, accepted input formats, and communication preferences.

  ### Discovery Endpoint

  ```
  GET /api/v1/ai/a2a/discover
  Authorization: Bearer <jwt_token>
  ```

  Returns a list of agents available to the current account, filtered by permissions. Each entry includes the agent's ID, name, description, supported task types, and status.

  **Response Example:**

  ```json
  {
    "status": "success",
    "data": {
      "agents": [
        {
          "id": "01942a3b-...",
          "name": "Code Reviewer",
          "description": "Reviews pull requests for quality and security",
          "capabilities": ["code_review", "security_scan"],
          "status": "available",
          "card_url": "/api/v1/ai/a2a/agent-card/01942a3b-..."
        }
      ]
    }
  }
  ```

  ### Agent Card Endpoint

  ```
  GET /api/v1/ai/a2a/agent-card/:agent_id
  Authorization: Bearer <jwt_token>
  ```

  Returns the full agent card with detailed capability descriptions, input/output schemas, and configuration options.

  ## Task Lifecycle

  A2A tasks follow a well-defined lifecycle: **created → submitted → working → completed/failed/cancelled**.

  ### Sending a Task

  ```
  POST /api/v1/ai/a2a/tasks
  Authorization: Bearer <jwt_token>
  Content-Type: application/json

  {
    "target_agent_id": "01942a3b-...",
    "task_type": "code_review",
    "input": {
      "repository": "powernode-platform",
      "pull_request": 42
    },
    "priority": "normal",
    "callback_url": "/api/v1/ai/a2a/tasks/callback"
  }
  ```

  ### Retrieving Task Status

  ```
  GET /api/v1/ai/a2a/tasks/:task_id
  Authorization: Bearer <jwt_token>
  ```

  ### Cancelling a Task

  ```
  DELETE /api/v1/ai/a2a/tasks/:task_id
  Authorization: Bearer <jwt_token>
  ```

  Cancellation is best-effort — if the agent has already completed the task, the cancellation is a no-op.

  ## JSON-RPC Dispatch

  For more advanced interactions, A2A provides a full JSON-RPC 2.0 dispatch endpoint.

  ```
  POST /api/v1/ai/a2a/jsonrpc
  Authorization: Bearer <jwt_token>
  Content-Type: application/json

  {
    "jsonrpc": "2.0",
    "method": "tasks/send",
    "params": {
      "target_agent_id": "01942a3b-...",
      "task": {
        "type": "analysis",
        "input": { "data": "..." }
      }
    },
    "id": "req-001"
  }
  ```

  **Supported methods:**

  | Method | Description |
  |--------|-------------|
  | `tasks/send` | Submit a new task to an agent |
  | `tasks/get` | Retrieve task status and results |
  | `tasks/cancel` | Cancel a running task |
  | `agents/discover` | List available agents |
  | `agents/card` | Get a specific agent's card |

  ## Federation

  A2A supports federation with external agent systems, allowing Powernode agents to communicate with agents running on other platforms.

  ### How Federation Works

  1. **Register External Endpoint** — Configure an external A2A-compatible endpoint in your account settings
  2. **Certificate Exchange** — Mutual TLS or shared JWT signing keys establish trust
  3. **Namespace Isolation** — External agents appear with a `federated/` prefix to avoid naming conflicts
  4. **Task Routing** — The protocol service automatically routes tasks to the correct system based on agent ID namespace

  ### Federation Security

  - All federated requests are authenticated with JWT tokens scoped to the originating account
  - Rate limiting applies per-federation-endpoint
  - Task data never leaves the originating account's data boundary unless explicitly permitted
  - Audit logs track all cross-boundary interactions

  ## Push Notifications

  For long-running tasks, A2A supports push notifications so the requesting agent does not need to poll for status updates.

  ### Subscribing to Updates

  When sending a task, include a `callback_url` in the request body. The A2A protocol service will POST status updates to this URL as the task progresses.

  **Notification Payload:**

  ```json
  {
    "task_id": "01942a3b-...",
    "status": "completed",
    "result": { "findings": [...] },
    "completed_at": "2026-02-15T10:30:00Z"
  }
  ```

  ### Notification Events

  | Event | Triggered When |
  |-------|---------------|
  | `task.accepted` | Target agent acknowledges the task |
  | `task.working` | Agent begins processing |
  | `task.progress` | Agent reports intermediate progress |
  | `task.completed` | Task finished successfully |
  | `task.failed` | Task encountered an error |
  | `task.cancelled` | Task was cancelled |

  ## Security Model

  A2A enforces security at multiple layers:

  - **JWT Authentication** — Every request must include a valid JWT token
  - **Account Scoping** — Agents can only discover and communicate with agents in the same account (unless federated)
  - **Permission Checks** — The requesting user must have `ai.a2a.send` permission to send tasks, `ai.a2a.manage` to configure federation
  - **Rate Limiting** — Per-account and per-agent rate limits prevent abuse
  - **Audit Trail** — All A2A interactions are logged for compliance

  ## Related Articles

  - [AI Orchestration Overview](/kb/ai-orchestration-overview)
  - [Agent Teams and Multi-Agent Orchestration](/kb/agent-teams-multi-agent-orchestration)
  - [Trust & Autonomy System](/kb/trust-autonomy-system)

  ---

  Need help with A2A integration? Contact ai-support@powernode.org
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(slug: "a2a-protocol-agent-communication")
article.assign_attributes(
  title: "A2A Protocol: Agent-to-Agent Communication",
  category: ai_cat,
  author: author,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "JSON-RPC 2.0 based protocol for inter-agent communication with discovery, task lifecycle management, federation, and push notifications.",
  content: a2a_protocol_content,
  views_count: 0,
  likes_count: 0,
  published_at: Time.current
)
article.save!

puts "    ✅ A2A Protocol: Agent-to-Agent Communication"

# Article 29: Trust & Autonomy System
trust_autonomy_content = <<~MARKDOWN
  # Trust & Autonomy System

  Powernode's Trust & Autonomy system provides a graduated framework for controlling how much independence AI agents have. Agents start with minimal autonomy and earn greater freedom as they demonstrate reliability across multiple trust dimensions.

  ## Trust Tiers

  The system defines four trust tiers, each with specific thresholds and capabilities:

  | Tier | Threshold Range | Description |
  |------|----------------|-------------|
  | **Supervised** | 0.0 – 0.39 | Agent needs approval for all actions |
  | **Monitored** | 0.4 – 0.69 | Agent can act but all actions are logged and reviewed |
  | **Trusted** | 0.7 – 0.89 | Agent acts independently with periodic spot-checks |
  | **Autonomous** | 0.9 – 1.0 | Agent is fully self-directed with minimal oversight |

  ### What Each Tier Can Do

  **Supervised (0.0 – 0.39):**
  - Must request approval before executing any tool
  - Cannot commit code or modify resources without human sign-off
  - All outputs are reviewed before being used downstream
  - Ideal for newly created agents or agents assigned to sensitive tasks

  **Monitored (0.4 – 0.69):**
  - Can execute read-only tools without approval
  - Write operations still require approval
  - All actions are logged for post-hoc review
  - Can participate in team discussions autonomously

  **Trusted (0.7 – 0.89):**
  - Can execute most tools independently
  - Only high-risk operations (deployments, deletions, financial) require approval
  - Periodic spot-checks rather than comprehensive review
  - Can delegate sub-tasks to other agents

  **Autonomous (0.9 – 1.0):**
  - Fully self-directed execution
  - Can create and manage sub-agents
  - Can approve other agents' requests (within scope)
  - Only critical safety boundaries enforced
  - Still subject to budget limits and security policies

  ## Trust Dimensions

  Trust scores are calculated across five weighted dimensions:

  | Dimension | Weight | What It Measures |
  |-----------|--------|-----------------|
  | **task_completion** | 30% | Ratio of successfully completed tasks to total assigned |
  | **code_quality** | 25% | Lint scores, test pass rates, review approval rates |
  | **security_compliance** | 20% | Adherence to security policies, no credential leaks |
  | **communication** | 15% | Quality of status updates, accurate progress reporting |
  | **learning_rate** | 10% | Improvement over time, adaptation to feedback |

  ## TrustEngineService

  The `TrustEngineService` is the core service that calculates and manages agent trust scores.

  ### Score Calculation

  ```ruby
  # The service calculates a weighted composite score
  composite_score = (
    task_completion * 0.30 +
    code_quality * 0.25 +
    security_compliance * 0.20 +
    communication * 0.15 +
    learning_rate * 0.10
  )
  ```

  Each dimension score ranges from 0.0 to 1.0. The composite score determines which trust tier the agent occupies.

  ### Score Updates

  Trust scores are updated after each significant event:

  - **Task completion** — Success increases `task_completion`, failure decreases it
  - **Code review** — Approval increases `code_quality`, rejection decreases it
  - **Security scan** — Clean scan increases `security_compliance`, findings decrease it
  - **Status reports** — Timely, accurate reports increase `communication`
  - **Feedback loops** — Demonstrating improvement from feedback increases `learning_rate`

  ## Promotion and Demotion

  ### Promotion

  An agent is promoted to a higher trust tier when:

  1. Its composite score crosses the tier threshold
  2. The score has been stable above the threshold for a configurable period (default: 7 days)
  3. No critical security events have occurred in the evaluation window

  ### Demotion

  An agent is demoted when:

  1. Its composite score drops below the current tier's minimum threshold
  2. A critical security event occurs (immediate demotion to Supervised)
  3. Consecutive task failures exceed a configurable threshold

  Demotion is intentionally more aggressive than promotion — trust is slow to build and quick to lose.

  ## AgentBudget Controls

  Each trust tier has associated budget controls managed through the `AgentBudget` model:

  | Control | Supervised | Monitored | Trusted | Autonomous |
  |---------|-----------|-----------|---------|------------|
  | **Token limit/day** | 10,000 | 50,000 | 200,000 | 1,000,000 |
  | **Cost cap/day** | $1.00 | $5.00 | $25.00 | $100.00 |
  | **Max concurrent tasks** | 1 | 3 | 10 | 50 |
  | **Tool execution limit/hr** | 10 | 50 | 200 | Unlimited |

  Budget limits are enforced in real-time. When an agent reaches its limit, execution is paused until the next budget period or until an administrator manually increases the budget.

  ### Budget Overrides

  Administrators can override default budget limits for specific agents. Overrides persist across trust tier changes but are capped at the next tier's defaults.

  ## AgentTrustScore Model

  The `AgentTrustScore` model maintains the historical record of an agent's trust scores:

  ```ruby
  # Key fields
  agent_id          # Reference to the AI agent
  composite_score   # Current weighted score (0.0 - 1.0)
  tier              # Current trust tier (supervised, monitored, trusted, autonomous)
  dimensions        # JSON hash of individual dimension scores
  evaluation_window # Time period for the current evaluation
  promoted_at       # When the agent was last promoted
  demoted_at        # When the agent was last demoted
  ```

  Historical scores are retained for auditing and trend analysis. The system uses this history to calculate the stability requirement for promotion.

  ## Best Practices

  1. **Start all agents at Supervised** — Never skip the trust-building process
  2. **Configure dimension weights** per use case — Security-critical agents should weight `security_compliance` higher
  3. **Review demotion events** — Demotions often indicate a systemic issue, not just a one-off failure
  4. **Set realistic budgets** — Overly restrictive budgets cause task failures that lower trust scores
  5. **Monitor learning_rate** — Agents that plateau may need prompt tuning or model upgrades

  ## Related Articles

  - [AI Orchestration Overview](/kb/ai-orchestration-overview)
  - [Memory Tiers & Knowledge Management](/kb/memory-tiers-knowledge-management)
  - [AI Governance and Policies](/kb/ai-governance-policies)

  ---

  Need help configuring trust tiers? Contact ai-support@powernode.org
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(slug: "trust-autonomy-system")
article.assign_attributes(
  title: "Trust & Autonomy System",
  category: ai_cat,
  author: author,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Graduated trust framework with four tiers (supervised, monitored, trusted, autonomous), five trust dimensions, budget controls, and automatic promotion/demotion.",
  content: trust_autonomy_content,
  views_count: 0,
  likes_count: 0,
  published_at: Time.current
)
article.save!

puts "    ✅ Trust & Autonomy System"

# Article 30: Memory Tiers & Knowledge Management
memory_tiers_content = <<~MARKDOWN
  # Memory Tiers & Knowledge Management

  Powernode's AI memory system organizes agent knowledge across four tiers, each optimized for different access patterns, retention periods, and search capabilities. This tiered architecture ensures agents have fast access to recent context while maintaining long-term knowledge through vector embeddings.

  ## Memory Architecture Overview

  ```
  ┌─────────────────────────────────────────────────┐
  │                  Agent Request                    │
  │                       │                           │
  │              ┌────────▼────────┐                  │
  │              │ MemoryRouterService │              │
  │              └────────┬────────┘                  │
  │         ┌─────────┬───┴───┬──────────┐           │
  │    ┌────▼───┐ ┌───▼───┐ ┌▼──────┐ ┌─▼─────┐    │
  │    │Working │ │Short  │ │Long   │ │Shared │    │
  │    │(Redis) │ │Term   │ │Term   │ │(Team) │    │
  │    │        │ │(PG)   │ │(pgvec)│ │(pgvec)│    │
  │    └────────┘ └───────┘ └───────┘ └───────┘    │
  └─────────────────────────────────────────────────┘
  ```

  ## The Four Tiers

  | Tier | Storage | Retention | Search Method | Use Case |
  |------|---------|-----------|--------------|----------|
  | **Working** | Redis | Session-scoped | Key lookup | Current task context, scratch space |
  | **Short Term** | PostgreSQL | TTL-based (configurable) | SQL queries | Recent conversations, task history |
  | **Long Term** | PostgreSQL + pgvector | Permanent | Cosine similarity | Learned patterns, domain knowledge |
  | **Shared** | PostgreSQL + pgvector + ACL | Permanent | Cosine similarity + ACL filter | Team-wide knowledge, best practices |

  ### Working Memory (Redis)

  Working memory is the agent's immediate context — the scratchpad for the current task.

  - **Storage**: Redis key-value store
  - **Lifetime**: Expires when the agent session ends
  - **Access**: Direct key lookup (O(1))
  - **Typical Contents**: Current task parameters, intermediate results, conversation turns
  - **Size Limit**: 1MB per agent session

  ### Short Term Memory (PostgreSQL with TTL)

  Short-term memory persists beyond a single session but has a finite lifetime.

  - **Storage**: PostgreSQL `ai_agent_short_term_memories` table
  - **Lifetime**: Configurable TTL (default: 7 days)
  - **Access**: SQL queries with indexing
  - **Typical Contents**: Recent task outcomes, conversation summaries, temporary learnings
  - **Model**: `AgentShortTermMemory` with automatic TTL-based expiration

  ```ruby
  # TTL-based expiration
  # Memories older than their TTL are automatically archived or deleted
  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }
  ```

  ### Long Term Memory (pgvector Embeddings)

  Long-term memory stores knowledge that the agent has learned over time, indexed for semantic search.

  - **Storage**: PostgreSQL with pgvector extension
  - **Lifetime**: Permanent (subject to decay scoring)
  - **Access**: Cosine similarity search via `nearest_neighbors`
  - **Typical Contents**: Learned patterns, domain expertise, successful strategies
  - **Embedding Dimension**: 1536 (OpenAI ada-002 compatible)

  ```ruby
  # Semantic search for relevant memories
  memories = agent.long_term_memories
    .nearest_neighbors(:embedding, query_vector, distance: "cosine")
    .where("neighbor_distance <= ?", 1.0 - similarity_threshold)
    .limit(10)
  ```

  ### Shared Memory (pgvector + ACL)

  Shared memory is team-wide knowledge accessible to multiple agents, governed by access control lists.

  - **Storage**: PostgreSQL with pgvector extension
  - **Lifetime**: Permanent
  - **Access**: Cosine similarity + ACL-based filtering
  - **Typical Contents**: Team best practices, shared domain knowledge, organizational standards
  - **Model**: `SharedKnowledge` with `provenance` column tracking knowledge origin

  ## MemoryRouterService

  The `MemoryRouterService` is the central routing layer that determines where memories should be stored and retrieved from.

  ### Routing Logic

  ```ruby
  # Simplified routing decision
  case memory_type
  when :ephemeral      then store_in_working_memory(data)
  when :recent         then store_in_short_term(data, ttl: 7.days)
  when :learned        then store_in_long_term(data)
  when :team_knowledge then store_in_shared(data, acl: team_acl)
  end
  ```

  ### Retrieval Priority

  When an agent requests context, the router queries tiers in priority order:

  1. **Working memory** — Exact match on current task keys
  2. **Short-term memory** — Recent, relevant memories
  3. **Long-term memory** — Semantic search for relevant knowledge
  4. **Shared memory** — Team knowledge matching the query (ACL-filtered)

  Results are merged, deduplicated, and ranked by relevance before being injected into the agent's context window.

  ## ConsolidationService

  The `ConsolidationService` promotes important memories up the tier hierarchy.

  ### Promotion Rules

  | From | To | Trigger |
  |------|----|---------|
  | Working → Short Term | Memory accessed 3+ times in a session |
  | Short Term → Long Term | Memory accessed across 5+ sessions, high relevance score |
  | Long Term → Shared | Memory useful to 3+ agents, admin approval or auto-promotion |

  ### Deduplication

  During consolidation, the service checks for duplicates using cosine similarity:

  - Similarity >= 0.95 → Exact duplicate, skip
  - Similarity 0.85–0.94 → Near duplicate, merge metadata
  - Similarity < 0.85 → Distinct memory, proceed with promotion

  ## DecayService

  The `DecayService` applies temporal decay to memories, ensuring that stale knowledge does not pollute agent context.

  ### Decay Algorithm

  ```ruby
  # Temporal decay with access boost
  decay_score = base_relevance * (decay_factor ** days_since_last_access)
  # Memories below threshold are archived
  if decay_score < archive_threshold
    archive_memory(memory)
  end
  ```

  - **Decay factor**: 0.95 per day (configurable)
  - **Access boost**: Each access resets the decay clock
  - **Archive threshold**: 0.1 (memories below this are moved to cold storage)

  ## IntegrityService

  Per OWASP ASI05 guidelines, the `IntegrityService` ensures memory integrity using SHA-256 checksums.

  - Every memory entry has a SHA-256 hash of its content
  - On retrieval, the hash is verified before the memory is used
  - Hash mismatches trigger an alert and the memory is quarantined
  - Prevents tampering with agent knowledge by malicious inputs

  ## SharedKnowledgeService

  The `SharedKnowledgeService` manages team-wide knowledge with ACL-based access control.

  ### Access Control

  ```ruby
  # ACL structure
  {
    "read": ["team_a", "team_b"],
    "write": ["team_a"],
    "admin": ["lead_agent_id"]
  }
  ```

  - Agents can only read shared knowledge if their team is in the `read` ACL
  - Write access allows agents to contribute new shared knowledge
  - Admin access allows modifying ACLs and deleting entries

  ### Semantic Search

  ```ruby
  # Search shared knowledge with ACL filtering
  results = SharedKnowledge
    .accessible_by(agent)
    .nearest_neighbors(:embedding, query_vector, distance: "cosine")
    .limit(5)
  ```

  ## Best Practices

  1. **Keep working memory lean** — Only store what's needed for the current task
  2. **Set appropriate TTLs** — Short-term memories should expire before they become stale
  3. **Monitor consolidation** — Excessive promotion can bloat long-term memory
  4. **Review shared knowledge** — Periodically audit team knowledge for accuracy
  5. **Watch decay scores** — Important memories with low access should be manually boosted

  ## Related Articles

  - [Compound Learning System](/kb/compound-learning-system)
  - [Trust & Autonomy System](/kb/trust-autonomy-system)
  - [AI Governance and Policies](/kb/ai-governance-policies)

  ---

  Need help with memory configuration? Contact ai-support@powernode.org
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(slug: "memory-tiers-knowledge-management")
article.assign_attributes(
  title: "Memory Tiers & Knowledge Management",
  category: ai_cat,
  author: author,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Four-tier memory architecture (working, short-term, long-term, shared) with pgvector semantic search, temporal decay, consolidation, and integrity verification.",
  content: memory_tiers_content,
  views_count: 0,
  likes_count: 0,
  published_at: Time.current
)
article.save!

puts "    ✅ Memory Tiers & Knowledge Management"

# Article 31: Compound Learning System
compound_learning_content = <<~MARKDOWN
  # Compound Learning System

  The Compound Learning system enables AI agents to accumulate knowledge over time, transforming individual task outcomes into reusable insights that improve future performance. Rather than starting from scratch each session, agents leverage a growing library of proven strategies, failure patterns, and domain-specific knowledge.

  ## How It Works

  ```
  Task Outcome → AutoExtractorService → CompoundLearningService
       │                                        │
       │         ┌──────────────────────────────┤
       │         │              │               │
       │    Extraction    Deduplication    Storage
       │         │              │               │
       │         ▼              ▼               ▼
       │    Learning       Similarity      ai_compound
       │    Identified      Check           _learnings
       │                  (≥0.92 = dup)       table
       │                                       │
       └───────────────────────────────────────┤
                                               │
                              ┌─────────┬──────┴──────┐
                              │         │             │
                          Injection  Promotion   Maintenance
                          (context)  (cross-team) (daily job)
  ```

  ## AutoExtractorService

  The `AutoExtractorService` is the entry point for the compound learning pipeline. It monitors four types of events and extracts learnings from each.

  ### Event Types

  | Event Type | Trigger | What Is Extracted |
  |------------|---------|-------------------|
  | **Success Events** | Task completed successfully | Strategies that worked, effective tool chains, optimal parameters |
  | **Failure Events** | Task failed or timed out | Root cause patterns, anti-patterns, environmental preconditions |
  | **Review Feedback** | Human or agent review | Quality insights, missed edge cases, improvement suggestions |
  | **Evaluation Results** | Automated quality scoring | Performance benchmarks, regression indicators, efficiency metrics |

  ### Extraction Process

  1. The event payload is analyzed for extractable patterns
  2. Context is gathered from the agent's trajectory and memory
  3. A structured learning record is created with:
     - **Content**: The actual learning (natural language + structured data)
     - **Category**: What domain the learning applies to
     - **Confidence**: How certain the extraction is (0.0 – 1.0)
     - **Embedding**: Vector representation for similarity search

  ## CompoundLearningService

  The `CompoundLearningService` orchestrates the full lifecycle of compound learnings.

  ### Extraction

  Extraction is always active — it runs regardless of feature flags. Every task outcome is processed for potential learnings.

  ```ruby
  CompoundLearningService.extract(
    agent: agent,
    event_type: :success,
    event_data: { task_id: task.id, outcome: result }
  )
  ```

  ### Deduplication

  Before storing a new learning, the service checks for existing duplicates using cosine similarity on the embedding vectors:

  - **Similarity >= 0.92** → Duplicate detected, the existing learning's metadata is updated (access count, last seen)
  - **Similarity 0.80 – 0.91** → Related but distinct, stored as a new learning with a cross-reference
  - **Similarity < 0.80** → Novel learning, stored independently

  The 0.92 threshold was chosen empirically to balance deduplication accuracy with knowledge diversity.

  ### Context Injection

  When enabled via the `:compound_learning_injection` feature flag, relevant learnings are injected into an agent's context before task execution.

  ```ruby
  # Injection retrieves top-k relevant learnings
  relevant_learnings = CompoundLearningService.retrieve_for_context(
    agent: agent,
    task_description: task.description,
    limit: 5
  )
  # Learnings are formatted and prepended to the agent's system prompt
  ```

  **Feature flag**: `:compound_learning_injection`
  - **Enabled**: Learnings are injected into agent context
  - **Disabled**: Learnings are stored but not used (useful for A/B testing)

  ### Cross-Team Promotion

  When a learning proves valuable across multiple agents, it can be promoted to team-wide or organization-wide scope.

  **Feature flag**: `:compound_learning_promotion`
  - **Enabled**: High-effectiveness learnings are automatically promoted
  - **Disabled**: Learnings remain agent-scoped (promotion requires manual action)

  **Promotion Criteria:**

  | Criterion | Threshold |
  |-----------|-----------|
  | Effectiveness score | >= 0.85 |
  | Used by agents | >= 3 different agents |
  | Success rate when applied | >= 80% |
  | Age | >= 7 days (stability requirement) |

  ### Maintenance

  The `AiCompoundLearningMaintenanceJob` runs daily at **3:45 AM UTC** and performs:

  1. **Decay** — Reduce effectiveness scores of unused learnings
  2. **Archival** — Move learnings with effectiveness < 0.1 to cold storage
  3. **Consolidation** — Merge highly similar learnings (>= 0.95 similarity)
  4. **Statistics** — Update aggregate metrics for the dashboard

  ## Effectiveness Tracking

  Each compound learning has an `effectiveness_score` (0.0 – 1.0) that evolves over time:

  ```ruby
  # Score increases when a learning contributes to task success
  learning.effectiveness_score += 0.05 * success_weight

  # Score decreases when a learning is present but task fails
  learning.effectiveness_score -= 0.02 * failure_weight

  # Natural decay for unused learnings
  learning.effectiveness_score *= 0.99  # per day
  ```

  The effectiveness score directly impacts retrieval ranking — higher-effectiveness learnings are prioritized during context injection.

  ## Frontend: CompoundLearningPage

  The Compound Learning dashboard is accessible at `/app/ai/learning` and provides:

  ### Metrics Dashboard

  - **Total Learnings**: Count of active compound learnings
  - **Average Effectiveness**: Mean effectiveness score across all learnings
  - **Extraction Rate**: Learnings extracted per day
  - **Promotion Rate**: Percentage of learnings promoted to team scope

  ### Learnings List

  - Browse all compound learnings with filtering by category, effectiveness, and scope
  - View learning details including content, usage history, and cross-references
  - Manually promote or archive learnings
  - Export learnings for analysis

  ## Configuration

  | Setting | Default | Description |
  |---------|---------|-------------|
  | `extraction_enabled` | `true` | Always on — cannot be disabled |
  | `injection_enabled` | Feature flag | Controls context injection |
  | `promotion_enabled` | Feature flag | Controls cross-team promotion |
  | `dedup_threshold` | `0.92` | Cosine similarity threshold for deduplication |
  | `injection_limit` | `5` | Max learnings injected per task |
  | `maintenance_hour` | `3:45 UTC` | When daily maintenance runs |
  | `decay_rate` | `0.99/day` | Daily effectiveness decay multiplier |
  | `archive_threshold` | `0.1` | Effectiveness below this triggers archival |

  ## Related Articles

  - [Memory Tiers & Knowledge Management](/kb/memory-tiers-knowledge-management)
  - [Agent Trajectories](/kb/agent-trajectories)
  - [AI Monitoring Dashboard](/kb/ai-monitoring-dashboard)

  ---

  Need help with compound learning? Contact ai-support@powernode.org
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(slug: "compound-learning-system")
article.assign_attributes(
  title: "Compound Learning System",
  category: ai_cat,
  author: author,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Automatic learning extraction from task outcomes with deduplication, context injection, cross-team promotion, effectiveness tracking, and daily maintenance.",
  content: compound_learning_content,
  views_count: 0,
  likes_count: 0,
  published_at: Time.current
)
article.save!

puts "    ✅ Compound Learning System"

# Article 32: Worktree Sandboxes & Git Integration
worktree_sandboxes_content = <<~MARKDOWN
  # Worktree Sandboxes & Git Integration

  Powernode provides isolated execution environments for AI agents through Git worktree-based sandboxes. This approach gives each agent its own working copy of the repository without the overhead of full clones, enabling safe parallel code modifications with structured merge strategies.

  ## Architecture Overview

  ```
  Main Repository (.git)
       │
       ├── Worktree: ai/session-abc/feature-auth
       │     └── Agent A working on authentication
       │
       ├── Worktree: ai/session-def/fix-api
       │     └── Agent B fixing API endpoints
       │
       └── Worktree: ai/session-ghi/add-tests
             └── Agent C writing test coverage
  ```

  Git worktrees share the same `.git` directory but have independent working directories and branches. This means agents can work on different branches simultaneously without conflicts.

  ## WorktreeSandboxIntegrationService

  The `WorktreeSandboxIntegrationService` manages the full lifecycle of worktree-based sandboxes.

  ### Session Lifecycle

  ```
  Create → Lock → Execute → Unlock → Merge → Cleanup
    │       │        │         │        │        │
    │       │        │         │        │        └── Remove worktree
    │       │        │         │        └── Apply merge strategy
    │       │        │         └── Release lock
    │       │        └── Agent performs work
    │       └── Acquire exclusive lock
    └── Create worktree + branch
  ```

  ### Creating a Sandbox

  ```ruby
  sandbox = WorktreeSandboxIntegrationService.create(
    session_id: session.id,
    repository_path: "/path/to/repo",
    base_branch: "develop",
    suffix: "feature-auth"
  )
  # Creates worktree at: /path/to/repo/.worktrees/ai/session-{id}/feature-auth
  # Creates branch: ai/session-{id}/feature-auth
  ```

  ### Branch Naming Convention

  All AI agent branches follow a consistent naming scheme:

  ```
  ai/session-{session_id}/{suffix}
  ```

  - `ai/` prefix identifies agent-created branches
  - `session-{id}` groups branches by orchestration session
  - `{suffix}` describes the work being done (e.g., `feature-auth`, `fix-bug-123`)

  ### Config Auto-Copy

  When a worktree is created, the service automatically copies essential configuration files from the main working directory:

  | File | Purpose |
  |------|---------|
  | `.env` | Environment variables |
  | `.env.local` | Local overrides |
  | `.tool-versions` | Language version manager config |
  | `.ruby-version` | Ruby version specification |
  | `.node-version` | Node.js version specification |

  This ensures the agent's working environment matches the project configuration without requiring manual setup.

  ## Merge Strategies

  After agents complete their work, the service supports three strategies for integrating changes:

  ### Integration Branch (`integration_branch`)

  All agent branches are merged into a single integration branch for unified testing.

  ```
  develop ──────────────────────── integration/session-{id}
       │                                   ▲
       ├── ai/session-{id}/feature-auth ──┤
       ├── ai/session-{id}/fix-api ───────┤
       └── ai/session-{id}/add-tests ─────┘
  ```

  **Best for**: Teams that want a single PR with all agent changes combined.

  ### Sequential (`sequential`)

  Agent branches are merged one by one into the base branch, resolving conflicts at each step.

  ```
  develop ── merge(feature-auth) ── merge(fix-api) ── merge(add-tests)
  ```

  **Best for**: When changes might conflict and need ordered resolution.

  ### Manual (`manual`)

  Agent branches are left as-is for human review. No automatic merging occurs.

  ```
  develop (unchanged)
       ├── ai/session-{id}/feature-auth  (ready for PR)
       ├── ai/session-{id}/fix-api       (ready for PR)
       └── ai/session-{id}/add-tests     (ready for PR)
  ```

  **Best for**: High-stakes changes where human review before merge is required.

  ## Health Checks and Pruning

  ### Health Checks

  The service periodically verifies worktree health:

  - **Worktree exists** — The directory is present and contains a valid checkout
  - **Branch is valid** — The branch reference exists and is not corrupted
  - **Lock state** — Locks are not stale (abandoned by crashed processes)
  - **Disk usage** — Worktrees are not consuming excessive disk space

  ### Stale Worktree Pruning

  Worktrees that are no longer needed are automatically cleaned up:

  - Sessions completed > 24 hours ago → Worktree pruned
  - Sessions failed > 6 hours ago → Worktree pruned
  - Orphaned worktrees (no matching session) → Pruned immediately

  ```ruby
  WorktreeSandboxIntegrationService.prune_stale(
    max_age: 24.hours,
    dry_run: false
  )
  ```

  ## Container Sandboxes (Docker)

  For workloads that require more isolation than Git worktrees provide, the `SandboxManagerService` offers Docker container-based sandboxes.

  ### When to Use Containers

  | Scenario | Worktree | Container |
  |----------|----------|-----------|
  | Code editing and commits | Preferred | Possible |
  | Running tests | Possible | Preferred |
  | Installing dependencies | Not recommended | Preferred |
  | Network-isolated execution | Not possible | Preferred |
  | Quick iteration | Preferred | Slower startup |

  ### Container Lifecycle

  ```ruby
  sandbox = SandboxManagerService.create(
    image: "powernode/agent-sandbox:latest",
    resources: { cpu: "2", memory: "4Gi" },
    volumes: ["/path/to/worktree:/workspace"],
    network: "isolated"
  )
  ```

  ## AgentWorkspaceService

  The `AgentWorkspaceService` coordinates both worktree and container approaches, providing a unified interface for agent workspace management.

  ### Workspace Selection

  ```ruby
  workspace = AgentWorkspaceService.provision(
    agent: agent,
    task: task,
    preferences: {
      isolation_level: :standard,  # :minimal (worktree), :standard (worktree + locked), :full (container)
      merge_strategy: :integration_branch
    }
  )
  ```

  The service selects the appropriate sandbox type based on the requested isolation level and task requirements.

  ## Best Practices

  1. **Use worktrees for code tasks** — They are faster to create and more Git-native
  2. **Use containers for execution** — When agents need to run tests or install packages
  3. **Always set a merge strategy** — Leaving branches without a strategy leads to orphaned work
  4. **Monitor disk usage** — Worktrees share the object store but still consume space for working files
  5. **Clean up promptly** — Stale worktrees and containers waste resources

  ## Related Articles

  - [Using the AI Sandbox](/kb/using-ai-sandbox)
  - [Team Orchestration Patterns](/kb/team-orchestration-patterns)
  - [CI/CD Pipeline Integration](/kb/cicd-pipeline-integration)

  ---

  Need help with sandbox configuration? Contact ai-support@powernode.org
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(slug: "worktree-sandboxes-git-integration")
article.assign_attributes(
  title: "Worktree Sandboxes & Git Integration",
  category: ai_cat,
  author: author,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Git worktree-based isolation for AI agents with session lifecycle management, config auto-copy, three merge strategies, health checks, and container sandbox alternatives.",
  content: worktree_sandboxes_content,
  views_count: 0,
  likes_count: 0,
  published_at: Time.current
)
article.save!

puts "    ✅ Worktree Sandboxes & Git Integration"

# Article 33: Review Workflows
review_workflows_content = <<~MARKDOWN
  # Review Workflows

  Powernode's Review Workflow system provides structured quality gates for AI agent outputs. Whether you need mandatory human approval before deployment or advisory feedback that does not block execution, the review system adapts to your governance requirements.

  ## Overview

  The `ReviewWorkflowService` manages the complete review lifecycle, supporting two distinct modes that can be configured per team or per agent.

  ## Review Modes

  ### Blocking Mode

  In blocking mode, execution halts until a reviewer (human or agent) explicitly approves or rejects the output.

  ```
  Agent Output → Review Created → ⏸ Execution Paused
                                         │
                              ┌───────────┤
                              │           │
                          Approved    Rejected
                              │           │
                      Resume Execution  Return to Agent
                                       (with feedback)
  ```

  **Use Cases:**
  - Production deployments
  - Financial calculations
  - Security-sensitive operations
  - Customer-facing content generation

  ### Shadow Mode

  In shadow mode, reviews happen in parallel with continued execution. The review is advisory — it does not block the agent's workflow.

  ```
  Agent Output → Review Created → Execution Continues
                       │                    │
                       ▼                    ▼
                  Review Runs          Task Completes
                       │
                       ▼
                  Findings Logged
                  (advisory only)
  ```

  **Use Cases:**
  - Development and testing workflows
  - Learning and training new agents
  - Low-risk content generation
  - Gathering data to tune review policies

  ## Review Data Model

  The `ai_task_reviews` table tracks every review:

  | Field | Type | Description |
  |-------|------|-------------|
  | `task_id` | UUID | The task being reviewed |
  | `reviewer_agent_id` | UUID | Agent performing the review (null for human reviews) |
  | `reviewer_user_id` | UUID | Human reviewer (null for agent reviews) |
  | `review_mode` | String | `blocking` or `shadow` |
  | `status` | String | `pending`, `in_progress`, `approved`, `rejected`, `expired` |
  | `findings` | JSONB | Array of structured finding objects |
  | `completeness` | JSONB | Completeness check results |
  | `started_at` | Timestamp | When the review began |
  | `completed_at` | Timestamp | When the review finished |

  ## Review Findings

  Findings are structured observations from the review process, each with a severity level and category.

  ### Severity Levels

  | Severity | Description | Blocking Impact |
  |----------|-------------|----------------|
  | **Critical** | Must be fixed before approval | Auto-reject in blocking mode |
  | **High** | Should be fixed, significant risk | Reviewer decision required |
  | **Medium** | Recommended improvement | Does not block approval |
  | **Low** | Minor suggestion | Does not block approval |
  | **Info** | Observation, no action needed | Informational only |

  ### Finding Categories

  | Category | What It Covers |
  |----------|---------------|
  | **Security** | Vulnerabilities, credential exposure, injection risks |
  | **Performance** | N+1 queries, memory leaks, slow algorithms |
  | **Correctness** | Logic errors, edge cases, data integrity |
  | **Style** | Code formatting, naming conventions, readability |
  | **Documentation** | Missing docs, outdated comments, unclear descriptions |

  ### Finding Structure

  ```json
  {
    "severity": "high",
    "category": "security",
    "title": "SQL injection risk in search parameter",
    "description": "The search parameter is interpolated directly into the SQL query without sanitization.",
    "location": {
      "file": "app/services/search_service.rb",
      "line": 42
    },
    "suggestion": "Use parameterized queries: where('name LIKE ?', \"%\#{sanitize(query)}%\")"
  }
  ```

  ## Completeness Checks

  The review system verifies that reviews cover all required areas before accepting them as complete.

  ### Default Completeness Areas

  | Area | Description |
  |------|-------------|
  | **Functionality** | Does the code do what it's supposed to? |
  | **Error Handling** | Are edge cases and errors handled? |
  | **Security** | Are there security implications? |
  | **Testing** | Are tests present and sufficient? |
  | **Documentation** | Is the change documented? |

  ### Completeness Scoring

  ```json
  {
    "areas_reviewed": ["functionality", "error_handling", "security", "testing"],
    "areas_missing": ["documentation"],
    "completeness_score": 0.80,
    "is_complete": false,
    "minimum_required": 0.90
  }
  ```

  If the completeness score is below the minimum threshold, the review is flagged as incomplete and the reviewer is prompted to cover missing areas.

  ## Frontend Components

  ### ReviewPanel

  The `ReviewPanel` component provides a unified interface for viewing and managing reviews:

  - **Review Status** — Current status with color-coded severity indicators
  - **Findings List** — All findings grouped by category with severity badges
  - **Completeness Indicator** — Visual progress bar showing review coverage
  - **Action Buttons** — Approve, reject, or request changes (blocking mode only)
  - **Timeline** — Chronological view of review events

  ### ReviewConfigSection

  The `ReviewConfigSection` component allows team-level review configuration:

  - **Default Mode** — Set the default review mode (blocking or shadow) for the team
  - **Auto-Assignment** — Configure rules for automatic reviewer assignment
  - **Required Areas** — Specify which completeness areas are mandatory
  - **Escalation Rules** — Define when reviews should be escalated to human reviewers
  - **Timeout Settings** — Maximum time before a review expires

  ## Configuration

  ### Per-Team Configuration

  ```ruby
  team.review_config = {
    default_mode: "blocking",
    required_completeness: 0.90,
    auto_assign_reviewer: true,
    escalation_timeout: 2.hours,
    required_areas: ["functionality", "security", "testing"]
  }
  ```

  ### Per-Agent Configuration

  Individual agents can override team defaults:

  ```ruby
  agent.review_config = {
    mode: "shadow",          # Override team default
    skip_areas: ["style"],   # Don't require style review for this agent
    reviewer_preference: "agent"  # Prefer agent reviewers over human
  }
  ```

  ## Best Practices

  1. **Start with blocking mode** — Switch to shadow only after establishing trust
  2. **Configure required areas** based on risk — Security-critical tasks need full completeness
  3. **Use severity thresholds** — Auto-reject only on critical findings; let reviewers decide on high
  4. **Monitor shadow reviews** — They provide valuable signal about agent quality without blocking work
  5. **Set reasonable timeouts** — Expired reviews create bottlenecks in blocking mode

  ## Related Articles

  - [Trust & Autonomy System](/kb/trust-autonomy-system)
  - [Agent Trajectories](/kb/agent-trajectories)
  - [AI Governance and Policies](/kb/ai-governance-policies)

  ---

  Need help configuring review workflows? Contact ai-support@powernode.org
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(slug: "review-workflows")
article.assign_attributes(
  title: "Review Workflows",
  category: ai_cat,
  author: author,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Structured review system with blocking and shadow modes, severity-graded findings, completeness checks, and per-team/per-agent configuration.",
  content: review_workflows_content,
  views_count: 0,
  likes_count: 0,
  published_at: Time.current
)
article.save!

puts "    ✅ Review Workflows"

# Article 34: Role Profiles
role_profiles_content = <<~MARKDOWN
  # Role Profiles

  Role Profiles define the behavioral blueprint for AI agents — what they are good at, how they communicate, and what tools they can access. Powernode ships with six system profiles covering common agent roles, and supports custom profiles for organization-specific needs.

  ## System Profiles

  The platform includes six pre-seeded system profiles that cannot be deleted:

  | Profile | Slug | Primary Purpose |
  |---------|------|----------------|
  | **Developer** | `developer` | Write, refactor, and debug code |
  | **Reviewer** | `reviewer` | Review code, documents, and agent outputs |
  | **Researcher** | `researcher` | Gather information, analyze data, synthesize findings |
  | **Writer** | `writer` | Create documentation, articles, and content |
  | **Planner** | `planner` | Break down tasks, create plans, coordinate work |
  | **Tester** | `tester` | Write tests, run test suites, report coverage |

  ## Ai::RoleProfile Model

  Each role profile is stored in the `ai_role_profiles` table with the following structure:

  | Field | Type | Description |
  |-------|------|-------------|
  | `role_type` | String | The general category (e.g., `development`, `quality`, `content`) |
  | `slug` | String | Unique identifier (e.g., `developer`, `reviewer`) |
  | `name` | String | Display name |
  | `description` | Text | Human-readable description of the role |
  | `prompt_template` | Text | Base system prompt for agents with this role |
  | `quality_checks` | JSONB | Definitions of what this role validates |
  | `tool_access` | JSONB | Which MCP tools are available to this role |
  | `is_system` | Boolean | Whether this is a built-in profile (cannot be deleted) |
  | `is_active` | Boolean | Whether the profile is available for assignment |

  ## Prompt Templates

  Each profile includes a `prompt_template` that defines the agent's base behavior. This template is prepended to the agent's system prompt during execution.

  ### Developer Profile Template (Example)

  ```markdown
  You are a software developer agent. Your primary responsibilities are:

  - Writing clean, well-structured code that follows project conventions
  - Refactoring existing code for improved readability and performance
  - Debugging issues by analyzing error messages and stack traces
  - Following the project's coding standards and style guides

  When writing code:
  - Always include error handling
  - Write self-documenting code with clear variable names
  - Add comments only when the "why" is not obvious from the code
  - Consider edge cases and input validation

  When debugging:
  - Start by reproducing the issue
  - Check logs and error messages
  - Form a hypothesis before making changes
  - Verify the fix does not introduce regressions
  ```

  ### Reviewer Profile Template (Example)

  ```markdown
  You are a code review agent. Your primary responsibilities are:

  - Reviewing code changes for correctness, security, and performance
  - Providing constructive feedback with specific suggestions
  - Checking for adherence to project standards
  - Identifying potential bugs and edge cases

  When reviewing:
  - Focus on logic and correctness first
  - Check for security implications
  - Evaluate error handling completeness
  - Assess test coverage
  - Be specific in feedback — reference exact lines and suggest alternatives
  ```

  ## Quality Check Definitions

  The `quality_checks` field specifies what each role is expected to validate:

  ```json
  {
    "developer": {
      "checks": [
        { "name": "syntax_valid", "description": "Code parses without syntax errors", "required": true },
        { "name": "tests_pass", "description": "All related tests pass", "required": true },
        { "name": "lint_clean", "description": "No linting violations", "required": false },
        { "name": "type_check", "description": "Type checker reports no errors", "required": false }
      ]
    },
    "reviewer": {
      "checks": [
        { "name": "security_reviewed", "description": "Security implications assessed", "required": true },
        { "name": "correctness_verified", "description": "Logic verified for correctness", "required": true },
        { "name": "edge_cases_checked", "description": "Edge cases identified", "required": true },
        { "name": "documentation_reviewed", "description": "Documentation is adequate", "required": false }
      ]
    }
  }
  ```

  ## Tool Access Controls

  The `tool_access` field defines which MCP tools are available to agents with this profile:

  ```json
  {
    "developer": {
      "allowed_tools": [
        "filesystem_read",
        "filesystem_write",
        "git_operations",
        "terminal_execute",
        "web_search"
      ],
      "denied_tools": [
        "deployment_trigger",
        "database_admin"
      ]
    },
    "researcher": {
      "allowed_tools": [
        "filesystem_read",
        "web_search",
        "web_fetch",
        "database_query"
      ],
      "denied_tools": [
        "filesystem_write",
        "terminal_execute",
        "deployment_trigger"
      ]
    }
  }
  ```

  Tool access is enforced at the MCP layer — even if an agent attempts to use a denied tool, the request is rejected before execution.

  ## Custom Profiles

  Organizations can create custom profiles tailored to their specific workflows.

  ### Creating a Custom Profile

  ```ruby
  Ai::RoleProfile.create!(
    role_type: "specialized",
    slug: "security-auditor",
    name: "Security Auditor",
    description: "Specialized agent for security auditing and vulnerability assessment",
    prompt_template: "You are a security auditor agent...",
    quality_checks: {
      checks: [
        { name: "vulnerability_scan", description: "Run vulnerability scanner", required: true },
        { name: "dependency_audit", description: "Check dependency security", required: true }
      ]
    },
    tool_access: {
      allowed_tools: ["filesystem_read", "web_search", "security_scanner"],
      denied_tools: ["filesystem_write", "deployment_trigger"]
    },
    is_system: false,
    is_active: true
  )
  ```

  ### Custom Profile Guidelines

  1. **Be specific in prompt templates** — Vague instructions lead to inconsistent behavior
  2. **Minimize tool access** — Grant only the tools needed for the role (principle of least privilege)
  3. **Define quality checks** — Even if not enforced, they guide the agent's self-evaluation
  4. **Test before deploying** — Run the profile in shadow mode before using it in production

  ## RoleProfileSelector Component

  The `RoleProfileSelector` is a frontend component for assigning profiles to agents within a team.

  ### Features

  - **Profile Browser** — Grid view of all available profiles with descriptions
  - **Search and Filter** — Filter by role type, active status, and system/custom
  - **Profile Details** — Expandable view showing prompt template, quality checks, and tool access
  - **Quick Assignment** — One-click profile assignment to team roles
  - **Comparison View** — Side-by-side comparison of two profiles

  ## Profile Assignment

  Profiles are assigned to agents through their team role. The assignment is stored in the `TeamRole` metadata:

  ```ruby
  team_role = Ai::TeamRole.find(role_id)
  team_role.metadata["role_profile_id"] = profile.id
  team_role.save!
  ```

  When an agent is activated, the system loads its assigned profile and applies the prompt template, quality checks, and tool access controls.

  ## Best Practices

  1. **Use system profiles as starting points** — Customize by creating new profiles, not modifying system ones
  2. **Keep prompt templates focused** — One role = one responsibility
  3. **Review tool access regularly** — As new MCP tools are added, update profile access lists
  4. **Version your custom profiles** — Include a version field in metadata for tracking changes
  5. **Monitor quality check pass rates** — Low pass rates may indicate the profile needs tuning

  ## Related Articles

  - [Creating and Managing AI Agents](/kb/creating-managing-ai-agents)
  - [Team Orchestration Patterns](/kb/team-orchestration-patterns)
  - [MCP Servers and Context Management](/kb/mcp-servers-context-management)

  ---

  Need help creating custom profiles? Contact ai-support@powernode.org
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(slug: "role-profiles")
article.assign_attributes(
  title: "Role Profiles",
  category: ai_cat,
  author: author,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Six system role profiles (developer, reviewer, researcher, writer, planner, tester) with prompt templates, quality checks, tool access controls, and custom profile creation.",
  content: role_profiles_content,
  views_count: 0,
  likes_count: 0,
  published_at: Time.current
)
article.save!

puts "    ✅ Role Profiles"

# Article 35: Agent Trajectories
agent_trajectories_content = <<~MARKDOWN
  # Agent Trajectories

  A trajectory is the complete execution trace of an AI agent's work — from the moment a task is assigned to the final outcome. Trajectories provide full observability into what an agent did, why it made certain decisions, and how well it performed.

  ## Core Concepts

  ### What Is a Trajectory?

  A trajectory captures the entire execution flow of an agent working on a task. Unlike simple logs that record individual events, trajectories organize execution into logical chapters with quality scoring and outcome tracking.

  ```
  Trajectory: "Implement user authentication"
  ├── Chapter 1: Research Phase
  │   ├── Event: Searched codebase for existing auth patterns
  │   ├── Event: Read authentication documentation
  │   └── Event: Identified JWT-based auth strategy
  ├── Chapter 2: Implementation Phase
  │   ├── Event: Created AuthService class
  │   ├── Event: Added JWT token generation
  │   ├── Event: Implemented login endpoint
  │   └── Event: Added password validation
  ├── Chapter 3: Testing Phase
  │   ├── Event: Wrote unit tests for AuthService
  │   ├── Event: Wrote integration tests for login flow
  │   └── Event: All 12 tests passing
  └── Outcome: Success (quality_score: 0.92)
  ```

  ## Data Model

  ### ai_trajectories Table

  | Field | Type | Description |
  |-------|------|-------------|
  | `agent_id` | UUID | The agent that executed the trajectory |
  | `task_id` | UUID | The task being worked on |
  | `team_id` | UUID | The team context (if any) |
  | `status` | String | `running`, `completed`, `failed`, `timeout` |
  | `outcome` | String | `success`, `failure`, `partial`, `timeout` |
  | `quality_score` | Decimal | Overall quality assessment (0.0 – 1.0) |
  | `started_at` | Timestamp | When execution began |
  | `completed_at` | Timestamp | When execution finished |
  | `total_tokens` | Integer | Total tokens consumed |
  | `total_cost` | Decimal | Total cost incurred |
  | `metadata` | JSONB | Additional execution metadata |

  ### ai_trajectory_chapters Table

  | Field | Type | Description |
  |-------|------|-------------|
  | `trajectory_id` | UUID | Parent trajectory |
  | `title` | String | Chapter name (e.g., "Research Phase") |
  | `chapter_type` | String | Category of work (research, implementation, testing, review) |
  | `sequence_number` | Integer | Order within the trajectory |
  | `status` | String | `running`, `completed`, `failed` |
  | `started_at` | Timestamp | When the chapter began |
  | `completed_at` | Timestamp | When the chapter finished |
  | `events` | JSONB | Array of structured event records |
  | `summary` | Text | AI-generated summary of the chapter |
  | `metrics` | JSONB | Chapter-specific metrics (tokens, tool calls, etc.) |

  ## TrajectoryService

  The `TrajectoryService` is the primary interface for recording and analyzing trajectories.

  ### Recording Events

  ```ruby
  # Start a new trajectory
  trajectory = TrajectoryService.start(
    agent: agent,
    task: task,
    team: team
  )

  # Begin a chapter
  chapter = TrajectoryService.begin_chapter(
    trajectory: trajectory,
    title: "Research Phase",
    chapter_type: "research"
  )

  # Record events within the chapter
  TrajectoryService.record_event(
    chapter: chapter,
    event_type: "tool_call",
    data: {
      tool: "filesystem_read",
      input: { path: "app/services/auth_service.rb" },
      output: { content: "..." },
      tokens: 1500
    }
  )

  # Complete the chapter
  TrajectoryService.complete_chapter(
    chapter: chapter,
    summary: "Analyzed existing codebase and identified JWT auth pattern"
  )

  # Complete the trajectory
  TrajectoryService.complete(
    trajectory: trajectory,
    outcome: "success"
  )
  ```

  ### Quality Scoring

  The service calculates quality scores based on four factors:

  | Factor | Weight | Measurement |
  |--------|--------|------------|
  | **Task Completion** | 40% | Did the agent achieve the stated goal? |
  | **Error Rate** | 25% | Ratio of errors/retries to successful operations |
  | **Token Efficiency** | 20% | Tokens used relative to task complexity |
  | **Time Efficiency** | 15% | Time taken relative to task complexity baseline |

  ```ruby
  quality_score = (
    task_completion_score * 0.40 +
    (1.0 - error_rate) * 0.25 +
    token_efficiency_score * 0.20 +
    time_efficiency_score * 0.15
  )
  ```

  ### Outcome Tracking

  | Outcome | Description |
  |---------|-------------|
  | **Success** | Task completed, all acceptance criteria met |
  | **Failure** | Task could not be completed, agent gave up or hit a dead end |
  | **Partial** | Some objectives met but not all |
  | **Timeout** | Task exceeded the allocated time budget |

  ## Frontend Components

  ### TrajectoryViewer

  The `TrajectoryViewer` component provides a rich visualization of a single trajectory:

  - **Timeline View** — Chronological display of chapters and events
  - **Chapter Cards** — Expandable cards for each chapter with summary and events
  - **Event Details** — Click-through to see tool call inputs/outputs
  - **Quality Metrics** — Visual breakdown of the four quality factors
  - **Token Usage** — Chart showing token consumption over time
  - **Cost Summary** — Total cost with per-chapter breakdown

  ### TrajectoryList

  The `TrajectoryList` component provides a browsable list of past trajectories:

  - **Filtering** — By agent, team, outcome, date range, quality score
  - **Sorting** — By date, quality score, cost, duration
  - **Summary Cards** — Each trajectory shown with key metrics at a glance
  - **Bulk Actions** — Export, archive, or tag multiple trajectories
  - **Search** — Full-text search across trajectory events and summaries

  ## Learning Integration

  Trajectories feed directly into the Compound Learning system:

  1. **Successful trajectories** are analyzed for effective strategies and patterns
  2. **Failed trajectories** are analyzed for anti-patterns and failure modes
  3. **High-quality trajectories** (score >= 0.9) are flagged as exemplars for similar future tasks
  4. **Trajectory comparisons** identify which approaches work better for specific task types

  ```ruby
  # After trajectory completion, trigger learning extraction
  CompoundLearningService.extract(
    agent: trajectory.agent,
    event_type: trajectory.outcome == "success" ? :success : :failure,
    event_data: {
      trajectory_id: trajectory.id,
      quality_score: trajectory.quality_score,
      chapters: trajectory.chapters.map(&:summary)
    }
  )
  ```

  ## Analytics and Reporting

  Trajectory data powers several analytics views:

  - **Agent Performance** — Track quality scores over time per agent
  - **Task Type Analysis** — Identify which task types agents excel at or struggle with
  - **Cost Optimization** — Find trajectories with high cost but low quality for investigation
  - **Team Efficiency** — Compare trajectory metrics across teams
  - **Trend Detection** — Spot improving or degrading performance trends

  ## Best Practices

  1. **Name chapters descriptively** — Good chapter names make trajectories readable months later
  2. **Record tool call details** — Input/output recording enables debugging and replay
  3. **Set quality baselines** — Establish expected quality scores per task type
  4. **Review low-scoring trajectories** — They often reveal systemic issues
  5. **Use trajectory data for prompt tuning** — Patterns from successful trajectories improve prompts

  ## Related Articles

  - [Compound Learning System](/kb/compound-learning-system)
  - [AI Monitoring Dashboard](/kb/ai-monitoring-dashboard)
  - [Trust & Autonomy System](/kb/trust-autonomy-system)

  ---

  Need help with trajectory analysis? Contact ai-support@powernode.org
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(slug: "agent-trajectories")
article.assign_attributes(
  title: "Agent Trajectories",
  category: ai_cat,
  author: author,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Complete execution traces with chapters, quality scoring, outcome tracking, and integration with the compound learning system for continuous agent improvement.",
  content: agent_trajectories_content,
  views_count: 0,
  likes_count: 0,
  published_at: Time.current
)
article.save!

puts "    ✅ Agent Trajectories"

# Article 36: Team Orchestration Patterns
team_orchestration_content = <<~MARKDOWN
  # Team Orchestration Patterns

  Powernode supports multiple team structures and coordination strategies for multi-agent orchestration. Choosing the right combination of team type and coordination strategy is critical for effective agent collaboration.

  ## Team Types

  ### Functional Teams

  A functional team consists of agents with the **same skill set** working together on related tasks.

  ```
  Functional Team: "Backend Dev Squad"
  ├── Agent: Backend Dev A (developer profile)
  ├── Agent: Backend Dev B (developer profile)
  └── Agent: Backend Dev C (developer profile)
  ```

  **When to Use:**
  - Large volume of similar tasks (e.g., migrating 50 API endpoints)
  - Tasks that benefit from parallel execution with identical skill sets
  - Load balancing across multiple agents

  **Strengths:** High throughput for homogeneous work, simple coordination
  **Weaknesses:** No diversity of perspective, bottleneck if tasks require different skills

  ### Cross-Functional Teams

  A cross-functional team combines agents with **different skill sets** to cover all aspects of a deliverable.

  ```
  Cross-Functional Team: "Feature Team"
  ├── Agent: Frontend Dev (developer profile)
  ├── Agent: Backend Dev (developer profile)
  ├── Agent: QA Engineer (tester profile)
  └── Agent: Tech Writer (writer profile)
  ```

  **When to Use:**
  - End-to-end feature development
  - Tasks that span multiple domains
  - Quality-focused work requiring built-in review

  **Strengths:** Complete coverage, built-in quality gates, diverse perspectives
  **Weaknesses:** More complex coordination, potential for idle agents during sequential phases

  ### Hierarchical Teams

  A hierarchical team has a **lead agent** that plans work and delegates to subordinate agents.

  ```
  Hierarchical Team: "Architecture Team"
  ├── Lead: Tech Lead Agent (planner profile)
  │   ├── Delegate: Dev Agent A (developer profile)
  │   ├── Delegate: Dev Agent B (developer profile)
  │   └── Delegate: Reviewer Agent (reviewer profile)
  ```

  **When to Use:**
  - Complex tasks requiring planning and decomposition
  - Work that needs centralized decision-making
  - Projects where task dependencies matter

  **Strengths:** Clear ownership, structured planning, efficient delegation
  **Weaknesses:** Single point of failure (lead agent), potential bottleneck at lead

  ### Swarm Teams

  A swarm team is **dynamic and self-organizing** — agents claim tasks based on availability and capability.

  ```
  Swarm Team: "Incident Response"
  ├── Agent A (available) → Claims "Investigate logs"
  ├── Agent B (available) → Claims "Check monitoring"
  ├── Agent C (busy) → Working on previous task
  └── Agent D (available) → Claims "Notify stakeholders"
  ```

  **When to Use:**
  - Incident response and firefighting
  - Unpredictable workloads with varying task types
  - Environments where agents come and go dynamically

  **Strengths:** Maximum flexibility, no single point of failure, adaptive to changing conditions
  **Weaknesses:** Harder to predict, potential for duplicate work, requires sophisticated conflict resolution

  ## Coordination Strategies

  ### Round Robin

  Tasks are distributed evenly to agents in rotation, ensuring balanced workload.

  ```
  Tasks: [T1, T2, T3, T4, T5, T6]
  Agent A: T1, T4
  Agent B: T2, T5
  Agent C: T3, T6
  ```

  **Best Paired With:** Functional teams
  **Pros:** Simple, fair distribution, predictable
  **Cons:** Does not account for task complexity or agent capability differences

  ### Parallel

  All agents work simultaneously on the **same input**, producing independent outputs that are then aggregated.

  ```
  Input: "Analyze security of auth module"
  Agent A → Security findings (perspective 1)
  Agent B → Security findings (perspective 2)
  Agent C → Security findings (perspective 3)
  Aggregation → Merged findings with confidence scores
  ```

  **Best Paired With:** Functional teams, swarm teams
  **Pros:** Diverse perspectives, higher confidence through consensus, fast completion
  **Cons:** Higher resource usage (N agents for 1 task), requires aggregation logic

  ### Sequential (Pipeline)

  Each agent's output feeds into the next agent's input, forming a processing pipeline.

  ```
  Agent A (Researcher) → Research findings
       ↓
  Agent B (Developer) → Implementation based on research
       ↓
  Agent C (Tester) → Test results for implementation
       ↓
  Agent D (Reviewer) → Final review and approval
  ```

  **Best Paired With:** Cross-functional teams
  **Pros:** Natural workflow, each stage adds value, clear handoff points
  **Cons:** Slower (serial execution), one slow agent blocks the pipeline

  ### Manager-Led

  A lead agent creates a plan, decomposes tasks, and delegates to team members.

  ```
  Lead Agent: "Build user dashboard"
  ├── Decompose into subtasks
  │   ├── Subtask 1: "Design API endpoints" → Assign to Dev A
  │   ├── Subtask 2: "Build React components" → Assign to Dev B
  │   ├── Subtask 3: "Write integration tests" → Assign to Tester
  │   └── Subtask 4: "Update documentation" → Assign to Writer
  ├── Monitor progress
  ├── Resolve blockers
  └── Merge and deliver
  ```

  **Best Paired With:** Hierarchical teams
  **Pros:** Intelligent task decomposition, dependency management, centralized oversight
  **Cons:** Requires a capable lead agent, lead agent is a bottleneck

  ### Consensus

  All agents contribute to a decision, and the outcome is determined by majority agreement or weighted voting.

  ```
  Question: "Should we refactor the payment module?"
  Agent A: Yes (confidence: 0.9) → Weight: 0.9
  Agent B: Yes (confidence: 0.7) → Weight: 0.7
  Agent C: No  (confidence: 0.6) → Weight: 0.6
  Result: Yes (weighted score: 1.6 vs 0.6)
  ```

  **Best Paired With:** Cross-functional teams, functional teams
  **Pros:** Democratic, reduces individual bias, higher confidence in decisions
  **Cons:** Slower decision-making, requires odd number of agents to avoid ties

  ## TeamChannel Communication

  Teams communicate through `TeamChannel`, a persistent messaging system that supports multiple message types:

  | Channel Type | Purpose | Visibility |
  |-------------|---------|------------|
  | **Broadcast** | Announcements to all team members | All agents |
  | **Topic** | Discussion threads on specific subjects | Subscribed agents |
  | **Escalation** | Issues requiring attention or resolution | Lead + relevant agents |
  | **Task** | Task-specific updates and handoffs | Assigned agents |

  ## Real-World Examples

  ### Development Team

  ```yaml
  Team Type: hierarchical
  Coordination: manager_led
  Members:
    - Lead: Tech Lead (planner profile)
    - Dev A: Backend Developer (developer profile)
    - Dev B: Frontend Developer (developer profile)
    - QA: Test Engineer (tester profile)
    - Reviewer: Code Reviewer (reviewer profile)
  Workflow:
    1. Lead decomposes feature into backend + frontend tasks
    2. Dev A and Dev B work in parallel on their respective parts
    3. QA writes tests while devs implement
    4. Reviewer reviews both implementations
    5. Lead merges and delivers
  ```

  ### Content Production Team

  ```yaml
  Team Type: cross_functional
  Coordination: sequential
  Members:
    - Researcher: Research Agent (researcher profile)
    - Writer: Content Writer (writer profile)
    - Reviewer: Editor Agent (reviewer profile)
  Workflow:
    1. Researcher gathers information and produces brief
    2. Writer creates content based on research brief
    3. Reviewer edits and provides feedback
    4. Writer incorporates feedback (loop until approved)
  ```

  ### Security Audit Team

  ```yaml
  Team Type: functional
  Coordination: parallel
  Members:
    - Auditor A: Security Auditor (custom profile)
    - Auditor B: Security Auditor (custom profile)
    - Auditor C: Security Auditor (custom profile)
  Workflow:
    1. All auditors independently analyze the target
    2. Findings are aggregated and deduplicated
    3. Confidence scores are calculated from agreement
    4. Final report generated from merged findings
  ```

  ## Composition Guardrails

  The `validate_team_composition` validation ensures teams have the required structure:

  - **Minimum members** — Teams must have at least 2 agents
  - **Role coverage** — Cross-functional teams must cover required roles
  - **Lead presence** — Hierarchical teams must have exactly one lead
  - **Profile assignment** — All team members must have an assigned role profile

  ```ruby
  # Validation example
  team = Ai::AgentTeam.new(
    team_type: "hierarchical",
    coordination_strategy: "manager_led",
    members: [dev_a, dev_b]  # Missing lead!
  )
  team.valid?
  # => false
  # => errors: "Hierarchical teams require exactly one lead agent"
  ```

  ## Choosing the Right Pattern

  | Scenario | Team Type | Strategy | Why |
  |----------|-----------|----------|-----|
  | Build a feature | Hierarchical | Manager-led | Complex decomposition, clear ownership |
  | Migrate endpoints | Functional | Round robin | High volume, identical tasks |
  | Security audit | Functional | Parallel | Multiple perspectives, consensus |
  | Content pipeline | Cross-functional | Sequential | Natural flow from research to publication |
  | Incident response | Swarm | N/A (self-organizing) | Unpredictable, time-critical |
  | Architecture decision | Cross-functional | Consensus | Need buy-in from multiple perspectives |

  ## Best Practices

  1. **Match team type to task complexity** — Simple tasks need functional teams; complex tasks need cross-functional or hierarchical
  2. **Keep teams small** — 3-5 agents is optimal; larger teams increase coordination overhead
  3. **Balance roles** — In cross-functional teams, ensure no critical role is missing
  4. **Choose coordination deliberately** — The wrong strategy can make a good team ineffective
  5. **Monitor team health** — Use the composition health endpoint to catch issues early

  ## Related Articles

  - [Agent Teams and Multi-Agent Orchestration](/kb/agent-teams-multi-agent-orchestration)
  - [Role Profiles](/kb/role-profiles)
  - [Review Workflows](/kb/review-workflows)

  ---

  Need help designing your team structure? Contact ai-support@powernode.org
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(slug: "team-orchestration-patterns")
article.assign_attributes(
  title: "Team Orchestration Patterns",
  category: ai_cat,
  author: author,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "Four team types (functional, cross-functional, hierarchical, swarm) and five coordination strategies (round robin, parallel, sequential, manager-led, consensus) with real-world examples.",
  content: team_orchestration_content,
  views_count: 0,
  likes_count: 0,
  published_at: Time.current
)
article.save!

puts "    ✅ Team Orchestration Patterns"

# Article 37: CI/CD Pipeline Integration
cicd_pipeline_content = <<~MARKDOWN
  # CI/CD Pipeline Integration

  Powernode's AI orchestration platform integrates with CI/CD pipelines to automate testing, security scanning, and deployment workflows triggered by agent code changes. The platform supports both GitHub Actions and Gitea Actions runners, with AI-powered analysis layered on top of traditional pipeline tools.

  ## Runner Support

  ### RunnerDispatchService

  The `RunnerDispatchService` abstracts the differences between CI/CD platforms, providing a unified interface for dispatching and monitoring pipeline runs.

  ```ruby
  RunnerDispatchService.dispatch(
    repository: repo,
    workflow: "ci.yml",
    ref: "ai/session-abc/feature-auth",
    inputs: {
      run_tests: true,
      run_security_scan: true,
      run_lint: true
    }
  )
  ```

  ### GitHub Actions Integration

  | Feature | Support |
  |---------|---------|
  | Webhook triggers | Receive push, PR, and status events |
  | Workflow dispatch | Trigger workflows via API |
  | Status checks | Monitor check runs and check suites |
  | Artifact management | Download and analyze build artifacts |
  | Matrix builds | Support for matrix strategy results |

  **Webhook Configuration:**

  ```yaml
  # GitHub webhook events to configure
  Events:
    - push
    - pull_request
    - check_run
    - check_suite
    - workflow_run
    - status

  Payload URL: https://your-powernode.com/api/v1/webhooks/github
  Content Type: application/json
  Secret: (configured in account settings)
  ```

  ### Gitea Actions Integration

  Gitea Actions provides a GitHub Actions-compatible workflow engine for self-hosted Gitea instances.

  | Feature | Support |
  |---------|---------|
  | Webhook triggers | Push, PR, and status events via Gitea webhooks |
  | Workflow dispatch | Trigger via Gitea API |
  | Status checks | Monitor Gitea Actions status |
  | Artifact management | Access Gitea Actions artifacts |

  **Gitea-Specific Considerations:**

  - Gitea API endpoints differ from GitHub (`/api/v1/repos/` prefix)
  - Authentication uses Gitea personal access tokens
  - Some GitHub Actions may need adaptation for Gitea Actions compatibility
  - Runner registration uses Gitea's runner management API

  ## PipelineIntelligenceService

  The `PipelineIntelligenceService` applies AI analysis to pipeline data, providing optimization recommendations and predictive insights.

  ### Analysis Capabilities

  | Analysis | Description |
  |----------|-------------|
  | **Build Time Optimization** | Identifies slow steps and suggests parallelization |
  | **Flaky Test Detection** | Detects intermittently failing tests from historical data |
  | **Failure Pattern Recognition** | Categorizes failures by root cause |
  | **Resource Utilization** | Tracks CPU, memory, and runner usage patterns |
  | **Dependency Impact** | Maps which dependency changes cause the most failures |

  ### Example Analysis Output

  ```json
  {
    "pipeline_id": "01942a3b-...",
    "analysis": {
      "build_time": {
        "current": "12m 34s",
        "optimized_estimate": "8m 15s",
        "recommendations": [
          {
            "type": "parallelization",
            "description": "Tests in spec/models/ and spec/services/ can run in parallel",
            "estimated_saving": "3m 20s"
          },
          {
            "type": "caching",
            "description": "Bundle install takes 2m but dependencies rarely change",
            "estimated_saving": "1m 45s"
          }
        ]
      },
      "flaky_tests": [
        {
          "test": "spec/services/payment_service_spec.rb:42",
          "failure_rate": "15%",
          "pattern": "Timing-dependent — fails under heavy load"
        }
      ]
    }
  }
  ```

  ## Security Scanning Integration

  AI agents can trigger and analyze security scans as part of the CI/CD pipeline.

  ### Automated Security Workflow

  ```
  Agent Code Change
       │
       ▼
  Push to Branch → Trigger CI Pipeline
       │
       ├── Unit Tests
       ├── Integration Tests
       ├── Lint Checks
       └── Security Scans
            ├── SAST (Static Analysis)
            ├── Dependency Audit
            ├── Secret Detection
            └── Container Scanning
                   │
                   ▼
            AI Analysis of Findings
                   │
                   ▼
            Prioritized Report + Auto-Fix Suggestions
  ```

  ### SupplyChainAnalysisService

  The `SupplyChainAnalysisService` specifically focuses on dependency security:

  - **Dependency Tree Analysis** — Maps the full dependency tree and identifies transitive risks
  - **CVE Matching** — Cross-references dependencies against known vulnerability databases
  - **License Compliance** — Checks dependency licenses against your organization's policy
  - **Update Recommendations** — Suggests safe update paths for vulnerable dependencies
  - **Risk Scoring** — Assigns risk scores based on vulnerability severity, exploitability, and dependency depth

  ## Pipeline Templates

  Pre-built pipeline templates for common AI agent workflows:

  ### Code Review Pipeline

  ```yaml
  name: AI Code Review
  on:
    pull_request:
      types: [opened, synchronize]

  jobs:
    ai-review:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - name: Run AI Code Review
          uses: powernode/ai-review-action@v1
          with:
            agent_id: ${{ secrets.REVIEW_AGENT_ID }}
            review_mode: shadow
            categories: [security, correctness, performance]
  ```

  ### Security Audit Pipeline

  ```yaml
  name: AI Security Audit
  on:
    schedule:
      - cron: '0 6 * * 1'  # Weekly on Monday
    workflow_dispatch:

  jobs:
    security-audit:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - name: Dependency Audit
          uses: powernode/supply-chain-action@v1
          with:
            scan_depth: full
            fail_on: critical
        - name: AI Analysis
          uses: powernode/ai-analysis-action@v1
          with:
            agent_id: ${{ secrets.SECURITY_AGENT_ID }}
            analysis_type: security
  ```

  ### Testing Pipeline

  ```yaml
  name: AI-Triggered Tests
  on:
    push:
      branches: ['ai/**']

  jobs:
    test:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - name: Setup
          run: bundle install && npm install
        - name: Backend Tests
          run: bundle exec rspec --format json --out results/rspec.json
        - name: Frontend Tests
          run: CI=true npm test -- --json --outputFile=results/jest.json
        - name: Report to Powernode
          uses: powernode/report-results-action@v1
          with:
            results_path: results/
            trajectory_id: ${{ github.event.head_commit.message }}
  ```

  ## Deployment Automation

  ### Approval Gates

  Deployments triggered by AI agents pass through configurable approval gates:

  | Gate | Condition | Configurable |
  |------|-----------|-------------|
  | **All Tests Pass** | CI pipeline must be green | Required (cannot skip) |
  | **Security Clear** | No critical security findings | Required (cannot skip) |
  | **Review Approved** | Human or agent review approved | Per-team setting |
  | **Budget Check** | Deployment cost within budget | Per-environment |
  | **Schedule Window** | Within allowed deployment window | Per-environment |

  ### Deployment Flow

  ```
  Agent Code Change → CI Pipeline (green) → Security Scan (clear)
       → Review (approved) → Approval Gates (passed)
       → Deploy to Staging → Smoke Tests → Deploy to Production
  ```

  ## Monitoring Pipeline Health

  ### Key Metrics

  | Metric | Description | Alert Threshold |
  |--------|-------------|----------------|
  | **Build Success Rate** | Percentage of successful builds | < 90% |
  | **Mean Build Time** | Average pipeline duration | > 15 minutes |
  | **Flaky Test Rate** | Percentage of intermittent failures | > 5% |
  | **Security Finding Rate** | New security findings per build | > 0 critical |
  | **Deployment Frequency** | Successful deployments per day | Trend-based |
  | **Mean Time to Recovery** | Time from failure to fix | > 1 hour |

  ### Pipeline Dashboard

  The AI Monitoring Dashboard includes a CI/CD section showing:

  - Real-time pipeline status for all active builds
  - Historical build success rates with trend lines
  - Flaky test tracking with automatic detection
  - Security finding trends over time
  - Cost tracking per pipeline and per agent

  ## Best Practices

  1. **Always run CI on agent branches** — Never merge agent code without passing pipeline
  2. **Use security scanning** — AI-generated code needs the same security rigor as human code
  3. **Set up flaky test detection** — Agent code changes can expose latent test issues
  4. **Monitor pipeline costs** — AI agents can trigger many pipeline runs; set budget alerts
  5. **Use pipeline templates** — Standardize workflows across teams for consistency
  6. **Review AI-generated pipeline configs** — Agents should not modify CI configuration without review

  ## Related Articles

  - [Worktree Sandboxes & Git Integration](/kb/worktree-sandboxes-git-integration)
  - [Team Orchestration Patterns](/kb/team-orchestration-patterns)
  - [AI Governance and Policies](/kb/ai-governance-policies)

  ---

  Need help with pipeline integration? Contact ai-support@powernode.org
MARKDOWN

article = KnowledgeBase::Article.find_or_initialize_by(slug: "cicd-pipeline-integration")
article.assign_attributes(
  title: "CI/CD Pipeline Integration",
  category: ai_cat,
  author: author,
  status: "published",
  is_public: true,
  is_featured: false,
  excerpt: "GitHub and Gitea Actions integration with AI-powered pipeline analysis, security scanning, deployment automation, and pre-built workflow templates.",
  content: cicd_pipeline_content,
  views_count: 0,
  likes_count: 0,
  published_at: Time.current
)
article.save!

puts "    ✅ CI/CD Pipeline Integration"

puts "  ✅ AI Orchestration Advanced articles created (10 articles)"
