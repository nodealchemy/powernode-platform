# frozen_string_literal: true

module Ai
  module DataSourceGraph
    # Bridges Ai::DataSource records into the knowledge graph as
    # entity_type "data_source" nodes with pgvector embeddings, mirroring
    # Ai::SkillGraph::BridgeService. The resulting nodes back semantic
    # data-source discovery (Ai::DataSources::SemanticDiscoveryService) and
    # contribute their node confidence to the source's effectiveness score.
    class BridgeService
      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Create/update the KG node linked to a data source, regenerating the
      # pgvector embedding from its name/description/type/endpoint names.
      def sync_data_source(ds)
        # DELIBERATELY the bare association — do NOT "fix" this to a scoped read
        # by analogy with Ai::Skill (019fedd4 / 019ff1eb scoped 15 skill reads).
        # A data source is never global (ai_data_sources.account_id is NOT NULL,
        # no GloballyScopable), so there is no per-account fan-out to disambiguate
        # and an account scope here can only ever be a no-op. And the revive branch
        # below is why a STATUS scope is actively harmful: it finds an archived
        # node and revives it, so scoped it would take the create branch and add a
        # duplicate that index_ai_kg_nodes_on_ai_data_source_id — partial, NOT
        # unique — does not prevent. See the has_one comment on Ai::DataSource.
        node = ds.knowledge_graph_node

        text = build_embedding_text(ds)
        embedding = embedding_service.generate(text)

        if node.present?
          node.update!(
            name: ds.name,
            description: ds.description,
            properties: build_data_source_properties(ds),
            confidence: 1.0,
            status: "active",
            last_seen_at: Time.current
          )
          node.set_embedding!(embedding) if embedding
        else
          node = graph_service.create_node(
            name: ds.name,
            node_type: "entity",
            entity_type: "data_source",
            description: ds.description,
            properties: build_data_source_properties(ds),
            confidence: 1.0,
            metadata: { ai_data_source_id: ds.id }
          )
          # Link the node to the data source via the FK
          node.update!(ai_data_source_id: ds.id)
          node.set_embedding!(embedding) if embedding
        end

        node
      rescue StandardError => e
        Rails.logger.error "[DataSourceGraph::BridgeService] sync_data_source failed for #{ds.id}: #{e.message}"
        nil
      end

      # Bulk sync all active account data sources.
      def sync_all_data_sources
        sources = Ai::DataSource.for_account(account).active
        results = { synced: 0, failed: 0 }

        sources.find_each do |ds|
          if sync_data_source(ds)
            results[:synced] += 1
          else
            results[:failed] += 1
          end
        end

        Rails.logger.info "[DataSourceGraph::BridgeService] Bulk sync complete: #{results.inspect}"
        results
      end

      private

      def graph_service
        @graph_service ||= Ai::KnowledgeGraph::GraphService.new(account)
      end

      def embedding_service
        @embedding_service ||= Ai::Memory::EmbeddingService.new(account: account)
      end

      def build_embedding_text(ds)
        parts = [ds.name]
        parts << ds.description if ds.description.present?
        parts << "category: #{ds.source_type}" if ds.source_type.present?
        endpoint_names = ds.endpoints.pluck(:name).compact
        parts << "endpoints: #{endpoint_names.join(', ')}" if endpoint_names.any?
        parts.join(" | ")
      end

      def build_data_source_properties(ds)
        {
          source_type: ds.source_type,
          protocol: ds.protocol,
          auth_scheme: ds.auth_scheme,
          health_status: ds.health_status,
          is_active: ds.is_active,
          # to_f so the jsonb property is a real number, not a decimal-as-string.
          effectiveness_score: ds.effectiveness_score&.to_f,
          usage_count: ds.usage_count,
          endpoint_count: ds.endpoints.count
        }.compact
      end
    end
  end
end
