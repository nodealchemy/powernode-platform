# frozen_string_literal: true

module Ai
  module Memory
    class ConsolidationService
      PROMOTION_THRESHOLD = 3       # access_count needed for short_term -> long_term
      SIMILARITY_THRESHOLD = 0.92   # dedup threshold
      SHARED_PROMOTION_LIMIT = 50   # max entries to promote per run
      DEDUP_BATCH_SIZE = 100        # entries per dedup batch

      attr_reader :account

      def initialize(account:)
        @account = account
        @embedding_service = Ai::Memory::EmbeddingService.new(account: account)
        @integrity_service = Ai::Memory::IntegrityService.new(account: account)
      end

      # Consolidate short-term memories to long-term for an agent
      # Finds frequently accessed STM entries, checks for duplicates, creates
      # CompoundLearning records, seals them, and archives the originals.
      #
      # @param agent [Ai::Agent] The agent whose STM to consolidate
      # @param session_id [String, nil] Limit to a specific session
      # @return [Hash] { promoted: Integer, skipped_duplicates: Integer, errors: Integer }
      def consolidate_short_term(agent:, session_id: nil)
        stats = { promoted: 0, skipped_duplicates: 0, errors: 0 }

        scope = Ai::AgentShortTermMemory
          .for_agent(agent.id)
          .active
          .frequently_accessed
          .where("access_count >= ?", PROMOTION_THRESHOLD)

        scope = scope.for_session(session_id) if session_id.present?

        scope.find_each do |memory|
          result = promote_stm_to_long_term(memory, agent)

          case result
          when :promoted
            stats[:promoted] += 1
          when :duplicate
            stats[:skipped_duplicates] += 1
          when :error
            stats[:errors] += 1
          end
        end

        Rails.logger.info(
          "[MemoryConsolidation] STM consolidation for agent=#{agent.id}: " \
          "promoted=#{stats[:promoted]} duplicates=#{stats[:skipped_duplicates]} errors=#{stats[:errors]}"
        )

        stats
      end

      # Consolidate team learnings into shared knowledge
      # Finds high-importance CompoundLearnings from a team, deduplicates
      # against existing SharedKnowledge, creates new shared entries.
      #
      # @param team [Ai::AgentTeam] The team whose learnings to promote
      # @param min_importance [Float] Minimum importance threshold (0.0-1.0)
      # @return [Hash] { promoted: Integer, skipped_duplicates: Integer, errors: Integer }
      def consolidate_to_shared(team:, min_importance: 0.7)
        stats = { promoted: 0, skipped_duplicates: 0, errors: 0 }

        candidates = Ai::CompoundLearning
          .active
          .for_team(team.id)
          .where(account_id: account.id)
          .where("importance_score >= ?", min_importance)
          .order(importance_score: :desc)
          .limit(SHARED_PROMOTION_LIMIT)

        candidates.find_each do |learning|
          result = promote_learning_to_shared(learning, team)

          case result
          when :promoted
            stats[:promoted] += 1
          when :duplicate
            stats[:skipped_duplicates] += 1
          when :error
            stats[:errors] += 1
          end
        end

        Rails.logger.info(
          "[MemoryConsolidation] Shared promotion for team=#{team.id}: " \
          "promoted=#{stats[:promoted]} duplicates=#{stats[:skipped_duplicates]} errors=#{stats[:errors]}"
        )

        stats
      end

      # Merge similar entries within a tier to reduce redundancy
      # Finds entries with >SIMILARITY_THRESHOLD similarity, merges content,
      # combines metadata, retains the highest importance, and archives duplicates.
      #
      # @param tier [String] "long_term", "shared", or "context"
      # @param agent [Ai::Agent, nil] Limit to a specific agent (for long_term/context)
      # @return [Hash] { merged: Integer, archived: Integer, errors: Integer }
      def deduplicate(tier:, agent: nil)
        stats = { merged: 0, archived: 0, errors: 0 }

        case tier
        when "long_term"
          deduplicate_compound_learnings(agent, stats)
        when "shared"
          deduplicate_shared_knowledge(stats)
        when "context"
          deduplicate_context_entries(agent, stats)
        else
          Rails.logger.warn("[MemoryConsolidation] Unknown tier for dedup: #{tier}")
        end

        Rails.logger.info(
          "[MemoryConsolidation] Dedup tier=#{tier}: " \
          "merged=#{stats[:merged]} archived=#{stats[:archived]} errors=#{stats[:errors]}"
        )

        stats
      end

      # Run full consolidation pipeline
      # @param agent [Ai::Agent, nil] Target agent (runs for all account agents if nil)
      # @return [Hash] Combined stats from all pipeline stages
      def run_pipeline(agent: nil)
        pipeline_stats = {
          short_term_consolidation: {},
          shared_consolidation: {},
          dedup_long_term: {},
          dedup_shared: {},
          dedup_context: {}
        }

        agents = agent ? [agent] : account_agents

        # 1. Consolidate short-term for each agent
        stm_totals = { promoted: 0, skipped_duplicates: 0, errors: 0 }
        agents.each do |ag|
          result = consolidate_short_term(agent: ag)
          stm_totals[:promoted] += result[:promoted]
          stm_totals[:skipped_duplicates] += result[:skipped_duplicates]
          stm_totals[:errors] += result[:errors]
        end
        pipeline_stats[:short_term_consolidation] = stm_totals

        # 2. Consolidate to shared for each team
        shared_totals = { promoted: 0, skipped_duplicates: 0, errors: 0 }
        account_teams.each do |team|
          result = consolidate_to_shared(team: team)
          shared_totals[:promoted] += result[:promoted]
          shared_totals[:skipped_duplicates] += result[:skipped_duplicates]
          shared_totals[:errors] += result[:errors]
        end
        pipeline_stats[:shared_consolidation] = shared_totals

        # 3. Deduplicate within tiers
        pipeline_stats[:dedup_long_term] = deduplicate(tier: "long_term", agent: agent)
        pipeline_stats[:dedup_shared] = deduplicate(tier: "shared")

        if agent
          pipeline_stats[:dedup_context] = deduplicate(tier: "context", agent: agent)
        else
          ctx_totals = { merged: 0, archived: 0, errors: 0 }
          agents.each do |ag|
            result = deduplicate(tier: "context", agent: ag)
            ctx_totals[:merged] += result[:merged]
            ctx_totals[:archived] += result[:archived]
            ctx_totals[:errors] += result[:errors]
          end
          pipeline_stats[:dedup_context] = ctx_totals
        end

        Rails.logger.info("[MemoryConsolidation] Pipeline complete: #{pipeline_stats.to_json}")
        pipeline_stats
      end

      private

      # === STM Promotion ===

      def promote_stm_to_long_term(memory, agent)
        content = memory.memory_value
        content_text = content.is_a?(Hash) ? content.except("_integrity_hash", "_sealed_at").to_json : content.to_s

        # Generate embedding for dedup check
        embedding = @embedding_service.generate(content_text)

        # Check for duplicates in long-term
        if embedding
          duplicates = Ai::CompoundLearning.find_similar(
            embedding,
            account_id: account.id,
            threshold: SIMILARITY_THRESHOLD
          )

          if duplicates.any?
            # Boost existing instead of creating duplicate
            duplicates.first.boost_importance!(0.03)
            return :duplicate
          end
        end

        # Create new CompoundLearning
        learning = Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          content: content_text,
          category: map_memory_type_to_category(memory.memory_type),
          scope: "team",
          status: "active",
          importance_score: calculate_promotion_importance(memory),
          confidence_score: 0.7,
          extraction_method: "consolidation",
          embedding: embedding,
          metadata: {
            "memory_key" => memory.memory_key,
            "source_session" => memory.session_id,
            "original_access_count" => memory.access_count,
            "consolidated_at" => Time.current.iso8601
          }
        )

        # Seal the new entry
        @integrity_service.seal(learning)

        # Archive the original STM entry by setting it to expire immediately
        memory.update_columns(expires_at: Time.current)

        :promoted
      rescue StandardError => e
        Rails.logger.error("[MemoryConsolidation] STM promotion failed for id=#{memory.id}: #{e.message}")
        :error
      end

      # === Shared Knowledge Promotion ===

      def promote_learning_to_shared(learning, team)
        # Check for duplicates in shared knowledge via semantic search
        if learning.embedding.present?
          existing = Ai::SharedKnowledge
            .where(account_id: account.id)
            .with_embedding
            .semantic_search(learning.embedding, limit: 3, threshold: SIMILARITY_THRESHOLD)

          if existing.any?
            existing.first.touch_usage!
            return :duplicate
          end
        else
          # Fallback text-based dedup
          text_match = Ai::SharedKnowledge
            .where(account_id: account.id)
            .where("content ILIKE ?", "%#{Ai::SharedKnowledge.sanitize_sql_like(learning.content.truncate(100))}%")
            .first

          return :duplicate if text_match.present?
        end

        # Create shared knowledge entry
        shared = Ai::SharedKnowledge.create!(
          account: account,
          title: learning.title || "Learning: #{learning.content.truncate(80)}",
          content: learning.content,
          content_type: "text",
          source_type: "agent",
          source_id: learning.source_agent_id,
          tags: learning.tags || [],
          access_level: "team",
          quality_score: learning.effective_importance,
          provenance: {
            "source" => "consolidation",
            "team_id" => team.id,
            "team_name" => team.name,
            "original_learning_id" => learning.id,
            "category" => learning.category,
            "promoted_at" => Time.current.iso8601
          },
          embedding: learning.embedding
        )

        # Seal the new shared knowledge entry
        @integrity_service.seal(shared)

        :promoted
      rescue StandardError => e
        Rails.logger.error("[MemoryConsolidation] Shared promotion failed for learning=#{learning.id}: #{e.message}")
        :error
      end

      # === Deduplication ===

      def deduplicate_compound_learnings(agent, stats)
        scope = Ai::CompoundLearning
          .active
          .where(account_id: account.id)
          .with_embedding
          .order(importance_score: :desc)

        scope = scope.where(source_agent_id: agent.id) if agent

        processed_ids = Set.new

        scope.limit(DEDUP_BATCH_SIZE).each do |entry|
          next if processed_ids.include?(entry.id)

          similar = Ai::CompoundLearning.find_similar(
            entry.embedding,
            account_id: account.id,
            threshold: SIMILARITY_THRESHOLD
          ).where.not(id: entry.id)

          similar.each do |duplicate|
            next if processed_ids.include?(duplicate.id)

            merge_compound_learnings(entry, duplicate)
            processed_ids.add(duplicate.id)
            stats[:archived] += 1
          end

          stats[:merged] += 1 if similar.any?
        end
      rescue StandardError => e
        Rails.logger.error("[MemoryConsolidation] CompoundLearning dedup failed: #{e.message}")
        stats[:errors] += 1
      end

      def deduplicate_shared_knowledge(stats)
        scope = Ai::SharedKnowledge
          .where(account_id: account.id)
          .with_embedding
          .order(quality_score: :desc, usage_count: :desc)

        processed_ids = Set.new

        scope.limit(DEDUP_BATCH_SIZE).each do |entry|
          next if processed_ids.include?(entry.id)

          similar = Ai::SharedKnowledge
            .where(account_id: account.id)
            .with_embedding
            .where.not(id: entry.id)
            .semantic_search(entry.embedding, limit: 5, threshold: SIMILARITY_THRESHOLD)

          similar.each do |duplicate|
            next if processed_ids.include?(duplicate.id)

            merge_shared_knowledge(entry, duplicate)
            processed_ids.add(duplicate.id)
            stats[:archived] += 1
          end

          stats[:merged] += 1 if similar.any?
        end
      rescue StandardError => e
        Rails.logger.error("[MemoryConsolidation] SharedKnowledge dedup failed: #{e.message}")
        stats[:errors] += 1
      end

      def deduplicate_context_entries(agent, stats)
        return unless agent

        scope = Ai::ContextEntry
          .active
          .by_agent(agent.id)
          .with_embedding
          .order(importance_score: :desc)

        processed_ids = Set.new

        scope.limit(DEDUP_BATCH_SIZE).each do |entry|
          next if processed_ids.include?(entry.id)
          next unless entry.embedding.present?

          similar = Ai::ContextEntry
            .active
            .by_agent(agent.id)
            .with_embedding
            .where.not(id: entry.id)
            .nearest_neighbors(:embedding, entry.embedding, distance: "cosine")
            .limit(5)
            .to_a
            .select { |e| e.neighbor_distance <= 1.0 - SIMILARITY_THRESHOLD }

          similar.each do |duplicate|
            next if processed_ids.include?(duplicate.id)

            merge_context_entries(entry, duplicate)
            processed_ids.add(duplicate.id)
            stats[:archived] += 1
          end

          stats[:merged] += 1 if similar.any?
        end
      rescue StandardError => e
        Rails.logger.error("[MemoryConsolidation] ContextEntry dedup failed: #{e.message}")
        stats[:errors] += 1
      end

      # === Merge helpers ===

      def merge_compound_learnings(keeper, duplicate)
        # Keep the higher importance, merge metadata, archive the duplicate
        new_importance = [keeper.importance_score, duplicate.importance_score].max
        new_confidence = [keeper.confidence_score, duplicate.confidence_score].max
        combined_access = keeper.access_count + duplicate.access_count

        keeper.update!(
          importance_score: new_importance,
          confidence_score: new_confidence,
          access_count: combined_access,
          metadata: (keeper.metadata || {}).merge(
            "merged_ids" => ((keeper.metadata || {})["merged_ids"] || []) + [duplicate.id],
            "last_merge_at" => Time.current.iso8601
          )
        )

        duplicate.supersede!(keeper)
      end

      def merge_shared_knowledge(keeper, duplicate)
        new_quality = [keeper.quality_score || 0, duplicate.quality_score || 0].max
        combined_usage = keeper.usage_count + duplicate.usage_count
        combined_tags = ((keeper.tags || []) + (duplicate.tags || [])).uniq

        keeper.update!(
          quality_score: new_quality,
          usage_count: combined_usage,
          tags: combined_tags,
          provenance: (keeper.provenance || {}).merge(
            "merged_ids" => ((keeper.provenance || {})["merged_ids"] || []) + [duplicate.id],
            "last_merge_at" => Time.current.iso8601
          )
        )

        duplicate.destroy
      end

      def merge_context_entries(keeper, duplicate)
        new_importance = [keeper.importance_score || 0, duplicate.importance_score || 0].max
        new_confidence = [keeper.confidence_score || 0, duplicate.confidence_score || 0].max
        combined_access = keeper.access_count + duplicate.access_count

        keeper.update!(
          importance_score: new_importance,
          confidence_score: new_confidence,
          access_count: combined_access,
          metadata: (keeper.metadata || {}).merge(
            "merged_ids" => ((keeper.metadata || {})["merged_ids"] || []) + [duplicate.id],
            "last_merge_at" => Time.current.iso8601
          )
        )

        duplicate.archive!
      end

      # === Utility ===

      def map_memory_type_to_category(memory_type)
        case memory_type
        when "observation" then "discovery"
        when "plan" then "best_practice"
        when "tool_result" then "fact"
        when "conversation" then "pattern"
        else "fact"
        end
      end

      def calculate_promotion_importance(memory)
        # Base importance from access frequency
        base = [memory.access_count / 10.0, 0.8].min
        # Boost for non-general types
        type_boost = memory.memory_type == "general" ? 0.0 : 0.1
        [(base + type_boost).round(4), 1.0].min
      end

      def account_agents
        Ai::Agent.where(account_id: account.id).limit(100)
      end

      def account_teams
        Ai::AgentTeam.where(account_id: account.id).limit(50)
      end
    end
  end
end
