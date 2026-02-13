# frozen_string_literal: true

module Ai
  module Context
    class RotDetectionService
      # Thresholds for staleness detection
      AGE_DECAY_HALF_LIFE_DAYS = 30
      MIN_ACCESS_FREQUENCY = 0.01  # accesses per day
      STALENESS_THRESHOLD = 0.7    # above this = stale
      ARCHIVE_THRESHOLD = 0.9      # above this = archive candidate

      def initialize(account:)
        @account = account
      end

      # Detect stale context entries and return rot report
      def detect(scope: :all, limit: 100)
        entries = fetch_entries(scope)
        now = Time.current

        scored = entries.filter_map do |entry|
          staleness = calculate_staleness(entry, now)
          next if staleness < STALENESS_THRESHOLD

          {
            entry_id: entry.id,
            entry_key: entry.entry_key,
            context_id: entry.ai_persistent_context_id,
            staleness_score: staleness.round(3),
            age_days: ((now - entry.created_at) / 1.day).round(1),
            last_accessed_days_ago: entry.respond_to?(:last_accessed_at) && entry.last_accessed_at ? ((now - entry.last_accessed_at) / 1.day).round(1) : nil,
            recommendation: staleness >= ARCHIVE_THRESHOLD ? "archive" : "review",
            factors: staleness_factors(entry, now)
          }
        end

        scored = scored.sort_by { |s| -s[:staleness_score] }.first(limit)

        {
          total_scanned: entries.size,
          stale_count: scored.size,
          archive_candidates: scored.count { |s| s[:recommendation] == "archive" },
          review_candidates: scored.count { |s| s[:recommendation] == "review" },
          entries: scored,
          scanned_at: now.iso8601
        }
      end

      # Auto-archive entries above the archive threshold
      def auto_archive!(dry_run: false)
        report = detect(scope: :all)
        archive_entries = report[:entries].select { |e| e[:recommendation] == "archive" }

        return { archived: 0, dry_run: true, candidates: archive_entries.size } if dry_run

        archived_count = 0
        archive_entries.each do |entry_data|
          entry = Ai::ContextEntry.find_by(id: entry_data[:entry_id])
          next unless entry

          entry.update!(
            metadata: (entry.metadata || {}).merge(
              archived_at: Time.current.iso8601,
              archived_reason: "context_rot",
              staleness_score: entry_data[:staleness_score]
            )
          )
          archived_count += 1
        rescue StandardError => e
          Rails.logger.warn "[ContextRotDetection] Failed to archive entry #{entry_data[:entry_id]}: #{e.message}"
        end

        Rails.logger.info "[ContextRotDetection] Archived #{archived_count} stale entries for account #{@account.id}"
        { archived: archived_count, dry_run: false, candidates: archive_entries.size }
      end

      private

      def fetch_entries(scope)
        base = Ai::ContextEntry.joins(:persistent_context)
          .where(ai_persistent_contexts: { account_id: @account.id })

        case scope
        when :agent_memory
          base.where(ai_persistent_contexts: { context_type: "agent_memory" })
        when :knowledge_base
          base.where(ai_persistent_contexts: { context_type: "knowledge_base" })
        else
          base
        end
      end

      def calculate_staleness(entry, now)
        age_score = age_decay_score(entry, now)
        access_score = access_frequency_score(entry, now)
        importance_score = 1.0 - (entry.importance_score || 0.5)

        # Weighted combination
        (age_score * 0.4) + (access_score * 0.3) + (importance_score * 0.3)
      end

      def age_decay_score(entry, now)
        age_days = (now - entry.created_at) / 1.day
        # Exponential decay: score increases as age grows
        1.0 - (0.5**(age_days / AGE_DECAY_HALF_LIFE_DAYS))
      end

      def access_frequency_score(entry, now)
        return 0.8 unless entry.respond_to?(:last_accessed_at) && entry.last_accessed_at

        days_since_access = (now - entry.last_accessed_at) / 1.day
        # Higher score = more stale (longer since last access)
        [days_since_access / (AGE_DECAY_HALF_LIFE_DAYS * 2), 1.0].min
      end

      def staleness_factors(entry, now)
        {
          age_decay: age_decay_score(entry, now).round(3),
          access_recency: access_frequency_score(entry, now).round(3),
          low_importance: (1.0 - (entry.importance_score || 0.5)).round(3)
        }
      end
    end
  end
end
