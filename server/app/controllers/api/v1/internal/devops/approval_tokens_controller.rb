# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Devops
        # Internal API for worker service to manage approval tokens
        class ApprovalTokensController < InternalBaseController
          # POST /api/v1/internal/devops/approval_tokens/expire_stale
          # Called by ApprovalExpiryJob to expire tokens and fail step executions
          def expire_stale
            # Find and expire all pending tokens that have passed their expiry date
            expired_tokens = ::Devops::StepApprovalToken.pending.where("expires_at < ?", Time.current)
            expired_count = expired_tokens.count

            # Get unique step executions that will be affected
            affected_execution_ids = expired_tokens.pluck(:step_execution_id).uniq

            # Expire the tokens
            expired_tokens.update_all(status: "expired", updated_at: Time.current)

            # Handle step executions where ALL tokens are now expired/rejected
            failed_steps_count = 0
            affected_execution_ids.each do |execution_id|
              execution = ::Devops::StepExecution.find_by(id: execution_id)
              next unless execution&.waiting_approval?

              # Check if there are any remaining pending/approved tokens
              remaining_valid = execution.approval_tokens.where(status: %w[pending approved]).exists?

              unless remaining_valid
                # All tokens are expired or rejected - fail the step
                execution.handle_approval_response!(
                  approved: false,
                  comment: "Approval request expired (no response received before deadline)"
                )
                failed_steps_count += 1
              end
            end

            render_success({
              expired_count: expired_count,
              failed_steps_count: failed_steps_count,
              affected_execution_ids: affected_execution_ids
            })
          rescue StandardError => e
            Rails.logger.error("Error expiring approval tokens: #{e.message}")
            render_error("Failed to expire tokens: #{e.message}", status: :internal_server_error)
          end

          # GET /api/v1/internal/devops/approval_tokens/pending_count
          # Returns count of pending tokens (useful for monitoring)
          def pending_count
            count = ::Devops::StepApprovalToken.pending.count
            expiring_soon = ::Devops::StepApprovalToken.pending.where("expires_at < ?", 1.hour.from_now).count

            render_success({
              total_pending: count,
              expiring_within_hour: expiring_soon
            })
          end
        end
      end
    end
  end
end
