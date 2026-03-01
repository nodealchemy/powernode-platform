# frozen_string_literal: true

module Ai
  module Memory
    class StorageService
      module Experiential
        extend ActiveSupport::Concern

        # Store an experiential memory
        def store_experiential(content:, context: {}, outcome_success: nil, importance: nil, tags: [], source_type: "agent_output")
          require_agent!

          @experiential_context ||= find_or_create_experiential_context
          @embedding_service ||= EmbeddingService.new(account: account)

          entry_key = generate_experiential_key(content)
          embedding = generate_embedding(content)

          entry = @experiential_context.context_entries.create!(
            entry_key: entry_key,
            entry_type: "memory",
            memory_type: "experiential",
            content: normalize_experiential_content(content),
            content_text: extract_experiential_text(content),
            embedding: embedding,
            metadata: { "context" => context },
            source_type: source_type,
            ai_agent_id: @agent.id,
            importance_score: importance || calculate_experiential_importance(outcome_success),
            confidence_score: calculate_experiential_confidence(context),
            decay_rate: DEFAULT_DECAY_RATE,
            context_tags: tags,
            task_context: context,
            outcome_success: outcome_success,
            version: 1
          )

          consolidate_experiential_if_needed(entry)
          entry
        end

        # Semantic search for relevant experiential memories
        def search_experiential(query, limit: 10, threshold: 0.7, tags: nil, outcome_filter: nil)
          require_agent!

          @experiential_context ||= find_or_create_experiential_context
          @embedding_service ||= EmbeddingService.new(account: account)

          query_embedding = @embedding_service.generate(query)
          return experiential_keyword_search(query, limit: limit, tags: tags) unless query_embedding

          scope = build_experiential_search_scope(tags: tags, outcome_filter: outcome_filter)

          if Ai::ContextEntry.embedding_column_exists?
            results = scope
              .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
              .limit(limit)
              .to_a
              .select { |e| e.neighbor_distance <= 1.0 - threshold }

            keyword_results = experiential_keyword_search(query, limit: 5, tags: tags)
            merge_experiential_results(results, keyword_results, limit)
          else
            experiential_keyword_search(query, limit: limit, tags: tags)
          end
        end

        # Get experiential memories by outcome
        def successful_outcomes(limit: 20)
          require_agent!
          @experiential_context ||= find_or_create_experiential_context

          @experiential_context.context_entries
            .active.experiential.by_agent(@agent.id)
            .successful_outcomes
            .order(importance_score: :desc)
            .limit(limit)
            .map(&:entry_details)
        end

        def failed_outcomes(limit: 20)
          require_agent!
          @experiential_context ||= find_or_create_experiential_context

          @experiential_context.context_entries
            .active.experiential.by_agent(@agent.id)
            .failed_outcomes
            .order(importance_score: :desc)
            .limit(limit)
            .map(&:entry_details)
        end

        # Get recent experiential memories
        def recent_experiential(limit: 20)
          require_agent!
          @experiential_context ||= find_or_create_experiential_context

          @experiential_context.context_entries
            .active.experiential.by_agent(@agent.id)
            .recent.limit(limit)
            .map(&:entry_details)
        end

        # Get most important experiential memories
        def most_important_experiential(limit: 20)
          require_agent!
          @experiential_context ||= find_or_create_experiential_context

          @experiential_context.context_entries
            .active.experiential.by_agent(@agent.id)
            .order(importance_score: :desc)
            .limit(limit)
            .map(&:entry_details)
        end

        # Get experiential memories by tag
        def experiential_by_tag(tag, limit: 20)
          require_agent!
          @experiential_context ||= find_or_create_experiential_context

          @experiential_context.context_entries
            .active.experiential.by_agent(@agent.id)
            .with_tag(tag)
            .order(importance_score: :desc)
            .limit(limit)
            .map(&:entry_details)
        end

        # Boost importance of an experiential memory
        def reinforce(entry_id, boost: 0.1)
          require_agent!
          @experiential_context ||= find_or_create_experiential_context

          entry = @experiential_context.context_entries
            .active.experiential.find_by(id: entry_id)
          return unless entry

          entry.boost_importance!(boost)
          entry.touch(:last_accessed_at)
          entry
        end

        # Decay all experiential memories
        def apply_experiential_decay
          require_agent!
          @experiential_context ||= find_or_create_experiential_context

          @experiential_context.context_entries
            .active.experiential.by_agent(@agent.id)
            .where("decay_rate > 0")
            .find_each do |entry|
              entry.send(:decay_relevance)
              entry.save!
            end
        end

        # Consolidate similar experiential memories
        def consolidate_similar_experiential(similarity_threshold: 0.9)
          require_agent!
          @experiential_context ||= find_or_create_experiential_context

          entries = @experiential_context.context_entries
            .active.experiential.by_agent(@agent.id)
            .with_embedding
            .order(created_at: :desc)

          consolidated = 0

          entries.each do |entry|
            similar = find_similar_experiential_entries(entry, threshold: similarity_threshold)
            similar.each do |similar_entry|
              merge_experiential_entries(entry, similar_entry)
              consolidated += 1
            end
          end

          consolidated
        end

        # Remove old low-importance experiential memories
        def cleanup_experiential(max_age_days: 90, min_importance: 0.2)
          require_agent!
          @experiential_context ||= find_or_create_experiential_context

          cutoff = max_age_days.days.ago

          @experiential_context.context_entries
            .active.experiential.by_agent(@agent.id)
            .where("created_at < ?", cutoff)
            .where("importance_score < ?", min_importance)
            .find_each(&:archive!)
        end

        private

        def find_or_create_experiential_context
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

        def generate_experiential_key(content)
          text = extract_experiential_text(content)
          "exp_#{Digest::SHA256.hexdigest(text)[0..15]}_#{Time.current.to_i}"
        end

        def generate_embedding(content)
          @embedding_service ||= EmbeddingService.new(account: account)
          text = extract_experiential_text(content)
          @embedding_service.generate(text)
        rescue StandardError => e
          Rails.logger.warn "Failed to generate embedding: #{e.message}"
          nil
        end

        def normalize_experiential_content(content)
          case content
          when Hash then content
          when String then { "text" => content }
          else { "value" => content.to_s }
          end
        end

        def extract_experiential_text(content)
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

        def calculate_experiential_importance(outcome_success)
          case outcome_success
          when true then DEFAULT_IMPORTANCE
          when false then DEFAULT_IMPORTANCE + 0.2
          else DEFAULT_IMPORTANCE
          end
        end

        def calculate_experiential_confidence(context)
          base = 0.5
          base += 0.1 if context["task_id"].present?
          base += 0.1 if context["workflow_run_id"].present?
          base += 0.1 if context["duration_ms"].present?
          base += 0.1 if context["from_agent_id"].present?
          [base, 1.0].min
        end

        def build_experiential_search_scope(tags: nil, outcome_filter: nil)
          scope = @experiential_context.context_entries
            .active.experiential.by_agent(@agent.id)

          scope = scope.with_tag(tags) if tags.present?

          case outcome_filter
          when :success then scope.successful_outcomes
          when :failure then scope.failed_outcomes
          else scope
          end
        end

        def experiential_keyword_search(query, limit:, tags: nil)
          scope = build_experiential_search_scope(tags: tags)

          scope
            .where("content_text ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
            .order(importance_score: :desc)
            .limit(limit)
            .map { |e| e.entry_details.merge(similarity: 0.5) }
        end

        def merge_experiential_results(vector_results, keyword_results, limit)
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

        def consolidate_experiential_if_needed(new_entry)
          entry_count = @experiential_context.context_entries
            .active.experiential.by_agent(@agent.id).count

          return unless entry_count > 1000

          similar = find_similar_experiential_entries(new_entry, threshold: 0.95)
          similar.each { |e| merge_experiential_entries(new_entry, e) }
        end

        def find_similar_experiential_entries(entry, threshold:)
          return [] unless entry.embedding.present? && Ai::ContextEntry.embedding_column_exists?

          @experiential_context.context_entries
            .active.experiential.by_agent(@agent.id)
            .where.not(id: entry.id)
            .where("ai_context_entries.created_at < ?", entry.created_at)
            .nearest_neighbors(:embedding, entry.embedding, distance: "cosine")
            .limit(5)
            .to_a
            .select { |e| e.neighbor_distance <= 1.0 - threshold }
        end

        def merge_experiential_entries(target, source)
          target.importance_score = [target.importance_score, source.importance_score].max
          target.access_count += source.access_count
          target.context_tags = (target.context_tags + source.context_tags).uniq
          target.metadata = target.metadata.merge(
            "merged_from" => (target.metadata["merged_from"] || []) + [source.id]
          )

          target.save!
          source.archive!
        end
      end
    end
  end
end
