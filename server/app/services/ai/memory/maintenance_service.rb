# frozen_string_literal: true

module Ai
  module Memory
    # MaintenanceService - Unified maintenance for memory consolidation, decay, and integrity
    # Consolidates ConsolidationService, DecayService, IntegrityService
    class MaintenanceService
      include Consolidation
      include Decay
      include Integrity

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

      # Backward-compatible aliases
      alias_method :run_pipeline, :run_consolidation_pipeline
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
