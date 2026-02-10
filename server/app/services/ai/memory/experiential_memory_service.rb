# frozen_string_literal: true

module Ai
  module Memory
    # Experiential Memory Service - Store past outcomes, interactions, learned patterns
    # Uses vector similarity search, importance scoring, and temporal decay
    class ExperientialMemoryService
      DEFAULT_DECAY_RATE = 0.01  # Importance decays ~1% per day
      DEFAULT_IMPORTANCE = 0.5

      def initialize(agent:, account:)
        @agent = agent
        @account = account
        @persistent_context = find_or_create_context
        @embedding_service = EmbeddingService.new(account: account)
      end

      # Store an experiential memory
      def store(content:, context: {}, outcome_success: nil, importance: nil, tags: [], source_type: "agent_output")
        entry_key = generate_entry_key(content)

        # Generate embedding for semantic search
        embedding = generate_embedding(content)

        entry = @persistent_context.context_entries.create!(
          entry_key: entry_key,
          entry_type: "memory",
          memory_type: "experiential",
          content: normalize_content(content),
          content_text: extract_text(content),
          metadata: { "context" => context, "embedding" => embedding },
          source_type: source_type,
          ai_agent_id: @agent.id,
          importance_score: importance || calculate_importance(outcome_success),
          confidence_score: calculate_confidence(context),
          decay_rate: DEFAULT_DECAY_RATE,
          context_tags: tags,
          task_context: context,
          outcome_success: outcome_success,
          version: 1
        )

        # Consolidate similar memories if needed
        consolidate_if_needed(entry)

        entry
      end

      # Semantic search for relevant memories
      def search(query, limit: 10, threshold: 0.7, tags: nil, outcome_filter: nil)
        # Generate query embedding
        query_embedding = @embedding_service.generate(query)

        return keyword_search(query, limit: limit, tags: tags) unless query_embedding

        # Use pgvector similarity search
        scope = build_search_scope(tags: tags, outcome_filter: outcome_filter)

        if Ai::ContextEntry.embedding_column_exists?
          # Vector similarity search via neighbor gem
          # NOTE: neighbor_distance is a virtual column — cannot use in WHERE clause
          results = scope
            .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
            .limit(limit)
            .to_a
            .select { |e| e.neighbor_distance <= 1.0 - threshold }

          # Combine with keyword results for better coverage
          keyword_results = keyword_search(query, limit: 5, tags: tags)

          merge_results(results, keyword_results, limit)
        else
          keyword_search(query, limit: limit, tags: tags)
        end
      end

      # Get memories by outcome
      def successful_outcomes(limit: 20)
        @persistent_context.context_entries
          .active
          .experiential
          .by_agent(@agent.id)
          .successful_outcomes
          .order(importance_score: :desc)
          .limit(limit)
          .map(&:entry_details)
      end

      def failed_outcomes(limit: 20)
        @persistent_context.context_entries
          .active
          .experiential
          .by_agent(@agent.id)
          .failed_outcomes
          .order(importance_score: :desc)
          .limit(limit)
          .map(&:entry_details)
      end

      # Get recent memories
      def recent(limit: 20)
        @persistent_context.context_entries
          .active
          .experiential
          .by_agent(@agent.id)
          .recent
          .limit(limit)
          .map(&:entry_details)
      end

      # Get most important memories
      def most_important(limit: 20)
        @persistent_context.context_entries
          .active
          .experiential
          .by_agent(@agent.id)
          .order(importance_score: :desc)
          .limit(limit)
          .map(&:entry_details)
      end

      # Get memories by tag
      def by_tag(tag, limit: 20)
        @persistent_context.context_entries
          .active
          .experiential
          .by_agent(@agent.id)
          .with_tag(tag)
          .order(importance_score: :desc)
          .limit(limit)
          .map(&:entry_details)
      end

      # Boost importance of a memory (when it proves useful)
      def reinforce(entry_id, boost: 0.1)
        entry = find_entry(entry_id)
        return unless entry

        entry.boost_importance!(boost)
        entry.touch(:last_accessed_at)
        entry
      end

      # Decay all experiential memories (called periodically)
      def apply_decay
        @persistent_context.context_entries
          .active
          .experiential
          .by_agent(@agent.id)
          .where("decay_rate > 0")
          .find_each do |entry|
            entry.send(:decay_relevance)
            entry.save!
          end
      end

      # Consolidate similar memories to prevent bloat
      def consolidate_similar(similarity_threshold: 0.9)
        entries = @persistent_context.context_entries
          .active
          .experiential
          .by_agent(@agent.id)
          .with_embedding
          .order(created_at: :desc)

        consolidated = 0

        entries.each do |entry|
          # Find similar older entries
          similar = find_similar_entries(entry, threshold: similarity_threshold)

          similar.each do |similar_entry|
            # Merge into the newer entry and archive the older one
            merge_entries(entry, similar_entry)
            consolidated += 1
          end
        end

        consolidated
      end

      # Remove old low-importance memories
      def cleanup(max_age_days: 90, min_importance: 0.2)
        cutoff = max_age_days.days.ago

        @persistent_context.context_entries
          .active
          .experiential
          .by_agent(@agent.id)
          .where("created_at < ?", cutoff)
          .where("importance_score < ?", min_importance)
          .find_each(&:archive!)
      end

      private

      def find_or_create_context
        Ai::PersistentContext.find_or_create_by!(
          account_id: @account.id,
          context_type: "agent_memory",
          scope: "agent",
          ai_agent_id: @agent.id,
          name: "#{@agent.name} Experiential Memory"
        ) do |ctx|
          ctx.access_control = { "level" => "private" }
          ctx.retention_policy = {
            "max_entries" => 5000,
            "max_age_days" => 180,
            "archive_before_delete" => true
          }
        end
      end

      def find_entry(entry_id)
        @persistent_context.context_entries
          .active
          .experiential
          .find_by(id: entry_id)
      end

      def generate_entry_key(content)
        text = extract_text(content)
        "exp_#{Digest::SHA256.hexdigest(text)[0..15]}_#{Time.current.to_i}"
      end

      def generate_embedding(content)
        text = extract_text(content)
        @embedding_service.generate(text)
      rescue StandardError => e
        Rails.logger.warn "Failed to generate embedding: #{e.message}"
        nil
      end

      def normalize_content(content)
        case content
        when Hash then content
        when String then { "text" => content }
        else { "value" => content.to_s }
        end
      end

      def extract_text(content)
        case content
        when Hash
          [
            content["text"],
            content["input_summary"],
            content["output_summary"],
            content["description"]
          ].compact.join(" ").truncate(2000)
        when String
          content.truncate(2000)
        else
          content.to_s.truncate(2000)
        end
      end

      def calculate_importance(outcome_success)
        case outcome_success
        when true then DEFAULT_IMPORTANCE
        when false then DEFAULT_IMPORTANCE + 0.2  # Failures are more important
        else DEFAULT_IMPORTANCE
        end
      end

      def calculate_confidence(context)
        # Higher confidence for more detailed context
        base = 0.5
        base += 0.1 if context["task_id"].present?
        base += 0.1 if context["workflow_run_id"].present?
        base += 0.1 if context["duration_ms"].present?
        base += 0.1 if context["from_agent_id"].present?
        [ base, 1.0 ].min
      end

      def build_search_scope(tags: nil, outcome_filter: nil)
        scope = @persistent_context.context_entries
          .active
          .experiential
          .by_agent(@agent.id)

        scope = scope.with_tag(tags) if tags.present?

        case outcome_filter
        when :success then scope.successful_outcomes
        when :failure then scope.failed_outcomes
        else scope
        end
      end

      def keyword_search(query, limit:, tags: nil)
        scope = build_search_scope(tags: tags)

        scope
          .where("content_text ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
          .order(importance_score: :desc)
          .limit(limit)
          .map { |e| e.entry_details.merge(similarity: 0.5) }
      end

      def merge_results(vector_results, keyword_results, limit)
        # Combine and deduplicate
        seen_ids = Set.new
        combined = []

        vector_results.each do |entry|
          next if seen_ids.include?(entry.id)

          seen_ids << entry.id
          combined << entry.entry_details.merge(similarity: entry.try(:similarity) || 0.8)
        end

        keyword_results.each do |entry|
          entry_id = entry[:id]
          next if seen_ids.include?(entry_id)

          seen_ids << entry_id
          combined << entry
        end

        combined.sort_by { |e| -(e[:similarity] || 0) }.first(limit)
      end

      def consolidate_if_needed(new_entry)
        # Only consolidate if we have many entries
        entry_count = @persistent_context.context_entries
          .active
          .experiential
          .by_agent(@agent.id)
          .count

        return unless entry_count > 1000

        # Find and consolidate similar entries
        similar = find_similar_entries(new_entry, threshold: 0.95)
        similar.each { |e| merge_entries(new_entry, e) }
      end

      def find_similar_entries(entry, threshold:)
        return [] unless entry.embedding.present? && Ai::ContextEntry.embedding_column_exists?

        @persistent_context.context_entries
          .active
          .experiential
          .by_agent(@agent.id)
          .where.not(id: entry.id)
          .where("ai_context_entries.created_at < ?", entry.created_at)
          .nearest_neighbors(:embedding, entry.embedding, distance: "cosine")
          .limit(5)
          .to_a
          .select { |e| e.neighbor_distance <= 1.0 - threshold }
      end

      def merge_entries(target, source)
        # Combine importance scores
        target.importance_score = [ target.importance_score, source.importance_score ].max

        # Merge access counts
        target.access_count += source.access_count

        # Merge tags
        target.context_tags = (target.context_tags + source.context_tags).uniq

        # Add merge note to metadata
        target.metadata = target.metadata.merge(
          "merged_from" => (target.metadata["merged_from"] || []) + [ source.id ]
        )

        target.save!
        source.archive!
      end
    end
  end
end
