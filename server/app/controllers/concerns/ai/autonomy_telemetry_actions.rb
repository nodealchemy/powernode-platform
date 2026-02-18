# frozen_string_literal: true

module Ai
  module AutonomyTelemetryActions
    extend ActiveSupport::Concern

    # GET /api/v1/ai/autonomy/telemetry
    def telemetry_events
      service = ::Ai::Autonomy::TelemetryService.new(account: current_account)
      events = service.query_events(
        category: params[:category],
        limit: params[:limit]&.to_i || 100
      )

      render_success(data: events.map { |e| serialize_telemetry_event(e) })
    end

    # GET /api/v1/ai/autonomy/telemetry/:agent_id
    def agent_telemetry
      agent = current_account.ai_agents.find(params[:agent_id])
      service = ::Ai::Autonomy::TelemetryService.new(account: current_account)
      events = service.for_agent(agent, limit: params[:limit]&.to_i || 100)

      render_success(data: events.map { |e| serialize_telemetry_event(e) })
    rescue ActiveRecord::RecordNotFound
      render_not_found("Agent")
    end

    private

    def serialize_telemetry_event(event)
      {
        id: event.id,
        agent_id: event.agent_id,
        event_category: event.event_category,
        event_type: event.event_type,
        sequence_number: event.sequence_number,
        parent_event_id: event.parent_event_id,
        correlation_id: event.correlation_id,
        event_data: event.event_data,
        outcome: event.outcome,
        created_at: event.created_at
      }
    end
  end
end
