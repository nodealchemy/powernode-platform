# frozen_string_literal: true

module Ai
  module Learning
    class MemoryConsolidationService
      MAX_EPISODIC_MEMORIES = 1000
      CONSOLIDATION_BATCH_SIZE = 50

      def initialize(account:)
        @account = account
      end

      def consolidate
        prune_expired_memories
        consolidate_similar_memories
        enforce_retention_limits
      end

      private

      def prune_expired_memories
        return unless defined?(Ai::Memory::EpisodicMemory)

        Ai::Memory::EpisodicMemory.where(account: @account)
                                   .where("expires_at IS NOT NULL AND expires_at < ?", Time.current)
                                   .delete_all
      rescue => e
        Rails.logger.error "[MemoryConsolidation] Pruning failed: #{e.message}"
      end

      def consolidate_similar_memories
        return unless defined?(Ai::Memory::EpisodicMemory)

        agents = Ai::Agent.where(account: @account)
        agents.find_each do |agent|
          memories = Ai::Memory::EpisodicMemory.where(
            account: @account,
            agent_id: agent.id
          ).order(created_at: :desc)

          next if memories.count < CONSOLIDATION_BATCH_SIZE

          # Group by context type/category if available
          memories.group_by { |m| m.metadata&.dig("category") || "general" }.each do |category, group|
            next if group.size < 5

            # Keep most recent 5, summarize the rest
            to_consolidate = group[5..]
            next if to_consolidate.blank?

            summary_content = to_consolidate.map { |m| m.content.to_s.truncate(200) }.join("\n")

            consolidated = Ai::Memory::EpisodicMemory.create!(
              account: @account,
              agent_id: agent.id,
              content: "Consolidated from #{to_consolidate.size} memories (#{category}): #{summary_content.truncate(2000)}",
              memory_type: "consolidated",
              metadata: {
                category: category,
                consolidated_count: to_consolidate.size,
                source_ids: to_consolidate.map(&:id),
                consolidated_at: Time.current.iso8601
              }
            )

            to_consolidate.each(&:destroy)
          end
        end
      rescue => e
        Rails.logger.error "[MemoryConsolidation] Consolidation failed: #{e.message}"
      end

      def enforce_retention_limits
        return unless defined?(Ai::Memory::EpisodicMemory)

        Ai::Agent.where(account: @account).find_each do |agent|
          count = Ai::Memory::EpisodicMemory.where(
            account: @account,
            agent_id: agent.id
          ).count

          next if count <= MAX_EPISODIC_MEMORIES

          excess = count - MAX_EPISODIC_MEMORIES
          Ai::Memory::EpisodicMemory.where(
            account: @account,
            agent_id: agent.id
          ).order(created_at: :asc).limit(excess).delete_all
        end
      rescue => e
        Rails.logger.error "[MemoryConsolidation] Retention enforcement failed: #{e.message}"
      end
    end
  end
end
