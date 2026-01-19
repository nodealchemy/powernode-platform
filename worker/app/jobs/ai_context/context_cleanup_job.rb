# frozen_string_literal: true

module AiContext
  class ContextCleanupJob < BaseJob
    sidekiq_options queue: 'maintenance',
                    retry: 2,
                    dead: false

    # Cleanup expired entries, apply retention policies, and manage storage
    def execute(account_id = nil, options = {})
      log_info("Starting AI context cleanup", account_id: account_id)

      results = {
        expired_entries_cleaned: 0,
        retention_policies_applied: 0,
        low_importance_cleaned: 0,
        orphaned_entries_cleaned: 0
      }

      # Cleanup expired entries
      results[:expired_entries_cleaned] = cleanup_expired_entries(account_id)

      # Apply retention policies
      results[:retention_policies_applied] = apply_retention_policies(account_id)

      # Cleanup low importance entries if storage is high
      if options[:cleanup_low_importance]
        results[:low_importance_cleaned] = cleanup_low_importance_entries(account_id, options)
      end

      # Cleanup orphaned entries
      results[:orphaned_entries_cleaned] = cleanup_orphaned_entries(account_id)

      log_info("AI context cleanup completed", **results)
      track_cleanup_metrics(results)

      results
    end

    private

    def cleanup_expired_entries(account_id)
      log_info("Cleaning up expired context entries", account_id: account_id)

      # Call backend to cleanup expired entries
      params = { action: "cleanup_expired" }
      params[:account_id] = account_id if account_id

      response = api_client.post("/api/v1/internal/ai_context/cleanup", params)

      if response[:success]
        count = response[:data][:cleaned] || 0
        log_info("Cleaned up expired entries", count: count)
        count
      else
        log_error("Failed to cleanup expired entries", error: response[:error])
        0
      end
    rescue StandardError => e
      log_error("Error cleaning up expired entries", exception: e)
      0
    end

    def apply_retention_policies(account_id)
      log_info("Applying retention policies", account_id: account_id)

      # Fetch contexts with retention policies
      contexts = fetch_contexts_with_retention(account_id)
      applied = 0

      contexts.each do |context|
        result = apply_retention_policy(context)
        applied += 1 if result[:success]
      end

      log_info("Applied retention policies", count: applied)
      applied
    rescue StandardError => e
      log_error("Error applying retention policies", exception: e)
      0
    end

    def fetch_contexts_with_retention(account_id)
      params = { has_retention_policy: true, page: 1, per_page: 100 }
      params[:account_id] = account_id if account_id

      response = api_client.get("/api/v1/ai/contexts", params)

      return [] unless response[:success]

      response[:data][:contexts] || []
    end

    def apply_retention_policy(context)
      context_id = context[:id]
      policy = context[:retention_policy]

      return { success: false } if policy.blank?

      cleaned = 0

      # Apply max age policy
      if policy["max_age_days"].present?
        result = cleanup_old_entries(context_id, policy["max_age_days"])
        cleaned += result
      end

      # Apply max entries policy
      if policy["max_entries"].present?
        result = enforce_entry_limit(context_id, policy["max_entries"])
        cleaned += result
      end

      { success: true, cleaned: cleaned }
    end

    def cleanup_old_entries(context_id, max_age_days)
      response = api_client.post("/api/v1/internal/ai_context/cleanup", {
        context_id: context_id,
        action: "cleanup_old",
        max_age_days: max_age_days
      })

      response[:success] ? (response[:data][:cleaned] || 0) : 0
    end

    def enforce_entry_limit(context_id, max_entries)
      response = api_client.post("/api/v1/internal/ai_context/cleanup", {
        context_id: context_id,
        action: "enforce_limit",
        max_entries: max_entries
      })

      response[:success] ? (response[:data][:cleaned] || 0) : 0
    end

    def cleanup_low_importance_entries(account_id, options = {})
      log_info("Cleaning up low importance entries", account_id: account_id)

      threshold = options[:importance_threshold] || 0.1
      max_age_days = options[:max_age_for_low_importance] || 30

      params = {
        action: "cleanup_low_importance",
        importance_threshold: threshold,
        max_age_days: max_age_days
      }
      params[:account_id] = account_id if account_id

      response = api_client.post("/api/v1/internal/ai_context/cleanup", params)

      if response[:success]
        count = response[:data][:cleaned] || 0
        log_info("Cleaned up low importance entries", count: count)
        count
      else
        log_error("Failed to cleanup low importance entries", error: response[:error])
        0
      end
    rescue StandardError => e
      log_error("Error cleaning up low importance entries", exception: e)
      0
    end

    def cleanup_orphaned_entries(account_id)
      log_info("Cleaning up orphaned entries", account_id: account_id)

      params = { action: "cleanup_orphaned" }
      params[:account_id] = account_id if account_id

      response = api_client.post("/api/v1/internal/ai_context/cleanup", params)

      if response[:success]
        count = response[:data][:cleaned] || 0
        log_info("Cleaned up orphaned entries", count: count)
        count
      else
        0
      end
    rescue StandardError => e
      log_error("Error cleaning up orphaned entries", exception: e)
      0
    end
  end
end
