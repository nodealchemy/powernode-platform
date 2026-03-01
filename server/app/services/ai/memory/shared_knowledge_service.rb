# frozen_string_literal: true

module Ai
  module Memory
    # Shared Knowledge Service - Manages SharedKnowledge entries with semantic search
    # and ACL-based access control. Uses pgvector for similarity search and deduplication.
    #
    # Unlike StorageService shared learning methods (which use MemoryPool), this service operates
    # directly on the Ai::SharedKnowledge model with vector embeddings.
    class SharedKnowledgeService
      SIMILARITY_THRESHOLD = 0.3
      DEDUP_THRESHOLD = 0.92
      MAX_RESULTS = 20
      CHARS_PER_TOKEN = 4
      ACCESS_LEVEL_HIERARCHY = %w[private team account global].freeze

      def initialize(account:)
        @account = account
        @embedding_service = EmbeddingService.new(account: account)
      end

      # Create a new shared knowledge entry with deduplication
      def create(title:, content:, content_type: "text", access_level: "team",
                 tags: [], metadata: {}, agent: nil, team: nil, source_type: "manual")
        validate_content_type!(content_type)
        validate_access_level!(access_level)

        embedding = @embedding_service.generate(content)

        # Check for near-duplicates via semantic search
        if embedding && Ai::SharedKnowledge.where(account: @account).with_embedding.exists?
          duplicates = Ai::SharedKnowledge
            .where(account: @account)
            .nearest_neighbors(:embedding, embedding, distance: "cosine")
            .first(3)

          if duplicates.any? && duplicates.first.neighbor_distance <= (1.0 - DEDUP_THRESHOLD)
            existing = duplicates.first
            existing.touch_usage!
            Rails.logger.info("[SharedKnowledge] Duplicate detected for '#{title}', existing entry: #{existing.id}")
            return {
              success: false,
              error: "Duplicate knowledge entry detected",
              existing_entry_id: existing.id,
              similarity: (1.0 - existing.neighbor_distance).round(4)
            }
          end
        end

        entry = Ai::SharedKnowledge.create!(
          account: @account,
          title: title,
          content: content,
          content_type: content_type,
          access_level: access_level,
          tags: tags,
          provenance: (metadata || {}).merge("source_type" => source_type),
          source_type: source_type,
          embedding: embedding,
          quality_score: calculate_quality_score(content, tags, metadata),
          usage_count: 0
        )

        entry.compute_integrity_hash!

        Rails.logger.info("[SharedKnowledge] Created entry '#{title}' (#{entry.id}) [#{access_level}/#{content_type}]")
        { success: true, entry: serialize_entry(entry) }
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[SharedKnowledge] Create failed: #{e.message}")
        { success: false, error: e.message }
      rescue ArgumentError
        raise
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Create failed: #{e.class} - #{e.message}")
        { success: false, error: "Failed to create knowledge entry" }
      end

      # Semantic search with ACL filtering
      def search(query:, access_level: nil, content_type: nil, team: nil,
                 tags: nil, limit: MAX_RESULTS)
        query_embedding = @embedding_service.generate(query)

        scope = Ai::SharedKnowledge.where(account: @account)

        # Apply ACL filtering
        scope = scope.accessible_by(access_level) if access_level.present?

        # Apply content type filter
        scope = scope.by_content_type(content_type) if content_type.present?

        # Apply tag filter
        scope = scope.with_any_tags(tags) if tags.present? && tags.is_a?(Array) && tags.any?

        results = if query_embedding && scope.with_embedding.exists?
          scope
            .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
            .limit(limit)
            .select { |e| e.neighbor_distance <= (1.0 - SIMILARITY_THRESHOLD) }
        else
          # Fallback to keyword search
          keyword_search(query, scope, limit)
        end

        entries = results.map do |entry|
          entry.touch_usage!
          serialized = serialize_entry(entry)
          serialized[:similarity] = (1.0 - entry.neighbor_distance).round(4) if entry.respond_to?(:neighbor_distance) && entry.neighbor_distance
          serialized[:freshness] = freshness_indicator(entry.updated_at)
          serialized
        end

        Rails.logger.info("[SharedKnowledge] Search for '#{query.truncate(50)}' returned #{entries.size} results")
        { success: true, entries: entries, count: entries.size }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Search failed: #{e.message}")
        { success: false, error: "Search failed", entries: [], count: 0 }
      end

      # Update an existing entry
      def update(entry_id:, title: nil, content: nil, metadata: nil, tags: nil,
                 content_type: nil, access_level: nil)
        entry = find_entry!(entry_id)
        return entry_not_found(entry_id) unless entry

        validate_content_type!(content_type) if content_type
        validate_access_level!(access_level) if access_level

        attrs = {}
        attrs[:title] = title if title.present?
        attrs[:content_type] = content_type if content_type.present?
        attrs[:access_level] = access_level if access_level.present?
        attrs[:tags] = tags if tags
        attrs[:provenance] = entry.provenance.merge(metadata) if metadata.is_a?(Hash)

        content_changed = content.present? && content != entry.content
        if content_changed
          attrs[:content] = content
          attrs[:embedding] = @embedding_service.generate(content)
          attrs[:quality_score] = calculate_quality_score(
            content,
            tags || entry.tags,
            metadata || entry.provenance
          )
        end

        entry.update!(attrs) if attrs.any?
        entry.compute_integrity_hash! if content_changed

        Rails.logger.info("[SharedKnowledge] Updated entry #{entry_id}#{content_changed ? ' (content+embedding regenerated)' : ''}")
        { success: true, entry: serialize_entry(entry.reload) }
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("[SharedKnowledge] Update failed for #{entry_id}: #{e.message}")
        { success: false, error: e.message }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Update failed: #{e.class} - #{e.message}")
        { success: false, error: "Failed to update knowledge entry" }
      end

      # Archive an entry (soft delete via metadata flag)
      def archive(entry_id:)
        entry = find_entry!(entry_id)
        return entry_not_found(entry_id) unless entry

        entry.update!(
          provenance: entry.provenance.merge(
            "archived" => true,
            "archived_at" => Time.current.iso8601
          )
        )

        Rails.logger.info("[SharedKnowledge] Archived entry #{entry_id}")
        { success: true, entry_id: entry_id }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Archive failed for #{entry_id}: #{e.message}")
        { success: false, error: "Failed to archive knowledge entry" }
      end

      # Promote entry access level (private → team → account → global)
      def promote(entry_id:, new_access_level:)
        entry = find_entry!(entry_id)
        return entry_not_found(entry_id) unless entry

        validate_access_level!(new_access_level)

        current_index = ACCESS_LEVEL_HIERARCHY.index(entry.access_level)
        new_index = ACCESS_LEVEL_HIERARCHY.index(new_access_level)

        if new_index.nil? || current_index.nil?
          return { success: false, error: "Invalid access level" }
        end

        if new_index <= current_index
          return {
            success: false,
            error: "Cannot demote access level from '#{entry.access_level}' to '#{new_access_level}'"
          }
        end

        old_level = entry.access_level
        entry.update!(
          access_level: new_access_level,
          provenance: entry.provenance.merge(
            "promoted_at" => Time.current.iso8601,
            "promoted_from" => old_level
          )
        )

        Rails.logger.info("[SharedKnowledge] Promoted entry #{entry_id}: #{entry.access_level} → #{new_access_level}")
        { success: true, entry: serialize_entry(entry.reload) }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Promote failed for #{entry_id}: #{e.message}")
        { success: false, error: "Failed to promote knowledge entry" }
      end

      # Import high-importance CompoundLearning entries as SharedKnowledge
      def import_from_learnings(team: nil, min_importance: 0.7)
        scope = Ai::CompoundLearning
          .active
          .for_account(@account.id)
          .where("importance_score >= ?", min_importance)

        scope = scope.for_team(team.id) if team

        imported = 0
        skipped = 0

        scope.find_each do |learning|
          # Map compound learning category to shared knowledge content type
          content_type = map_learning_to_content_type(learning.category)

          result = create(
            title: learning.title || learning.content.truncate(100),
            content: learning.content,
            content_type: content_type,
            access_level: learning.scope == "global" ? "account" : "team",
            tags: learning.tags || [],
            metadata: {
              "source_type" => "import",
              "imported_from" => "compound_learning",
              "source_learning_id" => learning.id,
              "source_category" => learning.category,
              "original_importance" => learning.importance_score
            }.freeze,
            source_type: "import"
          )

          if result[:success]
            imported += 1
          else
            skipped += 1
          end
        end

        Rails.logger.info("[SharedKnowledge] Import complete: #{imported} imported, #{skipped} skipped (duplicates)")
        { success: true, imported: imported, skipped: skipped }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Import from learnings failed: #{e.message}")
        { success: false, error: "Import failed", imported: 0, skipped: 0 }
      end

      # Get knowledge statistics
      def stats(team: nil)
        scope = Ai::SharedKnowledge.where(account: @account)

        # Exclude archived entries from stats
        scope = scope.where.not("provenance @> ?", { archived: true }.to_json)

        by_access_level = scope.group(:access_level).count
        by_content_type = scope.group(:content_type).count
        total = scope.count
        avg_quality = scope.average(:quality_score)&.to_f&.round(4) || 0
        total_usage = scope.sum(:usage_count)
        with_embeddings = scope.with_embedding.count

        most_used = scope
          .where("usage_count > 0")
          .order(usage_count: :desc)
          .limit(5)
          .map { |e| serialize_entry(e) }

        recently_added = scope
          .order(created_at: :desc)
          .limit(10)
          .map { |e| serialize_entry(e) }

        {
          success: true,
          stats: {
            total: total,
            by_access_level: by_access_level,
            by_content_type: by_content_type,
            avg_quality_score: avg_quality,
            total_usage: total_usage,
            with_embeddings: with_embeddings,
            embedding_coverage: total.positive? ? (with_embeddings.to_f / total * 100).round(1) : 0,
            most_used: most_used,
            recently_added: recently_added
          }
        }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Stats failed: #{e.message}")
        { success: false, error: "Failed to compute stats", stats: {} }
      end

      # Batch recalculate quality scores for entries not recalculated in 24h
      def recalculate_all_quality(batch_size: 100)
        scope = Ai::SharedKnowledge.where(account: @account)
          .where.not("provenance @> ?", { archived: true }.to_json)
          .where("last_quality_recalc_at < ? OR last_quality_recalc_at IS NULL", 24.hours.ago)
          .where("last_event_processed_at IS NULL OR last_event_processed_at < ?", 24.hours.ago)

        recalculated = 0
        skipped = Ai::SharedKnowledge.where(account: @account)
          .where.not("provenance @> ?", { archived: true }.to_json)
          .where("last_event_processed_at >= ?", 24.hours.ago)
          .count

        scope.find_each(batch_size: batch_size) do |entry|
          entry.recalculate_quality_score!
          recalculated += 1
        end

        Rails.logger.info("[SharedKnowledge] Batch quality recalc: #{recalculated} updated, #{skipped} skipped by event-driven")
        { success: true, recalculated: recalculated, skipped_by_event: skipped }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Batch quality recalc failed: #{e.message}")
        { success: false, error: e.message, recalculated: 0 }
      end

      # Build LLM context from relevant shared knowledge within a token budget
      def build_context(query:, agent: nil, token_budget: 2000)
        char_budget = token_budget * CHARS_PER_TOKEN

        search_result = search(
          query: query,
          access_level: agent ? "team" : "account",
          limit: MAX_RESULTS
        )

        return { success: true, context: nil, token_estimate: 0, entry_ids: [] } unless search_result[:success] && search_result[:entries].any?

        lines = ["## Shared Knowledge"]
        used_chars = lines.first.length + 2
        entry_ids = []

        search_result[:entries].each do |entry|
          label = "[#{entry[:content_type]}]"
          similarity_note = entry[:similarity] ? " (#{(entry[:similarity] * 100).round}% match)" : ""
          line = "- #{label}#{similarity_note} #{entry[:title]}: #{entry[:content].truncate(200)}"

          break if used_chars + line.length > char_budget

          lines << line
          used_chars += line.length + 1
          entry_ids << entry[:id]
        end

        if lines.size == 1
          return { success: true, context: nil, token_estimate: 0, entry_ids: [] }
        end

        context = lines.join("\n")

        {
          success: true,
          context: context,
          token_estimate: (used_chars / CHARS_PER_TOKEN.to_f).ceil,
          entry_ids: entry_ids
        }
      rescue StandardError => e
        Rails.logger.error("[SharedKnowledge] Context build failed: #{e.message}")
        { success: false, context: nil, token_estimate: 0, entry_ids: [] }
      end

      private

      def find_entry!(entry_id)
        Ai::SharedKnowledge.find_by(id: entry_id, account: @account)
      end

      def entry_not_found(entry_id)
        { success: false, error: "Knowledge entry not found: #{entry_id}" }
      end

      def validate_content_type!(content_type)
        return if Ai::SharedKnowledge::CONTENT_TYPES.include?(content_type)

        raise ArgumentError, "Invalid content_type '#{content_type}'. Must be one of: #{Ai::SharedKnowledge::CONTENT_TYPES.join(', ')}"
      end

      def validate_access_level!(access_level)
        return if Ai::SharedKnowledge::ACCESS_LEVELS.include?(access_level)

        raise ArgumentError, "Invalid access_level '#{access_level}'. Must be one of: #{Ai::SharedKnowledge::ACCESS_LEVELS.join(', ')}"
      end

      def calculate_quality_score(content, tags, metadata)
        score = 0.5

        # Longer, more detailed content scores higher
        score += [content.to_s.length / 2000.0, 0.15].min

        # Having tags indicates well-organized content
        score += [tags.to_a.length * 0.03, 0.1].min

        # Having metadata indicates rich context
        score += [metadata.to_h.keys.length * 0.02, 0.1].min

        # Content with structure (headers, lists, code blocks) scores higher
        score += 0.05 if content.to_s.match?(/^#+\s/m)
        score += 0.05 if content.to_s.match?(/^[-*]\s/m)
        score += 0.05 if content.to_s.match?(/```/)

        [score.round(4), 1.0].min
      end

      def keyword_search(query, scope, limit)
        return scope.none if query.blank?

        keywords = query.downcase.split(/\s+/).reject { |w| w.length < 3 }.first(5)
        return scope.recent.limit(limit) if keywords.empty?

        where_clauses = []
        bind_values = []
        keywords.each do |kw|
          sanitized = Ai::SharedKnowledge.sanitize_sql_like(kw)
          where_clauses << "(LOWER(title) LIKE ? OR LOWER(content) LIKE ?)"
          bind_values.push("%#{sanitized}%", "%#{sanitized}%")
        end

        scope.where(where_clauses.join(" OR "), *bind_values).recent.limit(limit)
      end

      def map_learning_to_content_type(category)
        case category
        when "pattern", "anti_pattern", "best_practice"
          "procedure"
        when "fact", "discovery"
          "fact"
        when "failure_mode"
          "snippet"
        when "performance_insight"
          "text"
        else
          "text"
        end
      end

      def freshness_indicator(updated_at)
        return "stale" unless updated_at

        age_days = (Time.current - updated_at) / 1.day
        if age_days < 7
          "fresh"
        elsif age_days < 30
          "aging"
        else
          "stale"
        end
      end

      def serialize_entry(entry)
        {
          id: entry.id,
          title: entry.title,
          content: entry.content,
          content_type: entry.content_type,
          access_level: entry.access_level,
          tags: entry.tags,
          provenance: entry.provenance,
          source_type: entry.source_type,
          quality_score: entry.quality_score,
          usage_count: entry.usage_count,
          last_used_at: entry.last_used_at&.iso8601,
          integrity_verified: entry.verify_integrity!,
          created_at: entry.created_at&.iso8601,
          updated_at: entry.updated_at&.iso8601
        }
      end
    end
  end
end
