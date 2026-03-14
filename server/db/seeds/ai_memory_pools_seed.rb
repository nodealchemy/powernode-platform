# frozen_string_literal: true

# AI Memory Pools Seed
# Seeds the default shared memory pool with Claude Code conventions and platform knowledge.
# This ensures a fresh db:seed populates the memory that Claude Code relies on via MCP.
#
# Idempotent — merges into existing data without clobbering runtime additions.

Rails.logger.info "[MemoryPoolSeed] Starting memory pool seeding..."

admin_account = Account.find_by(name: "Powernode Admin")

unless admin_account
  Rails.logger.warn "[MemoryPoolSeed] Admin account not found — skipping"
  return
end

# Find the MCP client agent (Claude Code) to set as owner
claude_code_agent = Ai::Agent.find_by(account: admin_account, agent_type: "mcp_client")

# ---------------------------------------------------------------------------
# Default Shared Memory Pool
# ---------------------------------------------------------------------------
pool = Ai::MemoryPool.find_or_initialize_by(pool_id: "default")
pool.assign_attributes(
  account: admin_account,
  name: "Default Memory Pool",
  pool_type: "shared",
  scope: "persistent",
  owner_agent_id: claude_code_agent&.id,
  access_control: { "public" => true },
  persist_across_executions: true,
  retention_policy: { "max_entries" => 1000, "cleanup_strategy" => "lru" },
  metadata: { "source" => "seed", "version" => "1.0" }
)

# Seed data — merged so runtime additions are preserved
seed_data = {
  "claude_code" => {
    "project_structure" => {
      "summary" => "Powernode platform project structure",
      "backend" => "Rails 8 API in server/",
      "frontend" => "React TypeScript in frontend/",
      "worker" => "Sidekiq standalone in worker/",
      "business" => "Git submodule at extensions/business/",
      "database" => "PostgreSQL with UUIDv7 primary keys, JWT auth",
      "ai_paths" => {
        "models" => "server/app/models/ai/",
        "services" => "server/app/services/ai/",
        "frontend" => "frontend/src/features/ai/"
      }
    },
    "ai_providers" => {
      "summary" => "AI provider configuration and agent model assignments",
      "ollama_remote" => "NEVER install Ollama locally - OLLAMA_API_ENDPOINT points to remote server",
      "agent_model_config" => "Lives in mcp_metadata['model_config'] - NO model column on ai_agents",
      "ollama_models" => {
        "general" => "qwen2.5:14b",
        "operational_routing" => "llama3.1:8b",
        "code_gen_tests_docs" => "qwen2.5-coder:14b"
      },
      "provider_priority" => "Ollama=1, Anthropic=1, OpenAI=2, Grok=3"
    },
    "key_patterns" => {
      "summary" => "Core coding patterns and conventions",
      "backend" => {
        "responses" => "render_success()/render_error() mandatory",
        "pragma" => "# frozen_string_literal: true required",
        "logging" => "Rails.logger only, no puts/print"
      },
      "frontend" => {
        "colors" => "Theme classes only: bg-theme-*, text-theme-*",
        "access_control" => "Permission-based only, NEVER roles",
        "logging" => "import { logger } from '@/shared/utils/logger', no console.log"
      },
      "migrations" => "Never create separate indexes for t.references - use inline index: option",
      "routes" => "Place named routes before /:id to avoid matching conflicts",
      "git" => {
        "no_attribution" => "No Claude attribution in commits",
        "no_v_prefix" => "Tags use 0.2.0 not v0.2.0",
        "submodule_push_order" => "ALWAYS push submodules before parent repo"
      }
    },
    "workspace_communication" => {
      "summary" => "MANDATORY workspace chat communication rules",
      "rules" => [
        "When receiving workspace message, ALWAYS reply via platform.send_message",
        "Send initial message stating what you're about to do",
        "Send conclusion message when work is finished",
        "Never silently handle workspace requests - always acknowledge and report back",
        "Questions go to workspace, NOT the local CLI user"
      ]
    },
    "mcp_protocol" => {
      "summary" => "MCP session protocol, workflow, and reinforcement rules",
      "session_start" => "Run platform.knowledge_health + platform.learning_metrics to establish baselines",
      "token_files" => {
        "oauth" => "/tmp/powernode_mcp_token.txt",
        "session" => "/tmp/powernode_sse_session.txt"
      },
      "workflow" => "ALWAYS query platform.* MCP tools before reading files - generated docs are FALLBACK only",
      "reinforcement" => {
        "when_using_learning" => "Call platform.reinforce_learning with ID immediately",
        "when_using_knowledge" => "Call platform.rate_knowledge with entry_id (4-5 useful, 1-2 outdated)",
        "when_conflicting" => "Call platform.resolve_contradiction immediately"
      },
      "contribution_triggers" => {
        "bug_fix" => "discovery",
        "dead_code" => "discovery",
        "new_pattern" => "pattern",
        "anti_pattern" => "failure_mode",
        "best_practice" => "best_practice"
      }
    },
    "auth_gotchas" => {
      "summary" => "JWT and authentication gotchas",
      "sub_claim_required" => "handle_user_token does User.find(payload[:sub]) - using user_id causes error",
      "canonical_token" => "payload: sub, account_id, email, type: 'access', version: 2",
      "proxy_masks_errors" => "ProxySecurityValidator catches ALL StandardError, returns generic 500",
      "two_auth_systems" => "JWT (main API) vs Doorkeeper OAuth 2.1 (MCP endpoint)"
    },
    "mcp_tool_gotchas" => {
      "summary" => "MCP tool parameter gotchas from E2E smoke test",
      "auth" => "Doorkeeper OAuth 2.1 tokens (NOT JWT). Endpoint: POST /api/v1/mcp/message",
      "param_fixes" => {
        "rate_update_promote_knowledge" => "entry_id NOT knowledge_id",
        "get_agent" => "agent_id NOT id",
        "get_skill_context" => "input_text NOT input",
        "create_kb_article" => "category_slug NOT category",
        "delete_document" => "requires BOTH document_id AND knowledge_base_id",
        "create_learning" => "response has NO created ID - must query afterward",
        "extract_to_knowledge_graph" => "requires active LLM - silent 0 entities if unavailable"
      }
    },
    "test_strategy" => {
      "summary" => "Test database strategy and patterns",
      "database_cleaner" => "deletion strategy (not truncation) - avoids deadlocks",
      "run" => "bundle exec rspec spec/ (single process only)",
      "e2e" => {
        "page_objects" => "e2e/pages/ai/, specs in e2e/ai/",
        "selectors" => "data-testid > class*=pattern > getByRole"
      }
    },
    "systemd_services" => {
      "summary" => "Systemd service management",
      "units" => %w[powernode-backend@ powernode-worker@ powernode-worker-web@ powernode-frontend@ powernode.target],
      "manage" => "sudo scripts/systemd/powernode-installer.sh install|status|add-instance",
      "ports" => { "backend" => 3000, "frontend" => 3001, "worker_web" => 4567 },
      "worker_redis" => "redis://localhost:6379/1 (DB 1 not 0)"
    },
    "pgvector" => {
      "summary" => "pgvector + neighbor gem config and gotchas",
      "gem" => "neighbor 0.6.0 (NOT raw pgvector gem)",
      "indexes" => "HNSW not IVFFlat (works on empty tables)",
      "cosine" => "nearest_neighbors(:embedding, vector, distance: 'cosine')",
      "gotcha_virtual" => "neighbor_distance is virtual - cannot use in WHERE clause",
      "shared_knowledge" => "Uses provenance column not metadata"
    },
    "compound_learning" => {
      "summary" => "Compound learning system details",
      "maintenance_cascade" => "decay(3:45) > consolidation(4:00) > skills(4:15) > knowledge(4:30) > KG(4:45) > docs(5:30)",
      "semantic_threshold" => "SharedKnowledgeService SIMILARITY_THRESHOLD = 0.5",
      "promotion_gate" => "access_count >= 2 required for cross-team promotion",
      "constructors" => "Both CompoundLearningService and SharedKnowledgeService use keyword arg account:"
    },
    "gitea_gotchas" => {
      "summary" => "Gitea API gotchas",
      "slashed_branches" => "Contents API fails for refs with slashes - resolve_ref fixes via get_branch",
      "compare_commits" => "Returns empty for slashed branches (Gitea bug) - use list_commits"
    },
    "mission_pipeline" => {
      "summary" => "Mission pipeline E2E verified flow",
      "stages" => "analyzing > feature_approval > planning > prd_approval > executing > testing > reviewing > code_approval > deploying > previewing > merging > completed",
      "gotchas" => {
        "worker_race" => "Stop worker for manual testing to avoid duplicate RalphLoops",
        "agent_resolution" => "Set default_agent explicitly on RalphLoop",
        "branch_timing" => "Branch must be created BEFORE PrdGenerationService.generate!",
        "ralph_task_columns" => "No name column - use task_key and description"
      }
    }
  }
}

