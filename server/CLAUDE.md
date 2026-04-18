# Server CLAUDE.md

Rails 8 API backend for Powernode.

## Critical Rules

- `# frozen_string_literal: true` pragma in every .rb file
- `Rails.logger` only - no puts/print
- Always use `render_success()`, `render_error()`
- Use `current_user.has_permission?('name')` - NEVER `permissions.include?()`
- Controllers: `Api::V1` namespace, inherit ApplicationController
- Migrations: Index in `t.references` declaration - never separate

## MCP-First Backend Workflow

**Always query MCP before writing backend code.** This is mandatory, not optional.

### Session Start (MANDATORY — every session touching backend code)

Before writing any code:
1. `platform.query_learnings` — check for existing patterns/gotchas in the area being modified
2. `platform.search_knowledge` — find relevant procedures/references for the subsystem
3. `platform.search_knowledge_graph` — understand entity relationships that may be affected

### Before Creating/Modifying

| Task | MCP Query |
|------|-----------|
| Models or migrations | `platform.search_knowledge_graph` — entity relationships, column conventions, FK patterns |
| Services | `platform.discover_skills` + `platform.code_semantic_search` — find existing services by meaning before creating new ones |
| Controllers or API endpoints | `platform.query_learnings` — API anti-patterns, response format gotchas |
| Refactoring shared code | `platform.code_blast_radius` — trace all files affected before renaming/moving symbols |
| Understanding unfamiliar code | `platform.code_file_skeleton` + `platform.code_context_tree` — structure without reading every line |
| MCP tools or actions | `platform.search_knowledge` query: "MCP tool schema" |
| Permission logic | `platform.search_knowledge` query: "permission system" |
| AI agent features | `platform.search_knowledge_graph` query: "AI orchestration" |
| Billing/payments | `platform.search_knowledge` query: "billing" or "payment integration" |
| Agent/team resources | `platform.list_agents` / `platform.list_teams` — inspect existing resources |
| Memory tier operations | `platform.search_memory` + `platform.memory_stats` — understand current memory state |
| RAG / knowledge bases | `platform.list_knowledge_bases` + `platform.search_documents` — check existing document stores |
| Pipeline / CI/CD | `platform.list_pipelines` + `platform.get_pipeline_status` — verify pipeline state |
| Content (KB articles / pages) | `platform.list_kb_articles` / `platform.list_pages` — check existing content |
| Autonomy models/services | `platform.search_knowledge` query: "agent autonomy" |
| Kill switch / escalation | `platform.search_knowledge` query: "kill switch" |

### During Work

- **Before new associations**: `platform.search_knowledge_graph` for existing entity relationships to avoid duplication
- **Before new service patterns**: `platform.query_learnings` category: `pattern` + `platform.code_semantic_search` — check if the pattern exists or has known issues
- **Before adding gems**: `platform.query_learnings` query: "gem name" — check for known integration gotchas
- **Before refactoring**: `platform.code_blast_radius` — understand full impact before changing shared symbols
- **Before adding files**: `platform.code_context_tree` — understand directory structure and naming conventions

### After Work (MANDATORY for non-trivial changes)

| Change type | Contribution |
|-------------|-------------|
| New model/migration pattern | `platform.extract_to_knowledge_graph` — entities, relationships, FK conventions |
| Service bug fix | `platform.create_learning` category: `discovery` — root cause + fix |
| New API pattern | `platform.create_learning` category: `best_practice` |
| Reusable service | `platform.create_skill` — codify the approach |

## Context-Aware Documentation (file fallback)

Query MCP first. Use these files when MCP returns no relevant results:

