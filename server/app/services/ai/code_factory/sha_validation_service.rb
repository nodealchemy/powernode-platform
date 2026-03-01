# frozen_string_literal: true

module Ai
  module CodeFactory
    class ShaValidationService
      class ValidationError < StandardError; end

      def initialize(account:)
        @account = account
        @logger = Rails.logger
      end

      # Check if a review state is still valid for the given SHA
      def validate_review_state(review_state:, current_head_sha:)
        if review_state.sha_current?(current_head_sha)
          { valid: true, stale: false, reason: nil }
        else
          { valid: false, stale: true, reason: "Head SHA changed from #{review_state.head_sha} to #{current_head_sha}" }
        end
      end

      # Invalidate all non-stale review states for a PR when new push detected
      def invalidate_for_new_push(repository_id:, pr_number:, new_head_sha:)
        states = @account.ai_code_factory_review_states
          .where(repository_id: repository_id, pr_number: pr_number)
          .where.not(status: "stale")
          .where.not(head_sha: new_head_sha)

        count = 0
        states.find_each do |state|
          state.mark_stale!("New push detected: #{new_head_sha}")
          count += 1
        end

        @logger.info("[CodeFactory::ShaValidation] Invalidated #{count} review states for PR ##{pr_number}")
        { invalidated_count: count, new_head_sha: new_head_sha }
      end
    end
  end
end
