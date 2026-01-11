# frozen_string_literal: true

module Api
  module V1
    module Devops
      # Public API for pipeline step approvals via email tokens
      # No authentication required - token provides authorization
      class StepApprovalsController < ApplicationController
        skip_before_action :authenticate_request, raise: false
        before_action :find_token_by_param

        # GET /api/v1/devops/step_approvals/:token
        # Returns approval token details (for the approval response page)
        def show
          if @token.nil?
            return render_error("Invalid or expired approval token", :not_found)
          end

          unless @token.can_respond?
            return render_error("This approval request has already been #{@token.status}", :gone)
          end

          render_success(serialize_token(@token))
        end

        # POST /api/v1/devops/step_approvals/:token/approve
        def approve
          if @token.nil?
            return render_error("Invalid or expired approval token", :not_found)
          end

          unless @token.can_respond?
            return render_error("This approval request has already been #{@token.status}", :gone)
          end

          # Check if comment is required
          if @token.step_execution.pipeline_step.approval_requires_comment? && params[:comment].blank?
            return render_error("A comment is required for this approval", status: :unprocessable_content)
          end

          if @token.approve!(comment: params[:comment], by_user: current_user_from_token)
            render_success({ status: "approved", message: "Step has been approved and will continue execution" })
          else
            render_error("Failed to process approval", :unprocessable_content)
          end
        end

        # POST /api/v1/devops/step_approvals/:token/reject
        def reject
          if @token.nil?
            return render_error("Invalid or expired approval token", :not_found)
          end

          unless @token.can_respond?
            return render_error("This approval request has already been #{@token.status}", :gone)
          end

          # Check if comment is required
          if @token.step_execution.pipeline_step.approval_requires_comment? && params[:comment].blank?
            return render_error("A comment is required for this rejection", status: :unprocessable_content)
          end

          if @token.reject!(comment: params[:comment], by_user: current_user_from_token)
            render_success({ status: "rejected", message: "Step has been rejected and pipeline will fail" })
          else
            render_error("Failed to process rejection", :unprocessable_content)
          end
        end

        private

        def find_token_by_param
          @token = ::Devops::StepApprovalToken.find_by_token(params[:token])
        end

        # Try to identify user if they're logged in (optional)
        def current_user_from_token
          return nil unless request.headers["Authorization"].present?

          token = request.headers["Authorization"].to_s.split(" ").last
          return nil if token.blank?

          decoded = Security::JwtService.decode(token)
          return nil unless decoded

          User.find_by(id: decoded[:user_id])
        rescue StandardError
          nil
        end

        def serialize_token(token)
          {
            step_name: token.step_execution.step_name,
            pipeline_name: token.step_execution.pipeline_run.pipeline.name,
            run_number: token.step_execution.pipeline_run.run_number,
            trigger_type: token.step_execution.pipeline_run.trigger_type,
            trigger_context: token.step_execution.pipeline_run.trigger_context,
            status: token.status,
            expires_at: token.expires_at.iso8601,
            time_remaining_seconds: token.time_remaining,
            requires_comment: token.step_execution.pipeline_step.approval_requires_comment?,
            step_configuration: {
              step_type: token.step_execution.pipeline_step.step_type,
              description: token.step_execution.pipeline_step.configuration["description"]
            }
          }
        end
      end
    end
  end
end
