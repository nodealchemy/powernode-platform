# frozen_string_literal: true

module Api
  module V1
    module Internal
      # Internal API for worker service to create approval tokens
      class StepApprovalsController < InternalBaseController
        # GET /api/v1/internal/step_approvals/:step_execution_id
        # Returns step execution details for email template
        def show
          step_execution = CiCd::StepExecution.find(params[:step_execution_id])

          render_success({
            id: step_execution.id,
            step_name: step_execution.step_name,
            step_type: step_execution.step_type,
            status: step_execution.status,
            logs: step_execution.logs,
            pipeline_step: {
              id: step_execution.pipeline_step.id,
              name: step_execution.pipeline_step.name,
              requires_approval: step_execution.pipeline_step.requires_approval?,
              approval_timeout_hours: step_execution.pipeline_step.approval_timeout_hours,
              approval_requires_comment: step_execution.pipeline_step.approval_requires_comment?,
              configuration: step_execution.pipeline_step.configuration
            },
            pipeline_run: {
              id: step_execution.pipeline_run.id,
              run_number: step_execution.pipeline_run.run_number,
              trigger_type: step_execution.pipeline_run.trigger_type,
              trigger_context: step_execution.pipeline_run.trigger_context,
              status: step_execution.pipeline_run.status
            },
            pipeline: {
              id: step_execution.pipeline_run.pipeline.id,
              name: step_execution.pipeline_run.pipeline.name,
              slug: step_execution.pipeline_run.pipeline.slug,
              account_id: step_execution.pipeline_run.pipeline.account_id
            }
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Step execution not found", :not_found)
        end

        # POST /api/v1/internal/step_approvals/:step_execution_id/create_tokens
        # Creates approval tokens for each recipient
        def create_tokens
          step_execution = CiCd::StepExecution.find(params[:step_execution_id])
          recipients = params[:recipients] || []

          tokens = []

          recipients.each do |recipient|
            email = recipient["value"] || recipient["email"]
            user_id = recipient["user_id"]

            # Find user if user_id provided
            user = user_id ? User.find_by(id: user_id) : nil

            # Create token
            token, raw_token = CiCd::StepApprovalToken.create_for_recipient(
              step_execution: step_execution,
              recipient_email: email,
              recipient_user: user,
              expires_in: step_execution.pipeline_step.approval_timeout_hours.hours
            )

            tokens << {
              id: token.id,
              raw_token: raw_token,
              recipient_email: email,
              expires_at: token.expires_at.iso8601
            }
          end

          render_success({ tokens: tokens })
        rescue ActiveRecord::RecordNotFound
          render_error("Step execution not found", :not_found)
        rescue StandardError => e
          Rails.logger.error("Failed to create approval tokens: #{e.message}")
          render_error("Failed to create tokens: #{e.message}", :unprocessable_entity)
        end
      end
    end
  end
end
