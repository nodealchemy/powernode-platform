# frozen_string_literal: true

module Api
  module V1
    module AiWorkflows
      # Public API for token-based approval of AI workflow human_approval nodes
      # No authentication required - the token itself provides authorization
      class ApprovalTokensController < ApplicationController
        skip_before_action :authenticate_request, raise: false
        before_action :find_token_by_param

        # GET /api/v1/ai_workflows/approval_tokens/:token
        def show
          render_success(serialize_token(@token))
        end

        # POST /api/v1/ai_workflows/approval_tokens/:token/approve
        def approve
          unless @token.can_respond?
            return render_error(
              @token.expired? ? "Approval request has expired" : "Token has already been used",
              status: :unprocessable_content
            )
          end

          # Check if comment is required
          node = @token.node_execution.node
          if node&.configuration&.dig("require_comment") && params[:comment].blank?
            return render_error("A comment is required for this approval", status: :unprocessable_content)
          end

          if @token.approve!(comment: params[:comment], by_user: current_user_from_token)
            render_success({
              message: "Workflow step approved successfully",
              token: serialize_token(@token.reload)
            })
          else
            render_error("Failed to approve workflow step", status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai_workflows/approval_tokens/:token/reject
        def reject
          unless @token.can_respond?
            return render_error(
              @token.expired? ? "Approval request has expired" : "Token has already been used",
              status: :unprocessable_content
            )
          end

          # Check if comment is required
          node = @token.node_execution.node
          if node&.configuration&.dig("require_comment") && params[:comment].blank?
            return render_error("A comment is required for this rejection", status: :unprocessable_content)
          end

          if @token.reject!(comment: params[:comment], by_user: current_user_from_token)
            render_success({
              message: "Workflow step rejected",
              token: serialize_token(@token.reload)
            })
          else
            render_error("Failed to reject workflow step", status: :unprocessable_content)
          end
        end

        private

        def find_token_by_param
          digest = ::Ai::WorkflowApprovalToken.generate_digest(params[:token])
          @token = ::Ai::WorkflowApprovalToken.find_by(token_digest: digest)

          render_error("Invalid or expired approval token", status: :not_found) unless @token
        end

        def current_user_from_token
          # Try to extract user from Authorization header if present
          return nil unless request.headers["Authorization"].present?

          begin
            token = request.headers["Authorization"]&.split(" ")&.last
            decoded = Security::JwtService.decode(token)
            User.find_by(id: decoded["sub"] || decoded["user_id"])
          rescue JWT::DecodeError, JWT::ExpiredSignature, ActiveRecord::RecordNotFound
            nil
          end
        end

        def serialize_token(token)
          node_execution = token.node_execution
          workflow_run = node_execution.workflow_run
          workflow = workflow_run.workflow
          node = node_execution.node

          {
            id: token.id,
            status: token.status,
            recipient_email: token.recipient_email,
            expires_at: token.expires_at,
            responded_at: token.responded_at,
            response_comment: token.response_comment,
            time_remaining_seconds: token.time_remaining,
            can_respond: token.can_respond?,
            require_comment: node&.configuration&.dig("require_comment") || false,
            workflow: {
              id: workflow.id,
              name: workflow.name
            },
            workflow_run: {
              id: workflow_run.id,
              run_id: workflow_run.run_id,
              trigger_type: workflow_run.trigger_type,
              status: workflow_run.status
            },
            node_execution: {
              id: node_execution.id,
              node_name: node&.name || "Human Approval",
              node_type: node_execution.node_type,
              approval_message: node_execution.metadata["approval_message"],
              status: node_execution.status
            }
          }
        end
      end
    end
  end
end
