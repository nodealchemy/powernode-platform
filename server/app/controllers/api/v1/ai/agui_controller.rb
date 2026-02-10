# frozen_string_literal: true

module Api
  module V1
    module Ai
      class AguiController < ApplicationController
        include ActionController::Live

        before_action :authenticate_request
        before_action :validate_permissions

        # POST /api/v1/ai/agui/run
        def run
          response.headers["Content-Type"] = "text/event-stream"
          response.headers["X-Accel-Buffering"] = "no"
          response.headers["Cache-Control"] = "no-cache"

          session = find_or_create_session
          service = protocol_service

          result = service.run_agent(session: session, input: params[:input])

          events = session.agui_events.ordered
          events.each do |event|
            sse_data = event.to_sse_data.to_json
            response.stream.write("data: #{sse_data}\n\n")
          end
        rescue StandardError => e
          Rails.logger.error "[AG-UI Controller] SSE run error: #{e.message}"
          error_data = { type: "RUN_ERROR", error: e.message }.to_json
          response.stream.write("data: #{error_data}\n\n") rescue nil
        ensure
          response.stream.close rescue nil
        end

        # GET /api/v1/ai/agui/sessions
        def sessions
          service = protocol_service
          sessions_list = service.list_sessions(filter_params)

          render_success(
            sessions: sessions_list.map { |s| serialize_session(s) }
          )
        end

        # POST /api/v1/ai/agui/sessions
        def create_session
          service = protocol_service
          session = service.create_session(
            thread_id: session_params[:thread_id] || "thread_#{SecureRandom.hex(8)}",
            user: current_user,
            agent_id: session_params[:agent_id],
            tools: session_params[:tools] || [],
            capabilities: session_params[:capabilities] || {}
          )

          render_success(session: serialize_session(session), status: :created)
        end

        # GET /api/v1/ai/agui/sessions/:id
        def show_session
          session = protocol_service.get_session(params[:id])
          render_success(session: serialize_session(session))
        rescue ActiveRecord::RecordNotFound
          render_not_found("Session")
        end

        # DELETE /api/v1/ai/agui/sessions/:id
        def destroy_session
          protocol_service.destroy_session(params[:id])
          render_success(message: "Session destroyed")
        rescue ActiveRecord::RecordNotFound
          render_not_found("Session")
        end

        # POST /api/v1/ai/agui/sessions/:id/state
        def push_state
          session = protocol_service.get_session(params[:id])
          sync_service = ::Ai::Agui::StateSyncService.new(session: session)

          delta = Array(params[:state_delta]).map do |op|
            op.respond_to?(:to_unsafe_h) ? op.to_unsafe_h : op.to_h
          end
          result = sync_service.push_state(state_delta: delta)

          render_success(
            sequence: result[:sequence],
            snapshot: result[:snapshot]
          )
        rescue ActiveRecord::RecordNotFound
          render_not_found("Session")
        rescue ::Ai::Agui::StateSyncService::PatchError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # GET /api/v1/ai/agui/sessions/:id/events
        def events
          events_list = protocol_service.get_events(
            session_id: params[:id],
            after_sequence: params[:after_sequence]&.to_i,
            limit: [params[:limit]&.to_i || 100, 500].min
          )

          render_success(
            events: events_list.map(&:to_sse_data)
          )
        rescue ActiveRecord::RecordNotFound
          render_not_found("Session")
        end

        private

        def validate_permissions
          return if current_worker || current_service

          require_permission("ai.agents.read")
        end

        def protocol_service
          @protocol_service ||= ::Ai::Agui::ProtocolService.new(account: current_account)
        end

        def find_or_create_session
          if params[:session_id].present?
            protocol_service.get_session(params[:session_id])
          else
            protocol_service.create_session(
              thread_id: params[:thread_id] || "thread_#{SecureRandom.hex(8)}",
              user: current_user,
              agent_id: params[:agent_id]
            )
          end
        end

        def session_params
          params.permit(:thread_id, :agent_id, tools: [], capabilities: {})
        end

        def filter_params
          params.permit(:status, :thread_id, :agent_id).to_h.symbolize_keys
        end

        def serialize_session(session)
          {
            id: session.id,
            account_id: session.account_id,
            user_id: session.user_id,
            agent_id: session.agent_id,
            thread_id: session.thread_id,
            run_id: session.run_id,
            parent_run_id: session.parent_run_id,
            status: session.status,
            state: session.state,
            tools: session.tools,
            capabilities: session.capabilities,
            sequence_number: session.sequence_number,
            started_at: session.started_at,
            completed_at: session.completed_at,
            last_event_at: session.last_event_at,
            expires_at: session.expires_at,
            created_at: session.created_at,
            updated_at: session.updated_at
          }
        end
      end
    end
  end
end
