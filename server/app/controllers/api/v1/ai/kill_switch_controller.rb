# frozen_string_literal: true

module Api
  module V1
    module Ai
      class KillSwitchController < ApplicationController
        before_action :validate_permissions
        before_action :validate_write_permissions, only: %i[halt resume]

        # POST /api/v1/ai/kill_switch/halt
        def halt
          service = kill_switch_service

          if service.halted?
            return render_error("AI activity is already suspended", status: :conflict)
          end

          event = service.emergency_halt!(
            reason: params[:reason] || "Emergency halt triggered by user",
            triggered_by: current_user
          )

          render_success(
            event: serialize_event(event),
            kill_switch_status: service.status
          )
        end

        # POST /api/v1/ai/kill_switch/resume
        def resume
          service = kill_switch_service

          unless service.halted?
            return render_error("AI activity is not currently suspended", status: :conflict)
          end

          mode = %w[full minimal].include?(params[:mode]) ? params[:mode].to_sym : :full

          event = service.resume!(
            triggered_by: current_user,
            mode: mode
          )

          render_success(
            event: serialize_event(event),
            kill_switch_status: service.status
          )
        end

        # GET /api/v1/ai/kill_switch/status
        def status
          render_success(kill_switch_service.status)
        end

        # GET /api/v1/ai/kill_switch/preview_restore
        def preview_restore
          preview = kill_switch_service.preview_restore

          if preview.nil?
            return render_error("No snapshot available (AI activity is not suspended)", status: :not_found)
          end

          render_success(preview)
        end

        # GET /api/v1/ai/kill_switch/events
        def events
          limit = [params[:limit]&.to_i || 20, 100].min
          events = kill_switch_service.events(limit: limit)

          render_success(
            events: events.map { |e| serialize_event(e) },
            total_count: current_user.account.ai_kill_switch_events.count
          )
        end

        private

        def kill_switch_service
          @kill_switch_service ||= ::Ai::Autonomy::KillSwitchService.new(account: current_user.account)
        end

        def validate_permissions
          require_permission("ai.kill_switch.manage")
        end

        def validate_write_permissions
          require_permission("ai.kill_switch.manage")
        end

        def serialize_event(event)
          triggered_by = event.triggered_by
          {
            id: event.id,
            event_type: event.event_type,
            reason: event.reason,
            triggered_by: triggered_by ? {
              id: triggered_by.id,
              email: triggered_by.email,
              name: triggered_by.name
            } : nil,
            impact: event.impact,
            resume_mode: event.resume_mode,
            created_at: event.created_at.iso8601
          }
        end
      end
    end
  end
end
