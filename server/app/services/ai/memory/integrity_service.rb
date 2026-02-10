# frozen_string_literal: true

module Ai
  module Memory
    class IntegrityService
      SUPPORTED_ENTRY_TYPES = %w[
        Ai::AgentShortTermMemory
        Ai::SharedKnowledge
        Ai::ContextEntry
        Ai::CompoundLearning
      ].freeze

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Compute and store integrity hash for a memory entry
      # @param entry [ActiveRecord] A supported memory model instance
      # @return [Hash] { sealed: bool, hash: String, entry_id: String }
      def seal(entry)
        validate_entry_type!(entry)

        hash = compute_hash(entry_content(entry), entry_metadata(entry))

        case entry
        when Ai::SharedKnowledge
          # SharedKnowledge has a dedicated integrity_hash column and compute_integrity_hash!
          entry.update!(integrity_hash: hash)
        when Ai::CompoundLearning
          entry.update!(metadata: (entry.metadata || {}).merge("integrity_hash" => hash, "sealed_at" => Time.current.iso8601))
        when Ai::ContextEntry
          entry.update!(metadata: (entry.metadata || {}).merge("integrity_hash" => hash, "sealed_at" => Time.current.iso8601))
        when Ai::AgentShortTermMemory
          # STM stores hash in memory_value metadata or a dedicated field
          current_value = entry.memory_value || {}
          updated_value = if current_value.is_a?(Hash)
            current_value.merge("_integrity_hash" => hash, "_sealed_at" => Time.current.iso8601)
          else
            { "original" => current_value, "_integrity_hash" => hash, "_sealed_at" => Time.current.iso8601 }
          end
          entry.update!(memory_value: updated_value)
        end

        Rails.logger.info("[MemoryIntegrity] Sealed #{entry.class.name} id=#{entry.id} hash=#{hash[0..15]}...")
        { sealed: true, hash: hash, entry_id: entry.id }
      rescue StandardError => e
        Rails.logger.error("[MemoryIntegrity] Seal failed for #{entry.class.name} id=#{entry.id}: #{e.message}")
        { sealed: false, hash: nil, entry_id: entry.id, error: e.message }
      end

      # Verify integrity of a memory entry
      # @param entry [ActiveRecord] A supported memory model instance
      # @return [Hash] { valid: bool, expected_hash: String, actual_hash: String, tampered: bool }
      def verify(entry)
        validate_entry_type!(entry)

        stored_hash = stored_hash_for(entry)
        return { valid: true, expected_hash: nil, actual_hash: nil, tampered: false, unsealed: true } if stored_hash.blank?

        actual_hash = compute_hash(entry_content(entry), entry_metadata(entry))
        valid = stored_hash == actual_hash

        unless valid
          Rails.logger.warn("[MemoryIntegrity] Tamper detected: #{entry.class.name} id=#{entry.id} expected=#{stored_hash[0..15]}... actual=#{actual_hash[0..15]}...")
        end

        { valid: valid, expected_hash: stored_hash, actual_hash: actual_hash, tampered: !valid }
      rescue StandardError => e
        Rails.logger.error("[MemoryIntegrity] Verify failed for #{entry.class.name} id=#{entry.id}: #{e.message}")
        { valid: false, expected_hash: nil, actual_hash: nil, tampered: false, error: e.message }
      end

      # Batch verify all entries for an agent across memory tiers
      # @param agent [Ai::Agent] The agent whose memories to audit
      # @param tier [String, nil] Optional tier filter: "short_term", "long_term", "context"
      # @return [Hash] { total: Integer, verified: Integer, failed: Integer, entries: Array }
      def audit(agent:, tier: nil)
        results = { total: 0, verified: 0, failed: 0, unsealed: 0, entries: [] }

        # Short-term memories
        if tier.nil? || tier == "short_term"
          audit_short_term_memories(agent, results)
        end

        # Long-term memories (CompoundLearning)
        if tier.nil? || tier == "long_term"
          audit_compound_learnings(agent, results)
        end

        # Context entries
        if tier.nil? || tier == "context"
          audit_context_entries(agent, results)
        end

        Rails.logger.info(
          "[MemoryIntegrity] Audit complete for agent=#{agent.id}: " \
          "total=#{results[:total]} verified=#{results[:verified]} " \
          "failed=#{results[:failed]} unsealed=#{results[:unsealed]}"
        )

        results
      end

      # Verify and report on shared knowledge integrity
      # @param scope [Symbol] :account or :global
      # @return [Hash] { total: Integer, verified: Integer, failed: Integer, entries: Array }
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
          "[MemoryIntegrity] SharedKnowledge audit: " \
          "total=#{results[:total]} verified=#{results[:verified]} " \
          "failed=#{results[:failed]} unsealed=#{results[:unsealed]}"
        )

        results
      end

      private

      # SHA-256 of canonical JSON representation
      # @param content [Object] The content to hash
      # @param metadata [Hash] Metadata to include in hash computation
      # @return [String] Hex digest
      def compute_hash(content, metadata = {})
        canonical = {
          content: normalize_content(content),
          metadata: metadata.sort.to_h
        }.to_json

        Digest::SHA256.hexdigest(canonical)
      end

      # Normalize content for consistent hashing regardless of type
      def normalize_content(content)
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

      # Extract content from different entry types for hashing
      def entry_content(entry)
        case entry
        when Ai::AgentShortTermMemory
          value = entry.memory_value
          # Exclude internal integrity fields from hash computation
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

      # Extract relevant metadata for hashing (subset that should remain immutable)
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

      # Retrieve the stored integrity hash from an entry
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
    end
  end
end
