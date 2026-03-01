# frozen_string_literal: true

module Ai
  module SkillGraph
    class ResearchService
      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Main entry point: multi-source research on a topic
      def research(topic:, sources: %w[knowledge_graph knowledge_bases mcp federation], requesting_agent: nil)
        results = {
          topic: topic,
          sources_queried: sources,
          requesting_agent_id: requesting_agent&.id,
          researched_at: Time.current,
          findings: {}
        }

        sources.each do |source|
          case source
          when "knowledge_graph" then results[:findings][:knowledge_graph] = search_knowledge_graph(topic: topic)
          when "knowledge_bases" then results[:findings][:knowledge_bases] = search_knowledge_bases(topic: topic)
          when "mcp" then results[:findings][:mcp] = search_mcp_tools(topic: topic)
          when "federation" then results[:findings][:federation] = search_federation(topic: topic)
          when "web" then results[:findings][:web] = search_web(topic: topic)
          end
        end

        results[:total_findings] = results[:findings].values.sum { |v| v.is_a?(Array) ? v.size : 0 }
        results
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::ResearchService] research failed: #{e.message}"
        results.merge(error: e.message)
      end

      # Detect overlaps between a proposed skill and existing skills
      def detect_overlaps(proposed_name:, proposed_description:)
        text = "#{proposed_name}: #{proposed_description}"
        embedding = embedding_service.generate(text)
        return { overlaps: [], warning: "Could not generate embedding" } unless embedding

        candidates = account.ai_knowledge_graph_nodes
          .skill_nodes.active.with_embeddings
          .nearest_neighbors(:embedding, embedding, distance: "cosine")
          .first(20)

        overlaps = candidates.filter_map do |node|
          similarity = 1.0 - node.neighbor_distance
          next if similarity < 0.5

          {
            skill_id: node.ai_skill_id,
            skill_name: node.name,
            node_id: node.id,
            similarity: similarity.round(4),
            severity: overlap_severity(similarity)
          }
        end

        { overlaps: overlaps.sort_by { |o| -o[:similarity] }, count: overlaps.size }
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::ResearchService] detect_overlaps failed: #{e.message}"
        { overlaps: [], error: e.message }
      end

      # Suggest dependencies for a proposed skill
      def suggest_dependencies(proposed_skill_attrs:)
        text = "#{proposed_skill_attrs[:name]}: #{proposed_skill_attrs[:description]}"
        embedding = embedding_service.generate(text)
        return [] unless embedding

        candidates = account.ai_knowledge_graph_nodes
          .skill_nodes.active.with_embeddings
          .nearest_neighbors(:embedding, embedding, distance: "cosine")
          .first(15)

        candidates.filter_map do |node|
          similarity = 1.0 - node.neighbor_distance
          next if similarity < 0.5 || similarity > 0.92 # Skip duplicates and too-distant

          skill = Ai::Skill.find_by(id: node.ai_skill_id)
          next unless skill

          relation = if skill.category == proposed_skill_attrs[:category]
            similarity > 0.8 ? "enhances" : "requires"
          else
            "composes"
          end

          {
            skill_id: skill.id,
            skill_name: skill.name,
            relation_type: relation,
            confidence: similarity.round(4)
          }
        end
      rescue StandardError => e
        Rails.logger.error "[SkillGraph::ResearchService] suggest_dependencies failed: #{e.message}"
        []
      end

      private

      def search_knowledge_graph(topic:)
        embedding = embedding_service.generate(topic)
        return [] unless embedding

        nodes = account.ai_knowledge_graph_nodes
          .skill_nodes.active.with_embeddings
          .nearest_neighbors(:embedding, embedding, distance: "cosine")
          .first(10)

        nodes.filter_map do |node|
          similarity = 1.0 - node.neighbor_distance
          next if similarity < 0.4

          {
            node_id: node.id,
            name: node.name,
            description: node.description,
            skill_id: node.ai_skill_id,
            similarity: similarity.round(4),
            properties: node.properties
          }
        end
      rescue StandardError => e
        Rails.logger.warn "[SkillGraph::ResearchService] KG search failed: #{e.message}"
        []
      end

      def search_knowledge_bases(topic:)
        service = Ai::Memory::SharedKnowledgeService.new(account: account)
        result = service.search(query: topic, limit: 10)
        entries = result.is_a?(Hash) ? (result[:entries] || []) : Array(result)

        entries.map do |entry|
          entry_obj = entry.is_a?(Hash) ? entry : nil
          {
            id: entry_obj ? entry_obj[:id] : entry.id,
            title: entry_obj ? entry_obj[:title] : entry.title,
            content_preview: (entry_obj ? entry_obj[:content] : entry.content)&.truncate(200),
            relevance: entry_obj ? entry_obj[:similarity] : nil
          }
        end
      rescue StandardError => e
        Rails.logger.warn "[SkillGraph::ResearchService] KB search failed: #{e.message}"
        []
      end

      def search_mcp_tools(topic:)
        servers = McpServer.where(account_id: [account.id, nil]).where(status: "connected")
        matches = []

        servers.find_each do |server|
          tools = server.respond_to?(:cached_tools) ? server.cached_tools : []
          next unless tools.is_a?(Array)

          tools.each do |tool|
            tool_text = "#{tool['name']} #{tool['description']}"
            if topic.downcase.split(/\s+/).any? { |word| tool_text.downcase.include?(word) }
              matches << {
                server_id: server.id,
                server_name: server.name,
                tool_name: tool["name"],
                tool_description: tool["description"]
              }
            end
          end
        end

        matches.first(10)
      rescue StandardError => e
        Rails.logger.warn "[SkillGraph::ResearchService] MCP search failed: #{e.message}"
        []
      end

      def search_federation(topic:)
        return [] unless defined?(Ai::A2a::ProtocolService)

        service = Ai::A2a::ProtocolService.new(account: account)
        result = service.discover_agents(task_description: topic)
        agents = result[:success] ? (result[:agents] || []) : []

        agents.first(5).map do |agent|
          {
            agent_name: agent[:name],
            agent_url: agent[:agent_card]&.dig("url"),
            capabilities: agent[:agent_card]&.dig("capabilities"),
            relevance: "federated"
          }
        end
      rescue StandardError => e
        Rails.logger.warn "[SkillGraph::ResearchService] Federation search failed: #{e.message}"
        []
      end

      def search_web(topic:)
        return [] unless Shared::FeatureFlagService.enabled?(:skill_lifecycle_research, account)

        [{
          source: "web_research",
          topic: topic,
          status: "available",
          note: "Web research requires skill_lifecycle_research feature flag and LLM integration"
        }]
      end

      def overlap_severity(similarity)
        if similarity >= 0.92
          "duplicate"
        elsif similarity >= 0.7
          "high_overlap"
        else
          "moderate_overlap"
        end
      end

      def embedding_service
        @embedding_service ||= Ai::Memory::EmbeddingService.new(account: account)
      end
    end
  end
end
