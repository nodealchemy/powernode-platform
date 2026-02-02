# frozen_string_literal: true

module Api
  module V1
    module Ai
      # RalphLoopWebhooksController - Handles event-triggered Ralph Loop execution
      #
      # Provides a webhook endpoint for external systems (Git hooks, CI/CD, etc.)
      # to trigger Ralph Loop iterations without authentication.
      #
      # Security:
      # - Token-based authentication (unique per loop)
      # - Rate limiting via Rack::Attack
      # - Validation of loop state before execution
      #
      class RalphLoopWebhooksController < ApplicationController
        # Skip standard authentication - use webhook token instead
        skip_before_action :authenticate_user!
        skip_before_action :verify_authenticity_token

        before_action :verify_webhook_token
        before_action :validate_loop_state

        # POST /api/v1/ai/ralph_loops/webhook/:token
        # Trigger execution of an event-triggered Ralph Loop
        #
        # @param token [String] The unique webhook token for the loop
        # @param payload [Hash] Optional payload data to pass to the execution
        #
        # @return [JSON] Execution result with triggered_at timestamp
        #
        def trigger
          service = ::Ai::Ralph::ExecutionService.new(
            ralph_loop: @ralph_loop,
            account: @ralph_loop.account
          )

          result = case @ralph_loop.status
          when "pending"
                     service.start_loop
          when "paused"
                     service.resume_loop
          when "running"
                     service.run_iteration
          else
                     { success: false, error: "Loop in terminal state: #{@ralph_loop.status}" }
          end

          if result[:success]
            # Update execution tracking
            @ralph_loop.update!(last_scheduled_at: Time.current)
            @ralph_loop.increment_daily_iteration_count!

            # Log the webhook trigger
            log_webhook_trigger(result)

            render_success(
              result.merge(
                triggered_at: Time.current.iso8601,
                loop_id: @ralph_loop.id,
                loop_status: @ralph_loop.reload.status
              )
            )
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        rescue StandardError => e
          Rails.logger.error("Ralph Loop webhook trigger failed: #{e.message}")
          render_error("Webhook trigger failed: #{e.message}", status: :internal_server_error)
        end

        # GET /api/v1/ai/ralph_loops/webhook/:token/status
        # Get current status of the Ralph Loop (for monitoring)
        #
        def status
          render_success(
            loop_id: @ralph_loop.id,
            name: @ralph_loop.name,
            status: @ralph_loop.status,
            scheduling_mode: @ralph_loop.scheduling_mode,
            schedule_paused: @ralph_loop.schedule_paused,
            current_iteration: @ralph_loop.current_iteration,
            total_tasks: @ralph_loop.total_tasks,
            completed_tasks: @ralph_loop.completed_tasks,
            progress_percentage: @ralph_loop.progress_percentage,
            last_scheduled_at: @ralph_loop.last_scheduled_at&.iso8601,
            daily_iteration_count: @ralph_loop.daily_iteration_count
          )
        end

        private

        def verify_webhook_token
          token = params[:token]

          unless token.present?
            render_error("Webhook token is required", status: :unauthorized)
            return
          end

          @ralph_loop = ::Ai::RalphLoop.find_by(webhook_token: token)

          unless @ralph_loop
            render_error("Invalid webhook token", status: :unauthorized)
            nil
          end
        end

        def validate_loop_state
          return unless @ralph_loop

          # Check if loop is event-triggered
          unless @ralph_loop.scheduling_mode == "event_triggered"
            render_error(
              "Loop is not event-triggered (mode: #{@ralph_loop.scheduling_mode})",
              status: :unprocessable_content
            )
            return
          end

          # Check if schedule is paused
          if @ralph_loop.schedule_paused?
            render_error(
              "Loop schedule is paused: #{@ralph_loop.schedule_paused_reason}",
              status: :unprocessable_content
            )
            return
          end

          # Check if loop is in terminal state
          if @ralph_loop.terminal?
            render_error(
              "Loop is in terminal state: #{@ralph_loop.status}",
              status: :unprocessable_content
            )
            return
          end

          # Check if within schedule date range
          unless @ralph_loop.within_schedule_range?
            render_error(
              "Loop is outside its scheduled date range",
              status: :unprocessable_content
            )
            return
          end

          # Check daily limit
          if @ralph_loop.exceeded_daily_limit?
            render_error(
              "Daily iteration limit exceeded",
              status: :too_many_requests
            )
            nil
          end
        end

        def log_webhook_trigger(result)
          Rails.logger.info(
            "Ralph Loop webhook triggered: loop_id=#{@ralph_loop.id}, " \
            "name=#{@ralph_loop.name}, status=#{@ralph_loop.status}, " \
            "result=#{result[:success] ? 'success' : 'failed'}"
          )

          # Optionally create audit log
          AuditLog.create(
            account_id: @ralph_loop.account_id,
            action: "ai.ralph_loops.webhook_trigger",
            auditable: @ralph_loop,
            details: {
              source_ip: request.remote_ip,
              user_agent: request.user_agent,
              payload: params[:payload]&.to_unsafe_h
            }
          )
        rescue StandardError => e
          Rails.logger.warn("Failed to create audit log: #{e.message}")
        end
      end
    end
  end
end
