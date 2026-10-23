# frozen_string_literal: true

module Ai
  module Tools
    class SemanticToolDiscoveryService
      CACHE_TTL = 6.hours
      CACHE_PREFIX = "tool_discovery"
      SIMILARITY_THRESHOLD = 0.3
      MAX_RESULTS = 10
      # Tool embeddings warmed per discovery call (one batch request, not one per tool).
      WARM_BATCH_LIMIT = 1000
      # How long a failed/unconfigured embedding provider is left alone.
      UNAVAILABLE_TTL = 5.minutes

      def initialize(account:)
        @account = account
      end

      # Discover tools by natural language query
      # Returns ranked list of tool definitions with relevance scores.
      # `limit: nil` returns the whole ranking, for a caller that filters after.
      def discover(query:, capabilities: nil, limit: MAX_RESULTS)
        candidates = collect_all_tools
        candidates = filter_by_capabilities(candidates, capabilities) if capabilities.present?

        ranked = rank_by_relevance(query, candidates)
        limit ? ranked.first(limit) : ranked
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

        # Platform tools (static registry + extension-registered tools).
        #
        # ADVERTISEMENT surface (IMP-5039d026da0d): this list is both the
        # candidate set for #discover and the corpus #index_tools! embeds, so an
        # action the registry refuses to advertise must not be in it — otherwise
        # discovery-by-embedding steers an agent at an action tools/list does not
        # offer and the tool cannot run. Before the predicate call below this
        # walked the raw map, which is why the docker-runtime actions stayed in
        # the index in core mode after IMP-2836d290f99a.
        #
        # `agent: nil` (the default) is what the predicate is asked here: the
        # index is per-ACCOUNT and cached under the account id, and no agent is
        # in scope, so the question is availability, not any one agent's grants.
        PlatformApiToolRegistry.all_tools.each do |name, class_name|
          klass = class_name.constantize
          next unless PlatformApiToolRegistry.advertised_action?(name, klass)

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

      # One discovery call costs at most ONE embedding request to the worker: the
      # query plus however many tool embeddings are not cached yet (capped by
      # WARM_BATCH_LIMIT), sent as a single batch. Tool embeddings are read from
      # the cache, never generated one by one; a tool still without one is scored
      # by keyword. Before this, a cold cache cost one worker request per catalog
      # tool per call (~680), each one costing the server two internal API calls.
      def rank_by_relevance(query, tools)
        return tools if tools.empty?

        query_embedding, tool_embeddings = embeddings_for(query, tools)
        return keyword_fallback(query, tools) unless query_embedding

        scored = tools.filter_map do |tool|
          tool_embedding = tool_embeddings[tool[:id]]

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

      # @return [Array(Array<Float>|nil, Hash{String=>Array<Float>})]
      def embeddings_for(query, tools)
        return [ nil, {} ] if embeddings_unavailable?

        query_key = "query:#{Digest::SHA256.hexdigest(query)}"
        query_embedding = Rails.cache.read(query_key)
        tool_embeddings = {}
        missing = []
        tools.each do |tool|
          cached = Rails.cache.read(tool_cache_key(tool))
          cached ? tool_embeddings[tool[:id]] = cached : missing << tool
        end
        missing = missing.first(WARM_BATCH_LIMIT)

        texts = []
        texts << query unless query_embedding
        texts += missing.map { |t| t[:search_text] }
        return [ query_embedding, tool_embeddings ] if texts.empty?

        provider = find_embedding_provider
        return [ query_embedding, tool_embeddings ] unless provider

        vectors = provider.generate_batch(texts)
        raise "embedding provider returned no vectors" if vectors.blank?

        unless query_embedding
          query_embedding = vectors.shift
          Rails.cache.write(query_key, query_embedding, expires_in: CACHE_TTL) if query_embedding
        end
        missing.each_with_index do |tool, idx|
          next unless vectors[idx]

          tool_embeddings[tool[:id]] = vectors[idx]
          Rails.cache.write(tool_cache_key(tool), vectors[idx], expires_in: CACHE_TTL)
        end
        [ query_embedding, tool_embeddings ]
      rescue StandardError => e
        # No provider, or it is down: fall back to keywords and do not ask again
        # for a while, so a missing provider costs one attempt per window.
        Rails.logger.warn "[SemanticToolDiscovery] Embedding unavailable, using keyword relevance: #{e.class}: #{e.message}"
        Rails.cache.write(unavailable_cache_key, true, expires_in: UNAVAILABLE_TTL)
        [ nil, {} ]
      end

      def tool_cache_key(tool)
        "#{CACHE_PREFIX}:#{@account&.id}:embedding:#{tool[:id]}"
      end

      def unavailable_cache_key
        "#{CACHE_PREFIX}:#{@account&.id}:embeddings_unavailable"
      end

      def embeddings_unavailable?
        Rails.cache.read(unavailable_cache_key).present?
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

        provider.generate(text)
      rescue StandardError => e
        Rails.logger.warn "[SemanticToolDiscovery] Embedding generation failed: #{e.message}"
        nil
      end

      # IMP-019fe370: this used to build an agent CHAT client
      # (TrackedWorkerLlmClient -> WorkerLlmClient) and call generate_embedding on
      # it. Neither answers that method, so every call raised NoMethodError through
      # method_missing, was swallowed by the rescue above, and semantic discovery
      # ran on nil embeddings — permanently degraded to keyword matching, silently.
      # Ai::Memory::EmbeddingService is the account's real embedding seam (the same
      # one RagService and memory storage use) and caches in Redis.
      def find_embedding_provider
        return @embedding_provider if defined?(@embedding_provider)

        @embedding_provider = (::Ai::Memory::EmbeddingService.new(account: @account) if @account)
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
