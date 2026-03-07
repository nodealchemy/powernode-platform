# frozen_string_literal: true

module Ai
  module Memory
    class RouterService
      # Memory tiers in order of access speed
      TIERS = %w[working short_term long_term shared].freeze

      attr_reader :account, :agent

      def initialize(account:, agent:)
        @account = account
        @agent = agent
      end

      # Read memory cascading through tiers
      # Checks working → short-term → long-term → shared knowledge
      # @param key [String] Memory key to look up
      # @param session_id [String] Current session ID (for working/short-term)
      # @param options [Hash] Options like tier, limit, threshold
      # @return [Hash] Memory value with tier source
      def read(key:, session_id: nil, **options)
        tier = options[:tier]

        # If specific tier requested, only check that tier
        if tier.present?
          return read_from_tier(tier, key, session_id, options)
        end

        # Cascade through tiers
        TIERS.each do |t|
          result = read_from_tier(t, key, session_id, options)
          return result if result[:found]
        end

        { found: false, key: key, tier: nil, value: nil }
      end

      # Write memory to the appropriate tier
      # @param key [String] Memory key
      # @param value [Object] Memory value (will be stored as JSON)
      # @param tier [String] Target tier (default: short_term)
      # @param session_id [String] Session ID (required for working/short-term)
      # @param options [Hash] Additional options (ttl, type, tags)
      def write(key:, value:, tier: "short_term", session_id: nil, **options)
        case tier
        when "working"
          write_working(key, value, session_id, options)
        when "short_term"
          write_short_term(key, value, session_id, options)
        when "long_term"
          write_long_term(key, value, options)
        when "shared"
          write_shared(key, value, options)
        else
          Rails.logger.warn("[MemoryRouter] Unknown tier: #{tier}, defaulting to short_term")
          write_short_term(key, value, session_id, options)
        end
      rescue StandardError => e
        Rails.logger.error("[MemoryRouter] Write failed: key=#{key} tier=#{tier} error=#{e.message}")
        { success: false, error: e.message }
      end

      # Delete memory from a specific tier
      def delete(key:, tier:, session_id: nil)
        case tier
        when "working"
          delete_working(key, session_id)
        when "short_term"
          delete_short_term(key, session_id)
        when "long_term"
          # Long-term memories are not deleted, but deprecated
          deprecate_long_term(key)
        when "shared"
          # Shared knowledge requires explicit access
          { success: false, error: "Shared knowledge cannot be deleted via router" }
        end
      end

      # Semantic search across long-term and shared tiers
      # @param query_embedding [Array<Float>] Query vector
      # @param options [Hash] threshold, limit, tiers
      def semantic_search(query_embedding:, **options)
        threshold = options[:threshold] || 0.7
        limit = options[:limit] || 10
        tiers = options[:tiers] || %w[long_term shared]
        results = []

        if tiers.include?("long_term")
          results += search_compound_learnings(query_embedding, threshold, limit)
        end

        if tiers.include?("shared")
          results += search_shared_knowledge(query_embedding, threshold, limit)
        end

        # Sort by relevance (lower distance = more relevant)
        results.sort_by { |r| r[:distance] }.first(limit)
      end

      # Get memory statistics across all tiers
      def stats
        {
          working: working_memory_stats,
          short_term: short_term_stats,
          long_term: long_term_stats,
          shared: shared_stats
        }
      end

      # Consolidate short-term memories into long-term
      def consolidate!(session_id:)
        memories = Ai::AgentShortTermMemory
          .for_agent(agent.id)
          .for_session(session_id)
          .active
          .frequently_accessed
          .limit(20)

        consolidated = 0
        memories.find_each do |memory|
          next unless memory.access_count >= 3 # Only consolidate frequently accessed

          write_long_term(memory.memory_key, memory.memory_value, {
            source: "consolidation",
            original_session: session_id,
            access_count: memory.access_count
          })
          consolidated += 1
        end

        Rails.logger.info("[MemoryRouter] Consolidated #{consolidated} memories from session #{session_id}")
        { consolidated: consolidated, session_id: session_id }
      end

      private

      # === Working Memory (in-sandbox, Redis-backed) ===

      def read_working(key, session_id, _options)
        return { found: false, tier: "working" } unless session_id

        redis_key = working_memory_key(session_id, key)
        value = Powernode::Redis.client.get(redis_key)

        if value.present?
          { found: true, tier: "working", key: key, value: JSON.parse(value) }
        else
          { found: false, tier: "working" }
        end
      rescue StandardError
        { found: false, tier: "working" }
      end

      def write_working(key, value, session_id, options)
        return { success: false, error: "session_id required for working memory" } unless session_id

        redis_key = working_memory_key(session_id, key)
        ttl = options[:ttl] || 1800 # 30 minutes default

        Powernode::Redis.client.setex(redis_key, ttl, value.to_json)
        { success: true, tier: "working", key: key }
      end

      def delete_working(key, session_id)
        return { success: false } unless session_id

        Powernode::Redis.client.del(working_memory_key(session_id, key))
        { success: true, tier: "working" }
      end

      def working_memory_key(session_id, key)
        "wm:#{agent.id}:#{session_id}:#{key}"
      end

      # === Short-Term Memory (PostgreSQL with TTL) ===

      def read_short_term(key, session_id, _options)
        scope = Ai::AgentShortTermMemory
          .for_agent(agent.id)
          .active
          .where(memory_key: key)

        scope = scope.for_session(session_id) if session_id
        memory = scope.first

        if memory
          memory.touch_access!
          { found: true, tier: "short_term", key: key, value: memory.memory_value, id: memory.id }
        else
          { found: false, tier: "short_term" }
        end
      end

      def write_short_term(key, value, session_id, options)
        session_id ||= "default"

        memory = Ai::AgentShortTermMemory.find_or_initialize_by(
          agent_id: agent.id,
          session_id: session_id,
          memory_key: key
        )

        memory.assign_attributes(
          account: account,
          memory_value: value,
          memory_type: options[:type] || "general",
          ttl_seconds: options[:ttl] || 3600,
          expires_at: Time.current + (options[:ttl] || 3600).seconds
        )

        memory.save!
        { success: true, tier: "short_term", key: key, id: memory.id }
      end

      def delete_short_term(key, session_id)
        scope = Ai::AgentShortTermMemory.for_agent(agent.id).where(memory_key: key)
        scope = scope.for_session(session_id) if session_id
        count = scope.delete_all
        { success: true, deleted: count }
      end

      # === Long-Term Memory (pgvector via CompoundLearning) ===

      def read_long_term(key, _session_id, _options)
        learning = Ai::CompoundLearning
          .where(account_id: account.id)
          .active
          .where("metadata->>'memory_key' = ?", key)
          .order(created_at: :desc)
          .first

        if learning
          { found: true, tier: "long_term", key: key, value: { content: learning.content, category: learning.category }, id: learning.id }
        else
          { found: false, tier: "long_term" }
        end
      end

      def write_long_term(key, value, options)
        content = value.is_a?(Hash) ? value.to_json : value.to_s

        Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          content: content,
          category: options[:category] || "fact",
          scope: "team",
          status: "active",
          importance_score: options[:importance] || 0.5,
          confidence_score: options[:confidence] || 0.7,
          extraction_method: options[:source] || "manual",
          metadata: { memory_key: key }.merge(options.except(:category, :importance, :confidence, :source, :ttl, :type))
        )

        { success: true, tier: "long_term", key: key }
      end

      def deprecate_long_term(key)
        Ai::CompoundLearning
          .where(account_id: account.id)
          .where("metadata->>'memory_key' = ?", key)
          .update_all(status: "deprecated")

        { success: true, tier: "long_term" }
      end

      # === Shared Knowledge (pgvector) ===

      def read_shared(key, _session_id, _options)
        knowledge = Ai::SharedKnowledge
          .where(account_id: account.id)
          .where(title: key)
          .accessible_by("team")
          .order(created_at: :desc)
          .first

        if knowledge
          knowledge.touch_usage!
          { found: true, tier: "shared", key: key, value: { title: knowledge.title, content: knowledge.content }, id: knowledge.id }
        else
          { found: false, tier: "shared" }
        end
      end

      def write_shared(key, value, options)
        content = value.is_a?(Hash) ? (value[:content] || value.to_json) : value.to_s

        Ai::SharedKnowledge.create!(
          account: account,
          title: key,
          content: content,
          content_type: options[:content_type] || "text",
          source_type: "agent",
          source_id: agent.id,
          tags: options[:tags] || [],
          access_level: options[:access_level] || "team",
          provenance: { agent_id: agent.id, agent_name: agent.name, created_via: "memory_router" },
          integrity_hash: Digest::SHA256.hexdigest(content)
        )

        { success: true, tier: "shared", key: key }
      end

      # === Semantic Search ===

      def search_compound_learnings(embedding, threshold, limit)
        distance_threshold = 1.0 - threshold

        Ai::CompoundLearning
          .where(account_id: account.id)
          .active
          .with_embedding
          .nearest_neighbors(:embedding, embedding, distance: "cosine")
          .limit(limit)
          .to_a
          .select { |e| e.neighbor_distance <= distance_threshold }
          .map do |cl|
            {
              tier: "long_term",
              id: cl.id,
              content: cl.content,
              category: cl.category,
              distance: cl.neighbor_distance,
              score: 1.0 - cl.neighbor_distance
            }
          end
      rescue StandardError => e
        Rails.logger.warn("[MemoryRouter] Compound learning search failed: #{e.message}")
        []
      end

      def search_shared_knowledge(embedding, threshold, limit)
        Ai::SharedKnowledge.semantic_search(embedding, limit: limit, threshold: threshold).map do |sk|
          {
            tier: "shared",
            id: sk.id,
            title: sk.title,
            content: sk.content,
            distance: sk.neighbor_distance,
            score: 1.0 - sk.neighbor_distance
          }
        end
      rescue StandardError => e
        Rails.logger.warn("[MemoryRouter] Shared knowledge search failed: #{e.message}")
        []
      end

      # === Stats ===

      def working_memory_stats
        count = 0
        Powernode::Redis.client.scan_each(match: "wm:#{agent.id}:*") { count += 1 }
        { count: count }
      rescue StandardError
        { count: 0 }
      end

      def short_term_stats
        scope = Ai::AgentShortTermMemory.for_agent(agent.id)
        {
          total: scope.count,
          active: scope.active.count,
          expired: scope.expired.count
        }
      end

      def long_term_stats
        scope = Ai::CompoundLearning.where(account_id: account.id, source_agent_id: agent.id)
        {
          total: scope.count,
          active: scope.active.count
        }
      end

      def shared_stats
        scope = Ai::SharedKnowledge.where(account_id: account.id)
        {
          total: scope.count,
          with_embedding: scope.with_embedding.count
        }
      end

      def read_from_tier(tier, key, session_id, options)
        case tier
        when "working" then read_working(key, session_id, options)
        when "short_term" then read_short_term(key, session_id, options)
        when "long_term" then read_long_term(key, session_id, options)
        when "shared" then read_shared(key, session_id, options)
        else { found: false, tier: tier }
        end
      end
    end
  end
end
