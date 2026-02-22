# frozen_string_literal: true

module Ai
  module AutonomyTelemetryActions
    extend ActiveSupport::Concern

    # GET /api/v1/ai/autonomy/telemetry
    def telemetry_events
      service = ::Ai::Autonomy::TelemetryService.new(account: current_account)
      events = service.query_events(
        agent_id: params[:agent_id],
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

    # POST /api/v1/ai/autonomy/telemetry
    def create_telemetry_event
      account = resolve_account_for_agent(params[:agent_id])
      return render_error("Agent not found", status: :not_found) unless account

      agent = account.ai_agents.find(params[:agent_id])
      service = ::Ai::Autonomy::TelemetryService.new(account: account)

      event = service.record_event(
        agent: agent,
        category: params[:event_category],
        event_type: params[:event_type],
        data: params[:event_data]&.to_unsafe_h || {},
        correlation_id: params[:correlation_id],
        parent_event_id: params[:parent_event_id],
        outcome: params[:outcome]
      )

      render_success(data: serialize_telemetry_event(event), status: :created)
    rescue ActiveRecord::RecordNotFound
      render_not_found("Agent")
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.message, status: :unprocessable_content)
    end

    private

    def resolve_account_for_agent(agent_id)
      if current_account
        current_account
      elsif current_worker || current_service
        Ai::Agent.find_by(id: agent_id)&.account
      end
    end

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