# Deep merge seed data into existing pool data (preserves runtime additions)
pool.data = (pool.data || {}).deep_merge(seed_data)
pool.save!

key_count = seed_data["claude_code"].keys.size
Rails.logger.info "[MemoryPoolSeed] Seeded default pool with #{key_count} claude_code memory keys"

# ---------------------------------------------------------------------------
# Platform Conventions Pool (team_shared)
# ---------------------------------------------------------------------------
dev_team = Ai::AgentTeam.find_by(account: admin_account, name: "Powernode Development Team")

if dev_team
  conventions_pool = Ai::MemoryPool.find_or_initialize_by(
    account: admin_account,
    pool_type: "team_shared",
    team_id: dev_team.id
  )

  # Only set attributes if new record (don't overwrite existing team pool)
  if conventions_pool.new_record?
    conventions_pool.assign_attributes(
      name: "Powernode Platform Conventions",
      scope: "persistent",
      owner_agent_id: claude_code_agent&.id,
      access_control: { "public" => false, "agents" => dev_team.memberships.pluck(:ai_agent_id).compact },
      persist_across_executions: true,
      data: {},
      metadata: { "source" => "seed", "team" => dev_team.name }
    )
    conventions_pool.save!
    Rails.logger.info "[MemoryPoolSeed] Created team conventions pool for #{dev_team.name}"
  else
    Rails.logger.info "[MemoryPoolSeed] Team conventions pool already exists — skipping"
  end
else
  Rails.logger.info "[MemoryPoolSeed] Dev team not found — skipping conventions pool"
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
pool_count = Ai::MemoryPool.where(account: admin_account).count

Rails.logger.info "[MemoryPoolSeed] Complete!"
puts "   Memory pools: #{pool_count}"
puts "   Default pool keys: #{pool.statistics[:total_keys]}"
puts "   Memory pool seeding completed!"
