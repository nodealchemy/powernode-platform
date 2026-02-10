# frozen_string_literal: true

module Ai
  module Memory
    # MaintenanceService - Unified maintenance for memory consolidation, decay, and integrity
    # Consolidates ConsolidationService, DecayService, IntegrityService
    class MaintenanceService
      # === Consolidation constants ===
      PROMOTION_THRESHOLD = 3
      SIMILARITY_THRESHOLD = 0.92
      SHARED_PROMOTION_LIMIT = 50
      DEDUP_BATCH_SIZE = 100

      # === Decay constants ===
      DEFAULT_DECAY_RATE = 0.01
      ARCHIVE_THRESHOLD = 0.1
      CLEANUP_BATCH_SIZE = 500
      REFRESH_BOOST_AMOUNT = 0.05
      STM_MAX_AGE_DAYS = 7

      # === Integrity constants ===
      SUPPORTED_ENTRY_TYPES = %w[
        Ai::AgentShortTermMemory
        Ai::SharedKnowledge
        Ai::ContextEntry
        Ai::CompoundLearning
      ].freeze

      attr_reader :account

      def initialize(account:)
        @account = account
        @embedding_service = Ai::Memory::EmbeddingService.new(account: account)
      end

      # ==================== Consolidation ====================

      # Consolidate short-term memories to long-term for an agent
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
          when :promoted then stats[:promoted] += 1
          when :duplicate then stats[:skipped_duplicates] += 1
          when :error then stats[:errors] += 1
          end
        end

        Rails.logger.info(
          "[MemoryMaintenance] STM consolidation for agent=#{agent.id}: " \
          "promoted=#{stats[:promoted]} duplicates=#{stats[:skipped_duplicates]} errors=#{stats[:errors]}"
        )

        stats
      end

      # Consolidate team learnings into shared knowledge
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
          when :promoted then stats[:promoted] += 1
          when :duplicate then stats[:skipped_duplicates] += 1
          when :error then stats[:errors] += 1
          end
        end

        Rails.logger.info(
          "[MemoryMaintenance] Shared promotion for team=#{team.id}: " \
          "promoted=#{stats[:promoted]} duplicates=#{stats[:skipped_duplicates]} errors=#{stats[:errors]}"
        )

        stats
      end

      # Merge similar entries within a tier to reduce redundancy
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
          Rails.logger.warn("[MemoryMaintenance] Unknown tier for dedup: #{tier}")
        end

        Rails.logger.info(
          "[MemoryMaintenance] Dedup tier=#{tier}: " \
          "merged=#{stats[:merged]} archived=#{stats[:archived]} errors=#{stats[:errors]}"
        )

        stats
      end

      # Run full consolidation pipeline
      def run_consolidation_pipeline(agent: nil)
        pipeline_stats = {
          short_term_consolidation: {},
          shared_consolidation: {},
          dedup_long_term: {},
          dedup_shared: {},
          dedup_context: {}
        }

        agents = agent ? [agent] : account_agents

        stm_totals = { promoted: 0, skipped_duplicates: 0, errors: 0 }
        agents.each do |ag|
          result = consolidate_short_term(agent: ag)
          stm_totals[:promoted] += result[:promoted]
          stm_totals[:skipped_duplicates] += result[:skipped_duplicates]
          stm_totals[:errors] += result[:errors]
        end
        pipeline_stats[:short_term_consolidation] = stm_totals

        shared_totals = { promoted: 0, skipped_duplicates: 0, errors: 0 }
        account_teams.each do |team|
          result = consolidate_to_shared(team: team)
          shared_totals[:promoted] += result[:promoted]
          shared_totals[:skipped_duplicates] += result[:skipped_duplicates]
          shared_totals[:errors] += result[:errors]
        end
        pipeline_stats[:shared_consolidation] = shared_totals

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

        Rails.logger.info("[MemoryMaintenance] Consolidation pipeline complete: #{pipeline_stats.to_json}")
        pipeline_stats
      end

      # Backward-compatible alias
      alias_method :run_pipeline, :run_consolidation_pipeline

      # ==================== Decay ====================

      # Apply temporal decay to all memory tiers for an agent
      def apply_decay(agent:)
        stats = { decayed_count: 0, archived_count: 0, by_tier: {} }

        stm_stats = decay_short_term_memories(agent)
        stats[:by_tier][:short_term] = stm_stats
        stats[:decayed_count] += stm_stats[:decayed]
        stats[:archived_count] += stm_stats[:archived]

        lt_stats = decay_compound_learnings(agent)
        stats[:by_tier][:long_term] = lt_stats
        stats[:decayed_count] += lt_stats[:decayed]
        stats[:archived_count] += lt_stats[:archived]

        ctx_stats = decay_context_entries(agent)
        stats[:by_tier][:context] = ctx_stats
        stats[:decayed_count] += ctx_stats[:decayed]
        stats[:archived_count] += ctx_stats[:archived]

        Rails.logger.info(
          "[MemoryMaintenance] Decay applied for agent=#{agent.id}: " \
          "decayed=#{stats[:decayed_count]} archived=#{stats[:archived_count]}"
        )

        stats
      end

      # Cleanup expired short-term memories
      def cleanup_expired(agent: nil)
        deleted = 0

        if agent
          expired_scope = Ai::AgentShortTermMemory
            .for_agent(agent.id)
            .expired

          deleted = expired_scope.delete_all

          aged_out = Ai::AgentShortTermMemory
            .for_agent(agent.id)
            .active
            .where("created_at < ?", STM_MAX_AGE_DAYS.days.ago)

          force_expired = aged_out.update_all(expires_at: Time.current)
          deleted += force_expired
        else
          deleted = Ai::AgentShortTermMemory
            .joins("INNER JOIN ai_agents ON ai_agents.id = ai_agent_short_term_memories.agent_id")
            .where(ai_agents: { account_id: account.id })
            .expired
            .limit(CLEANUP_BATCH_SIZE)
            .delete_all
        end

        Rails.logger.info("[MemoryMaintenance] Expired cleanup: deleted=#{deleted}")
        { deleted: deleted }
      end

      # Archive stale long-term memories below importance threshold
      def archive_stale(agent: nil, threshold: ARCHIVE_THRESHOLD)
        stats = { compound_archived: 0, context_archived: 0 }

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
          "[MemoryMaintenance] Stale archive: compound=#{stats[:compound_archived]} context=#{stats[:context_archived]}"
        )

        stats
      end

      # Refresh recently accessed memories by boosting importance
      def refresh_accessed(agent:, since: 1.day.ago)
        stats = { refreshed_count: 0, by_tier: {} }

        stm_refreshed = refresh_short_term(agent, since)
        stats[:by_tier][:short_term] = stm_refreshed
        stats[:refreshed_count] += stm_refreshed

        cl_refreshed = refresh_compound_learnings(agent, since)
        stats[:by_tier][:long_term] = cl_refreshed
        stats[:refreshed_count] += cl_refreshed

        ctx_refreshed = refresh_context_entries(agent, since)
        stats[:by_tier][:context] = ctx_refreshed
        stats[:refreshed_count] += ctx_refreshed

        Rails.logger.info(
          "[MemoryMaintenance] Refreshed #{stats[:refreshed_count]} recently accessed memories for agent=#{agent.id}"
        )

        stats
      end

      # Run full decay pipeline for the account
      def run_decay_pipeline(agent: nil)
        pipeline_stats = {
          decay: {},
          cleanup: {},
          archive: {},
          refresh: {}
        }

        agents = agent ? [agent] : account_agents

        decay_totals = { decayed_count: 0, archived_count: 0 }
        agents.each do |ag|
          result = apply_decay(agent: ag)
          decay_totals[:decayed_count] += result[:decayed_count]
          decay_totals[:archived_count] += result[:archived_count]
        end
        pipeline_stats[:decay] = decay_totals

        pipeline_stats[:cleanup] = cleanup_expired(agent: agent)
        pipeline_stats[:archive] = archive_stale(agent: agent)

        refresh_totals = { refreshed_count: 0 }
        agents.each do |ag|
          result = refresh_accessed(agent: ag)
          refresh_totals[:refreshed_count] += result[:refreshed_count]
        end
        pipeline_stats[:refresh] = refresh_totals

        Rails.logger.info("[MemoryMaintenance] Decay pipeline complete: #{pipeline_stats.to_json}")
        pipeline_stats
      end

      # ==================== Integrity ====================

      # Compute and store integrity hash for a memory entry
      def seal(entry)
        validate_entry_type!(entry)

        hash = compute_hash(entry_content(entry), entry_metadata(entry))

        case entry
        when Ai::SharedKnowledge
          entry.update!(integrity_hash: hash)
        when Ai::CompoundLearning
          entry.update!(metadata: (entry.metadata || {}).merge("integrity_hash" => hash, "sealed_at" => Time.current.iso8601))
        when Ai::ContextEntry
          entry.update!(metadata: (entry.metadata || {}).merge("integrity_hash" => hash, "sealed_at" => Time.current.iso8601))
        when Ai::AgentShortTermMemory
          current_value = entry.memory_value || {}
          updated_value = if current_value.is_a?(Hash)
            current_value.merge("_integrity_hash" => hash, "_sealed_at" => Time.current.iso8601)
          else
            { "original" => current_value, "_integrity_hash" => hash, "_sealed_at" => Time.current.iso8601 }
          end
          entry.update!(memory_value: updated_value)
        end

        Rails.logger.info("[MemoryMaintenance] Sealed #{entry.class.name} id=#{entry.id} hash=#{hash[0..15]}...")
        { sealed: true, hash: hash, entry_id: entry.id }
      rescue StandardError => e
        Rails.logger.error("[MemoryMaintenance] Seal failed for #{entry.class.name} id=#{entry.id}: #{e.message}")
        { sealed: false, hash: nil, entry_id: entry.id, error: e.message }
      end

      # Verify integrity of a memory entry
      def verify(entry)
        validate_entry_type!(entry)

        stored_hash = stored_hash_for(entry)
        return { valid: true, expected_hash: nil, actual_hash: nil, tampered: false, unsealed: true } if stored_hash.blank?

        actual_hash = compute_hash(entry_content(entry), entry_metadata(entry))
        valid = stored_hash == actual_hash

        unless valid
          Rails.logger.warn("[MemoryMaintenance] Tamper detected: #{entry.class.name} id=#{entry.id} expected=#{stored_hash[0..15]}... actual=#{actual_hash[0..15]}...")
        end

        { valid: valid, expected_hash: stored_hash, actual_hash: actual_hash, tampered: !valid }
      rescue StandardError => e
        Rails.logger.error("[MemoryMaintenance] Verify failed for #{entry.class.name} id=#{entry.id}: #{e.message}")
        { valid: false, expected_hash: nil, actual_hash: nil, tampered: false, error: e.message }
      end

      # Batch verify all entries for an agent across memory tiers
      def audit(agent:, tier: nil)
        results = { total: 0, verified: 0, failed: 0, unsealed: 0, entries: [] }

        if tier.nil? || tier == "short_term"
          audit_short_term_memories(agent, results)
        end

        if tier.nil? || tier == "long_term"
          audit_compound_learnings(agent, results)
        end

        if tier.nil? || tier == "context"
          audit_context_entries(agent, results)
        end

        Rails.logger.info(
          "[MemoryMaintenance] Audit complete for agent=#{agent.id}: " \
          "total=#{results[:total]} verified=#{results[:verified]} " \
          "failed=#{results[:failed]} unsealed=#{results[:unsealed]}"
        )

        results
      end

      # Verify and report on shared knowledge integrity
      def audit_shared_knowledge(scope: :account)
        results = { total: 0, verified: 0, failed: 0, unsealed: 0, entries: [] }

        knowledge_scope = Ai::SharedKnowledge.where(account_id: account.id)
        knowledge_scope = knowledge_scope.accessible_by("global") if scope == :global

        knowledge_scope.find_each do |entry|
          results[:total] += 1
          result = verify(entry)

          if result[:unsealed]
            results[:unsealed] += 1
          elsif result[:valid]
            results[:verified] += 1
          else
            results[:failed] += 1
            results[:entries] << {
              id: entry.id,
              title: entry.title,
              type: "SharedKnowledge",
              result: result
            }
          end
        end

        Rails.logger.info(
          "[MemoryMaintenance] SharedKnowledge audit: " \
          "total=#{results[:total]} verified=#{results[:verified]} " \
          "failed=#{results[:failed]} unsealed=#{results[:unsealed]}"
        )

        results
      end

      # Backward-compatible alias for audit
      alias_method :audit_integrity, :audit

      # ==================== Memory Management ====================

      # Get memory usage statistics
      def memory_stats
        contexts = Ai::PersistentContext.where(account: account)
        entries = Ai::ContextEntry.joins(:persistent_context)
                                .where(ai_persistent_contexts: { account_id: account.id })

        {
          total_contexts: contexts.count,
          active_contexts: contexts.active.count,
          archived_contexts: contexts.archived.count,
          total_entries: entries.count,
          active_entries: entries.active.count,
          total_size_bytes: contexts.sum(:data_size_bytes),
          contexts_by_type: contexts.group(:context_type).count,
          entries_by_type: entries.group(:entry_type).count,
          avg_importance: entries.active.average(:importance_score)&.round(3)
        }
      end

      # Get context health metrics
      def context_health(context:)
        entries = context.context_entries

        {
          entry_count: entries.count,
          active_entries: entries.active.count,
          archived_entries: entries.archived.count,
          expired_entries: entries.expired.count,
          entries_with_embeddings: entries.where.not(embedding: nil).count,
          avg_importance: entries.active.average(:importance_score)&.round(3),
          total_access_count: entries.sum(:access_count),
          last_accessed: entries.maximum(:last_accessed_at),
          data_size_bytes: context.data_size_bytes,
          retention_status: check_retention_status(context)
        }
      end

      # Sync context between agents
      def sync_context(from_context:, to_context:, entry_types: nil, min_importance: nil)
        scope = from_context.context_entries.active
        scope = scope.by_type(entry_types) if entry_types.present?
        scope = scope.where("importance_score >= ?", min_importance) if min_importance.present?

        synced = 0

        scope.find_each do |entry|
          existing = to_context.context_entries.find_by(entry_key: entry.entry_key)

          if existing.present?
            if entry.updated_at > existing.updated_at
              existing.update!(
                content: entry.content,
                metadata: entry.metadata,
                importance_score: entry.importance_score
              )
              synced += 1
            end
          else
            to_context.context_entries.create!(
              entry_key: entry.entry_key,
              entry_type: entry.entry_type,
              content: entry.content,
              metadata: entry.metadata.merge(synced_from: from_context.id),
              importance_score: entry.importance_score,
              source_type: "system",
              source_id: entry.id
            )
            synced += 1
          end
        end

        { synced: synced }
      end

      # Run full maintenance pipeline (consolidation + decay)
      def run_full_maintenance(agent: nil)
        {
          consolidation: run_consolidation_pipeline(agent: agent),
          decay: run_decay_pipeline(agent: agent)
        }
      end

      private

      # === Consolidation private helpers ===

      def promote_stm_to_long_term(memory, agent)
        content = memory.memory_value
        content_text = content.is_a?(Hash) ? content.except("_integrity_hash", "_sealed_at").to_json : content.to_s

        embedding = @embedding_service.generate(content_text)

        if embedding
          duplicates = Ai::CompoundLearning.find_similar(
            embedding,
            account_id: account.id,
            threshold: SIMILARITY_THRESHOLD
          )

          if duplicates.any?
            duplicates.first.boost_importance!(0.03)
            return :duplicate
          end
        end

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

        seal(learning)
        memory.update_columns(expires_at: Time.current)

        :promoted
      rescue StandardError => e
        Rails.logger.error("[MemoryMaintenance] STM promotion failed for id=#{memory.id}: #{e.message}")
        :error
      end

      def promote_learning_to_shared(learning, team)
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
          text_match = Ai::SharedKnowledge
            .where(account_id: account.id)
            .where("content ILIKE ?", "%#{Ai::SharedKnowledge.sanitize_sql_like(learning.content.truncate(100))}%")
            .first

          return :duplicate if text_match.present?
        end

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

        seal(shared)

        :promoted
      rescue StandardError => e
        Rails.logger.error("[MemoryMaintenance] Shared promotion failed for learning=#{learning.id}: #{e.message}")
        :error
      end

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
        Rails.logger.error("[MemoryMaintenance] CompoundLearning dedup failed: #{e.message}")
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
        Rails.logger.error("[MemoryMaintenance] SharedKnowledge dedup failed: #{e.message}")
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
        Rails.logger.error("[MemoryMaintenance] ContextEntry dedup failed: #{e.message}")
        stats[:errors] += 1
      end

      # === Consolidation merge helpers ===

      def merge_compound_learnings(keeper, duplicate)
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
        base = [memory.access_count / 10.0, 0.8].min
        type_boost = memory.memory_type == "general" ? 0.0 : 0.1
        [(base + type_boost).round(4), 1.0].min
      end

      # === Decay private helpers ===

      def decay_short_term_memories(agent)
        stats = { decayed: 0, archived: 0 }

        Ai::AgentShortTermMemory
          .for_agent(agent.id)
          .active
          .where("last_accessed_at < ?", 1.day.ago)
          .find_each do |memory|
            days_since_access = ((Time.current - (memory.last_accessed_at || memory.created_at)) / 1.day).to_f

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

      def decay_compound_learnings(agent)
        stats = { decayed: 0, archived: 0 }

        Ai::CompoundLearning
          .active
          .where(account_id: account.id, source_agent_id: agent.id)
          .where("updated_at < ?", 1.day.ago)
          .find_each do |learning|
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

      # === Integrity private helpers ===

      def compute_hash(content, metadata = {})
        canonical = {
          content: normalize_integrity_content(content),
          metadata: metadata.sort.to_h
        }.to_json

        Digest::SHA256.hexdigest(canonical)
      end

      def normalize_integrity_content(content)
        case content
        when Hash
          content.sort.to_h.to_json
        when Array
          content.to_json
        when NilClass
          ""
        else
          content.to_s
        end
      end

      def entry_content(entry)
        case entry
        when Ai::AgentShortTermMemory
          value = entry.memory_value
          if value.is_a?(Hash)
            value.except("_integrity_hash", "_sealed_at")
          else
            value
          end
        when Ai::SharedKnowledge
          entry.content
        when Ai::CompoundLearning
          entry.content
        when Ai::ContextEntry
          entry.content
        end
      end

      def entry_metadata(entry)
        case entry
        when Ai::AgentShortTermMemory
          {
            "memory_key" => entry.memory_key,
            "memory_type" => entry.memory_type,
            "agent_id" => entry.agent_id,
            "session_id" => entry.session_id
          }
        when Ai::SharedKnowledge
          {
            "title" => entry.title,
            "content_type" => entry.content_type,
            "source_type" => entry.source_type,
            "account_id" => entry.account_id
          }
        when Ai::CompoundLearning
          {
            "category" => entry.category,
            "scope" => entry.scope,
            "extraction_method" => entry.extraction_method,
            "account_id" => entry.account_id
          }
        when Ai::ContextEntry
          {
            "entry_key" => entry.entry_key,
            "entry_type" => entry.entry_type,
            "memory_type" => entry.memory_type,
            "version" => entry.version
          }
        else
          {}
        end
      end

      def stored_hash_for(entry)
        case entry
        when Ai::SharedKnowledge
          entry.integrity_hash
        when Ai::CompoundLearning
          entry.metadata&.dig("integrity_hash")
        when Ai::ContextEntry
          entry.metadata&.dig("integrity_hash")
        when Ai::AgentShortTermMemory
          value = entry.memory_value
          value.is_a?(Hash) ? value["_integrity_hash"] : nil
        end
      end

      def validate_entry_type!(entry)
        unless SUPPORTED_ENTRY_TYPES.include?(entry.class.name)
          raise ArgumentError, "Unsupported entry type: #{entry.class.name}. Supported: #{SUPPORTED_ENTRY_TYPES.join(', ')}"
        end
      end

      # === Audit helpers ===

      def audit_short_term_memories(agent, results)
        Ai::AgentShortTermMemory
          .for_agent(agent.id)
          .active
          .find_each do |entry|
            process_audit_entry(entry, "AgentShortTermMemory", results)
          end
      end

      def audit_compound_learnings(agent, results)
        Ai::CompoundLearning
          .where(account_id: account.id, source_agent_id: agent.id)
          .active
          .find_each do |entry|
            process_audit_entry(entry, "CompoundLearning", results)
          end
      end

      def audit_context_entries(agent, results)
        Ai::ContextEntry
          .by_agent(agent.id)
          .active
          .find_each do |entry|
            process_audit_entry(entry, "ContextEntry", results)
          end
      end

      def process_audit_entry(entry, type_label, results)
        results[:total] += 1
        result = verify(entry)

        if result[:unsealed]
          results[:unsealed] += 1
        elsif result[:valid]
          results[:verified] += 1
        else
          results[:failed] += 1
          results[:entries] << {
            id: entry.id,
            type: type_label,
            result: result
          }
        end
      end

      # === Utility ===

      def account_agents
        Ai::Agent.where(account_id: account.id).limit(100)
      end

      def account_teams
        Ai::AgentTeam.where(account_id: account.id).limit(50)
      end

      def check_retention_status(context)
        policy = context.retention_policy
        return "no_policy" if policy.blank?

        issues = []

        if policy["max_entries"].present?
          current = context.context_entries.active.count
          if current > policy["max_entries"]
            issues << "over_limit"
          elsif current > policy["max_entries"] * 0.9
            issues << "near_limit"
          end
        end

        if policy["max_age_days"].present?
          old_count = context.context_entries
            .active
            .where("created_at < ?", policy["max_age_days"].days.ago)
            .count

          issues << "has_old_entries" if old_count > 0
        end

        issues.empty? ? "healthy" : issues.join(",")
      end
    end
  end
end
