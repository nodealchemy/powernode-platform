# frozen_string_literal: true

module Ai
  module KnowledgePopulation
    # Creates knowledge graph nodes and edges from scanner output.
    # Nodes represent namespaces, models, services, frontend features, and
    # architectural concepts.  Edges capture part_of, depends_on, and uses
    # relationships.  Idempotent: existing nodes are skipped, duplicate edges
    # are rescued via unique constraint.
    class GraphBuilderService
      def initialize(account:, scan_data:)
        @account = account
        @scan_data = scan_data
        @graph_service = Ai::KnowledgeGraph::GraphService.new(account)
        @node_cache = {}
        @stats = { nodes_created: 0, nodes_skipped: 0, edges_created: 0, edges_skipped: 0 }
      end

      attr_reader :stats

      def build!
        Rails.logger.info("[KnowledgePopulation] Building knowledge graph...")

        build_namespace_nodes
        build_model_nodes
        build_service_nodes
        build_frontend_nodes
        build_concept_nodes
        build_model_edges
        build_service_edges

        Rails.logger.info("[KnowledgePopulation] Graph complete — #{@stats.inspect}")
        @stats
      end

      private

      # ================================================================
      # IDEMPOTENT HELPERS
      # ================================================================

      def find_or_create_node(name:, node_type:, **attrs)
        cache_key = "#{name}:#{node_type}"
        return @node_cache[cache_key] if @node_cache[cache_key]

        existing = @account.ai_knowledge_graph_nodes
                           .find_by(name: name, node_type: node_type)
        if existing
          @node_cache[cache_key] = existing
          @stats[:nodes_skipped] += 1
          return existing
        end

        node = @graph_service.create_node(name: name, node_type: node_type, **attrs)
        @node_cache[cache_key] = node
        @stats[:nodes_created] += 1
        node
      rescue StandardError => e
        Rails.logger.warn("[KnowledgePopulation] Node create failed '#{name}': #{e.message}")
        @stats[:nodes_skipped] += 1
        nil
      end

      def safe_create_edge(source:, target:, relation_type:, **attrs)
        return if source.nil? || target.nil?

        @graph_service.create_edge(
          source: source, target: target,
          relation_type: relation_type, **attrs
        )
        @stats[:edges_created] += 1
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        @stats[:edges_skipped] += 1
      rescue StandardError => e
        @stats[:edges_skipped] += 1
        Rails.logger.warn("[KnowledgePopulation] Edge failed #{relation_type}: #{e.message}")
      end

      # ================================================================
      # NAMESPACE NODES (~10-16)
      # ================================================================

      def build_namespace_nodes
        @scan_data[:models].each_key do |namespace|
          next if namespace == "Root"

          model_count = @scan_data[:models][namespace]&.size || 0
          find_or_create_node(
            name: namespace,
            node_type: "entity",
            entity_type: "technology",
            description: "#{namespace} namespace containing #{model_count} models",
            properties: { kind: "namespace", model_count: model_count }
          )
        end
      end

      # ================================================================
      # MODEL NODES (~300+)
      # ================================================================

      def build_model_nodes
        @scan_data[:models].each do |_namespace, models|
          models.each do |model|
            col_summary = model[:columns]
                            .reject { |c| %w[id created_at updated_at].include?(c[:name]) }
                            .map { |c| c[:name] }
                            .first(12).join(", ")
            assoc_summary = model[:associations]
                              .map { |a| "#{a[:macro]} :#{a[:name]}" }
                              .first(5).join(", ")

            find_or_create_node(
              name: model[:name],
              node_type: "entity",
              entity_type: "custom",
              description: "#{model[:name]} model (table: #{model[:table_name]}). " \
                           "Columns: #{col_summary}. Associations: #{assoc_summary}".truncate(500),
              properties: {
                kind: "model",
                namespace: _namespace,
                table_name: model[:table_name],
                column_count: model[:columns].size,
                association_count: model[:associations].size
              }
            )
          end
        end
      end

      # ================================================================
      # SERVICE NODES (~100+)
      # ================================================================

      def build_service_nodes
        @scan_data[:services].each do |namespace, services|
          services.each do |service|
            find_or_create_node(
              name: service[:name],
              node_type: "entity",
              entity_type: "custom",
              description: "Service #{service[:name]} (#{service[:file]})",
              properties: { kind: "service", namespace: namespace, file: service[:file] }
            )
          end
        end
      end

      # ================================================================
      # FRONTEND FEATURE NODES (~14)
      # ================================================================

      def build_frontend_nodes
        @scan_data[:frontend_features].each do |name, info|
          find_or_create_node(
            name: "Feature::#{name.camelize}",
            node_type: "entity",
            entity_type: "custom",
            description: "Frontend feature '#{name}' with #{info[:file_count]} files. " \
                         "Subdirectories: #{info[:subdirectories].join(', ')}",
            properties: {
              kind: "frontend_feature",
              file_count: info[:file_count],
              subdirectories: info[:subdirectories]
            }
          )
        end
      end

      # ================================================================
      # CONCEPT NODES (~20)
      # ================================================================

      CONCEPTS = [
        { name: "Authentication", description: "JWT-based authentication with 2FA and OAuth 2.1" },
        { name: "Authorization", description: "Permission-based access control with role-permission mapping" },
        { name: "Multi-tenancy", description: "Account-based tenant isolation for all resources" },
        { name: "Subscription Management", description: "Plan, subscription, payment, and invoice lifecycle" },
        { name: "AI Agent Orchestration", description: "Agent creation, teams, trust scoring, autonomy" },
        { name: "Workflow Engine", description: "DAG-based workflow execution with compensation and checkpointing" },
        { name: "Memory Tiers", description: "Working (Redis), short-term (PG+TTL), long-term (pgvector), shared (pgvector+ACL)" },
        { name: "RAG Pipeline", description: "Document chunking, embedding, hybrid search, and reranking" },
        { name: "Knowledge Graph", description: "Entity-relationship graph with multi-hop traversal" },
        { name: "Trust System", description: "Agent trust: supervised → monitored → trusted → autonomous" },
        { name: "Code Factory", description: "Automated PRD → task gen → evidence → remediation pipeline" },
        { name: "Mission Pipeline", description: "analyzing → planning → executing → testing → reviewing → deploying" },
        { name: "Container Sandbox", description: "Docker-based agent sandboxing for secure execution" },
        { name: "CI/CD Pipeline", description: "Pipeline execution with step handlers and approvals" },
        { name: "Supply Chain Security", description: "SBOM generation, vulnerability scanning, license compliance" },
        { name: "Chat Gateway", description: "Multi-channel messaging: Slack, Discord, Telegram, WhatsApp" },
        { name: "A2A Protocol", description: "Agent-to-Agent JSON-RPC 2.0 with federation" },
        { name: "MCP Tools", description: "Model Context Protocol tool registration and execution" },
        { name: "Compound Learning", description: "Pattern extraction from agent successes and failures" },
        { name: "Business Features", description: "Billing, BaaS, reseller, AI publisher via submodule" }
      ].freeze

      def build_concept_nodes
        CONCEPTS.each do |c|
          find_or_create_node(
            name: c[:name],
            node_type: "concept",
            description: c[:description],
            properties: { kind: "concept" }
          )
        end
      end

      # ================================================================
      # EDGES
      # ================================================================

      def build_model_edges
        @scan_data[:models].each do |namespace, models|
          namespace_node = @node_cache["#{namespace}:entity"] if namespace != "Root"

          models.each do |model|
            model_node = @node_cache["#{model[:name]}:entity"]
            next unless model_node

            # part_of: Model → Namespace
            if namespace_node
              safe_create_edge(
                source: model_node,
                target: namespace_node,
                relation_type: "part_of",
                label: "belongs to namespace"
              )
            end

            # depends_on: belongs_to associations
            model[:associations].each do |assoc|
              next unless assoc[:macro] == "belongs_to"

              target_name = assoc[:class_name]
              target_node = @node_cache["#{target_name}:entity"]
              next unless target_node

              safe_create_edge(
                source: model_node,
                target: target_node,
                relation_type: "depends_on",
                label: "belongs_to :#{assoc[:name]}",
                properties: { foreign_key: assoc[:foreign_key] }
              )
            end
          end
        end
      end

      def build_service_edges
        @scan_data[:services].each do |namespace, services|
          # Find the closest namespace node (walk up from Ai::Memory to Ai)
          ns_node = resolve_namespace_node(namespace)

          services.each do |service|
            service_node = @node_cache["#{service[:name]}:entity"]
            next unless service_node

            if ns_node
              safe_create_edge(
                source: service_node,
                target: ns_node,
                relation_type: "part_of",
                label: "service in namespace"
              )
            end
          end
        end
      end

      def resolve_namespace_node(namespace)
        parts = namespace.split("::")
        # Try exact match first, then progressively shorter prefixes
        parts.length.downto(1) do |len|
          candidate = parts[0...len].join("::")
          node = @node_cache["#{candidate}:entity"]
          return node if node
        end
        nil
      end
    end
  end
end
