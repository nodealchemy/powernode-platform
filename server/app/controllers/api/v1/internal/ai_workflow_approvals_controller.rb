# frozen_string_literal: true

module Api
  module V1
    module Internal
      # Internal API for worker service to manage AI workflow approval tokens
      class AiWorkflowApprovalsController < InternalBaseController
        before_action :set_node_execution, only: [:show, :create_tokens]

        # GET /api/v1/internal/ai_workflow_approvals/:node_execution_id
        # Returns node execution details for email template
        def show
          render_success(serialize_node_execution(@node_execution))
        end

        # POST /api/v1/internal/ai_workflow_approvals/:node_execution_id/create_tokens
        # Creates approval tokens for each recipient
        def create_tokens
          recipients = params[:recipients] || []
          tokens_data = []

          recipients.each do |recipient|
            recipient_email = recipient["value"] || recipient["email"]
            recipient_user = nil

            # If recipient is a user_id, look up the user
            if recipient["type"] == "user_id" || recipient["user_id"].present?
              user_id = recipient["value"] || recipient["user_id"]
              recipient_user = User.find_by(id: user_id)
              recipient_email = recipient_user&.email || recipient_email
            end

            next if recipient_email.blank?

            # Create the token
            token, raw_token = AiWorkflowApprovalToken.create_for_recipient(
              node_execution: @node_execution,
              recipient_email: recipient_email,
              recipient_user: recipient_user,
              expires_in: expiry_duration
            )

            tokens_data << {
              id: token.id,
              raw_token: raw_token,
              recipient_email: token.recipient_email,
              expires_at: token.expires_at.iso8601
            }
          end

          render_success({
            tokens: tokens_data,
            node_execution_id: @node_execution.id
          }, status: :created)
        rescue StandardError => e
          Rails.logger.error("Failed to create AI workflow approval tokens: #{e.message}")
          render_error("Failed to create tokens: #{e.message}", status: :unprocessable_entity)
        end

        # POST /api/v1/internal/ai_workflow_approvals/expire_stale
        # Called by ApprovalExpiryJob to expire tokens and handle affected executions
        def expire_stale
          # Find and expire all pending tokens that have passed their expiry date
          expired_tokens = AiWorkflowApprovalToken.pending.where("expires_at < ?", Time.current)
          expired_count = expired_tokens.count

          # Get unique node executions that will be affected
          affected_execution_ids = expired_tokens.pluck(:ai_workflow_node_execution_id).uniq

          # Expire the tokens
          expired_tokens.update_all(status: "expired", updated_at: Time.current)

          # Handle node executions where ALL tokens are now expired/rejected
          failed_executions_count = 0
          affected_execution_ids.each do |execution_id|
            execution = AiWorkflowNodeExecution.find_by(id: execution_id)
            next unless execution&.waiting_for_approval?

            # Check if there are any remaining pending/approved tokens
            remaining_valid = execution.approval_tokens.where(status: %w[pending approved]).exists?

            unless remaining_valid
              # All tokens are expired or rejected - fail the execution
              execution.approve_execution!(
                nil,
                {
                  "approved" => false,
                  "reason" => "Approval request expired (no response received before deadline)"
                }
              )
              failed_executions_count += 1
            end
          end

          render_success({
            expired_count: expired_count,
            failed_executions_count: failed_executions_count,
            affected_execution_ids: affected_execution_ids
          })
        rescue StandardError => e
          Rails.logger.error("Error expiring AI workflow approval tokens: #{e.message}")
          render_error("Failed to expire tokens: #{e.message}", status: :internal_server_error)
        end

        private

        def set_node_execution
          @node_execution = AiWorkflowNodeExecution.find(params[:node_execution_id] || params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Node execution not found", status: :not_found)
        end

        def expiry_duration
          # Get expiry from node configuration or default to 24 hours
          timeout_hours = @node_execution&.ai_workflow_node&.configuration&.dig("approval_timeout_hours") || 24
          timeout_hours.hours
        end

        def serialize_node_execution(execution)
          workflow_run = execution.ai_workflow_run
          workflow = workflow_run.ai_workflow
          node = execution.ai_workflow_node

          {
            id: execution.id,
            execution_id: execution.execution_id,
            node_name: node&.name || "Human Approval",
            node_type: execution.node_type,
            status: execution.status,
            approval_message: execution.metadata["approval_message"],
            approvers: execution.metadata["approvers"],
            workflow: {
              id: workflow.id,
              name: workflow.name,
              account_id: workflow.account_id
            },
            workflow_run: {
              id: workflow_run.id,
              run_id: workflow_run.run_id,
              trigger_type: workflow_run.trigger_type,
              status: workflow_run.status
            },
            node: {
              id: node&.id,
              name: node&.name,
              type: node&.node_type,
              configuration: node&.configuration&.slice("approval_message", "approval_timeout_hours", "require_comment")
            }
          }
        end
      end
    end
  end
end
