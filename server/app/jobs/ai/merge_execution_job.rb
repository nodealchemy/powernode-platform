# frozen_string_literal: true

module Ai
  class MergeExecutionJob < ApplicationJob
    queue_as :ai_execution

    def perform(session_id)
      session = Ai::WorktreeSession.find(session_id)
      return unless session.status == "merging"

      # Idempotency: check if merge operations already exist and are completed
      existing_completed = session.merge_operations.where(status: "completed").count
      if existing_completed > 0 && session.merge_operations.where(status: %w[pending in_progress]).none?
        Rails.logger.info "[MergeExecution] Merge already completed for session #{session_id}, skipping"
        return
      end

      merge_service = Ai::Git::MergeService.new(session: session)
      result = merge_service.execute

      if result[:success]
        session.complete!

        # Enqueue cleanup if auto_cleanup is enabled
        if session.auto_cleanup
          cleanup_delay = session.configuration.dig("cleanup_delay_seconds") || 0
          if cleanup_delay.positive?
            ::Ai::WorktreeCleanupJob.set(wait: cleanup_delay.seconds).perform_later(session.id)
          else
            ::Ai::WorktreeCleanupJob.perform_later(session.id)
          end
        end
      else
        session.fail!(
          error_message: result[:error] || "Merge failed",
          error_code: "MERGE_FAILED",
          error_details: { results: result[:results] }
        )
      end
    rescue StandardError => e
      Rails.logger.error "[MergeExecution] Job failed: #{e.message}"
      session = Ai::WorktreeSession.find_by(id: session_id)
      session&.fail!(error_message: e.message, error_code: "MERGE_JOB_FAILED")
    end
  end
end
