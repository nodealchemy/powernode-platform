# frozen_string_literal: true

class Ai::MemoryManagementService
  class MemoryError < StandardError; end

  class << self
    # ==================== Retention & Cleanup ====================

    # Apply retention policy to a context
    def apply_retention_policy(context:)
      policy = context.retention_policy
      return { cleaned: 0, archived: 0 } if policy.blank?

      results = { cleaned: 0, archived: 0 }

      # Apply max age policy
      if policy["max_age_days"].present?
        age_results = cleanup_old_entries(context, policy["max_age_days"].days)
        results[:cleaned] += age_results[:deleted]
        results[:archived] += age_results[:archived]
      end

      # Apply max entries policy
      if policy["max_entries"].present?
        count_results = enforce_entry_limit(context, policy["max_entries"])
        results[:cleaned] += count_results[:deleted]
        results[:archived] += count_results[:archived]
      end

      # Update context stats
      context.touch(:last_cleanup_at) if results[:cleaned] > 0 || results[:archived] > 0

      results
    end

    # Cleanup old entries across all contexts
    def cleanup_expired_entries
      expired = Ai::ContextEntry.expired.where(archived_at: nil)

      archived_count = 0
      deleted_count = 0

      expired.find_each do |entry|
        context = entry.ai_persistent_context
        policy = context.retention_policy

        if policy["archive_before_delete"]
          entry.archive!
          archived_count += 1
        else
          entry.destroy!
          deleted_count += 1
        end
      end

      { archived: archived_count, deleted: deleted_count }
    end

    # Archive old contexts
    def archive_inactive_contexts(older_than: 90.days)
      contexts = Ai::PersistentContext
        .active
        .where("last_accessed_at < ? OR (last_accessed_at IS NULL AND updated_at < ?)",
               older_than.ago, older_than.ago)

      archived_count = 0

      contexts.find_each do |context|
        context.archive!
        archived_count += 1
      end

      { archived: archived_count }
    end

    # Permanently delete archived contexts
    def purge_archived_contexts(older_than: 30.days)
      contexts = Ai::PersistentContext
        .archived
        .where("archived_at < ?", older_than.ago)

      deleted_count = contexts.count
      contexts.destroy_all

      { deleted: deleted_count }
    end

    # ==================== Memory Optimization ====================

    # Consolidate similar memories
    def consolidate_memories(context:, similarity_threshold: 0.9)
      return { consolidated: 0 } unless context.ai_context_entries.count > 1

      entries = context.ai_context_entries.active.where.not(embedding: nil).to_a
      consolidated = 0

      entries.each_with_index do |entry, i|
        next if entry.archived?

        similar = find_similar_entries(entry, entries[i + 1..], similarity_threshold)

        similar.each do |similar_entry|
          merge_entries(entry, similar_entry)
          consolidated += 1
        end
      end

      { consolidated: consolidated }
    end

    # Decay importance scores over time
    def decay_importance_scores(context: nil, decay_rate: 0.01)
      scope = Ai::ContextEntry.active
      scope = scope.where(ai_persistent_context: context) if context.present?

      updated = scope
        .where("importance_score > 0.1")
        .where("last_accessed_at < ? OR last_accessed_at IS NULL", 7.days.ago)
        .update_all("importance_score = GREATEST(importance_score - #{decay_rate}, 0.1)")

      { updated: updated }
    end

    # Boost frequently accessed entries
    def boost_frequent_entries(context: nil, access_threshold: 10, boost_amount: 0.1)
      scope = Ai::ContextEntry.active
      scope = scope.where(ai_persistent_context: context) if context.present?

      updated = scope
        .where("access_count >= ?", access_threshold)
        .where("importance_score < 1.0")
        .update_all("importance_score = LEAST(importance_score + #{boost_amount}, 1.0)")

      { updated: updated }
    end

    # ==================== Embedding Management ====================

    # Generate embeddings for entries without them
    def generate_missing_embeddings(context: nil, batch_size: 100)
      scope = Ai::ContextEntry.active.where(embedding: nil).where.not(content_text: nil)
      scope = scope.where(ai_persistent_context: context) if context.present?

      generated = 0
      failed = 0

      scope.limit(batch_size).find_each do |entry|
        embedding = generate_embedding(entry.content_text)

        if embedding.present?
          entry.update_column(:embedding, embedding)
          generated += 1
        else
          failed += 1
        end
      rescue StandardError => e
        Rails.logger.error("Failed to generate embedding for entry #{entry.id}: #{e.message}")
        failed += 1
      end

      { generated: generated, failed: failed, remaining: scope.count - batch_size }
    end

    # Refresh stale embeddings
    def refresh_stale_embeddings(context: nil, older_than: 30.days, batch_size: 100)
      scope = Ai::ContextEntry.active
        .where.not(embedding: nil)
        .where("updated_at > COALESCE(embedding_updated_at, created_at)")
        .or(
          Ai::ContextEntry.active
            .where.not(embedding: nil)
            .where("COALESCE(embedding_updated_at, created_at) < ?", older_than.ago)
        )

      scope = scope.where(ai_persistent_context: context) if context.present?

      refreshed = 0

      scope.limit(batch_size).find_each do |entry|
        embedding = generate_embedding(entry.content_text)

        if embedding.present?
          entry.update_columns(embedding: embedding, embedding_updated_at: Time.current)
          refreshed += 1
        end
      end

      { refreshed: refreshed }
    end

    # ==================== Analytics ====================

    # Get memory usage statistics
    def memory_stats(account:)
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
      entries = context.ai_context_entries

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

    # ==================== Import/Export ====================

    # Export memories for backup
    def export_memories(account:, format: :json, include_embeddings: false)
      contexts = Ai::PersistentContext.where(account: account).includes(:ai_context_entries)

      data = {
        exported_at: Time.current.iso8601,
        version: "1.0",
        account_id: account.id,
        contexts: contexts.map do |context|
          {
            context: context.context_summary,
            entries: context.ai_context_entries.map do |entry|
              snapshot = entry.entry_snapshot
              snapshot[:embedding] = entry.embedding if include_embeddings
              snapshot
            end
          }
        end
      }

      case format
      when :json
        data.to_json
      else
        data
      end
    end

    # Import memories from backup
    def import_memories(account:, data:, strategy: :merge)
      parsed = data.is_a?(String) ? JSON.parse(data).with_indifferent_access : data

      imported_contexts = 0
      imported_entries = 0

      (parsed[:contexts] || []).each do |context_data|
        context = case strategy
        when :merge
          find_or_create_context(account, context_data[:context])
        when :replace
          replace_context(account, context_data[:context])
        when :append
          create_new_context(account, context_data[:context])
        end

        (context_data[:entries] || []).each do |entry_data|
          import_entry(context, entry_data, strategy)
          imported_entries += 1
        end

        imported_contexts += 1
      end

      { contexts: imported_contexts, entries: imported_entries }
    end

    # ==================== Sync ====================

    # Sync context between agents
    def sync_context(from_context:, to_context:, entry_types: nil, min_importance: nil)
      scope = from_context.ai_context_entries.active
      scope = scope.by_type(entry_types) if entry_types.present?
      scope = scope.where("importance_score >= ?", min_importance) if min_importance.present?

      synced = 0

      scope.find_each do |entry|
        existing = to_context.ai_context_entries.find_by(entry_key: entry.entry_key)

        if existing.present?
          # Update if source is newer
          if entry.updated_at > existing.updated_at
            existing.update!(
              content: entry.content,
              metadata: entry.metadata,
              importance_score: entry.importance_score
            )
            synced += 1
          end
        else
          # Create new entry
          to_context.ai_context_entries.create!(
            entry_key: entry.entry_key,
            entry_type: entry.entry_type,
            content: entry.content,
            metadata: entry.metadata.merge(synced_from: from_context.id),
            importance_score: entry.importance_score,
            source_type: "sync",
            source_id: entry.id
          )
          synced += 1
        end
      end

      { synced: synced }
    end

    private

    def cleanup_old_entries(context, max_age)
      old_entries = context.ai_context_entries
        .active
        .where("created_at < ?", max_age.ago)
        .order(importance_score: :asc)

      policy = context.retention_policy
      archived = 0
      deleted = 0

      old_entries.find_each do |entry|
        if policy["archive_before_delete"]
          entry.archive!
          archived += 1
        else
          entry.destroy!
          deleted += 1
        end
      end

      { archived: archived, deleted: deleted }
    end

    def enforce_entry_limit(context, max_entries)
      current_count = context.ai_context_entries.active.count
      return { archived: 0, deleted: 0 } if current_count <= max_entries

      excess = current_count - max_entries
      policy = context.retention_policy

      # Remove lowest importance entries first
      entries_to_remove = context.ai_context_entries
        .active
        .order(importance_score: :asc, last_accessed_at: :asc)
        .limit(excess)

      archived = 0
      deleted = 0

      entries_to_remove.each do |entry|
        if policy["archive_before_delete"]
          entry.archive!
          archived += 1
        else
          entry.destroy!
          deleted += 1
        end
      end

      { archived: archived, deleted: deleted }
    end

    def find_similar_entries(entry, candidates, threshold)
      return [] unless entry.embedding.present?

      candidates.select do |candidate|
        next false unless candidate.embedding.present?
        next false if candidate.archived?

        similarity = cosine_similarity(entry.embedding, candidate.embedding)
        similarity >= threshold
      end
    end

    def cosine_similarity(vec1, vec2)
      # Calculate cosine similarity between two vectors
      dot_product = vec1.zip(vec2).sum { |a, b| a * b }
      magnitude1 = Math.sqrt(vec1.sum { |x| x ** 2 })
      magnitude2 = Math.sqrt(vec2.sum { |x| x ** 2 })

      return 0 if magnitude1.zero? || magnitude2.zero?

      dot_product / (magnitude1 * magnitude2)
    end

    def merge_entries(target, source)
      # Merge content if appropriate
      merged_content = merge_content(target.content, source.content)
      merged_metadata = target.metadata.deep_merge(source.metadata)
      merged_metadata["merged_from"] ||= []
      merged_metadata["merged_from"] << source.id

      target.update!(
        content: merged_content,
        metadata: merged_metadata,
        importance_score: [target.importance_score, source.importance_score].max,
        access_count: target.access_count + source.access_count
      )

      source.archive!
    end

    def merge_content(content1, content2)
      return content2 if content1.blank?
      return content1 if content2.blank?

      if content1.is_a?(Hash) && content2.is_a?(Hash)
        content1.deep_merge(content2)
      elsif content1.is_a?(Array) && content2.is_a?(Array)
        (content1 + content2).uniq
      else
        content1
      end
    end

    def generate_embedding(text)
      return nil if text.blank?

      # Placeholder for embedding generation
      # In production, this would call an embedding service (e.g., OpenAI)
      # For now, return nil and let the embedding job handle it

      # Example with OpenAI:
      # response = OpenAI::Client.new.embeddings(
      #   parameters: { model: "text-embedding-3-small", input: text }
      # )
      # response.dig("data", 0, "embedding")

      nil
    end

    def check_retention_status(context)
      policy = context.retention_policy
      return "no_policy" if policy.blank?

      issues = []

      if policy["max_entries"].present?
        current = context.ai_context_entries.active.count
        if current > policy["max_entries"]
          issues << "over_limit"
        elsif current > policy["max_entries"] * 0.9
          issues << "near_limit"
        end
      end

      if policy["max_age_days"].present?
        old_count = context.ai_context_entries
          .active
          .where("created_at < ?", policy["max_age_days"].days.ago)
          .count

        issues << "has_old_entries" if old_count > 0
      end

      issues.empty? ? "healthy" : issues.join(",")
    end

    def find_or_create_context(account, context_data)
      Ai::PersistentContext.find_or_create_by!(
        account: account,
        name: context_data[:name],
        context_type: context_data[:context_type]
      ) do |ctx|
        ctx.scope = context_data[:scope]
        ctx.description = context_data[:description]
      end
    end

    def replace_context(account, context_data)
      existing = Ai::PersistentContext.find_by(
        account: account,
        name: context_data[:name],
        context_type: context_data[:context_type]
      )

      existing&.ai_context_entries&.destroy_all
      existing || find_or_create_context(account, context_data)
    end

    def create_new_context(account, context_data)
      name = context_data[:name]
      counter = 1

      while Ai::PersistentContext.exists?(account: account, name: name)
        name = "#{context_data[:name]} (#{counter})"
        counter += 1
      end

      Ai::PersistentContext.create!(
        account: account,
        name: name,
        context_type: context_data[:context_type],
        scope: context_data[:scope],
        description: context_data[:description]
      )
    end

    def import_entry(context, entry_data, strategy)
      existing = context.ai_context_entries.find_by(entry_key: entry_data[:entry_key])

      if existing.present? && strategy == :merge
        existing.update!(
          content: entry_data[:content],
          metadata: existing.metadata.deep_merge(entry_data[:metadata] || {})
        )
      else
        context.ai_context_entries.create!(
          entry_key: entry_data[:entry_key],
          entry_type: entry_data[:entry_type],
          content: entry_data[:content],
          metadata: entry_data[:metadata] || {},
          importance_score: entry_data[:importance_score] || 0.5,
          source_type: "import"
        )
      end
    end
  end
end
