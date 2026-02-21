# frozen_string_literal: true

module Ai
  module KnowledgePopulation
    # Orchestrates population of all three knowledge stores:
    #   1. RAG Knowledge Base  — markdown documents for hybrid search
    #   2. Shared Knowledge    — quick-reference facts and conventions
    #   3. Knowledge Graph     — structural node/edge relationships
    #
    # Every operation is idempotent: existing documents are skipped,
    # shared knowledge dedup is at 0.92 similarity, and graph nodes/edges
    # use find-or-create + unique constraints.
    class PopulatorService
      TRUSTED_QUALITY_THRESHOLD = 0.75
      KB_NAME = "Platform Specification"

      def initialize(account:)
        @account = account
        @rag_service = Ai::RagService.new(account)
        @shared_knowledge_service = Ai::Memory::SharedKnowledgeService.new(account: account)
        @stats = { rag: {}, shared: {}, graph: {} }
      end

      attr_reader :stats

      # ================================================================
      # ORCHESTRATION
      # ================================================================

      def populate_all!
        scan_data = scan_codebase

        populate_rag!(scan_data)
        populate_shared!
        populate_graph!(scan_data)

        @stats
      end

      def populate_rag!(scan_data = nil)
        scan_data ||= scan_codebase
        documents = DocumentGeneratorService.new(scan_data).generate_all

        kb = find_or_create_knowledge_base

        created = 0
        skipped = 0
        failed = 0

        documents.each do |doc|
          if kb.documents.exists?(name: doc[:name])
            skipped += 1
            next
          end

          begin
            record = @rag_service.create_document(
              kb.id,
              {
                name: doc[:name],
                source_type: "api",
                content_type: "text/markdown",
                content: doc[:content],
                metadata: { category: doc[:category], generated_at: Time.current.iso8601 }
              }
            )

            @rag_service.process_document(kb.id, record.id)
            @rag_service.embed_chunks(kb.id, document_id: record.id)

            created += 1
            Rails.logger.info("[KnowledgePopulation] RAG doc created: '#{doc[:name]}' (#{created}/#{documents.size})")
          rescue StandardError => e
            failed += 1
            Rails.logger.error("[KnowledgePopulation] RAG doc failed '#{doc[:name]}': #{e.message}")
          end
        end

        @stats[:rag] = { created: created, skipped: skipped, failed: failed, total: documents.size }
      end

      def populate_shared!
        entries = shared_entries
        created = 0
        skipped = 0

        entries.each do |entry|
          result = @shared_knowledge_service.create(
            title: entry[:title],
            content: entry[:content],
            content_type: entry[:content_type],
            access_level: "account",
            tags: entry[:tags],
            metadata: { category: entry[:category], populated_by: "knowledge_population" },
            source_type: "manual"
          )

          if result[:success]
            created += 1
          else
            skipped += 1
          end
        end

        @stats[:shared] = { created: created, skipped: skipped, total: entries.size }
      end

      def populate_graph!(scan_data = nil)
        scan_data ||= scan_codebase
        builder = GraphBuilderService.new(account: @account, scan_data: scan_data)
        builder.build!
        @stats[:graph] = builder.stats
      end

      private

      def scan_codebase
        @scan_data ||= ScannerService.new.scan!
      end

      def find_or_create_knowledge_base
        existing = @account.ai_knowledge_bases.find_by(name: KB_NAME)
        return existing if existing

        @rag_service.create_knowledge_base({
          name: KB_NAME,
          description: "Comprehensive platform specification generated from codebase reflection. " \
                       "Contains architecture, model references, API endpoints, conventions, and patterns.",
          chunking_strategy: "recursive",
          chunk_size: 1000,
          chunk_overlap: 200
        })
      end

      # ==============================================================
      # SHARED KNOWLEDGE ENTRIES (~60)
      # ==============================================================

      def shared_entries
        development_conventions +
          architecture_decisions +
          testing_patterns +
          common_gotchas +
          migration_rules +
          api_patterns +
          service_patterns
      end

      # -- Development Conventions (~15) ----------------------------

      def development_conventions
        [
          sk("Mandatory render_success and render_error",
             "All Rails API controllers must use render_success() and render_error() for responses. " \
             "Never use render json: directly. These helpers ensure consistent API response format.",
             "procedure", %w[backend controller api], "convention"),

          sk("Frozen string literal pragma required",
             "Every Ruby file must begin with `# frozen_string_literal: true`. " \
             "Improves performance and prevents accidental string mutation.",
             "procedure", %w[backend ruby style], "convention"),

          sk("Theme classes only for styling",
             "Frontend must use theme-aware CSS classes: bg-theme-*, text-theme-*, border-theme-*. " \
             "Never hardcode colors. Ensures dark mode and custom themes work correctly.",
             "procedure", %w[frontend css theme], "convention"),

          sk("Permission-based access control never roles",
             "Frontend: currentUser?.permissions?.includes('users.manage'). " \
             "Backend: current_user.has_permission?('name') — never permissions.include?() (returns objects). " \
             "Never check roles for access control decisions.",
             "procedure", %w[security permissions frontend backend], "convention"),

          sk("No console.log in production frontend",
             "Use logger utility: import { logger } from '@/shared/utils/logger'. " \
             "Never use console.log in production. Logger respects environment settings.",
             "procedure", %w[frontend logging], "convention"),

          sk("No any types in TypeScript",
             "TypeScript code must use proper types — never `any`. " \
             "Define interfaces and types for all data structures.",
             "procedure", %w[frontend typescript], "convention"),

          sk("Rails.logger only no puts or print",
             "Backend: Rails.logger (info, warn, error, debug). " \
             "Never puts, print, or p in production code.",
             "procedure", %w[backend logging], "convention"),

          sk("Path aliases for cross-feature imports",
             "Frontend: @/shared/ for shared utilities, @/features/ for feature code. " \
             "Enterprise: @enterprise/ for intra-enterprise imports.",
             "procedure", %w[frontend imports], "convention"),

          sk("Global notifications only no local state",
             "Frontend success/error feedback uses global notification system only. " \
             "Never local component state for success/error messages.",
             "procedure", %w[frontend ux], "convention"),

          sk("Actions in PageContainer only",
             "Frontend page actions (buttons, links) go in PageContainer's actions prop. " \
             "Never add action buttons in page content area.",
             "procedure", %w[frontend layout], "convention"),

          sk("Flat navigation structure",
             "Frontend navigation: flat structure, no nested submenus. " \
             "Each nav item links directly to a page. Sub-navigation within pages via sections.",
             "procedure", %w[frontend navigation], "convention"),

          sk("Controller size limit 300 lines",
             "Rails controllers: max 300 lines. Extract query logic to services, " \
             "serialization to concerns. Keep controllers focused on request handling.",
             "procedure", %w[backend controller architecture], "convention"),

          sk("Eager loading with includes required",
             "Always .includes() when iterating associations. " \
             "Never bare .all followed by .map/.each accessing relations without eager loading.",
             "procedure", %w[backend performance database], "convention"),

          sk("Webhook receivers return 200 on errors",
             "Inbound webhook endpoints return 200 or 202 on processing errors — never 500. " \
             "500 causes provider retry storms (Stripe, PayPal will retry repeatedly).",
             "procedure", %w[backend webhooks api], "convention"),

          sk("JSON columns use lambda defaults",
             "ActiveRecord JSON columns: `attribute :config, :json, default: -> { {} }`. " \
             "Never `default: {}` — shares mutable object across instances.",
             "procedure", %w[backend database activerecord], "convention")
        ]
      end

      # -- Architecture Decisions (~10) ----------------------------

      def architecture_decisions
        [
          sk("UUIDv7 primary keys on all tables",
             "All database tables use UUIDv7 primary keys. Time-ordered, globally unique, " \
             "index-friendly identifiers supporting distributed systems.",
             "fact", %w[database architecture], "architecture"),

          sk("Worker HTTP API only architecture",
             "Worker (Sidekiq at worker/) is standalone, communicating with server via HTTP API only. " \
             "Jobs in worker/app/jobs/ — never server/app/jobs/. Server does NOT run Sidekiq.",
             "fact", %w[architecture worker sidekiq], "architecture"),

          sk("Enterprise submodule pattern",
             "Enterprise features at extensions/enterprise/ (git submodule). When absent, app runs " \
             "single-user self-hosted, all features unlocked. Gate: " \
             "Shared::FeatureGateService.enterprise_loaded? (backend), __ENTERPRISE__ (frontend).",
             "fact", %w[architecture enterprise], "architecture"),

          sk("Rails 8 API only mode",
             "Backend is Rails 8 API-only. No views, no asset pipeline. " \
             "All responses are JSON via render_success/render_error.",
             "fact", %w[architecture rails], "architecture"),

          sk("Systemd service management",
             "Services via systemd template units: powernode-backend@, powernode-worker@, " \
             "powernode-frontend@, powernode.target. Install: sudo scripts/systemd/powernode-installer.sh install. " \
             "Never use manual commands (rails server, sidekiq, npm start).",
             "procedure", %w[infrastructure systemd], "architecture"),

          sk("Redis database separation",
             "Worker uses Redis DB 1 (redis://localhost:6379/1). " \
             "Server uses Redis DB 0 for caching/sessions. Prevents key collisions.",
             "fact", %w[infrastructure redis], "architecture"),

          sk("JWT authentication system",
             "JWT tokens with configurable expiry. Issued on login, validated per request. " \
             "Frontend stores tokens in Authorization headers.",
             "fact", %w[security authentication], "architecture"),

          sk("PostgreSQL with pgvector extension",
             "PostgreSQL with pgvector for vector similarity search. " \
             "neighbor gem (0.6.0) provides Rails integration. " \
             "HNSW indexes (not IVFFlat) — works on empty tables.",
             "fact", %w[database pgvector ai], "architecture"),

          sk("HNSW indexes for vector search",
             "Vector columns use HNSW indexes (not IVFFlat). " \
             "IVFFlat requires training data, HNSW works on empty tables with good performance.",
             "fact", %w[database pgvector performance], "architecture"),

          sk("Feature flags via Flipper",
             "Feature flags via Flipper: Flipper.enabled?(:feature_name) or Flipper.enabled?(:feature_name, actor). " \
             "Notable: :compound_learning_injection, :compound_learning_promotion.",
             "fact", %w[architecture feature-flags], "architecture")
        ]
      end

      # -- Testing Patterns (~10) ---------------------------------

      def testing_patterns
        [
          sk("user_with_permissions test helper",
             "Create test users: user_with_permissions('perm.name') from permission_test_helpers.rb. " \
             "Creates user, role, assigns permission. Never create users manually.",
             "snippet", %w[testing rspec helpers], "testing"),

          sk("auth_headers_for test helper",
             "Auth headers: auth_headers_for(user) returns { Authorization: 'Bearer ...' }. " \
             "Use in all authenticated request specs.",
             "snippet", %w[testing rspec authentication], "testing"),

          sk("DatabaseCleaner deletion strategy",
             "Tests use DatabaseCleaner with :deletion (not :truncation). " \
             "TRUNCATE requires AccessExclusiveLock causing deadlocks. DELETE uses RowExclusiveLock.",
             "fact", %w[testing database performance], "testing"),

          sk("E2E page object model pattern",
             "E2E tests use page objects in e2e/pages/ and e2e/pages/ai/. " \
             "Page objects encapsulate selectors and interactions. Always use existing ones.",
             "procedure", %w[testing e2e playwright], "testing"),

          sk("AI test matchers",
             "Custom matchers: be_a_valid_ai_response, have_execution_status(:status), " \
             "create_audit_log(:action). In spec/support/ai_matchers.rb.",
             "snippet", %w[testing rspec ai], "testing"),

          sk("Shared examples for common test patterns",
             "Shared examples: 'requires authentication', 'requires permission', " \
             "'scopes to current account'. In spec/support/shared_examples/.",
             "snippet", %w[testing rspec shared-examples], "testing"),

          sk("Factory traits for model states",
             "Factories support :active, :paused, :archived traits. " \
             "AI factories in spec/factories/ai/.",
             "snippet", %w[testing factories rspec], "testing"),

          sk("CI=true for frontend tests",
             "Frontend tests: cd frontend && CI=true npm test. " \
             "Non-interactive mode for consistent CI behavior.",
             "procedure", %w[testing frontend ci], "testing"),

          sk("No parallel test processes",
             "Never run multiple rspec processes on same database. " \
             "parallel_tests removed due to TRUNCATE deadlocks. Single process only.",
             "fact", %w[testing database parallel], "testing"),

          sk("data-testid selectors for E2E",
             "E2E selector priority: data-testid first, class*=\"pattern\" second, getByRole third. " \
             "Add data-testid to new components.",
             "procedure", %w[testing e2e selectors], "testing")
        ]
      end

      # -- Common Gotchas (~10) ------------------------------------

      def common_gotchas
        [
          sk("pgvector neighbor_distance is virtual column",
             "neighbor_distance is a virtual column from nearest_neighbors() — cannot use in WHERE. " \
             "Load results first, then filter in Ruby. Or check exists? before querying.",
             "fact", %w[pgvector gotcha database], "gotcha"),

          sk("SharedKnowledge uses provenance not metadata",
             "Ai::SharedKnowledge uses `provenance` column (not `metadata`). " \
             "Always entry.provenance, not entry.metadata.",
             "fact", %w[ai gotcha model], "gotcha"),

          sk("Gitea slashed branch refs need resolve_ref",
             "Gitea contents API fails for slashed refs (mission/feature-name). " \
             "GiteaApiClient#resolve_ref converts to commit SHA via get_branch first.",
             "fact", %w[gitea gotcha devops], "gotcha"),

          sk("RVM and systemd never use set -u",
             "Never set -u (nounset) when sourcing RVM in systemd — uses uninitialized vars. " \
             "Use set -eo pipefail only. Also use POWERNODE_RUBY_VERSION (not RUBY_VERSION).",
             "fact", %w[systemd rvm gotcha], "gotcha"),

          sk("StartLimitIntervalSec belongs in Unit section",
             "Systemd: StartLimitIntervalSec and StartLimitBurst belong in [Unit], not [Service]. " \
             "Placing in [Service] silently ignores them.",
             "fact", %w[systemd gotcha infrastructure], "gotcha"),

          sk("ProtectSystem strict blocks home directory",
             "ProtectSystem=strict makes filesystem read-only. " \
             "Don't use in dev mode — blocks home directory and project files.",
             "fact", %w[systemd gotcha security], "gotcha"),

          sk("find_default_agent picks arbitrary order",
             "find_default_agent picks first active agent by arbitrary DB order. " \
             "May select Ollama over Grok. Set default_agent explicitly on RalphLoop.",
             "fact", %w[ai gotcha agent], "gotcha"),

          sk("compare_commits empty for slashed branches",
             "Gitea compare_commits API returns empty for slashed branch names. " \
             "Use list_commits as workaround.",
             "fact", %w[gitea gotcha devops], "gotcha"),

          sk("PiiRedactionService thresholds",
             "REDACTION_THRESHOLDS['restricted'] = 'pci' — only PCI-classified data redacted. " \
             "PII-classified data is not redacted. Intentional: PCI has stricter requirements.",
             "fact", %w[security gotcha pii], "gotcha"),

          sk("RalphTask has no name column",
             "RalphTask: use task_key (identifier) and description (details). " \
             "No name column. No key shortcut — always task_key.",
             "fact", %w[ai gotcha ralph], "gotcha")
        ]
      end

      # -- Migration Rules (~5) ------------------------------------

      def migration_rules
        [
          sk("Never separate indexes for t.references",
             "t.references auto-creates an index. Never add_index separately. " \
             "Customize inline: t.references :account, index: { unique: true }.",
             "procedure", %w[migration database index], "migration"),

          sk("Namespace foreign key prefixes",
             "FK naming: Ai:: → ai_ (ai_agent_id), Devops:: → ci_cd_ (ci_cd_pipeline_id), " \
             "BaaS:: → baas_ (baas_customer_id). Others: explicit FK or omit if unambiguous.",
             "procedure", %w[migration database naming], "migration"),

          sk("Always pair class_name with foreign_key",
             "Associations with class_name: must also specify foreign_key:. " \
             "Example: belongs_to :provider, class_name: 'Ai::Provider', foreign_key: 'ai_provider_id'.",
             "procedure", %w[migration associations activerecord], "migration"),

          sk("Namespaced model class_name uses double colon",
             "Use :: separator in class_name: — 'Ai::AgentTeam' not 'AiAgentTeam'. " \
             "Rails won't find the class without ::.",
             "procedure", %w[migration activerecord naming], "migration"),

          sk("Named routes before id parameter routes",
             "Place named routes (string segments) before /:id in routes.rb. " \
             "Otherwise :id matches the named route's string.",
             "procedure", %w[routes rails], "migration")
        ]
      end

      # -- API Patterns (~5) --------------------------------------

      def api_patterns
        [
          sk("Api V1 namespace for all controllers",
             "All API controllers: Api::V1 namespace, inherit ApplicationController. " \
             "Route prefix: /api/v1/. Enables API versioning.",
             "procedure", %w[api controller namespace], "api"),

          sk("Paginatable concern for collections",
             "Collection endpoints use Paginatable concern. " \
             "Supports page/per_page params. Returns pagination metadata.",
             "procedure", %w[api pagination], "api"),

          sk("Rate limiting on API endpoints",
             "API endpoints have rate limiting. Stricter on auth endpoints, " \
             "relaxed on data retrieval. Configured per-endpoint.",
             "fact", %w[api security rate-limiting], "api"),

          sk("Consistent error response format",
             "Errors via render_error with message and status. " \
             "Format: { success: false, error: { message: '...', code: '...' } }.",
             "procedure", %w[api errors response], "api"),

          sk("Service ports for platform components",
             "Default ports: backend=3000, frontend=3001, worker-web=4567. " \
             "Configured in systemd environment files at /etc/powernode/.",
             "fact", %w[infrastructure ports services], "api")
        ]
      end

      # -- Service Patterns (~5) ----------------------------------

      def service_patterns
        [
          sk("BaseAiService concern for AI services",
             "AI services include BaseAiService concern for common functionality: " \
             "account scoping, error handling, logging. At server/app/services/ai/concerns/.",
             "procedure", %w[ai service pattern], "service"),

          sk("Feature flags via Flipper for AI features",
             "AI flags via Flipper: :compound_learning_injection, :compound_learning_promotion. " \
             "Extraction always runs regardless of flags.",
             "procedure", %w[ai feature-flags flipper], "service"),

          sk("Circuit breaker pattern for external services",
             "External calls use circuit breaker (Ai::CircuitBreaker model). " \
             "Tracks failures, opens when threshold exceeded, prevents cascading failures.",
             "procedure", %w[resilience pattern circuit-breaker], "service"),

          sk("Embedding service with Redis caching",
             "Ai::Memory::EmbeddingService: vector embeddings with Redis cache (7-day TTL). " \
             "OpenAI text-embedding-3-small (1536d) or Ollama. Key: ai:embeddings:{account}:{hash}.",
             "fact", %w[ai embeddings caching], "service"),

          sk("Cosine distance for semantic search",
             "pgvector cosine distance: nearest_neighbors(:embedding, v, distance: 'cosine'). " \
             "neighbor_distance: 0=identical, 2=opposite. Similarity = 1 - distance. " \
             "Threshold: where('neighbor_distance <= ?', 1.0 - threshold).",
             "snippet", %w[ai pgvector search], "service")
        ]
      end

      # Helper to build an entry hash
      def sk(title, content, content_type, tags, category)
        { title: title, content: content, content_type: content_type, tags: tags, category: category }
      end
    end
  end
end
