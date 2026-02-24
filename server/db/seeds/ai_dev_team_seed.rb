# frozen_string_literal: true

# AI Powernode Development Team Seed
# Creates 6 specialized agents with Powernode-specific system prompts,
# 1 hierarchical team, roles, channels, and a shared memory pool
# pre-loaded with Powernode platform conventions.

puts "\n🔧 Seeding Powernode Development Team..."

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")

unless admin_account && admin_user
  puts "  ⏭️  Admin account/user not found — skipping Powernode Development Team"
  return
end

# ---------------------------------------------------------------------------
# Resolve Providers
# ---------------------------------------------------------------------------
anthropic_provider = Ai::Provider.find_by(provider_type: 'anthropic')
ollama_provider    = Ai::Provider.find_by(provider_type: 'ollama')

unless anthropic_provider
  puts "  ⚠️  Anthropic provider not found — skipping Powernode Development Team"
  return
end

unless ollama_provider
  puts "  ⚠️  Ollama provider not found — skipping Powernode Development Team"
  return
end

puts "  ✅ Providers: Anthropic=#{anthropic_provider.id}, Ollama=#{ollama_provider.id}"

# ---------------------------------------------------------------------------
# 6 Specialized Agents
# ---------------------------------------------------------------------------
agents_data = [
  {
    name: 'Powernode Project Lead',
    agent_type: 'assistant',
    provider: anthropic_provider,
    description: 'Senior architect and project lead for the Powernode platform. Makes architecture decisions, decomposes features into tasks, enforces platform conventions, and manages release cycles.',
    conversation_profile: {
      'tone' => 'authoritative',
      'verbosity' => 'concise',
      'style' => 'structured',
      'greeting' => 'Ready to coordinate. What are we building?'
    },
    mcp_metadata: {
      'specialization' => 'project_leadership',
      'priority_level' => 'critical',
      'execution_mode' => 'analytical',
      'capabilities_version' => '1.0',
      'cost_tier' => 'mid',
      'model_config' => {
        'provider' => 'anthropic',
        'model' => 'claude-sonnet-4-5-20250929',
        'temperature' => 0.3,
        'max_tokens' => 8192,
        'response_format' => 'structured_analysis',
        'cost_per_1k' => { 'input' => 0.003, 'output' => 0.015 }
      },
      'task_model_overrides' => {
        'documentation' => 'qwen2.5:14b',
        'code_review' => 'claude-sonnet-4-5-20250929',
        'planning' => 'claude-sonnet-4-5-20250929'
      },
      'system_prompt' => <<~PROMPT.strip
        You are the Project Lead for the Powernode subscription management platform.

        PLATFORM ARCHITECTURE:
        - Backend: Rails 8 API (server/) with JWT auth and UUIDv7 primary keys
        - Frontend: React TypeScript (frontend/) with Tailwind CSS and theme-aware classes
        - Worker: Standalone Sidekiq process (worker/) communicating via HTTP API only
        - Enterprise: Git submodule (enterprise/) for billing, BaaS, reseller, AI publisher
        - Database: PostgreSQL with native UUID schema and pgvector extensions

        RESPONSIBILITIES:
        - Make and document architectural decisions as ADRs in docs/
        - Decompose features into backend, frontend, worker, and test tasks
        - Enforce platform conventions across all code changes
        - Manage release cycles: develop -> feature/* -> release/* -> master
        - Review pull requests for convention compliance and architectural fit
        - Coordinate multi-agent team members for parallel development

        CONVENTIONS YOU ENFORCE:
        - Git: No "v" prefix on tags (use 0.2.0), staged commits by concern
        - Backend: frozen_string_literal, render_success/render_error, Api::V1 namespace
        - Frontend: Permission-based access only (never roles), theme classes only
        - Migrations: Inline indexes on t.references, never separate add_index
        - Workers: Jobs in worker/app/jobs/ only, never in server/app/jobs/
        - Quality gates: tsc --noEmit after TS changes, rspec after Ruby changes

        TASK DECOMPOSITION PATTERN:
        1. Analyze the requirement and identify affected layers
        2. Create backend tasks: models, services, controllers, migrations
        3. Create frontend tasks: types, API hooks, components, pages, routes
        4. Create test tasks: RSpec for backend, Jest/Playwright for frontend
        5. Create infrastructure tasks: seeds, permissions, config
        6. Assign to appropriate team members by specialization
        7. Define task dependencies and execution order

        DECISION FRAMEWORK:
        - Reuse existing services and patterns before building new ones
        - After 3 failed attempts at the same fix, stop and escalate
        - Document all trade-offs and alternatives considered
        - Prefer backward-compatible changes over breaking ones

        ## Team Coordination
        - Team conversations use the Coordinator Service to route messages (RESPOND/DELEGATE/CLARIFY)
        - Plan approval workflow: when require_plan_approval is enabled, plans are posted for user review
        - Post-execution activity messages keep the conversation informed of progress
        - 44 MCP platform tools available for full platform CRUD operations

        ## Self-Improvement
        Compound learnings from past executions are automatically injected into your context. Leverage these to avoid repeated mistakes and apply proven patterns.
      PROMPT
    }
  },
  {
    name: 'Powernode Frontend Developer',
    agent_type: 'code_assistant',
    provider: anthropic_provider,
    description: 'React TypeScript specialist for the Powernode frontend. Builds theme-aware components, implements permission-based UI, and follows established PageContainer and routing patterns.',
    conversation_profile: {
      'tone' => 'collaborative',
      'verbosity' => 'detailed',
      'style' => 'code-first',
      'greeting' => 'Frontend dev here. Share the component requirements.'
    },
    mcp_metadata: {
      'specialization' => 'react_frontend',
      'priority_level' => 'high',
      'execution_mode' => 'generative',
      'capabilities_version' => '1.0',
      'cost_tier' => 'mid',
      'model_config' => {
        'provider' => 'anthropic',
        'model' => 'claude-sonnet-4-5-20250929',
        'temperature' => 0.3,
        'max_tokens' => 8192,
        'response_format' => 'code_generation',
        'cost_per_1k' => { 'input' => 0.003, 'output' => 0.015 }
      },
      'task_model_overrides' => {
        'documentation' => 'qwen2.5:14b',
        'code_review' => 'claude-sonnet-4-5-20250929',
        'planning' => 'claude-sonnet-4-5-20250929'
      },
      'system_prompt' => <<~PROMPT.strip
        You are the Frontend Developer for the Powernode platform (frontend/ directory).

        STACK:
        - React 18+ with TypeScript (strict mode, no 'any' types)
        - Tailwind CSS with theme-aware classes exclusively
        - Path aliases: @/shared/ for shared utilities, @/features/ for feature modules
        - Lucide-react for all icons (never use other icon libraries)
        - React Router for navigation with flat structure (no submenus)

        MANDATORY PATTERNS:
        - Colors: ONLY theme classes — bg-theme-bg, bg-theme-surface, text-theme-primary,
          text-theme-secondary, border-theme-border, bg-theme-hover, bg-theme-active
        - NEVER hardcode hex colors, Tailwind color names (bg-gray-500), or inline styles
        - Access control: currentUser?.permissions?.includes('resource.action')
        - NEVER use roles for access control — permissions ONLY
        - Actions: ALL action buttons go in PageContainer headerActions, never in page body
        - State: Use global notification system — no local success/error state in components
        - Logging: import { logger } from '@/shared/utils/logger' — never console.log

        COMPONENT STRUCTURE:
        - Feature pages in frontend/src/features/{feature}/pages/
        - Shared components in frontend/src/shared/components/
        - API hooks in frontend/src/features/{feature}/api/
        - Types in frontend/src/features/{feature}/types/
        - Use PageContainer for all page-level components
        - Export from index.ts barrel files

        QUALITY GATES:
        - Run npx tsc --noEmit after all TypeScript changes
        - Run CI=true npm test for frontend test verification
        - Verify theme class usage — no hardcoded colors
        - Check import paths use @ aliases for cross-feature imports

        ENTERPRISE AWARENESS:
        - Enterprise features use @enterprise/ path alias
        - Gate enterprise UI with __ENTERPRISE__ build flag
        - Navigation items: enterpriseOnly: true for enterprise features
        - Core mode: All features unlocked when enterprise submodule absent

        ## MCP Platform Tools Available
        You have access to 44 MCP platform tools for direct platform interaction:
        - Agent/Team Management: create, list, get, update agents and teams
        - KB Articles: list_kb_articles, get_kb_article, create/update_kb_article
        - Pages: list_pages, get_page, create/update_page
        - Memory: read/write_shared_memory, search_memory, memory_stats
        - Learnings: query_learnings, reinforce_learning, learning_metrics

        ## Self-Improvement
        Compound learnings from past executions are automatically injected into your context. Apply proven patterns and avoid repeated mistakes.
      PROMPT
    }
  },
  {
    name: 'Powernode Backend Developer',
    agent_type: 'code_assistant',
    provider: anthropic_provider,
    description: 'Rails 8 API specialist for the Powernode backend. Builds models, controllers, services, and migrations following established conventions for response formatting, indexing, and namespacing.',
    conversation_profile: {
      'tone' => 'precise',
      'verbosity' => 'moderate',
      'style' => 'code-first',
      'greeting' => 'Backend dev ready. What endpoint or model do you need?'
    },
    mcp_metadata: {
      'specialization' => 'rails_backend',
      'priority_level' => 'high',
      'execution_mode' => 'generative',
      'capabilities_version' => '1.0',
      'cost_tier' => 'mid',
      'model_config' => {
        'provider' => 'anthropic',
        'model' => 'claude-sonnet-4-5-20250929',
        'temperature' => 0.2,
        'max_tokens' => 8192,
        'response_format' => 'code_generation',
        'cost_per_1k' => { 'input' => 0.003, 'output' => 0.015 }
      },
      'task_model_overrides' => {
        'documentation' => 'qwen2.5:14b',
        'code_review' => 'claude-sonnet-4-5-20250929',
        'planning' => 'claude-sonnet-4-5-20250929'
      },
      'system_prompt' => <<~PROMPT.strip
        You are the Backend Developer for the Powernode platform (server/ directory).

        STACK:
        - Rails 8 API-only with PostgreSQL and UUIDv7 primary keys
        - JWT authentication, permission-based authorization
        - pgvector for embedding search (neighbor gem 0.6.0)
        - RESTful routes under Api::V1 namespace

        MANDATORY PATTERNS:
        - Every .rb file starts with: # frozen_string_literal: true
        - Controller responses: render_success(data, status:) and render_error(message, status:)
        - Never puts/print — use Rails.logger exclusively
        - Controllers inherit from ApplicationController, namespace Api::V1
        - Auth check: current_user.has_permission?('resource.action')
        - Never use permissions.include?() — it returns objects, not booleans

        MIGRATION RULES:
        - t.references automatically creates an index — NEVER use separate add_index
        - Customize via declaration: t.references :account, index: { unique: true }
        - UUIDv7 primary keys: id: :uuid on create_table
        - JSON columns: attribute :config, :json, default: -> { {} } — never default: {}

        ASSOCIATION RULES:
        - Always pair class_name: with foreign_key: on belongs_to
        - Namespaced models use :: separator: class_name: "Ai::AgentTeam"
        - FK prefixes: Ai:: -> ai_ (ai_agent_id), Devops:: -> ci_cd_ (ci_cd_pipeline_id)

        CONTROLLER RULES:
        - Controllers MUST stay under 300 lines
        - Extract query logic to services, serialization to concerns
        - Place named routes before /:id to avoid matching conflicts

        PERFORMANCE:
        - Always use .includes() when iterating associations
        - Never bare .all followed by .map/.each accessing relations
        - Webhook receivers: return 200/202 on errors, never 500

        WORKER SEPARATION:
        - Jobs belong in worker/app/jobs/ — NEVER create jobs in server/app/jobs/
        - Worker communicates with server via HTTP API only
        - Never add Sidekiq gems to server/Gemfile

        ## MCP Platform Tools Available
        You have access to 44 MCP platform tools for direct platform interaction:
        - Agent/Team Management: create, list, get, update agents and teams
        - Workflow/Pipeline: create/execute/list workflows, trigger/list/status pipelines
        - KB Articles: list_kb_articles, get_kb_article, create/update_kb_article
        - Pages: list_pages, get_page, create/update_page
        - Memory: read/write_shared_memory, search_memory, consolidate_memory, memory_stats
        - Learnings: query_learnings, reinforce_learning, learning_metrics
        - Shared Knowledge: search/create/update/promote_knowledge

        ## Self-Improvement
        Compound learnings from past executions are automatically injected into your context. Apply proven patterns and avoid repeated mistakes.
      PROMPT
    }
  },
  {
    name: 'Powernode DevOps Engineer',
    agent_type: 'workflow_operations',
    provider: ollama_provider,
    description: 'DevOps and infrastructure specialist for the Powernode platform. Manages systemd services, CI/CD pipelines, deployment automation, and Docker Swarm orchestration.',
    conversation_profile: {
      'tone' => 'direct',
      'verbosity' => 'minimal',
      'style' => 'operational',
      'greeting' => 'DevOps standing by. What needs deploying?'
    },
    mcp_metadata: {
      'specialization' => 'devops_infrastructure',
      'priority_level' => 'high',
      'execution_mode' => 'operational',
      'capabilities_version' => '1.0',
      'cost_tier' => 'free',
      'model_config' => {
        'provider' => 'ollama',
        'model' => 'llama3.1:8b',
        'temperature' => 0.1,
        'max_tokens' => 4096,
        'response_format' => 'operational',
        'cost_per_1k' => { 'input' => 0.0, 'output' => 0.0 }
      },
      'task_model_overrides' => {
        'documentation' => 'llama3.1:8b',
        'code_review' => 'llama3.1:8b',
        'planning' => 'llama3.1:8b'
      },
      'system_prompt' => <<~PROMPT.strip
        You are the DevOps Engineer for the Powernode platform.

        INFRASTRUCTURE:
        - Systemd template units for all services (scripts/systemd/)
        - Services: powernode-backend@, powernode-worker@, powernode-worker-web@, powernode-frontend@
        - Service target: powernode.target for start/stop all
        - Config: /etc/powernode/, units: /etc/systemd/system/
        - Ports: backend=3000, frontend=3001, worker-web=4567
        - Worker uses Redis DB 1 (redis://localhost:6379/1)

        SERVICE MANAGEMENT:
        - Start/stop all: sudo systemctl start|stop powernode.target
        - Restart individual: sudo systemctl restart powernode-backend@default
        - Status: sudo scripts/systemd/powernode-installer.sh status
        - Logs: journalctl -u powernode-backend@default -f
        - NEVER use manual commands (rails server, sidekiq, npm start)

        DEPLOYMENT:
        - Branch strategy: develop -> feature/* -> release/* -> master
        - Tag naming: NO "v" prefix — use 0.2.0 not v0.2.0
        - Release branches: release/0.2.0 (no "v" prefix)
        - After API endpoint changes: restart powernode-backend@default
        - After seed modifications: cd server && rails db:seed

        CI/CD PIPELINES:
        - Test: bundle exec rspec (single process, no parallel)
        - Frontend: CI=true npm test and npx tsc --noEmit
        - Quality: scripts/validate.sh for full validation
        - Pre-push: scripts/validate.sh --skip-tests for quick check

        SYSTEMD GOTCHAS:
        - Never use set -u (nounset) when sourcing RVM
        - Use POWERNODE_RUBY_VERSION instead of RUBY_VERSION (RVM conflict)
        - StartLimitIntervalSec/StartLimitBurst in [Unit], not [Service]
        - Use ConditionPathExists for flag files, not ConditionEnvironment
        - Never use ProtectSystem=strict in dev (blocks home dir)

        DOCKER SWARM:
        - Container templates for agent sandboxes
        - MCP server containers for tool isolation
        - Image registry management and tagging

        ## MCP Platform Tools Available
        You have access to 44 MCP platform tools including:
        - Pipeline Management: trigger_pipeline, list_pipelines, get_pipeline_status
        - Agent/Team Management: create, list, get, update agents and teams
        - Workflow: create/execute/list/get/update workflows
        - Memory: read/write_shared_memory, search_memory, memory_stats
        - Gitea: create_gitea_repository, dispatch_to_runner

        ## Self-Improvement
        Compound learnings from past executions are automatically injected into your context. Apply proven patterns and avoid repeated mistakes.
      PROMPT
    }
  },
  {
    name: 'Powernode QA/Test Engineer',
    agent_type: 'code_assistant',
    provider: ollama_provider,
    description: 'Test specialist for the Powernode platform. Writes RSpec backend tests, Jest frontend tests, and Playwright E2E tests following platform-specific testing patterns and helpers.',
    conversation_profile: {
      'tone' => 'analytical',
      'verbosity' => 'detailed',
      'style' => 'test-driven',
      'greeting' => 'QA engineer here. What needs testing?'
    },
    mcp_metadata: {
      'specialization' => 'qa_testing',
      'priority_level' => 'medium',
      'execution_mode' => 'analytical',
      'capabilities_version' => '1.0',
      'cost_tier' => 'free',
      'model_config' => {
        'provider' => 'ollama',
        'model' => 'qwen2.5-coder:14b',
        'temperature' => 0.1,
        'max_tokens' => 4096,
        'response_format' => 'code_generation',
        'cost_per_1k' => { 'input' => 0.0, 'output' => 0.0 }
      },
      'task_model_overrides' => {
        'documentation' => 'qwen2.5:14b',
        'code_review' => 'qwen2.5-coder:14b',
        'planning' => 'qwen2.5-coder:14b'
      },
      'system_prompt' => <<~PROMPT.strip
        You are the QA/Test Engineer for the Powernode platform.

        BACKEND TESTING (RSpec):
        - Run: cd server && bundle exec rspec spec/ (single process only)
        - DatabaseCleaner with :deletion strategy (avoids TRUNCATE deadlocks)
        - Never run multiple rspec instances on the same database concurrently
        - Factories in spec/factories/ with traits (:active, :paused, :archived)
        - AI factories in spec/factories/ai/

        TEST HELPERS:
        - User setup: user_with_permissions('perm.name') from permission_test_helpers.rb
        - Auth headers: auth_headers_for(user) returns { Authorization: Bearer ... }
        - Response: json_response, json_response_data
        - Assertions: expect_success_response(data), expect_error_response(msg, status)
        - Never create users manually — always use helpers

        SHARED EXAMPLES:
        - include_examples 'requires authentication'
        - include_examples 'requires permission'
        - include_examples 'scopes to current account'
        - See spec/support/shared_examples/ for full list

        AI TEST SUPPORT:
        - Matchers: be_a_valid_ai_response, have_execution_status(:status), create_audit_log(:action)
        - Helpers: ProviderHelpers, AgentHelpers, WorkflowHelpers, SecurityHelpers
        - See spec/support/ai_matchers.rb and spec/support/ai_test_helpers.rb

        FRONTEND TESTING:
        - Run: cd frontend && CI=true npm test (always use CI=true)
        - Jest with React Testing Library
        - Test user interactions, not implementation details
        - Use data-testid attributes for test selectors

        E2E TESTING (Playwright):
        - Page Object Models in e2e/pages/, AI pages in e2e/pages/ai/
        - Selectors: data-testid first, then class*="pattern", then getByRole
        - Error suppression: page.on('pageerror', () => {}) in beforeEach
        - Conditional: if (await el.count() > 0) for optional elements
        - Add data-testid to new components for testability

        TEST-FIRST APPROACH:
        - Write failing test before implementing feature
        - Cover happy path, error cases, edge cases, and auth failures
        - Test all response codes and error messages for API endpoints

        ## MCP Platform Tools Available
        You have access to 44 MCP platform tools including:
        - Agent/Team Management: create, list, get, update agents and teams
        - Workflow: create/execute/list/get/update workflows
        - Memory: read/write_shared_memory, search_memory, memory_stats
        - Learnings: query_learnings, reinforce_learning, learning_metrics

        ## Self-Improvement
        Compound learnings from past executions are automatically injected into your context. Apply proven patterns and avoid repeated mistakes.
      PROMPT
    }
  },
  {
    name: 'Powernode Documentation Specialist',
    agent_type: 'content_generator',
    provider: ollama_provider,
    description: 'Documentation specialist for the Powernode platform. Writes API documentation, architectural decision records, knowledge base articles, and platform guides following the established docs/ directory structure.',
    conversation_profile: {
      'tone' => 'educational',
      'verbosity' => 'thorough',
      'style' => 'explanatory',
      'greeting' => 'Documentation specialist ready. What needs documenting?'
    },
    mcp_metadata: {
      'specialization' => 'documentation',
      'priority_level' => 'low',
      'execution_mode' => 'generative',
      'capabilities_version' => '1.0',
      'cost_tier' => 'free',
      'model_config' => {
        'provider' => 'ollama',
        'model' => 'qwen2.5-coder:14b',
        'temperature' => 0.4,
        'max_tokens' => 8192,
        'response_format' => 'documentation',
        'cost_per_1k' => { 'input' => 0.0, 'output' => 0.0 }
      },
      'task_model_overrides' => {
        'documentation' => 'qwen2.5-coder:14b',
        'code_review' => 'qwen2.5-coder:14b',
        'planning' => 'qwen2.5-coder:14b'
      },
      'system_prompt' => <<~PROMPT.strip
        You are the Documentation Specialist for the Powernode platform.

        DOCUMENTATION STRUCTURE:
        - docs/platform/ — Platform architecture and cross-cutting concerns
        - docs/backend/ — Backend specialist docs and API references
        - docs/frontend/ — Frontend patterns, components, and theme documentation
        - docs/testing/ — Testing strategies, patterns, and coverage reports
        - docs/services/ — Service documentation and integration guides
        - docs/infrastructure/ — Infrastructure setup and operational runbooks
        - NEVER save documentation to the project root folder

        DOCUMENT TYPES:
        - ADRs: Architecture Decision Records with context, decision, consequences
        - API docs: Endpoint reference with request/response examples
        - Guides: Step-by-step tutorials for common development tasks
        - Reference: Exhaustive parameter and configuration documentation
        - Knowledge base: User-facing help articles for the KB system

        WRITING STANDARDS:
        - Use clear, concise technical writing
        - Include code examples for all API endpoints and patterns
        - Show both correct and incorrect patterns (with explanations)
        - Keep documents focused — one concern per document
        - Use tables for parameter documentation
        - Include curl examples for API endpoints

        KEY PLATFORM DOCS TO MAINTAIN:
        - MCP_CONFIGURATION.md — MCP server setup and tool registration
        - PERMISSION_SYSTEM_REFERENCE.md — Permission names and role mappings
        - THEME_SYSTEM_REFERENCE.md — Theme class reference and usage
        - API_RESPONSE_STANDARDS.md — render_success/render_error patterns
        - UUID_SYSTEM_IMPLEMENTATION.md — UUIDv7 migration and usage
        - WORKFLOW_SYSTEM_STANDARDS.md — AI workflow creation and execution

        AUDIT MODE:
        - When asked to audit/review/analyze, save findings to docs/
        - Do NOT implement changes during audits — report only
        - Include severity ratings and remediation recommendations

        ## MCP Platform Tools Available
        You have access to 44 MCP platform tools including:
        - KB Article Management: list_kb_articles, get_kb_article, create_kb_article, update_kb_article
        - Page Management: list_pages, get_page, create_page, update_page
        - Compound Learning: query_learnings, reinforce_learning, learning_metrics
        - Shared Knowledge: search_knowledge, create_knowledge, update_knowledge, promote_knowledge
        - Memory: read_shared_memory, write_shared_memory, search_memory, memory_stats

        Use these tools to directly manage platform content and leverage organizational knowledge.

        ## Self-Improvement
        Your system prompt is automatically injected with relevant compound learnings from past executions. Review these learnings and apply proven patterns to improve your output quality.
      PROMPT
    }
  }
]

# ---------------------------------------------------------------------------
# Create Agents
# ---------------------------------------------------------------------------
agents = {}
agents_created = 0

agents_data.each do |ad|
  agent = Ai::Agent.find_or_create_by!(account: admin_account, name: ad[:name]) do |a|
    a.description = ad[:description]
    a.agent_type = ad[:agent_type]
    a.provider = ad[:provider]
    a.creator = admin_user
    a.status = 'active'
    a.version = '1.0.0'
    a.mcp_metadata = ad[:mcp_metadata]
    a.conversation_profile = ad[:conversation_profile] || {}
  end
  # Update conversation_profile and system_prompt on existing agents
  updates = {}
  if ad[:conversation_profile].present? && agent.conversation_profile.blank?
    updates[:conversation_profile] = ad[:conversation_profile]
  end
  # Always refresh system_prompt from seed data
  current_prompt = agent.mcp_metadata&.dig('system_prompt')
  seed_prompt = ad[:mcp_metadata]&.dig('system_prompt')
  if seed_prompt.present? && current_prompt != seed_prompt
    updates[:mcp_metadata] = (agent.mcp_metadata || {}).merge('system_prompt' => seed_prompt)
  end
  agent.update!(updates) if updates.present?
  agents[ad[:name]] = agent
  agents_created += 1
  model = ad[:mcp_metadata].dig('model_config', 'model')
  puts "  ✅ Agent '#{agent.name}' (#{ad[:provider].name} / #{model})"
end

# ---------------------------------------------------------------------------
# Team Definition
# ---------------------------------------------------------------------------
team = Ai::AgentTeam.find_or_create_by!(account: admin_account, name: 'Powernode Development Team') do |t|
  t.description = 'Hierarchical development team for the Powernode subscription management platform. Specialized agents for project leadership, frontend, backend, DevOps, QA, and documentation with Powernode-specific conventions embedded in system prompts.'
  t.team_type = 'hierarchical'
  t.coordination_strategy = 'manager_led'
  t.goal_description = 'Develop, test, and deploy features for the Powernode platform following established conventions and quality gates'
  t.team_config = {
    'max_iterations' => 15,
    'timeout_seconds' => 3600,
    'retry_on_failure' => true,
    'max_retries' => 3,
    'skip_on_member_failure' => true,
    'task_timeout_seconds' => 600,
    'repository_path' => '/opt/powernode',
    'base_branch' => 'develop',
    'merge_strategy' => 'integration_branch',
    'runner_execution' => false,
    'gitea_repository' => 'powernode/powernode-platform',
    'remote_push_enabled' => true,
    'pr_auto_create' => true,
    'pr_target_branch' => 'develop',
    'require_plan_approval' => true,
    'coordinator_enabled' => true,
    'post_execution_activity' => 'summarize_and_notify',
    'quality_gates' => {
      'backend' => 'bundle exec rspec',
      'frontend' => 'npx tsc --noEmit && CI=true npm test',
      'patterns' => 'scripts/quick-pattern-check.sh'
    }
  }
  t.review_config = {
    'production' => { 'mode' => 'blocking', 'require_approval' => true },
    'staging' => { 'mode' => 'shadow', 'require_approval' => false },
    'development' => { 'mode' => 'shadow', 'require_approval' => false }
  }
  t.status = 'active'
end

# Ensure coordinator_enabled, post_execution_activity, and require_plan_approval are set on existing teams
merged_config = team.team_config.reverse_merge(
  'coordinator_enabled' => true,
  'post_execution_activity' => 'summarize_and_notify',
  'require_plan_approval' => true,
  'compound_learning_injection' => true
).merge('task_timeout_seconds' => 600)
if merged_config != team.team_config
  team.update!(team_config: merged_config)
  puts "  🔄 Updated team config with missing keys"
end

puts "  ✅ Team '#{team.name}' (#{team.team_type})"

# ---------------------------------------------------------------------------
# Roles & Members
# ---------------------------------------------------------------------------
roles_data = [
  {
    role_name: 'Project Lead',
    role_type: 'manager',
    agent_name: 'Powernode Project Lead',
    role_description: 'Coordinates the Powernode development team, makes architecture decisions, enforces conventions, and manages release cycles',
    responsibilities: 'Architecture decisions, task decomposition, convention enforcement, release management, PR review',
    goals: 'Ensure high-quality, convention-compliant development across all platform layers',
    capabilities: %w[architecture_decisions task_decomposition convention_enforcement release_management code_review],
    constraints: %w[document_all_adrs enforce_quality_gates staged_commits],
    tools_allowed: %w[code_diff file_read structured_output git_operations task_management],
    context_access: { 'full_codebase' => true, 'infrastructure' => true, 'deployment' => true },
    priority_order: 0,
    can_delegate: true,
    can_escalate: true,
    max_concurrent_tasks: 8,
    is_lead: true,
    member_role: 'manager'
  },
  {
    role_name: 'Frontend Developer',
    role_type: 'specialist',
    agent_name: 'Powernode Frontend Developer',
    role_description: 'Builds React TypeScript components, pages, and features with theme-aware styling and permission-based access control',
    responsibilities: 'React components, TypeScript types, API hooks, pages, theme compliance, accessibility',
    goals: 'Deliver polished, accessible, theme-compliant frontend features',
    capabilities: %w[react_development typescript theme_implementation permission_gating component_design],
    constraints: %w[theme_classes_only permission_based_access no_console_log no_any_types],
    tools_allowed: %w[code_generation file_write tsc_check],
    context_access: { 'frontend' => true, 'api_contracts' => true },
    priority_order: 1,
    can_delegate: false,
    can_escalate: true,
    max_concurrent_tasks: 4,
    is_lead: false,
    member_role: 'executor'
  },
  {
    role_name: 'Backend Developer',
    role_type: 'specialist',
    agent_name: 'Powernode Backend Developer',
    role_description: 'Implements Rails API endpoints, models, services, and migrations following Powernode backend conventions',
    responsibilities: 'API endpoints, models, services, migrations, seeds, permission configuration',
    goals: 'Deliver reliable, well-tested backend functionality following Rails and Powernode conventions',
    capabilities: %w[rails_development api_design database_design service_implementation migration_writing],
    constraints: %w[frozen_string_literal render_success_error inline_indexes namespace_conventions],
    tools_allowed: %w[code_generation file_write database_operations],
    context_access: { 'backend' => true, 'database' => true, 'seeds' => true },
    priority_order: 2,
    can_delegate: false,
    can_escalate: true,
    max_concurrent_tasks: 4,
    is_lead: false,
    member_role: 'executor'
  },
  {
    role_name: 'DevOps Engineer',
    role_type: 'specialist',
    agent_name: 'Powernode DevOps Engineer',
    role_description: 'Manages systemd services, CI/CD pipelines, deployment automation, and infrastructure for the Powernode platform',
    responsibilities: 'Systemd management, CI/CD pipelines, deployment, Docker, monitoring, infrastructure',
    goals: 'Ensure reliable deployments, service health, and automated quality gates',
    capabilities: %w[systemd_management cicd_pipelines deployment_automation docker_operations monitoring],
    constraints: %w[no_manual_commands tag_no_v_prefix service_restart_after_changes],
    tools_allowed: %w[shell_execution service_management pipeline_control git_operations],
    context_access: { 'infrastructure' => true, 'deployment' => true, 'monitoring' => true },
    priority_order: 3,
    can_delegate: false,
    can_escalate: true,
    max_concurrent_tasks: 3,
    is_lead: false,
    member_role: 'executor'
  },
  {
    role_name: 'QA/Test Engineer',
    role_type: 'reviewer',
    agent_name: 'Powernode QA/Test Engineer',
    role_description: 'Writes and maintains RSpec, Jest, and Playwright tests using Powernode test helpers and shared examples',
    responsibilities: 'RSpec tests, Jest tests, Playwright E2E tests, test helpers, coverage analysis',
    goals: 'Achieve comprehensive test coverage using platform-specific test patterns and helpers',
    capabilities: %w[rspec_testing jest_testing playwright_e2e test_helper_usage coverage_analysis],
    constraints: %w[use_test_helpers single_process_rspec ci_true_frontend test_first],
    tools_allowed: %w[code_generation file_write test_execution],
    context_access: { 'test_suite' => true, 'api_contracts' => true, 'frontend' => true },
    priority_order: 4,
    can_delegate: false,
    can_escalate: true,
    max_concurrent_tasks: 3,
    is_lead: false,
    member_role: 'reviewer'
  },
  {
    role_name: 'Documentation Specialist',
    role_type: 'worker',
    agent_name: 'Powernode Documentation Specialist',
    role_description: 'Writes and maintains API documentation, ADRs, platform guides, and knowledge base articles',
    responsibilities: 'API docs, ADRs, platform guides, KB articles, audit reports, changelog entries',
    goals: 'Maintain comprehensive, accurate documentation for all platform features',
    capabilities: %w[api_documentation adr_writing guide_creation kb_articles audit_reporting],
    constraints: %w[docs_directory_structure no_root_files audit_report_only],
    tools_allowed: %w[file_write file_read structured_output markdown_formatting],
    context_access: { 'full_codebase' => true, 'documentation' => true },
    priority_order: 5,
    can_delegate: false,
    can_escalate: true,
    max_concurrent_tasks: 3,
    is_lead: false,
    member_role: 'facilitator'
  }
]

roles_created = 0
members_created = 0

roles_data.each do |rd|
  agent = agents[rd[:agent_name]]

  Ai::TeamRole.find_or_create_by!(agent_team: team, role_name: rd[:role_name]) do |r|
    r.account = admin_account
    r.ai_agent = agent
    r.role_type = rd[:role_type]
    r.role_description = rd[:role_description]
    r.responsibilities = rd[:responsibilities]
    r.goals = rd[:goals]
    r.capabilities = rd[:capabilities]
    r.constraints = rd[:constraints]
    r.tools_allowed = rd[:tools_allowed]
    r.context_access = rd[:context_access]
    r.priority_order = rd[:priority_order]
    r.can_delegate = rd[:can_delegate]
    r.can_escalate = rd[:can_escalate]
    r.max_concurrent_tasks = rd[:max_concurrent_tasks]
  end
  roles_created += 1

  Ai::AgentTeamMember.find_or_create_by!(
    ai_agent_team_id: team.id,
    ai_agent_id: agent.id
  ) do |m|
    m.role = rd[:member_role]
    m.is_lead = rd[:is_lead]
    m.priority_order = rd[:priority_order]
    m.capabilities = rd[:capabilities]
  end
  members_created += 1
end

# ---------------------------------------------------------------------------
# Channels
# ---------------------------------------------------------------------------
channels_data = [
  {
    name: 'pn-general',
    channel_type: 'broadcast',
    description: 'Team-wide announcements, architectural decisions, sprint updates, and convention changes for the Powernode platform',
    participant_roles: %w[Project\ Lead Frontend\ Developer Backend\ Developer DevOps\ Engineer QA/Test\ Engineer Documentation\ Specialist],
    message_schema: {
      'type' => 'object',
      'properties' => {
        'message' => { 'type' => 'string' },
        'priority' => { 'type' => 'string', 'enum' => %w[low normal high urgent] },
        'category' => { 'type' => 'string', 'enum' => %w[announcement decision convention sprint release] }
      }
    },
    routing_rules: { 'broadcast_to_all' => true }
  },
  {
    name: 'pn-code-review',
    channel_type: 'topic',
    description: 'Code review requests, convention compliance discussions, and PR feedback for Powernode changes',
    participant_roles: %w[Project\ Lead Frontend\ Developer Backend\ Developer QA/Test\ Engineer],
    message_schema: {
      'type' => 'object',
      'properties' => {
        'pr_id' => { 'type' => 'string' },
        'review_type' => { 'type' => 'string', 'enum' => %w[feature bugfix refactor convention] },
        'files_changed' => { 'type' => 'array' },
        'message' => { 'type' => 'string' }
      }
    },
    routing_rules: { 'route_by_role' => true, 'priority_routing' => true }
  },
  {
    name: 'pn-bugs',
    channel_type: 'escalation',
    description: 'Bug reports, regression alerts, and critical issue escalation for the Powernode platform',
    participant_roles: %w[Project\ Lead Backend\ Developer Frontend\ Developer QA/Test\ Engineer DevOps\ Engineer],
    message_schema: {
      'type' => 'object',
      'properties' => {
        'bug_id' => { 'type' => 'string' },
        'severity' => { 'type' => 'string', 'enum' => %w[critical high medium low] },
        'component' => { 'type' => 'string', 'enum' => %w[backend frontend worker infrastructure] },
        'description' => { 'type' => 'string' },
        'reproduction_steps' => { 'type' => 'array' }
      }
    },
    routing_rules: { 'escalate_by_severity' => true, 'route_by_component' => true }
  },
  {
    name: 'pn-deployments',
    channel_type: 'task',
    description: 'Deployment coordination, release tracking, and infrastructure change requests',
    participant_roles: %w[Project\ Lead DevOps\ Engineer Backend\ Developer],
    message_schema: {
      'type' => 'object',
      'properties' => {
        'deployment_id' => { 'type' => 'string' },
        'environment' => { 'type' => 'string', 'enum' => %w[development staging production] },
        'action' => { 'type' => 'string', 'enum' => %w[deploy rollback restart verify] },
        'version' => { 'type' => 'string' }
      }
    },
    routing_rules: { 'route_by_role' => true, 'require_approval_for_production' => true }
  }
]

channels_created = 0

channels_data.each do |cd|
  Ai::TeamChannel.find_or_create_by!(agent_team: team, name: cd[:name]) do |c|
    c.channel_type = cd[:channel_type]
    c.description = cd[:description]
    c.participant_roles = cd[:participant_roles]
    c.message_schema = cd[:message_schema]
    c.routing_rules = cd[:routing_rules]
    c.is_persistent = true
  end
  channels_created += 1
end

# ---------------------------------------------------------------------------
# Shared Memory Pool
# ---------------------------------------------------------------------------
memory_pool = Ai::MemoryPool.find_or_create_by!(
  account: admin_account,
  name: 'Powernode Platform Conventions'
) do |mp|
  mp.pool_type = 'team_shared'
  mp.scope = 'persistent'
  mp.version = 1
  mp.team_id = team.id
  mp.persist_across_executions = true
  mp.access_control = {
    'public' => false,
    'agents' => agents.values.map(&:id)
  }
  mp.data = {
    'platform' => {
      'name' => 'Powernode',
      'description' => 'Subscription lifecycle management platform',
      'tech_stack' => {
        'backend' => 'Rails 8 API, PostgreSQL, UUIDv7, JWT auth',
        'frontend' => 'React 18, TypeScript, Tailwind CSS, Lucide icons',
        'worker' => 'Standalone Sidekiq, HTTP API communication',
        'enterprise' => 'Git submodule, billing, BaaS, reseller, AI publisher',
        'infrastructure' => 'Systemd services, Docker Swarm, Redis'
      },
      'conventions' => {
        'backend' => [
          'frozen_string_literal pragma on all .rb files',
          'render_success/render_error for all controller responses',
          'Api::V1 namespace for all controllers',
          'Inline indexes on t.references in migrations — never separate add_index',
          'Namespaced models use :: separator in class_name',
          'Always pair class_name: with foreign_key: on belongs_to',
          'JSON columns: default: -> { {} } (lambda, never literal)',
          'Controllers under 300 lines — extract to services/concerns',
          'Always .includes() when iterating associations',
          'Rails.logger only — never puts/print',
          'current_user.has_permission? — never permissions.include?'
        ],
        'frontend' => [
          'Theme classes only: bg-theme-*, text-theme-*, border-theme-*',
          'Permission-based access: permissions.includes() — never roles',
          'Actions in PageContainer headerActions — never in page body',
          'Global notifications only — no local success/error state',
          'Path aliases: @/shared/, @/features/, @enterprise/',
          'No console.log — use logger from @/shared/utils/logger',
          'No any types — proper TypeScript typing required',
          'Lucide-react for all icons',
          'Flat navigation — no submenus'
        ],
        'git' => [
          'Branch strategy: develop -> feature/* -> release/* -> master',
          'No v prefix on tags: 0.2.0 not v0.2.0',
          'Staged commits: group by concern (models, services, controllers, etc.)',
          'No Claude attribution in commits',
          'Feature branches for all changes'
        ],
        'testing' => [
          'DatabaseCleaner :deletion strategy (no TRUNCATE)',
          'Single-process rspec only — never parallel on same DB',
          'user_with_permissions() for test user setup',
          'auth_headers_for() for API test authentication',
          'CI=true for all frontend test runs',
          'Test-first: write failing test before implementation'
        ],
        'infrastructure' => [
          'Systemd template units for all services',
          'Never use manual commands (rails server, sidekiq, npm start)',
          'sudo systemctl restart powernode-backend@default after API changes',
          'rails db:seed after seed modifications',
          'Ports: backend=3000, frontend=3001, worker-web=4567'
        ]
      },
      'core_models' => {
        'primary' => 'Account -> User (many), Subscription (one)',
        'subscription' => 'Subscription -> Plan, Payments, Invoices',
        'user' => 'User -> Roles, Permissions, Invitations',
        'ai' => 'Ai::Agent -> Provider, Executions, Conversations, Skills',
        'teams' => 'Ai::AgentTeam -> Members, Roles, Channels'
      }
    },
    'decisions' => [],
    'task_log' => []
  }
  mp.metadata = {
    'created_by' => 'seed',
    'team_name' => 'Powernode Development Team',
    'purpose' => 'Shared platform conventions and project context for all team agents'
  }
  mp.retention_policy = {
    'max_entries' => 5000,
    'ttl_days' => 365
  }
end

puts "  ✅ Memory pool '#{memory_pool.name}' (#{memory_pool.pool_type})"

# ---------------------------------------------------------------------------
# Agent Connections (shared memory links)
# ---------------------------------------------------------------------------
connections_created = 0

agents.each_value do |agent|
  Ai::AgentConnection.find_or_create_by!(
    account: admin_account,
    connection_type: 'shared_memory',
    source_type: 'Ai::Agent',
    source_id: agent.id,
    target_type: 'Ai::MemoryPool',
    target_id: memory_pool.id
  ) do |c|
    c.status = 'active'
    c.strength = 0.9
    c.metadata = { 'access_level' => 'read_write', 'pool_name' => memory_pool.name }
  end
  connections_created += 1
end

# ---------------------------------------------------------------------------
# MCP Server Connections
# ---------------------------------------------------------------------------
mcp_connections_created = 0

filesystem_mcp = McpServer.find_by(account: admin_account, name: 'Filesystem MCP')
database_mcp   = McpServer.find_by(account: admin_account, name: 'Database MCP')
web_fetch_mcp  = McpServer.find_by(account: admin_account, name: 'Web Fetch MCP')

mcp_assignments = {
  'Powernode Project Lead'            => [filesystem_mcp, database_mcp, web_fetch_mcp],
  'Powernode Frontend Developer'      => [filesystem_mcp, web_fetch_mcp],
  'Powernode Backend Developer'       => [filesystem_mcp, database_mcp],
  'Powernode DevOps Engineer'         => [filesystem_mcp, web_fetch_mcp],
  'Powernode QA/Test Engineer'        => [filesystem_mcp, database_mcp],
  'Powernode Documentation Specialist' => [filesystem_mcp, web_fetch_mcp]
}

mcp_assignments.each do |agent_name, mcp_servers|
  agent = agents[agent_name]
  next unless agent

  mcp_servers.compact.each do |mcp_server|
    Ai::AgentConnection.find_or_create_by!(
      account: admin_account,
      connection_type: 'mcp_tool_usage',
      source_type: 'Ai::Agent',
      source_id: agent.id,
      target_type: 'McpServer',
      target_id: mcp_server.id
    ) do |c|
      c.status = 'active'
      c.strength = 0.9
      c.metadata = { 'server_name' => mcp_server.name, 'auto_assigned' => true }
    end
    mcp_connections_created += 1
  end
end

if mcp_connections_created.positive?
  puts "  ✅ MCP Server Connections: #{mcp_connections_created}"
else
  puts "  ⚠️  MCP servers not found — skipping MCP connections"
end

# ---------------------------------------------------------------------------
# Skills Assignment
# ---------------------------------------------------------------------------
skills_assigned = 0

skill_assignments = {
  'Powernode Project Lead'            => %w[productivity product-management],
  'Powernode Frontend Developer'      => %w[productivity],
  'Powernode Backend Developer'       => %w[productivity data],
  'Powernode DevOps Engineer'         => %w[productivity],
  'Powernode QA/Test Engineer'        => %w[productivity],
  'Powernode Documentation Specialist' => %w[product-management]
}

skill_assignments.each do |agent_name, slugs|
  agent = agents[agent_name]
  next unless agent

  slugs.each do |slug|
    skill = Ai::Skill.find_by(slug: slug, status: 'active')
    next unless skill

    Ai::AgentSkill.find_or_create_by!(
      ai_agent_id: agent.id,
      ai_skill_id: skill.id
    ) do |as|
      as.is_active = true
      as.priority = 0
    end
    skills_assigned += 1
  end
end

if skills_assigned.positive?
  puts "  ✅ Skills Assigned: #{skills_assigned}"
else
  puts "  ⚠️  No matching skills found — skipping skill assignments"
end

# ---------------------------------------------------------------------------
# Role Profile Application
# ---------------------------------------------------------------------------
profiles_applied = 0

profile_mapping = {
  'Powernode Project Lead'            => 'lead',
  'Powernode QA/Test Engineer'        => 'reviewer',
  'Powernode Documentation Specialist' => 'documentation_expert'
}

profile_mapping.each do |agent_name, role_type|
  agent = agents[agent_name]
  next unless agent

  profile = Ai::RoleProfile.system_profiles.find_by(role_type: role_type)
  next unless profile

  team_role = Ai::TeamRole.find_by(agent_team: team, ai_agent_id: agent.id)
  if team_role
    team_role.update!(
      metadata: (team_role.metadata || {}).merge(
        'role_profile_id' => profile.id,
        'role_profile_slug' => profile.slug
      )
    )
    profiles_applied += 1
  end
end

if profiles_applied.positive?
  puts "  ✅ Role Profiles Applied: #{profiles_applied}"
else
  puts "  ⚠️  No matching role profiles — skipping"
end

# ---------------------------------------------------------------------------
# Infrastructure Bindings
# ---------------------------------------------------------------------------
infra_connections_created = 0

swarm_cluster = Devops::SwarmCluster.find_by(account: admin_account, status: 'connected')
docker_host   = Devops::DockerHost.find_by(account: admin_account) if defined?(Devops::DockerHost)

[swarm_cluster, docker_host].compact.each do |infra|
  Ai::AgentConnection.find_or_create_by!(
    account: admin_account,
    connection_type: 'infrastructure',
    source_type: 'Ai::AgentTeam',
    source_id: team.id,
    target_type: infra.class.name,
    target_id: infra.id
  ) do |c|
    c.status = 'active'
    c.strength = 1.0
    c.metadata = { 'name' => infra.name, 'binding_type' => 'team_infra' }
  end
  infra_connections_created += 1
end

if infra_connections_created.positive?
  puts "  ✅ Infrastructure Bindings: #{infra_connections_created}"
else
  puts "  ⚠️  No infrastructure found — skipping bindings"
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
puts "\n📊 Powernode Development Team Summary:"
puts "   Agents: #{agents_created}"
puts "   Team: #{team.name} (#{team.team_type}, #{team.coordination_strategy})"
puts "   Roles: #{roles_created}"
puts "   Members: #{members_created}"
puts "   Channels: #{channels_created}"
puts "   Memory Pool: #{memory_pool.name}"
puts "   Memory Connections: #{connections_created}"
puts "   MCP Connections: #{mcp_connections_created}"
puts "   Skills Assigned: #{skills_assigned}"
puts "   Role Profiles Applied: #{profiles_applied}"
puts "   Infrastructure Bindings: #{infra_connections_created}"
puts "✅ Powernode Development Team seeding completed!"
