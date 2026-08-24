# frozen_string_literal: true

module Ai
  module Tools
    class CodeMemoryTool < BaseTool
      include Concerns::CodebaseContextResolvable

      REQUIRED_PERMISSION = "ai.agents.read"

      # === Per-action permission gating (G4) ===
      #
      # This tool bundled WRITE and DESTRUCTIVE actions behind a single coarse
      # REQUIRED_PERMISSION of "ai.agents.read", and performed no check of its
      # own — so holding a READ permission was sufficient to run every one of
      # them. Proven by execution before the fix, with row oracles rather than
      # error strings.
      #
      # REST twin: KnowledgeGraphController gates reads on
      # ai.knowledge_graph.read and writes on ai.knowledge_graph.manage
      # (knowledge_graph_controller.rb:12-14).
      #
      # Keyed on the action that RUNS, never on the invoked NAME: a user
      # principal is deliberately not pinned to the tool name
      # (McpPlatformToolRegistrar#action_pinned_to_name?), so a name-keyed check
      # is bypassable by supplying a sibling :action.
      ACTION_PERMISSIONS = {
        "upsert_node" => "ai.knowledge_graph.manage",
        "create_relation" => "ai.knowledge_graph.manage",
        "bulk_index" => "ai.knowledge_graph.manage",
        "prune_stale" => "ai.knowledge_graph.manage"
      }.freeze


      CODE_ENTITY_TYPES = %w[file directory class module method function variable type_definition interface constant].freeze
      CODE_RELATION_TYPES = %w[imports calls defines inherits implements contains related_to depends_on uses].freeze

      def self.definition
        {
          name: "code_memory",
          description: "Code-aware memory graph operations: create/update code nodes, create relations, search the code graph, prune stale links, and trigger bulk indexing",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            repository_id: { type: "string", required: false, description: "Git repository ID, name, or full_name" },
            base_path: { type: "string", required: false, description: "Filesystem path to codebase root" },
            name: { type: "string", required: false, description: "Node name" },
            entity_type: { type: "string", required: false, description: "Entity type (class, method, function, etc.)" },
            file_path: { type: "string", required: false, description: "File path" },
            line_range: { type: "string", required: false, description: "Line range (e.g. '10-25')" },
            description: { type: "string", required: false, description: "Node description" },
            properties: { type: "object", required: false, description: "Additional properties" },
            source_node_id: { type: "string", required: false, description: "Source node ID (for create_relation)" },
            target_node_id: { type: "string", required: false, description: "Target node ID (for create_relation)" },
            relation_type: { type: "string", required: false, description: "Relation type" },
            weight: { type: "number", required: false, description: "Edge weight 0-1 (default 1.0)" },
            query: { type: "string", required: false, description: "Search query" },
            entity_types: { type: "array", required: false, description: "Filter by entity types" },
            max_depth: { type: "integer", required: false, description: "Graph traversal depth (default 2)" },
            top_k: { type: "integer", required: false, description: "Max results (default 10)" },
            dry_run: { type: "boolean", required: false, description: "Preview without executing (default true)" },
            path: { type: "string", required: false, description: "Subdirectory to index" },
            incremental: { type: "boolean", required: false, description: "Incremental indexing (default true)" }
          }
        }
      end

      def self.action_definitions
        {
          "code_upsert_node" => {
            description: "Create or update a code-aware knowledge graph node. Auto-generates embeddings for semantic search.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              name: { type: "string", required: true, description: "Qualified node name (e.g. 'User#full_name')" },
              entity_type: { type: "string", required: true, description: "Entity type: #{CODE_ENTITY_TYPES.join(', ')}" },
              file_path: { type: "string", required: false, description: "File path relative to codebase root" },
              line_range: { type: "string", required: false, description: "Line range (e.g. '10-25')" },
              description: { type: "string", required: false, description: "Human-readable description" },
              properties: { type: "object", required: false, description: "Additional metadata" }
            }
          },
          "code_create_relation" => {
            description: "Create a typed edge between two code nodes (e.g. imports, calls, inherits).",
            parameters: {
              source_node_id: { type: "string", required: true, description: "Source node ID" },
              target_node_id: { type: "string", required: true, description: "Target node ID" },
              relation_type: { type: "string", required: true, description: "Relation type: #{CODE_RELATION_TYPES.join(', ')}" },
              weight: { type: "number", required: false, description: "Edge weight 0-1 (default 1.0)" },
              properties: { type: "object", required: false, description: "Edge metadata" }
            }
          },
          "code_search_graph" => {
            description: "Search the code graph with optional multi-hop traversal. Combines name matching with graph expansion.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              query: { type: "string", required: true, description: "Search query" },
              entity_types: { type: "array", required: false, description: "Filter by entity types" },
              max_depth: { type: "integer", required: false, description: "Graph traversal depth (default 2)" },
              top_k: { type: "integer", required: false, description: "Max results (default 10)" }
            }
          },
          "code_prune_stale" => {
            description: "Find and remove/archive code nodes for files that no longer exist on disk (async — dispatched to the worker; result written to shared memory, retrieve via read_shared_memory). Use dry_run to preview.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              dry_run: { type: "boolean", required: false, description: "Preview without executing (default true)" }
            }
          },
          "code_bulk_index" => {
            description: "Trigger codebase indexing (async — dispatched to the worker; returns immediately). Parses source files, creates knowledge graph nodes/edges, and generates embeddings. Track progress with code_index_status.",
            parameters: {
              repository_id: { type: "string", required: false, description: "Git repository ID, name, or full_name" },
              base_path: { type: "string", required: false, description: "Filesystem path to codebase root" },
              path: { type: "string", required: false, description: "Subdirectory to index (default: entire codebase)" },
              incremental: { type: "boolean", required: false, description: "Only re-index changed files (default true)" }
            }
          }
        }
      end

      protected

      def call(params)
        action = params[:action].to_s

        unless action_permitted?(action)
          Rails.logger.warn(
            "[CodeMemoryTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case params[:action]
        when "upsert_node" then upsert_node(params)
        when "create_relation" then create_relation(params)
        when "search_graph" then search_graph(params)
        when "prune_stale" then prune_stale(params)
        when "bulk_index" then bulk_index(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      rescue ArgumentError => e
        { success: false, error: e.message }
      end

      private

      # ─── Upsert Node ──────────────────────────────────────────────

      def upsert_node(params)
        return { success: false, error: "name is required" } if params[:name].blank?
        return { success: false, error: "entity_type is required" } if params[:entity_type].blank?

        unless CODE_ENTITY_TYPES.include?(params[:entity_type])
          return { success: false, error: "Invalid entity_type. Valid: #{CODE_ENTITY_TYPES.join(', ')}" }
        end

        _repo, kb, _bp = resolve_project_context(params)

        properties = (params[:properties] || {}).merge({})
        properties["file_path"] = params[:file_path] if params[:file_path].present?

        if params[:line_range].present?
          parts = params[:line_range].split("-")
          properties["line_start"] = parts[0].to_i
          properties["line_end"] = parts[1]&.to_i || parts[0].to_i
        end

        existing = kb.knowledge_graph_nodes.find_by(
          account: account, name: params[:name], node_type: "code_entity", status: "active"
        )

        if existing
          existing.update!(
            entity_type: params[:entity_type],
            description: params[:description] || existing.description,
            properties: existing.properties.merge(properties),
            last_seen_at: Time.current
          )
          existing.record_mention!

          # Regenerate embedding if description changed
          if params[:description].present?
            embedding = generate_embedding("#{existing.name} #{existing.description}")
            existing.set_embedding!(embedding) if embedding
          end

          { success: true, action: "updated", node: serialize_node(existing) }
        else
          node = kb.knowledge_graph_nodes.create!(
            account: account,
            name: params[:name],
            node_type: "code_entity",
            entity_type: params[:entity_type],
            description: params[:description],
            properties: properties,
            status: "active",
            confidence: 1.0,
            mention_count: 1,
            last_seen_at: Time.current
          )

          # Generate embedding
          if params[:description].present?
            embedding = generate_embedding("#{node.name} #{node.description}")
            node.set_embedding!(embedding) if embedding
          end

          { success: true, action: "created", node: serialize_node(node) }
        end
      end

      # ─── Create Relation ───────────────────────────────────────────

      def create_relation(params)
        return { success: false, error: "source_node_id is required" } if params[:source_node_id].blank?
        return { success: false, error: "target_node_id is required" } if params[:target_node_id].blank?
        return { success: false, error: "relation_type is required" } if params[:relation_type].blank?

        unless CODE_RELATION_TYPES.include?(params[:relation_type])
          return { success: false, error: "Invalid relation_type. Valid: #{CODE_RELATION_TYPES.join(', ')}" }
        end

        source = Ai::KnowledgeGraphNode.find_by(id: params[:source_node_id], account: account, status: "active")
        target = Ai::KnowledgeGraphNode.find_by(id: params[:target_node_id], account: account, status: "active")

        return { success: false, error: "Source node not found" } unless source
        return { success: false, error: "Target node not found" } unless target

        existing = Ai::KnowledgeGraphEdge.find_by(
          account: account, source_node: source, target_node: target,
          relation_type: params[:relation_type], status: "active"
        )

        if existing
          existing.update!(
            weight: params[:weight] || existing.weight,
            properties: existing.properties.merge(params[:properties] || {})
          )
          { success: true, action: "updated", edge: serialize_edge(existing) }
        else
          edge = Ai::KnowledgeGraphEdge.create!(
            account: account,
            source_node: source,
            target_node: target,
            relation_type: params[:relation_type],
            weight: params[:weight] || 1.0,
            confidence: 1.0,
            properties: params[:properties] || {},
            status: "active"
          )
          { success: true, action: "created", edge: serialize_edge(edge) }
        end
      end

      # ─── Search Graph ──────────────────────────────────────────────

      def search_graph(params)
        return { success: false, error: "query is required" } if params[:query].blank?

        _repo, kb, _bp = resolve_project_context(params)
        top_k = (params[:top_k] || 10).to_i
        max_depth = (params[:max_depth] || 2).to_i
        entity_types = Array(params[:entity_types]).presence

        query = ActiveRecord::Base.sanitize_sql_like(params[:query])

        scope = kb.knowledge_graph_nodes
                   .where(account: account, node_type: "code_entity", status: "active")

        scope = scope.where(entity_type: entity_types) if entity_types

        # Name + description search
        matches = scope.where("name ILIKE :q OR description ILIKE :q OR properties->>'simple_name' ILIKE :q",
                              q: "%#{query}%")
                       .order(mention_count: :desc)
                       .limit(top_k)

        graph_service = Ai::KnowledgeGraph::GraphService.new(account)

        results = matches.map do |node|
          entry = serialize_node(node)

          # Optionally expand neighbors
          if max_depth > 0
            neighbors = graph_service.find_neighbors(node: node.id, depth: [max_depth, 3].min)
            entry[:neighbors] = neighbors.first(10)
          end

          entry
        end

        { success: true, results: results, count: results.size, query: params[:query] }
      end

      # ─── Prune Stale ───────────────────────────────────────────────

      def prune_stale(params)
        _repo, _kb, bp = resolve_project_context(params)
        dry_run = params[:dry_run] != false # default true
        result_key = "code_intel.prune_stale.#{params[:repository_id].presence || File.basename(bp)}"

        # Scans every indexed file node against disk (+ child nodes/edges) —
        # long-running on large repos → dispatch to the worker. The pruned-node
        # summary is written to the 'default' shared-memory pool under
        # result_key (retrieve via read_shared_memory). Logic lives in
        # Ai::Codebase::StalePruneService.
        WorkerJobService.enqueue_ai_code_analysis(
          operation: "prune_stale",
          account_id: account.id,
          base_path: bp,
          repository_id: params[:repository_id],
          result_key: result_key,
          options: { "dry_run" => dry_run }
        )

        {
          success: true,
          status: "enqueued",
          dry_run: dry_run,
          result_key: result_key,
          retrieve_via: "read_shared_memory(pool_id: 'default', key: '#{result_key}')",
          message: "Stale-node prune (#{dry_run ? 'dry run' : 'apply'}) dispatched to the worker."
        }
      end

      # ─── Bulk Index ────────────────────────────────────────────────

      def bulk_index(params)
        _repo, _kb, bp = resolve_project_context(params)
        incremental = params[:incremental] != false # default true

        # AST parse + embeddings across the whole repo is long-running →
        # dispatch to the worker (which drives the server's internal
        # /codebase/index endpoint). Returns immediately so the MCP call
        # never blocks or times out.
        WorkerJobService.enqueue_ai_codebase_index(
          account_id: account.id,
          base_path: bp,
          repository_id: params[:repository_id],
          path: params[:path],
          incremental: incremental
        )

        {
          success: true,
          status: "enqueued",
          message: "Codebase #{incremental ? 'incremental' : 'full'} re-index dispatched to the worker. Track progress with code_index_status.",
          base_path: bp,
          incremental: incremental
        }
      end

      # ─── Helpers ───────────────────────────────────────────────────

      def generate_embedding(text)
        embedding_service = Ai::Memory::EmbeddingService.new(account: account)
        embedding_service.generate(text)
      rescue => e
        Rails.logger.warn "[CodeMemoryTool] Embedding error: #{e.message}"
        nil
      end

      def serialize_node(node)
        {
          id: node.id,
          name: node.name,
          entity_type: node.entity_type,
          description: node.description,
          file_path: node.properties&.dig("file_path"),
          line_start: node.properties&.dig("line_start"),
          line_end: node.properties&.dig("line_end"),
          visibility: node.properties&.dig("visibility"),
          params: node.properties&.dig("params"),
          mention_count: node.mention_count,
          confidence: node.confidence
        }
      end

      def serialize_edge(edge)
        {
          id: edge.id,
          source_node_id: edge.source_node_id,
          target_node_id: edge.target_node_id,
          relation_type: edge.relation_type,
          weight: edge.weight,
          confidence: edge.confidence
        }
      end

      # Falls back to the class floor for read actions, which the registrar has
      # already enforced by the time this runs.
      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # Two explicit bypasses, matching the sibling tools' ladder: in-process
      # callers that opted in with `internal: true`, and an mTLS node principal
      # whose specific tool name already cleared Mcp::Principal#may_invoke?.
      # Never inferred from a nil user.
      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        # Compared against true rather than used for truthiness: nothing on the
        # MCP path coerces a permission answer.
        user.has_permission?(required_perm_for(action)) == true
      end

    end
  end
end
