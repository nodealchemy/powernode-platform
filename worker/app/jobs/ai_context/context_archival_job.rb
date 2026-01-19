# frozen_string_literal: true

module AiContext
  class ContextArchivalJob < BaseJob
    sidekiq_options queue: 'maintenance',
                    retry: 2,
                    dead: false

    # Archive inactive contexts and optionally purge old archived contexts
    def execute(options = {})
      log_info("Starting AI context archival job")

      results = {
        contexts_archived: 0,
        contexts_purged: 0,
        entries_archived: 0
      }

      # Archive inactive contexts
      results[:contexts_archived] = archive_inactive_contexts(options)

      # Archive old entries within active contexts
      results[:entries_archived] = archive_old_entries(options)

      # Purge old archived contexts if requested
      if options[:purge_archived]
        results[:contexts_purged] = purge_archived_contexts(options)
      end

      log_info("AI context archival completed", **results)
      track_cleanup_metrics(results)

      results
    end

    private

    def archive_inactive_contexts(options = {})
      inactive_days = options[:inactive_days] || 90

      log_info("Archiving contexts inactive for #{inactive_days} days")

      response = api_client.post("/api/v1/internal/ai_context/archive", {
        action: "archive_inactive",
        inactive_days: inactive_days
      })

      if response[:success]
        count = response[:data][:archived] || 0
        log_info("Archived inactive contexts", count: count)
        count
      else
        log_error("Failed to archive inactive contexts", error: response[:error])
        0
      end
    rescue StandardError => e
      log_error("Error archiving inactive contexts", exception: e)
      0
    end

    def archive_old_entries(options = {})
      max_age_days = options[:entry_max_age_days] || 180

      log_info("Archiving entries older than #{max_age_days} days")

      response = api_client.post("/api/v1/internal/ai_context/archive", {
        action: "archive_old_entries",
        max_age_days: max_age_days
      })

      if response[:success]
        count = response[:data][:archived] || 0
        log_info("Archived old entries", count: count)
        count
      else
        log_error("Failed to archive old entries", error: response[:error])
        0
      end
    rescue StandardError => e
      log_error("Error archiving old entries", exception: e)
      0
    end

    def purge_archived_contexts(options = {})
      archived_days = options[:purge_after_days] || 30

      log_info("Purging contexts archived for #{archived_days} days")

      response = api_client.post("/api/v1/internal/ai_context/archive", {
        action: "purge_archived",
        archived_days: archived_days
      })

      if response[:success]
        count = response[:data][:purged] || 0
        log_info("Purged archived contexts", count: count)
        count
      else
        log_error("Failed to purge archived contexts", error: response[:error])
        0
      end
    rescue StandardError => e
      log_error("Error purging archived contexts", exception: e)
      0
    end
  end
end