| When working on | MCP Query | File Fallback |
|-----------------|-----------|---------------|
| `app/services/mcp/*` | `platform.search_knowledge` query: "MCP tool" | [MCP_CONFIGURATION.md](../docs/platform/MCP_CONFIGURATION.md) |
| `app/models/ai/*` | `platform.search_knowledge_graph` query: "AI model" | [AI_ORCHESTRATION_GUIDE.md](../docs/platform/AI_ORCHESTRATION_GUIDE.md) |
| `app/controllers/api/v1/*` | `platform.search_knowledge` query: "API standards" | [API_RESPONSE_STANDARDS.md](../docs/platform/API_RESPONSE_STANDARDS.md) |
| `app/services/billing/*` | `platform.search_knowledge` query: "billing engine" | [BILLING_ENGINE_DEVELOPER_SPECIALIST.md](../docs/backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md) |
| `app/services/payments/*` | `platform.search_knowledge` query: "payment integration" | [PAYMENT_INTEGRATION_SPECIALIST.md](../docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md) |
| `db/migrate/*` | `platform.search_knowledge` query: "UUID migration" | [UUID_SYSTEM_IMPLEMENTATION.md](../docs/platform/UUID_SYSTEM_IMPLEMENTATION.md) |
| Permission models/services | `platform.search_knowledge` query: "permission system" | [PERMISSION_SYSTEM_REFERENCE.md](../docs/platform/PERMISSION_SYSTEM_REFERENCE.md) |

## Backend MCP Tool Reference

All 305 actions grouped by subsystem. Full parameter docs: [MCP_TOOL_CATALOG.md](../docs/platform/MCP_TOOL_CATALOG.md) (regenerable via `rails mcp:generate_tool_catalog`).

