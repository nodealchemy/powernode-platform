# frozen_string_literal: true

module Ai
  module Memory
    # Factual Memory Service - Store and retrieve verified facts
    # High confidence, no decay, structured queries
    class FactualMemoryService
      def initialize(agent:, account:)
        @agent = agent
        @account = account
        @persistent_context = find_or_create_context
      end

      # Store a verified fact
      def store(key:, value:, metadata: {}, source_type: "system", source_id: nil)
        entry = @persistent_context.context_entries.find_by(
          entry_key: key,
          archived_at: nil
        )

        content = normalize_content(value)

        if entry
          # Update existing fact if value changed
          if entry.content != content
            entry.update_content(content, create_version: true)
          else
            entry
          end
        else
          @persistent_context.context_entries.create!(
            entry_key: key,
            entry_type: "fact",
            memory_type: "factual",
            content: content,
            metadata: metadata,
            source_type: source_type,
            source_id: source_id,
            ai_agent_id: @agent.id,
            importance_score: 1.0,  # Facts are always important
            confidence_score: 1.0,  # Verified facts have full confidence
            decay_rate: 0.0,        # Facts don't decay
            version: 1
          )
        end
      end

      # Retrieve a specific fact by key
      def retrieve(key)
        entry = @persistent_context.context_entries
          .active
          .factual
          .find_by(entry_key: key)

        return nil unless entry

        entry.read_content
      end

      # Check if a fact exists
      def exists?(key)
        @persistent_context.context_entries
          .active
          .factual
          .exists?(entry_key: key)
      end

      # Get all facts for the agent
      def all(limit: 100)
        @persistent_context.context_entries
          .active
          .factual
          .by_agent(@agent.id)
          .order(created_at: :desc)
          .limit(limit)
          .map(&:entry_details)
      end

      # Search facts by key pattern
      def search_by_key(pattern)
        @persistent_context.context_entries
          .active
          .factual
          .by_agent(@agent.id)
          .where("entry_key ILIKE ?", "%#{pattern}%")
          .map(&:entry_details)
      end

      # Search facts by content
      def search_by_content(query)
        @persistent_context.context_entries
          .active
          .factual
          .by_agent(@agent.id)
          .where("content_text ILIKE ?", "%#{query}%")
          .map(&:entry_details)
      end

      # Remove a fact
      def remove(key)
        entry = @persistent_context.context_entries
          .active
          .factual
          .find_by(entry_key: key)

        entry&.archive!
      end

      # Bulk store facts
      def store_batch(facts)
        facts.map do |fact|
          store(
            key: fact[:key],
            value: fact[:value],
            metadata: fact[:metadata] || {},
            source_type: fact[:source_type] || "system",
            source_id: fact[:source_id]
          )
        end
      end

      # Get facts by category (using metadata)
      def by_category(category)
        @persistent_context.context_entries
          .active
          .factual
          .by_agent(@agent.id)
          .where("metadata->>'category' = ?", category)
          .map(&:entry_details)
      end

      # Export all facts
      def export
        all(limit: 10_000).map do |fact|
          {
            key: fact[:entry_key],
            value: fact[:content],
            metadata: fact[:metadata],
            created_at: fact[:created_at]
          }
        end
      end

      # Import facts from export
      def import(facts_data, overwrite: false)
        imported = 0
        skipped = 0

        facts_data.each do |fact|
          if exists?(fact[:key]) && !overwrite
            skipped += 1
            next
          end

          store(
            key: fact[:key],
            value: fact[:value],
            metadata: fact[:metadata] || {},
            source_type: "import"
          )
          imported += 1
        end

        { imported: imported, skipped: skipped }
      end

      private

      def find_or_create_context
        Ai::PersistentContext.find_or_create_by!(
          account_id: @account.id,
          context_type: "agent_memory",
          scope: "agent",
          ai_agent_id: @agent.id,
          name: "#{@agent.name} Factual Memory"
        ) do |ctx|
          ctx.access_control = { "level" => "private" }
          ctx.retention_policy = { "max_entries" => 10_000 }
        end
      end

      def normalize_content(value)
        case value
        when Hash
          value
        when String
          { "text" => value, "value" => value }
        when Numeric
          { "value" => value }
        when TrueClass, FalseClass
          { "value" => value }
        when Array
          { "items" => value }
        else
          { "value" => value.to_s }
        end
      end
    end
  end
end
