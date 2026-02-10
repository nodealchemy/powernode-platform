# frozen_string_literal: true

module Ai
  module Memory
    class DecayService
      DEFAULT_DECAY_RATE = 0.01     # 1% per day
      ARCHIVE_THRESHOLD = 0.1       # Archive when importance drops below this
      CLEANUP_BATCH_SIZE = 500
      REFRESH_BOOST_AMOUNT = 0.05   # Importance boost for recently accessed memories
      STM_MAX_AGE_DAYS = 7          # Force-expire STM entries older than this

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Apply temporal decay to all memory tiers for an agent
      # Reduces importance scores based on age and inactivity.
      #
      # @param agent [Ai::Agent] The agent whose memories to decay
      # @return [Hash] { decayed_count: Integer, archived_count: Integer, by_tier: Hash }
      def apply_decay(agent:)
        stats = { decayed_count: 0, archived_count: 0, by_tier: {} }

        # Decay short-term memories
        stm_stats = decay_short_term_memories(agent)
        stats[:by_tier][:short_term] = stm_stats
        stats[:decayed_count] += stm_stats[:decayed]
        stats[:archived_count] += stm_stats[:archived]

        # Decay long-term memories (CompoundLearning)
        lt_stats = decay_compound_learnings(agent)
        stats[:by_tier][:long_term] = lt_stats
        stats[:decayed_count] += lt_stats[:decayed]
        stats[:archived_count] += lt_stats[:archived]

        # Decay context entries
        ctx_stats = decay_context_entries(agent)
        stats[:by_tier][:context] = ctx_stats
        stats[:decayed_count] += ctx_stats[:decayed]
        stats[:archived_count] += ctx_stats[:archived]

        Rails.logger.info(
          "[MemoryDecay] Decay applied for agent=#{agent.id}: " \
          "decayed=#{stats[:decayed_count]} archived=#{stats[:archived_count]}"
        )

        stats
      end

      # Cleanup expired short-term memories
      # Uses the model's cleanup_expired! class method and also handles
      # aged-out entries that haven't been formally expired.
      #
      # @param agent [Ai::Agent, nil] Limit to a specific agent
      # @return [Hash] { deleted: Integer }
      def cleanup_expired(agent: nil)
        deleted = 0

        if agent
          # Agent-scoped cleanup
          expired_scope = Ai::AgentShortTermMemory
            .for_agent(agent.id)
            .expired

          deleted = expired_scope.delete_all

          # Also force-expire very old active entries
          aged_out = Ai::AgentShortTermMemory
            .for_agent(agent.id)
            .active
            .where("created_at < ?", STM_MAX_AGE_DAYS.days.ago)

          force_expired = aged_out.update_all(expires_at: Time.current)
          deleted += force_expired
        else
          # Account-wide cleanup via class method
          deleted = Ai::AgentShortTermMemory
            .joins("INNER JOIN ai_agents ON ai_agents.id = ai_agent_short_term_memories.agent_id")
            .where(ai_agents: { account_id: account.id })
            .expired
            .limit(CLEANUP_BATCH_SIZE)
            .delete_all
        end

        Rails.logger.info("[MemoryDecay] Expired cleanup: deleted=#{deleted}")
        { deleted: deleted }
      end

      # Archive stale long-term memories below importance threshold
      # Marks CompoundLearnings and ContextEntries as deprecated/archived
      # when their importance has decayed below the threshold.
      #
      # @param agent [Ai::Agent, nil] Limit to a specific agent
      # @param threshold [Float] Archive entries below this importance score
      # @return [Hash] { compound_archived: Integer, context_archived: Integer }
      def archive_stale(agent: nil, threshold: ARCHIVE_THRESHOLD)
        stats = { compound_archived: 0, context_archived: 0 }

        # Archive stale CompoundLearnings
        cl_scope = Ai::CompoundLearning
          .active
          .where(account_id: account.id)
          .where("importance_score < ?", threshold)
          .where("created_at < ?", 30.days.ago)

        cl_scope = cl_scope.where(source_agent_id: agent.id) if agent

        cl_scope.find_each(batch_size: CLEANUP_BATCH_SIZE) do |learning|
          learning.deprecate!
          stats[:compound_archived] += 1
        end

        # Archive stale ContextEntries
        ctx_scope = Ai::ContextEntry
          .active
          .where("importance_score IS NOT NULL AND importance_score < ?", threshold)
          .where("created_at < ?", 30.days.ago)

        ctx_scope = ctx_scope.by_agent(agent.id) if agent

        ctx_scope.find_each(batch_size: CLEANUP_BATCH_SIZE) do |entry|
          entry.archive!
          stats[:context_archived] += 1
        end

        Rails.logger.info(
          "[MemoryDecay] Stale archive: compound=#{stats[:compound_archived]} context=#{stats[:context_archived]}"
        )

        stats
      end

      # Refresh recently accessed memories by boosting importance
      # Counteracts temporal decay for memories that are still actively used.
      # Uses touch_access! pattern from AgentShortTermMemory.
      #
      # @param agent [Ai::Agent] The agent whose memories to refresh
      # @param since [Time] Only refresh entries accessed since this time
      # @return [Hash] { refreshed_count: Integer, by_tier: Hash }
      def refresh_accessed(agent:, since: 1.day.ago)
        stats = { refreshed_count: 0, by_tier: {} }

        # Refresh short-term memories
        stm_refreshed = refresh_short_term(agent, since)
        stats[:by_tier][:short_term] = stm_refreshed
        stats[:refreshed_count] += stm_refreshed

        # Refresh compound learnings
        cl_refreshed = refresh_compound_learnings(agent, since)
        stats[:by_tier][:long_term] = cl_refreshed
        stats[:refreshed_count] += cl_refreshed

        # Refresh context entries
        ctx_refreshed = refresh_context_entries(agent, since)
        stats[:by_tier][:context] = ctx_refreshed
        stats[:refreshed_count] += ctx_refreshed

        Rails.logger.info(
          "[MemoryDecay] Refreshed #{stats[:refreshed_count]} recently accessed memories for agent=#{agent.id}"
        )

        stats
      end

      # Run full decay pipeline for the account
      # @param agent [Ai::Agent, nil] Limit to specific agent or run for all
      # @return [Hash] Combined stats from all pipeline stages
      def run_pipeline(agent: nil)
        pipeline_stats = {
          decay: {},
          cleanup: {},
          archive: {},
          refresh: {}
        }

        agents = agent ? [agent] : account_agents

        # 1. Apply decay to all agents
        decay_totals = { decayed_count: 0, archived_count: 0 }
        agents.each do |ag|
          result = apply_decay(agent: ag)
          decay_totals[:decayed_count] += result[:decayed_count]
          decay_totals[:archived_count] += result[:archived_count]
        end
        pipeline_stats[:decay] = decay_totals

        # 2. Cleanup expired entries
        pipeline_stats[:cleanup] = cleanup_expired(agent: agent)

        # 3. Archive stale entries
        pipeline_stats[:archive] = archive_stale(agent: agent)

        # 4. Refresh recently accessed (counter-decay)
        refresh_totals = { refreshed_count: 0 }
        agents.each do |ag|
          result = refresh_accessed(agent: ag)
          refresh_totals[:refreshed_count] += result[:refreshed_count]
        end
        pipeline_stats[:refresh] = refresh_totals

        Rails.logger.info("[MemoryDecay] Pipeline complete: #{pipeline_stats.to_json}")
        pipeline_stats
      end

      private

      # === Short-Term Memory Decay ===

      def decay_short_term_memories(agent)
        stats = { decayed: 0, archived: 0 }

        Ai::AgentShortTermMemory
          .for_agent(agent.id)
          .active
          .where("last_accessed_at < ?", 1.day.ago)
          .find_each do |memory|
            days_since_access = ((Time.current - (memory.last_accessed_at || memory.created_at)) / 1.day).to_f

            # Reduce TTL proportionally for inactive memories
            if memory.ttl_seconds.present? && days_since_access > 1
              reduced_ttl = (memory.ttl_seconds * (1.0 - DEFAULT_DECAY_RATE * days_since_access)).to_i
              if reduced_ttl <= 0
                memory.update_columns(expires_at: Time.current)
                stats[:archived] += 1
              else
                new_expires = memory.created_at + reduced_ttl.seconds
                memory.update_columns(expires_at: new_expires) if new_expires < memory.expires_at
                stats[:decayed] += 1
              end
            end
          end

        stats
      end

      # === CompoundLearning Decay ===

      def decay_compound_learnings(agent)
        stats = { decayed: 0, archived: 0 }

        Ai::CompoundLearning
          .active
          .where(account_id: account.id, source_agent_id: agent.id)
          .where("updated_at < ?", 1.day.ago)
          .find_each do |learning|
            # Use the model's built-in decay_importance! method
            original_score = learning.importance_score
            learning.decay_importance!
            learning.reload

            if learning.importance_score < ARCHIVE_THRESHOLD && learning.created_at < 30.days.ago
              learning.deprecate!
              stats[:archived] += 1
            elsif learning.importance_score < original_score
              stats[:decayed] += 1
            end
          end

        stats
      end

      # === Context Entry Decay ===

      def decay_context_entries(agent)
        stats = { decayed: 0, archived: 0 }

        Ai::ContextEntry
          .active
          .by_agent(agent.id)
          .where("importance_score IS NOT NULL")
          .where("COALESCE(last_accessed_at, created_at) < ?", 1.day.ago)
          .find_each do |entry|
            days_since = ((Time.current - (entry.last_accessed_at || entry.created_at)) / 1.day).to_f
            decay_rate = entry.relevance_decay_rate.present? && entry.relevance_decay_rate > 0 ?
              entry.relevance_decay_rate : DEFAULT_DECAY_RATE

            new_importance = [entry.importance_score * ((1.0 - decay_rate) ** days_since), 0.0].max.round(4)

            if new_importance < ARCHIVE_THRESHOLD && entry.created_at < 30.days.ago
              entry.archive!
              stats[:archived] += 1
            elsif new_importance < entry.importance_score
              entry.update_columns(
                importance_score: new_importance,
                last_relevance_update: Time.current
              )
              stats[:decayed] += 1
            end
          end

        stats
      end

      # === Refresh (Counter-Decay) ===

      def refresh_short_term(agent, since)
        count = 0

        Ai::AgentShortTermMemory
          .for_agent(agent.id)
          .active
          .where("last_accessed_at >= ?", since)
          .find_each do |memory|
            memory.refresh_ttl!
            count += 1
          end

        count
      end

      def refresh_compound_learnings(agent, since)
        count = 0

        Ai::CompoundLearning
          .active
          .where(account_id: account.id, source_agent_id: agent.id)
          .where("updated_at >= ? OR (metadata->>'last_accessed_at')::timestamp >= ?", since, since)
          .find_each do |learning|
            learning.boost_importance!(REFRESH_BOOST_AMOUNT)
            count += 1
          end

        count
      end

      def refresh_context_entries(agent, since)
        count = 0

        Ai::ContextEntry
          .active
          .by_agent(agent.id)
          .where("last_accessed_at >= ?", since)
          .find_each do |entry|
            entry.boost_importance!(REFRESH_BOOST_AMOUNT)
            count += 1
          end

        count
      end

      # === Utility ===

      def account_agents
        Ai::Agent.where(account_id: account.id).limit(100)
      end
    end
  end
end