| Subsystem | Tools (all `platform.*`) |
|-----------|--------------------------|
| Agents | `create_agent`, `list_agents`, `get_agent`, `update_agent`, `execute_agent` |
| Agent Containers | `deploy_container_agent`, `container_status`, `container_logs`, `container_terminate` |
| Agent Introspection/Memory | `agent_introspect`, `agent_remember`, `agent_recall`, `agent_reflect`, `agent_forget` |
| Teams | `create_team`, `list_teams`, `get_team`, `update_team`, `add_team_member`, `execute_team`, `invite_agent`, `recruit_agent`, `optimize_team` |
| Tasks | `spawn_task`, `check_task_status`, `wait_for_task` |
| Pipelines | `trigger_pipeline`, `list_pipelines`, `get_pipeline_status` |
| Memory | `write_shared_memory`, `read_shared_memory`, `delete_shared_memory`, `search_memory`, `consolidate_memory`, `memory_stats`, `list_pools` |
| RAG | `query_knowledge_base`, `list_knowledge_bases`, `create_knowledge_base`, `add_document`, `process_document`, `search_documents`, `delete_document` |
| KB Articles | `list_kb_articles`, `get_kb_article`, `create_kb_article`, `update_kb_article` |
| Pages | `list_pages`, `get_page`, `create_page`, `update_page` |
| Knowledge | `search_knowledge`, `create_knowledge`, `update_knowledge`, `delete_knowledge`, `promote_knowledge` |
| Learnings | `query_learnings`, `create_learning`, `reinforce_learning`, `learning_metrics` |
| Quality | `verify_learning`, `dispute_learning`, `resolve_contradiction`, `rate_knowledge`, `knowledge_health` |
| Skills | `list_skills`, `get_skill`, `discover_skills`, `get_skill_context`, `skill_health`, `skill_metrics`, `create_skill`, `update_skill`, `delete_skill`, `toggle_skill` |
| Skill Evolution | `auto_evolve_skill`, `compose_skills`, `mutate_skill` |
| Challenges | `generate_self_challenge`, `get_challenge_result`, `list_challenges` |
| Graph | `search_knowledge_graph`, `reason_knowledge_graph`, `get_graph_node`, `list_graph_nodes`, `get_graph_neighbors`, `graph_statistics`, `get_subgraph`, `extract_to_knowledge_graph` |
| Codebase Discovery | `code_context_tree`, `code_file_skeleton`, `code_semantic_search`, `code_identifier_search`, `code_semantic_navigate`, `code_feature_hub` |
| Codebase Analysis | `code_blast_radius`, `code_static_analysis`, `code_index_status`, `code_analyze_section`, `code_dead_code`, `code_find_duplicates` |
| Codebase Memory | `code_upsert_node`, `code_create_relation`, `code_search_graph`, `code_prune_stale`, `code_bulk_index` |
| Autonomy (Safety) | `emergency_halt`, `emergency_resume`, `kill_switch_status` |
| Autonomy (Goals) | `create_agent_goal`, `list_agent_goals`, `update_agent_goal`, `decompose_goal` |
| Autonomy (Proposals/Escalations) | `create_proposal`, `propose_feature`, `escalate`, `report_issue`, `request_code_change`, `request_feedback` |
| Autonomy (Communication) | `send_proactive_notification`, `discover_claude_sessions` |
| Plans | `validate_plan`, `approve_plan` |
| Missions | `get_mission_status` |
| Ralph Loops | `list_ralph_loops`, `get_ralph_loop`, `pause_ralph_loop`, `resume_ralph_loop`, `delete_ralph_loop`, `get_ralph_loop_statistics` |
| Workspace | `send_message`, `list_messages`, `list_conversations`, `get_conversation_messages`, `send_concierge_message`, `confirm_concierge_action`, `create_workspace`, `list_workspaces` |
| Monitoring | `get_activity_feed`, `recent_events`, `get_notifications`, `mark_all_notifications_read`, `dismiss_notification`, `dismiss_all_notifications`, `integration_health`, `get_system_health`, `active_sessions` |
| Governance | `governance_dashboard`, `governance_scan`, `get_governance_report`, `list_governance_reports`, `resolve_governance_report` |
| Coordination (Signals/Pressure) | `emit_signal`, `perceive_signals`, `reinforce_signal`, `measure_pressure`, `perceive_pressure`, `detect_collusion` |
| DevOps | `create_gitea_repository`, `update_gitea_repository`, `dispatch_to_runner`, `get_api_reference` |
| Docker Hosts | `docker_list_hosts`, `docker_get_host`, `docker_sync_host`, `docker_test_host` |
| Docker Containers | `docker_list_containers`, `docker_get_container`, `docker_create_container`, `docker_start_container`, `docker_stop_container`, `docker_restart_container`, `docker_remove_container`, `docker_container_logs`, `docker_container_stats`, `docker_container_exec` |
| Docker Images | `docker_list_images`, `docker_pull_image`, `docker_remove_image`, `docker_tag_image` |
| Docker Services | `docker_list_services`, `docker_get_service`, `docker_create_service`, `docker_update_service`, `docker_scale_service`, `docker_rollback_service`, `docker_remove_service`, `docker_service_logs`, `docker_service_tasks` |
| Docker Stacks | `docker_list_stacks`, `docker_get_stack`, `docker_deploy_stack`, `docker_remove_stack`, `docker_adopt_stack` |
| Docker Clusters | `docker_list_clusters`, `docker_get_cluster`, `docker_cluster_health`, `docker_list_nodes`, `docker_node_promote`, `docker_node_demote`, `docker_node_drain`, `docker_node_activate`, `docker_list_secrets`, `docker_create_secret`, `docker_remove_secret`, `docker_list_configs`, `docker_create_config`, `docker_remove_config` |
| Docker Networks/Volumes | `docker_list_networks`, `docker_create_network`, `docker_remove_network`, `docker_list_volumes`, `docker_create_volume`, `docker_remove_volume` |
| Image Generation | `generate_image`, `list_generated_images` |
| Trading (Strategies) | `trading_list_strategies`, `trading_get_strategy`, `trading_create_strategy`, `trading_update_strategy`, `trading_pause_strategy`, `trading_activate_strategy`, `trading_demote_strategy`, `trading_decommission_strategy`, `trading_decline_strategy`, `trading_advance_phase`, `trading_recover_strategy`, `trading_strategy_performance`, `trading_strategy_versions`, `trading_get_strategy_params`, `trading_update_strategy_params`, `trading_seed_strategy_defaults`, `trading_seed_profit_formula` |
| Trading (Portfolios) | `trading_create_portfolio`, `trading_get_portfolio`, `trading_list_portfolios`, `trading_update_portfolio`, `trading_portfolio_summary`, `trading_portfolio_performance`, `trading_portfolio_allocations`, `trading_compounding_summary` |
| Trading (Positions/Orders) | `trading_list_positions`, `trading_open_positions`, `trading_closed_positions`, `trading_get_position`, `trading_close_position`, `trading_list_orders`, `trading_cancel_order`, `trading_list_trades` |
| Trading (Simulations/Backtests) | `trading_create_simulation`, `trading_get_simulation`, `trading_list_simulations`, `trading_run_simulation`, `trading_pause_simulation`, `trading_simulation_report`, `trading_run_backtest`, `trading_parameter_sweep`, `trading_list_sweep_proposals`, `trading_list_sweep_rules` |
| Trading (Training Sessions) | `trading_create_training_session`, `trading_get_training_session`, `trading_list_training_sessions`, `trading_cancel_training_session`, `trading_complete_training_session`, `trading_delete_training_session`, `trading_resume_training_session`, `trading_retry_training_session`, `trading_training_session_report` |
| Trading (Venues/Feeds) | `trading_list_venues`, `trading_get_venue`, `trading_test_venue_connection`, `trading_discover_venue_series`, `trading_list_price_feeds`, `trading_import_historical_data` |
| Trading (Subscriptions) | `trading_subscribe`, `trading_unsubscribe`, `trading_pause_subscription`, `trading_resume_subscription`, `trading_subscription_performance`, `trading_list_subscriptions`, `trading_follow_publisher`, `trading_unfollow_publisher`, `trading_list_publisher_follows`, `trading_publish_strategy`, `trading_unpublish_strategy`, `trading_get_published_strategy`, `trading_list_published_strategies` |
| Trading (Evolution) | `trading_trigger_evolution`, `trading_evolution_leaderboard`, `trading_get_evolution_epoch`, `trading_list_evolution_epochs` |
| Trading (Market) | `trading_market_arms`, `trading_market_discovery`, `trading_refresh_market_discovery`, `trading_market_regime` |
| Trading (Risk/Audit) | `trading_get_risk_profile`, `trading_update_risk_profile`, `trading_risk_events`, `trading_reset_circuit_breaker`, `trading_list_audit_logs`, `trading_lifecycle_summary`, `trading_fee_summary`, `trading_list_performance_fees`, `trading_list_signals`, `trading_list_forwarded_signals`, `trading_list_wallets` |

## Test Execution

```bash
bundle exec rspec spec/                          # Run full suite
bundle exec rspec spec/path_spec.rb              # Run single file
bundle exec rspec spec/path_spec.rb:42           # Run single example
```

- Uses `DatabaseCleaner` with `:deletion` strategy (avoids `TRUNCATE` deadlocks)
- Transactional fixtures enabled — each test rolls back automatically
- Frontend tests and TypeScript checks are always safe to run concurrently

## Worker Architecture

- This server does **NOT** run Sidekiq — the worker is a separate service (`worker/`)
- **NEVER** create job classes in `server/app/jobs/`
- The worker communicates with this server via HTTP API only
- Background work is dispatched to the worker, not run in-process

## Key Specialists

Use `platform.discover_skills` with your task description first. File fallbacks:

- [Rails Architect](../docs/backend/RAILS_ARCHITECT_SPECIALIST.md)
- [API Developer](../docs/backend/API_DEVELOPER_SPECIALIST.md)
- [Data Modeler](../docs/backend/DATA_MODELER_SPECIALIST.md)
- [Background Job Engineer](../docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md)
