# frozen_string_literal: true

module Api
  module V1
    module Ai
      class CoordinationDashboardController < ApplicationController
        before_action :validate_permissions

        # GET /api/v1/ai/coordination/summary
        def summary
          signals = current_account.ai_stigmergic_signals
          fields = current_account.ai_pressure_fields
          events = current_account.ai_team_restructure_events

          render_success(
            summary: {
              signals: {
                total: signals.count,
                active: signals.active.count,
                fading: signals.fading.count,
                by_type: signals.group(:signal_type).count
              },
              pressure_fields: {
                total: fields.count,
                actionable: fields.actionable.count,
                by_type: fields.group(:field_type).count,
                avg_pressure: fields.average(:pressure_value)&.to_f&.round(3) || 0
              },
              team_events: {
                total: events.count,
                recent_24h: events.where("created_at >= ?", 24.hours.ago).count,
                by_type: events.group(:event_type).count
              }
            }
          )
        end

        # GET /api/v1/ai/coordination/signals
        def signals
          scope = current_account.ai_stigmergic_signals.includes(:emitter_agent)
          scope = scope.active if params[:active] == "true"
          scope = scope.by_type(params[:signal_type]) if params[:signal_type].present?

          signals = scope.strongest.page(params[:page]).per(params[:per_page] || 20)

          render_success(
            items: signals.map { |s| serialize_signal(s) },
            total: signals.total_count,
            page: signals.current_page,
            per_page: signals.limit_value
          )
        end

        # GET /api/v1/ai/coordination/pressure_fields
        def pressure_fields
          scope = current_account.ai_pressure_fields
          scope = scope.actionable if params[:actionable] == "true"
          scope = scope.by_type(params[:field_type]) if params[:field_type].present?

          fields = scope.highest_pressure.page(params[:page]).per(params[:per_page] || 20)

          render_success(
            items: fields.map { |f| serialize_pressure_field(f) },
            total: fields.total_count,
            page: fields.current_page,
            per_page: fields.limit_value
          )
        end

        # GET /api/v1/ai/coordination/team_events
        def team_events
          scope = current_account.ai_team_restructure_events.includes(:team, :agent)
          scope = scope.by_type(params[:event_type]) if params[:event_type].present?
          scope = scope.for_team(params[:team_id]) if params[:team_id].present?

          events = scope.recent.page(params[:page]).per(params[:per_page] || 20)

          render_success(
            items: events.map { |e| serialize_team_event(e) },
            total: events.total_count,
            page: events.current_page,
            per_page: events.limit_value
          )
        end

        private

        def validate_permissions
          authorize_permission!("ai.manage")
        end

        def serialize_signal(signal)
          {
            id: signal.id,
            signal_type: signal.signal_type,
            signal_key: signal.signal_key,
            strength: signal.strength&.to_f,
            decay_rate: signal.decay_rate&.to_f,
            reinforce_count: signal.reinforce_count,
            perceive_count: signal.perceive_count,
            payload: signal.payload,
            emitter_agent: signal.emitter_agent ? { id: signal.emitter_agent.id, name: signal.emitter_agent.name } : nil,
            expires_at: signal.expires_at&.iso8601,
            created_at: signal.created_at.iso8601
          }
        end

        def serialize_pressure_field(field)
          {
            id: field.id,
            field_type: field.field_type,
            artifact_ref: field.artifact_ref,
            pressure_value: field.pressure_value&.to_f,
            threshold: field.threshold&.to_f,
            decay_rate: field.decay_rate&.to_f,
            dimensions: field.dimensions,
            actionable: field.actionable?,
            address_count: field.address_count,
            last_measured_at: field.last_measured_at&.iso8601,
            last_addressed_at: field.last_addressed_at&.iso8601,
            created_at: field.created_at.iso8601
          }
        end

        def serialize_team_event(event)
          {
            id: event.id,
            event_type: event.event_type,
            team: event.team ? { id: event.team.id, name: event.team.name } : nil,
            agent: event.agent ? { id: event.agent.id, name: event.agent.name } : nil,
            previous_state: event.previous_state,
            new_state: event.new_state,
            rationale: event.rationale,
            metrics_snapshot: event.metrics_snapshot,
            created_at: event.created_at.iso8601
          }
        end
      end
    end
  end
end
