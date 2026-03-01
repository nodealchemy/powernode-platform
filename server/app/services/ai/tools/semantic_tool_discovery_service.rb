# frozen_string_literal: true

module Ai
  module Tools
    class SemanticToolDiscoveryService
      include AgentBackedService
      CACHE_TTL = 6.hours
      CACHE_PREFIX = "tool_discovery"
      SIMILARITY_THRESHOLD = 0.3
      MAX_RESULTS = 10

      def initialize(account:)
        @account = account
      end

      # Discover tools by natural language query
      # Returns ranked list of tool definitions with relevance scores
      def discover(query:, capabilities: nil, limit: MAX_RESULTS)
        candidates = collect_all_tools
        candidates = filter_by_capabilities(candidates, capabilities) if capabilities.present?

        ranked = rank_by_relevance(query, candidates)
        ranked.first(limit)
      end

      # Index all available tools (called by worker job)
      def index_tools!
        tools = collect_all_tools
        embeddings = generate_embeddings(tools.map { |t| t[:search_text] })

        tools.each_with_index do |tool, idx|
          next unless embeddings[idx]

          cache_key = "#{CACHE_PREFIX}:#{@account.id}:embedding:#{tool[:id]}"
          Rails.cache.write(cache_key, embeddings[idx], expires_in: CACHE_TTL)
        end

        Rails.logger.info "[SemanticToolDiscovery] Indexed #{tools.size} tools for account #{@account.id}"
        tools.size
      end

      # Register a dynamic tool at runtime
      def self.register_dynamic_tool(account:, name:, description:, parameters:, handler:, metadata: {})
        tool_entry = {
          id: "dynamic.#{name}",
          name: name,
          description: description,
          parameters: parameters,
          handler_class: handler.is_a?(String) ? handler : handler.name,
          dynamic: true,
          registered_at: Time.current.iso8601,
          metadata: metadata
        }

        cache_key = "#{CACHE_PREFIX}:#{account.id}:dynamic_tools"
        existing = Rails.cache.read(cache_key) || []
        existing.reject! { |t| t[:name] == name }
        existing << tool_entry
        Rails.cache.write(cache_key, existing, expires_in: 24.hours)

        ::Mcp::SessionNotifier.notify_tools_changed(account)
        Rails.logger.info "[SemanticToolDiscovery] Registered dynamic tool '#{name}' for account #{account.id}"
        tool_entry
      end

      # Unregister a dynamic tool
      def self.unregister_dynamic_tool(account:, name:)
        cache_key = "#{CACHE_PREFIX}:#{account.id}:dynamic_tools"
        existing = Rails.cache.read(cache_key) || []
        existing.reject! { |t| t[:name] == name }
        Rails.cache.write(cache_key, existing, expires_in: 24.hours)

        ::Mcp::SessionNotifier.notify_tools_changed(account)
      end

      private

      def collect_all_tools
        tools = []

        # Platform tools (static registry)
        PlatformApiToolRegistry::TOOLS.each do |name, class_name|
          klass = class_name.constantize
          defn = klass.definition
          tools << {
            id: "platform.#{name}",
            name: name,
            description: defn[:description] || "",
            parameters: defn[:parameters] || {},
            source: "platform",
            search_text: build_search_text(name, defn)
          }
        rescue NameError, NotImplementedError => e
          Rails.logger.warn "[SemanticToolDiscovery] Skipping unavailable tool: #{class_name} - #{e.message}"
        end

        # MCP server tools (from database)
        if @account
          McpTool.joins(:mcp_server)
                 .where(mcp_servers: { account_id: @account.id })
                 .where(enabled: true)
                 .find_each do |tool|
            tools << {
              id: "mcp.#{tool.id}",
              name: tool.name,
              description: tool.description || "",
              parameters: tool.input_schema || {},
              source: "mcp_server",
              mcp_server_id: tool.mcp_server_id,
              search_text: build_search_text(tool.name, { description: tool.description })
            }
          end
        end

        # Dynamic tools (from cache)
        dynamic = Rails.cache.read("#{CACHE_PREFIX}:#{@account&.id}:dynamic_tools") || []
        dynamic.each do |tool|
          tools << tool.merge(
            source: "dynamic",
            search_text: build_search_text(tool[:name], { description: tool[:description] })
          )
        end

        # Agent-as-tool entries
        if @account
          Ai::Agent.where(account_id: @account.id, status: "active")
                   .where.not(agent_type: "workflow_optimizer")
                   .find_each do |agent|
            tools << {
              id: "agent.#{agent.id}",
              name: "invoke_agent_#{agent.name.parameterize(separator: '_')}",
              description: "Invoke the '#{agent.name}' AI agent: #{agent.description}",
              parameters: { prompt: { type: "string", description: "Input prompt for the agent", required: true } },
              source: "agent",
              agent_id: agent.id,
              search_text: "invoke agent #{agent.name} #{agent.description} #{agent.agent_type}"
            }
          end
        end

        tools
      end

      def filter_by_capabilities(tools, capabilities)
        capability_keywords = Array(capabilities).map(&:downcase)
        tools.select do |tool|
          text = tool[:search_text].downcase
          capability_keywords.any? { |kw| text.include?(kw) }
        end
      end

      def rank_by_relevance(query, tools)
        return tools if tools.empty?

        query_embedding = get_or_generate_embedding(query, "query:#{Digest::SHA256.hexdigest(query)}")
        return keyword_fallback(query, tools) unless query_embedding

        scored = tools.filter_map do |tool|
          tool_embedding = get_or_generate_embedding(
            tool[:search_text],
            "#{CACHE_PREFIX}:#{@account&.id}:embedding:#{tool[:id]}"
          )

          if tool_embedding
            score = cosine_similarity(query_embedding, tool_embedding)
            tool.merge(relevance_score: score) if score >= SIMILARITY_THRESHOLD
          else
            # Fallback to keyword matching
            kw_score = keyword_score(query, tool[:search_text])
            tool.merge(relevance_score: kw_score) if kw_score > 0
          end
        end

        scored.sort_by { |t| -t[:relevance_score] }
      end

      def keyword_fallback(query, tools)
        query_terms = query.downcase.split(/\s+/)
        scored = tools.map do |tool|
          score = keyword_score(query, tool[:search_text])
          tool.merge(relevance_score: score)
        end
        scored.select { |t| t[:relevance_score] > 0 }.sort_by { |t| -t[:relevance_score] }
      end

      def keyword_score(query, text)
        query_terms = query.downcase.split(/\s+/).uniq
        text_lower = text.downcase
        matches = query_terms.count { |term| text_lower.include?(term) }
        matches.to_f / [query_terms.size, 1].max
      end

      def build_search_text(name, definition)
        parts = [name.to_s.tr("_", " ")]
        parts << definition[:description].to_s if definition[:description].present?
        if definition[:parameters].is_a?(Hash)
          parts << definition[:parameters].keys.join(" ")
        end
        parts.join(" ")
      end

      def get_or_generate_embedding(text, cache_key)
        cached = Rails.cache.read(cache_key)
        return cached if cached

        embedding = generate_single_embedding(text)
        Rails.cache.write(cache_key, embedding, expires_in: CACHE_TTL) if embedding
        embedding
      end

      def generate_embeddings(texts)
        texts.map { |text| generate_single_embedding(text) }
      end

      def generate_single_embedding(text)
        return nil if text.blank?

        provider = find_embedding_provider
        return nil unless provider

        provider.generate_embedding(text)
      rescue StandardError => e
        Rails.logger.warn "[SemanticToolDiscovery] Embedding generation failed: #{e.message}"
        nil
      end

      def find_embedding_provider
        return @embedding_provider if defined?(@embedding_provider)

        @embedding_provider = if @account
          agent = resolve_service_agent("semantic-tool-scorer", fallback_name: "Semantic Tool Scorer")
          build_agent_client(agent) if agent
        end
      end

      def cosine_similarity(vec_a, vec_b)
        return 0.0 unless vec_a.is_a?(Array) && vec_b.is_a?(Array) && vec_a.size == vec_b.size

        dot = vec_a.zip(vec_b).sum { |a, b| a * b }
        mag_a = Math.sqrt(vec_a.sum { |x| x**2 })
        mag_b = Math.sqrt(vec_b.sum { |x| x**2 })

        return 0.0 if mag_a.zero? || mag_b.zero?

        dot / (mag_a * mag_b)
      end
    end
  end
end
