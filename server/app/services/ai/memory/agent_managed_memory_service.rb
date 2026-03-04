# frozen_string_literal: true

module Ai
  module Memory
    class AgentManagedMemoryService
      MAX_KEYS_PER_AGENT = 500
      REFLECT_COOLDOWN = 15.minutes
      CHARS_PER_TOKEN = 4

      def initialize(account:, agent:)
        @account = account
        @agent = agent
        @embedding_service = Ai::Memory::EmbeddingService.new(account: account)
      end

      # Store a key-value pair in agent's private memory pool
      def remember(key:, value:, ttl: nil, importance: 0.5, tags: [])
        pool = ensure_private_pool!

        # Enforce key cap with LRU eviction
        enforce_key_cap!(pool)

        # Generate embedding for semantic recall
        text_for_embedding = "#{key}: #{value.is_a?(Hash) ? value.to_json : value.to_s}"
        embedding = @embedding_service.generate(text_for_embedding.truncate(500))

        # Write to pool with metadata
        entry = {
          "value" => value,
          "importance" => importance,
          "tags" => tags,
          "embedding" => embedding,
          "created_at" => Time.current.iso8601,
          "updated_at" => Time.current.iso8601,
          "access_count" => 0
        }
        entry["expires_at"] = ttl.from_now.iso8601 if ttl

        pool.data[key] = entry
        pool.save!

        { key: key, stored: true, pool_id: pool.pool_id }
      end

      # Remove a memory key (hard delete or soft decay)
      def forget(key:, soft: false)
        pool = find_private_pool
        return { key: key, forgotten: false, reason: "no_pool" } unless pool

        if soft
          entry = pool.data[key]
          if entry
            entry["importance"] = [entry["importance"].to_f * 0.1, 0.01].max
            entry["decayed_at"] = Time.current.iso8601
            pool.save!
            { key: key, forgotten: true, mode: "soft_decay" }
          else
            { key: key, forgotten: false, reason: "key_not_found" }
          end
        else
          if pool.data.delete(key)
            pool.save!
            { key: key, forgotten: true, mode: "hard_delete" }
          else
            { key: key, forgotten: false, reason: "key_not_found" }
          end
        end
      end

      # On-demand STM consolidation with LLM summary
      def reflect
        pool = find_private_pool
        return { reflected: false, reason: "no_pool" } unless pool

        # Rate limiting
        last_reflect = pool.metadata["last_reflect_at"]
        if last_reflect && Time.parse(last_reflect) > REFLECT_COOLDOWN.ago
          return { reflected: false, reason: "cooldown", retry_after: REFLECT_COOLDOWN.to_i }
        end

        # Gather recent high-access entries for consolidation
        entries = pool.data.select do |_k, v|
          v.is_a?(Hash) && v["access_count"].to_i >= 2
        end

        return { reflected: false, reason: "no_entries_to_consolidate" } if entries.empty?

        # Build summary of patterns
        summary_parts = entries.map do |key, entry|
          "#{key}: #{entry['value'].to_s.truncate(100)} (importance: #{entry['importance']}, accessed: #{entry['access_count']}x)"
        end

        pool.metadata["last_reflect_at"] = Time.current.iso8601
        pool.metadata["reflect_count"] = (pool.metadata["reflect_count"].to_i + 1)
        pool.save!

        {
          reflected: true,
          entries_reviewed: entries.size,
          summary: summary_parts.first(10)
        }
      end

      # Semantic search across agent's private memory (+ optionally team_shared)
      def recall(query:, include_team: false, limit: 10, threshold: 0.5)
        embedding = @embedding_service.generate(query)
        results = []

        # Search private pool
        pool = find_private_pool
        if pool
          results += search_pool_entries(pool, embedding, query, threshold)
        end

        # Optionally search team_shared pools
        if include_team
          team_pools = Ai::MemoryPool.team_shared.where(account: @account)
            .where("access_control->>'agents' @> ? OR access_control->>'public' = 'true'", [@agent.id].to_json)
          team_pools.each do |tp|
            results += search_pool_entries(tp, embedding, query, threshold)
          end
        end

        # Sort by relevance and limit
        results.sort_by { |r| -r[:relevance] }.first(limit)
      end

      private

      def ensure_private_pool!
        pool = find_private_pool
        return pool if pool

        Ai::MemoryPool.create!(
          account: @account,
          name: "#{@agent.name} Private Memory",
          pool_type: "agent_private",
          scope: "persistent",
          owner_agent_id: @agent.id,
          persist_across_executions: true,
          access_control: { "agents" => [@agent.id], "public" => false },
          data: {},
          metadata: {}
        )
      end

      def find_private_pool
        Ai::MemoryPool.agent_private.for_agent(@agent.id).active.first
      end

      def enforce_key_cap!(pool)
        return if pool.data.size < MAX_KEYS_PER_AGENT

        # LRU eviction: remove least recently accessed entries
        sorted = pool.data.sort_by do |_k, v|
          v.is_a?(Hash) ? (v["updated_at"] || "2000-01-01") : "2000-01-01"
        end

        entries_to_remove = sorted.first(pool.data.size - MAX_KEYS_PER_AGENT + 10)
        entries_to_remove.each { |k, _| pool.data.delete(k) }
      end

      def search_pool_entries(pool, embedding, query, threshold)
        results = []

        pool.data.each do |key, entry|
          next unless entry.is_a?(Hash)

          # Check expiry
          if entry["expires_at"]
            next if Time.parse(entry["expires_at"]) <= Time.current
          end

          # Skip soft-decayed entries with very low importance
          next if entry["decayed_at"] && entry["importance"].to_f < 0.05

          # Calculate relevance
          relevance = if embedding && entry["embedding"]
            cosine_similarity(embedding, entry["embedding"])
          else
            keyword_relevance(query, key, entry)
          end

          next if relevance < threshold

          # Record access
          entry["access_count"] = entry["access_count"].to_i + 1
          entry["last_accessed_at"] = Time.current.iso8601

          results << {
            key: key,
            value: entry["value"],
            importance: entry["importance"].to_f,
            relevance: relevance,
            tags: entry["tags"] || [],
            pool_id: pool.pool_id,
            pool_type: pool.pool_type
          }
        end

        pool.save! if results.any? # Save access count updates

        results
      end

      def cosine_similarity(a, b)
        return 0.0 unless a.is_a?(Array) && b.is_a?(Array) && a.size == b.size

        dot = a.zip(b).sum { |x, y| x.to_f * y.to_f }
        mag_a = Math.sqrt(a.sum { |x| x.to_f**2 })
        mag_b = Math.sqrt(b.sum { |x| x.to_f**2 })

        return 0.0 if mag_a.zero? || mag_b.zero?

        dot / (mag_a * mag_b)
      end

      def keyword_relevance(query, key, entry)
        return 0.0 if query.blank?

        query_words = query.downcase.split(/\s+/)
        text = "#{key} #{entry['value']}".downcase
        matches = query_words.count { |w| text.include?(w) }
        matches.to_f / [query_words.size, 1].max
      end
    end
  end
end
