# frozen_string_literal: true

module Ai
  module KnowledgePopulation
    # Transforms scanner output into structured markdown documents suitable
    # for RAG ingestion.  Produces ~15 overview docs (domain knowledge + live
    # scanner data) and ~35 detail docs (model/service/route/job references).
    class DocumentGeneratorService
      def initialize(scan_data)
        @models = scan_data[:models] || {}
        @routes = scan_data[:routes] || {}
        @services = scan_data[:services] || {}
        @controllers = scan_data[:controllers] || {}
        @jobs = scan_data[:jobs] || {}
        @features = scan_data[:frontend_features] || {}
      end

      def generate_all
        generate_overviews +
          generate_model_references +
          generate_service_references +
          generate_controller_references +
          generate_job_references +
          generate_static_references
      end

      private

      # ================================================================
      # HELPERS
      # ================================================================

      def models_for_prefix(prefix)
        @models.flat_map { |ns, ms| (ns == prefix || ns.start_with?("#{prefix}::")) ? ms : [] }
      end

      def services_for_prefix(prefix)
        @services.flat_map { |ns, ss| (ns == prefix || ns.start_with?("#{prefix}::")) ? ss : [] }
      end

      def controllers_for_prefix(prefix)
        @controllers.flat_map { |ns, cs| (ns == prefix || ns.start_with?("#{prefix}::")) ? cs : [] }
      end

      def jobs_for_prefix(prefix)
        @jobs.flat_map { |ns, js| (ns == prefix || ns.start_with?("#{prefix}::")) ? js : [] }
      end

      def routes_for_prefix(prefix)
        @routes.flat_map { |ns, rs| (ns == prefix || ns.start_with?("#{prefix}/")) ? rs : [] }
      end

      # ================================================================
      # OVERVIEW DOCUMENTS (~15)
      # ================================================================

      def generate_overviews
        overview_definitions.map { |defn| build_overview(defn) }
      end

      def build_overview(defn)
        parts = ["# #{defn[:name]}\n", "## Overview\n#{defn[:desc]}\n"]

        # Model summary
        models = (defn[:model_prefixes] || []).flat_map { |p| models_for_prefix(p) }
        if models.any?
          parts << "## Models (#{models.size})\n"
          models.each { |m| parts << "- **#{m[:name]}** — `#{m[:table_name]}` (#{m[:columns].size} columns, #{m[:associations].size} associations)" }
          parts << ""
        end

        # Route summary
        routes = (defn[:route_prefixes] || []).flat_map { |p| routes_for_prefix(p) }
        if routes.any?
          parts << "## API Endpoints (#{routes.size})\n"
          parts << "| Method | Path | Action |"
          parts << "|--------|------|--------|"
          routes.first(30).each { |r| parts << "| #{r[:verb]} | `#{r[:path]}` | `#{r[:controller]}##{r[:action]}` |" }
          parts << "| ... | ... | ... |" if routes.size > 30
          parts << ""
        end

        parts << "## Key Patterns\n#{defn[:patterns]}\n" if defn[:patterns]

        { name: defn[:name], content: parts.join("\n"), category: "overview" }
      end

      # rubocop:disable Metrics/MethodLength
      def overview_definitions
        [
          {
            name: "Platform Architecture Overview",
            desc: "Powernode is a subscription lifecycle management platform built with Rails 8 API backend (server/), " \
                  "React TypeScript frontend (frontend/), and a standalone Sidekiq worker (worker/). It uses " \
                  "PostgreSQL with UUIDv7 primary keys, JWT authentication, and pgvector for AI vector search.\n\n" \
                  "Services run via systemd: backend on port 3000, frontend on 3001, worker-web on 4567. " \
                  "Enterprise features ship as a git submodule at extensions/enterprise/; when absent the app " \
                  "runs in single-user self-hosted mode with all features unlocked.",
            model_prefixes: ["Root"],
            route_prefixes: ["root"],
            patterns: "- UUIDv7 primary keys on all tables\n" \
                      "- `render_success()`/`render_error()` mandatory in controllers\n" \
                      "- `# frozen_string_literal: true` pragma in every Ruby file\n" \
                      "- Theme classes only: `bg-theme-*`, `text-theme-*`\n" \
                      "- Permission-based access control (never roles for gating)\n" \
                      "- Worker communicates with server via HTTP API only"
          },
          {
            name: "Authentication and Authorization",
            desc: "JWT-based authentication with role/permission access control. Users authenticate via " \
                  "email/password or OAuth 2.1 providers. 2FA via TOTP is available. API keys provide " \
                  "service-to-service auth.\n\n" \
                  "Access control is permission-based: frontend checks `currentUser?.permissions?.includes('name')`, " \
                  "backend uses `current_user.has_permission?('name')`. Roles are never used directly for access decisions.",
            model_prefixes: ["Root"],
            patterns: "- JWT tokens with configurable expiry\n" \
                      "- `current_user.has_permission?('name')` — never `permissions.include?()`\n" \
                      "- OAuth 2.1 for external providers\n- API key auth for services\n- 2FA via TOTP"
          },
          {
            name: "Account and User Management",
            desc: "Accounts are the top-level tenant. Each has users, subscriptions, and resources. " \
                  "Users can have multiple roles granting permissions. Invitations, delegation, and " \
                  "impersonation features are available.",
            model_prefixes: ["Root"],
            patterns: "- Multi-tenant with Account as root\n- User invitations with expiry\n" \
                      "- Delegation for temporary permission grants\n- Impersonation for admin support"
          },
          {
            name: "Subscription and Billing",
            desc: "Plan/subscription/payment/invoice lifecycle. Stripe and PayPal integrations (enterprise). " \
                  "Usage metering for consumption-based billing. PCI compliance enforced.",
            model_prefixes: ["Root"],
            patterns: "- Plan → Subscription → Payment → Invoice lifecycle\n" \
                      "- Usage metering for consumption billing\n" \
                      "- Webhook receivers return 200/202 on errors (never 500)\n- PCI compliance for payment data"
          },
          {
            name: "AI Agent Orchestration",
            desc: "Create, manage, and execute AI agents organized into teams with role profiles. " \
                  "Trust scores determine autonomy: supervised (0.0) → monitored (0.4) → trusted (0.7) → " \
                  "autonomous (0.9). Budgets control resource consumption. Lineage tracks parent-child " \
                  "relationships. Container and worktree sandbox isolation available.",
            model_prefixes: ["Ai"],
            route_prefixes: ["api/v1/ai"],
            patterns: "- AgentTeam composition guardrails (max 10 agents)\n" \
                      "- Role profiles: coordinator, researcher, developer, reviewer, tester, analyst\n" \
                      "- Trust scoring with behavioral fingerprinting\n" \
                      "- Budget tracking per-agent and per-team\n- Container and worktree sandbox isolation"
          },
          {
            name: "AI Workflows and Execution",
            desc: "DAG-based workflow execution engine. Workflows consist of nodes and edges forming " \
                  "directed acyclic graphs. Supports scheduling, compensation (rollback), checkpointing, " \
                  "templates, triggers, and human-in-the-loop approvals.",
            model_prefixes: ["Ai"],
            patterns: "- DAG execution with topological ordering\n" \
                      "- Node types: action, condition, loop, parallel, approval, notification\n" \
                      "- Compensation (rollback) for failed workflows\n" \
                      "- Checkpointing for long-running workflows\n" \
                      "- Schedule-based and event-based triggers"
          },
          {
            name: "AI Memory and Knowledge",
            desc: "Four-tier memory system:\n" \
                  "- **Working**: Redis-based, ephemeral per-execution\n" \
                  "- **Short-term**: PostgreSQL with TTL, per-agent session state\n" \
                  "- **Long-term**: pgvector embeddings, semantic retrieval\n" \
                  "- **Shared**: pgvector with ACL, cross-agent knowledge sharing\n\n" \
                  "MemoryRouterService routes to the correct tier. IntegrityService (OWASP ASI05) " \
                  "provides SHA-256 checksums. ConsolidationService promotes between tiers. " \
                  "DecayService applies temporal decay and archival.",
            model_prefixes: ["Ai"],
            patterns: "- Cosine distance: `nearest_neighbors(:embedding, vector, distance: \"cosine\")`\n" \
                      "- Dedup at 0.92 similarity threshold\n" \
                      "- Quality scoring (0-1) based on content length, tags, metadata\n" \
                      "- SharedKnowledge uses `provenance` column (not `metadata`)"
          },
          {
            name: "AI Skills and Learning",
            desc: "Skill graph manages reusable agent capabilities with versioning and conflict resolution. " \
                  "Compound learning extracts patterns from successes/failures. Trajectories track execution paths. " \
                  "Evaluations benchmark performance.",
            model_prefixes: ["Ai"],
            patterns: "- Skill versioning with semantic versions\n" \
                      "- Compound learning categories: pattern, anti_pattern, best_practice, fact, discovery\n" \
                      "- Feature flags: :compound_learning_injection, :compound_learning_promotion\n" \
                      "- Trajectory chapters track decision points"
          },
          {
            name: "AI Protocols A2A ACP MCP",
            desc: "Three inter-agent protocols:\n" \
                  "- **A2A**: JSON-RPC 2.0 for agent communication, discovery, task delegation, federation\n" \
                  "- **ACP**: Adapter for external agent ecosystems (8 endpoints at /api/v1/ai/acp/)\n" \
                  "- **MCP**: Tool registration and execution (30+ tools with parameter schemas)\n\n" \
                  "Agent cards describe capabilities for service discovery.",
            model_prefixes: ["Ai"],
            route_prefixes: ["api/v1/ai"],
            patterns: "- A2A: JSON-RPC 2.0 dispatch, push notifications\n" \
                      "- MCP: tool schemas with permission requirements\n" \
                      "- Federation: cross-instance A2A communication\n" \
                      "- Agent cards: capability advertisement"
          },
          {
            name: "AI Missions and Code Factory",
            desc: "Missions automate feature development through a structured pipeline:\n" \
                  "analyzing → feature_approval → planning → prd_approval → executing → testing → " \
                  "reviewing → code_approval → deploying → previewing → merging → completed.\n\n" \
                  "Code Factory handles PRD generation, task generation, evidence, harness gap analysis, " \
                  "and remediation. Ralph loops manage iterative development cycles.",
            model_prefixes: ["Ai"],
            patterns: "- Mission branches: mission/{id} (slashed refs need resolve_ref)\n" \
                      "- PrdGenerationService creates RalphLoop with tasks\n" \
                      "- RalphTask: task_key and description (no name column)\n" \
                      "- TestRunnerService auto-passes if no CI workflow\n" \
                      "- Set default_agent explicitly on RalphLoop"
          },
          {
            name: "DevOps Platform",
            desc: "Git provider integration (Gitea, GitHub, GitLab), CI/CD pipeline management, " \
                  "and deployment orchestration. Runner dispatch supports GitHub and Gitea runners.",
            model_prefixes: ["Devops"],
            route_prefixes: ["api/v1/devops", "api/v1/ai"],
            patterns: "- Git provider abstraction: GiteaApiClient, GitHubApiClient, GitLabApiClient\n" \
                      "- Pipeline execution with step handlers\n" \
                      "- Deployment strategies: rolling, blue-green, canary\n" \
                      "- Gitea slashed branch refs: resolve_ref via commit SHA"
          },
          {
            name: "Docker and Swarm Management",
            desc: "Docker host management, container lifecycle, image registry, and Swarm cluster " \
                  "orchestration. Multi-host Docker environments with service deployment via stacks.",
            model_prefixes: ["Devops"],
            patterns: "- Docker host registration and health monitoring\n" \
                      "- Container create/start/stop/remove lifecycle\n" \
                      "- Image pull/build/push operations\n" \
                      "- Swarm: services, stacks, secrets management"
          },
          {
            name: "Supply Chain Security",
            desc: "SBOM generation (Cargo, Gem, Go, Maven, NPM, Pip), vulnerability scanning, " \
                  "license compliance, and attestation management.",
            model_prefixes: ["SupplyChain"],
            patterns: "- 6 SBOM generators by ecosystem\n- Vulnerability scanning with severity classification\n" \
                      "- License compliance checking\n- Software attestation and provenance"
          },
          {
            name: "Chat and Messaging",
            desc: "Multi-channel chat gateway with adapters for Slack, Discord, Telegram, WhatsApp, " \
                  "Mattermost. Real-time messaging, scheduled messages, and AI agent integration.",
            model_prefixes: ["Chat"],
            patterns: "- Channel gateway with adapter pattern\n- Real-time messaging via WebSocket\n" \
                      "- Scheduled messages with delivery tracking\n- AI agent chat integration"
          },
          {
            name: "Marketing Content and Infrastructure",
            desc: "Marketing campaigns, email lists, social media adapters, KB articles, " \
                  "file management with multi-provider storage (S3/Azure/GCS/Local/NFS/SMB), " \
                  "and infrastructure monitoring.",
            model_prefixes: %w[Marketing FileManagement KnowledgeBase Monitoring],
            patterns: "- Campaign management with audience targeting\n" \
                      "- Multi-provider file storage with versioning\n" \
                      "- KB article management with search\n- Circuit breaker pattern for external services"
          }
        ]
      end
      # rubocop:enable Metrics/MethodLength

      # ================================================================
      # MODEL REFERENCE DOCUMENTS
      # ================================================================

      NAMESPACE_GROUPS = {
        "Ai" => "AI Models Complete Reference",
        "Devops" => "DevOps Models Reference",
        "SupplyChain" => "Supply Chain Models Reference",
        "Chat" => "Chat Models Reference",
        "Marketing" => "Marketing Models Reference",
        "FileManagement" => "File Management Models Reference",
        "BaaS" => "BaaS Models Reference",
        "Marketplace" => "Marketplace Models Reference",
        "DataManagement" => "Data Management Models Reference",
        "KnowledgeBase" => "Knowledge Base Models Reference",
        "Monitoring" => "Monitoring Models Reference",
        "Root" => "Core Platform Models Reference"
      }.freeze

      def generate_model_references
        covered_prefixes = NAMESPACE_GROUPS.keys
        docs = []

        NAMESPACE_GROUPS.each do |prefix, title|
          models = models_for_prefix(prefix)
          next if models.empty?

          docs << { name: title, content: build_model_reference(title, models), category: "detail" }
        end

        # Remaining models not in major namespaces
        remaining = @models.flat_map do |ns, ms|
          covered_prefixes.any? { |p| ns == p || ns.start_with?("#{p}::") } ? [] : ms
        end
        if remaining.any?
          docs << { name: "Additional Models Reference", content: build_model_reference("Additional Models Reference", remaining), category: "detail" }
        end

        docs
      end

      def build_model_reference(title, models)
        parts = ["# #{title}\n", "Total: #{models.size} models\n"]

        models.each do |m|
          parts << "## #{m[:name]}"
          parts << "- **Table**: `#{m[:table_name]}`"
          parts << "- **Primary Key**: `#{m[:primary_key]}`\n"

          if m[:columns].any?
            parts << "### Columns\n"
            parts << "| Column | Type | Nullable | Default |"
            parts << "|--------|------|----------|---------|"
            m[:columns].each { |c| parts << "| #{c[:name]} | #{c[:type]} | #{c[:null]} | #{c[:default].presence || '-'} |" }
            parts << ""
          end

          if m[:associations].any?
            parts << "### Associations\n"
            m[:associations].each do |a|
              line = "- `#{a[:macro]} :#{a[:name]}`"
              line += ", class_name: `#{a[:class_name]}`" if a[:class_name].present?
              line += ", foreign_key: `#{a[:foreign_key]}`" if a[:foreign_key].present?
              through = a.dig(:options, :through)
              line += ", through: `:#{through}`" if through.present?
              parts << line
            end
            parts << ""
          end

          if m[:validations].any?
            parts << "### Validations\n"
            m[:validations].each { |v| parts << "- `#{v[:kind]}` on #{v[:attributes].join(', ')}" }
            parts << ""
          end
        end

        parts.join("\n")
      end

      # ================================================================
      # SERVICE REFERENCE DOCUMENTS
      # ================================================================

      SERVICE_GROUPS = {
        "Ai" => "AI Services Reference",
        "Devops" => "DevOps Services Reference",
        "Mcp" => "MCP Services Reference"
      }.freeze

      def generate_service_references
        docs = []
        covered = SERVICE_GROUPS.keys

        SERVICE_GROUPS.each do |prefix, title|
          svcs = services_for_prefix(prefix)
          next if svcs.empty?

          docs << { name: title, content: build_list_reference(title, svcs, "service"), category: "detail" }
        end

        remaining = @services.flat_map { |ns, ss| covered.any? { |p| ns == p || ns.start_with?("#{p}::") } ? [] : ss }
        if remaining.any?
          docs << { name: "Other Services Reference", content: build_list_reference("Other Services Reference", remaining, "service"), category: "detail" }
        end

        docs
      end

      # ================================================================
      # CONTROLLER REFERENCE DOCUMENTS
      # ================================================================

      def generate_controller_references
        docs = []
        ai_ctrls = controllers_for_prefix("Api::V1::Ai")
        docs << { name: "AI API Controllers Reference", content: build_controller_reference("AI API Controllers Reference", ai_ctrls), category: "detail" } if ai_ctrls.any?

        other = @controllers.flat_map { |ns, cs| (ns.start_with?("Api::V1::Ai")) ? [] : cs }
        docs << { name: "Platform API Controllers Reference", content: build_controller_reference("Platform API Controllers Reference", other), category: "detail" } if other.any?

        docs
      end

      def build_controller_reference(title, ctrls)
        parts = ["# #{title}\n", "Total: #{ctrls.size} controllers\n"]
        ctrls.sort_by { |c| c[:name] }.each { |c| parts << "- `#{c[:name]}` — `#{c[:file]}`" }
        parts << ""

        # Match routes to these controllers
        ctrl_prefixes = ctrls.map { |c| c[:name].underscore.gsub("::", "/").gsub(/_controller$/, "") }
        matched_routes = @routes.values.flatten.select do |r|
          ctrl_prefixes.any? { |p| r[:controller] == p || r[:controller]&.start_with?("#{p}/") }
        end

        if matched_routes.any?
          parts << "## Endpoints (#{matched_routes.size})\n"
          parts << "| Method | Path | Action |"
          parts << "|--------|------|--------|"
          matched_routes.first(80).each { |r| parts << "| #{r[:verb]} | `#{r[:path]}` | `#{r[:controller]}##{r[:action]}` |" }
          parts << "| ... | ... | ... |" if matched_routes.size > 80
        end

        parts.join("\n")
      end

      # ================================================================
      # JOB REFERENCE DOCUMENTS
      # ================================================================

      def generate_job_references
        return [] if @jobs.empty?

        docs = []
        ai_jobs = jobs_for_prefix("Ai") + @jobs.fetch("Root", []).select { |j| j[:name].start_with?("Ai") }
        docs << { name: "AI Worker Jobs Reference", content: build_list_reference("AI Worker Jobs Reference", ai_jobs.uniq { |j| j[:name] }, "job"), category: "detail" } if ai_jobs.any?

        other = @jobs.flat_map { |ns, js| (ns == "Ai" || ns.start_with?("Ai::")) ? [] : js }
                     .reject { |j| j[:name].start_with?("Ai") }
        docs << { name: "Platform Worker Jobs Reference", content: build_list_reference("Platform Worker Jobs Reference", other, "job"), category: "detail" } if other.any?

        docs
      end

      # ================================================================
      # STATIC REFERENCE DOCUMENTS
      # ================================================================

      def generate_static_references
        [
          generate_frontend_reference,
          generate_conventions_reference,
          generate_testing_reference,
          generate_database_schema_reference
        ].compact
      end

      def generate_frontend_reference
        return nil if @features.empty?

        parts = ["# Frontend Architecture Reference\n",
                 "React TypeScript SPA with feature-based directory structure.\n"]
        @features.each do |name, info|
          parts << "## #{name}"
          parts << "- **Files**: #{info[:file_count]}"
          parts << "- **Subdirectories**: #{info[:subdirectories].join(', ')}" if info[:subdirectories].any?
          parts << ""
        end

        { name: "Frontend Architecture Reference", content: parts.join("\n"), category: "detail" }
      end

      def generate_conventions_reference
        { name: "Development Conventions Reference", category: "detail", content: <<~MD }
          # Development Conventions Reference

          ## Backend Conventions
          - `# frozen_string_literal: true` pragma required in every Ruby file
          - Use `render_success()` and `render_error()` for all API responses — never `render json:` directly
          - Controllers in `Api::V1` namespace, inherit `ApplicationController`
          - Use `Rails.logger` — never `puts` or `print`
          - JSON columns: always use lambda defaults `default: -> { {} }` — never `default: {}`
          - Eager loading: always `.includes()` when iterating associations
          - Controller size limit: 300 lines max — extract to services
          - Webhook receivers must return 200/202 on processing errors (never 500)
          - Namespaced models: `class_name: "Ai::Agent"` not `"AiAgent"`; always pair with `foreign_key:`

          ## Frontend Conventions
          - Theme classes only: `bg-theme-*`, `text-theme-*` (never hardcoded colors)
          - Permission-based access: `currentUser?.permissions?.includes('name')` — never roles
          - No `console.log` in production — use `logger` utility
          - No `any` types — proper TypeScript types required
          - Path aliases: `@/shared/`, `@/features/` for cross-feature imports
          - Actions in PageContainer only — none in page content
          - Global notifications only — no local success/error state
          - Flat navigation — no submenus

          ## Migration Conventions
          - UUIDv7 primary keys on all tables
          - Never separate `add_index` for `t.references` — use inline `index:` option
          - Namespace FK prefixes: `Ai::` → `ai_`, `Devops::` → `ci_cd_`, `BaaS::` → `baas_`
          - Named routes before `/:id` to avoid matching conflicts

          ## Git Conventions
          - Branch strategy: `develop` → `feature/*` → `release/*` → `master`
          - Tag naming: no "v" prefix — `0.2.0` not `v0.2.0`
          - Staged commits: group by concern (models, services, controllers, frontend, tests)

          ## Service Architecture
          - Worker communicates with server via HTTP API only — jobs in `worker/app/jobs/`
          - Systemd service management — never manual commands
          - Enterprise features via git submodule at `extensions/enterprise/`
          - Ports: backend=3000, frontend=3001, worker-web=4567
        MD
      end

      def generate_testing_reference
        { name: "Testing Patterns Reference", category: "detail", content: <<~MD }
          # Testing Patterns Reference

          ## RSpec Patterns
          - Run: `cd server && bundle exec rspec --format progress`
          - DatabaseCleaner with `:deletion` strategy (avoids TRUNCATE deadlocks)
          - Never run multiple rspec processes concurrently on same database
          - Transactional fixtures — each test rolls back automatically

          ## Test Helpers
          - `user_with_permissions('perm.name')` — creates user with permission (from `permission_test_helpers.rb`)
          - `auth_headers_for(user)` — returns `{ Authorization: 'Bearer ...' }`
          - `json_response`, `json_response_data` — parse response body
          - `expect_success_response(data)`, `expect_error_response(msg, status)`

          ## Shared Examples
          - `include_examples 'requires authentication'` — verifies auth required
          - `include_examples 'requires permission'` — verifies permission check
          - `include_examples 'scopes to current account'` — verifies tenant isolation

          ## AI Test Helpers
          - `ProviderHelpers`, `AgentHelpers`, `WorkflowHelpers`, `SecurityHelpers` (spec/support/ai_test_helpers.rb)
          - `be_a_valid_ai_response` — validates response structure
          - `have_execution_status(:status)` — checks execution
          - `create_audit_log(:action)` — verifies audit logging

          ## Factories
          - Located in `spec/factories/`, AI factories in `spec/factories/ai/`
          - Common traits: `:active`, `:paused`, `:archived`
          - Always use existing factories — never create users manually

          ## E2E Testing
          - Page objects in `e2e/pages/` and `e2e/pages/ai/`
          - Selectors: `data-testid` first, then `class*="pattern"`, then `getByRole`
          - Error suppression: `page.on('pageerror', () => {})` in `beforeEach`
          - Run: `cd frontend && CI=true npm test`
        MD
      end

      def generate_database_schema_reference
        all_models = @models.values.flatten
        return nil if all_models.empty?

        tables = all_models.map { |m| m[:table_name] }.uniq.sort
        parts = ["# Database Schema Overview\n", "Total tables: #{tables.size}\n"]

        parts << "## Tables\n"
        tables.each do |table|
          model = all_models.find { |m| m[:table_name] == table }
          next unless model

          col_summary = model[:columns].reject { |c| %w[id created_at updated_at].include?(c[:name]) }
                                       .map { |c| "`#{c[:name]}` (#{c[:type]})" }
                                       .first(10).join(", ")
          parts << "- **#{table}** (#{model[:name]}): #{col_summary}"
        end

        { name: "Database Schema Overview", content: parts.join("\n"), category: "detail" }
      end

      # ================================================================
      # SHARED BUILDER
      # ================================================================

      def build_list_reference(title, items, kind)
        parts = ["# #{title}\n", "Total: #{items.size} #{kind.pluralize}\n"]
        items.sort_by { |i| i[:name] }.each { |i| parts << "- `#{i[:name]}` — `#{i[:file]}`" }
        parts.join("\n")
      end
    end
  end
end
