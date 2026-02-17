# frozen_string_literal: true

module Api
  module V1
    module Ai
      class RalphLoopsSchedulingController < ApplicationController
        include AuditLogging
        include ::Ai::ResourceFiltering

        before_action :set_ralph_loop, only: %i[run_iteration run_all stop_run_all pause_schedule resume_schedule regenerate_webhook_token]
        before_action :validate_permissions

        # POST /api/v1/ai/ralph_loops/:id/run_iteration
        def run_iteration
          result = build_execution_service.run_iteration

          if result[:success]
            render_success(result)
            log_audit_event("ai.ralph_loops.run_iteration", @ralph_loop)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/ralph_loops/:id/run_all
        def run_all
          result = build_execution_service.run_all(
            stop_on_error: params[:stop_on_error] != false,
            parallel: ActiveModel::Type::Boolean.new.cast(params[:parallel]),
            max_parallel: (params[:max_parallel] || 4).to_i,
            merge_strategy: params[:merge_strategy] || "sequential"
          )

          if result[:success]
            render_success(result)
            log_audit_event("ai.ralph_loops.run_all", @ralph_loop)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/ralph_loops/:id/stop_run_all
        def stop_run_all
          result = build_execution_service.stop_run_all

          if result[:success]
            render_success(result)
            log_audit_event("ai.ralph_loops.stop_run_all", @ralph_loop)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/ralph_loops/:id/pause_schedule
        def pause_schedule
          unless @ralph_loop.schedulable?
            return render_error("Loop is not schedulable (mode: #{@ralph_loop.scheduling_mode})")
          end

          if @ralph_loop.schedule_paused?
            return render_error("Schedule is already paused")
          end

          reason = params[:reason]
          @ralph_loop.pause_schedule!(reason: reason)

          render_success(
            ralph_loop: @ralph_loop.reload.loop_details,
            message: "Schedule paused successfully"
          )
          log_audit_event("ai.ralph_loops.pause_schedule", @ralph_loop)
        rescue StandardError => e
          Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
          render_error("Failed to pause schedule: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/ralph_loops/:id/resume_schedule
        def resume_schedule
          unless @ralph_loop.schedulable?
            return render_error("Loop is not schedulable (mode: #{@ralph_loop.scheduling_mode})")
          end

          unless @ralph_loop.schedule_paused?
            return render_error("Schedule is not paused")
          end

          @ralph_loop.resume_schedule!

          render_success(
            ralph_loop: @ralph_loop.reload.loop_details,
            message: "Schedule resumed successfully",
            next_scheduled_at: @ralph_loop.next_scheduled_at&.iso8601
          )
          log_audit_event("ai.ralph_loops.resume_schedule", @ralph_loop)
        rescue StandardError => e
          Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
          render_error("Failed to resume schedule: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/ralph_loops/:id/regenerate_webhook_token
        def regenerate_webhook_token
          unless @ralph_loop.scheduling_mode == "event_triggered"
            return render_error("Loop is not event-triggered")
          end

          new_token = @ralph_loop.regenerate_webhook_token!

          render_success(
            webhook_token: new_token,
            webhook_url: webhook_url_for(@ralph_loop),
            message: "Webhook token regenerated successfully"
          )
          log_audit_event("ai.ralph_loops.regenerate_webhook_token", @ralph_loop)
        rescue StandardError => e
          Rails.logger.error("#{self.class.name}##{action_name} failed: #{e.message}")
          render_error("Failed to regenerate token: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/ai/ralph_loops/:id/parse_prd
        def parse_prd
          @ralph_loop = find_ralph_loop
          return unless @ralph_loop

          return render_error("PRD data is required", status: :bad_request) if params[:prd].blank?

          prd_data = params[:prd].respond_to?(:to_unsafe_h) ? params[:prd].to_unsafe_h : params[:prd]
          result = build_execution_service.parse_prd(prd_data)

          if result[:success]
            render_success(result)
            log_audit_event("ai.ralph_loops.parse_prd", @ralph_loop)
          else
            render_error(result[:error], status: :unprocessable_content)
          end
        end

        private

        def set_ralph_loop
          @ralph_loop = find_ralph_loop
        end

        def resolved_account
          @resolved_account ||= current_account || current_user&.account
        end

        def find_ralph_loop
          account = resolved_account
          unless account
            render_error("Unauthorized", status: :unauthorized)
            return nil
          end

          loop_record = account.ai_ralph_loops.find_by(id: params[:id])

          unless loop_record
            render_error("Ralph loop not found", status: :not_found)
            return nil
          end

          loop_record
        end

        def build_execution_service
          ::Ai::Ralph::ExecutionService.new(
            ralph_loop: @ralph_loop,
            account: resolved_account,
            user: current_user
          )
        end

        def validate_permissions
          return if current_worker || current_service

          permission_map = {
            %w[parse_prd] => "ai.workflows.create",
            %w[run_iteration run_all stop_run_all pause_schedule resume_schedule regenerate_webhook_token] => "ai.workflows.execute"
          }

          permission_map.each do |actions, permission|
            return require_permission(permission) if actions.include?(action_name)
          end
        end

        def webhook_url_for(ralph_loop)
          return nil unless ralph_loop.webhook_token.present?

          "#{request.base_url}/api/v1/ai/ralph_loops/webhook/#{ralph_loop.webhook_token}"
        end
      end
    end
  end
end
