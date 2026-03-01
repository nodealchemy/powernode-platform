# frozen_string_literal: true

module Ai
  module Agui
    class ProtocolService
      include Ai::Concerns::AccountScoped

      # ==========================================
      # AG-UI Protocol Event Types
      # ==========================================
      EVENT_TYPES = Ai::AguiEvent::EVENT_TYPES

      # ==========================================
      # Session Management
      # ==========================================

      def create_session(thread_id:, user: nil, agent_id: nil, tools: [], capabilities: {})
        Rails.logger.info "[AG-UI] Creating session for thread: #{thread_id}"

        session = Ai::AguiSession.create!(
          account: @account,
          user: user,
          agent_id: agent_id,
          thread_id: thread_id,
          tools: tools,
          capabilities: capabilities,
          status: "idle",
          expires_at: 24.hours.from_now
        )

        Rails.logger.info "[AG-UI] Session created: #{session.id}"
        session
      end

      def get_session(session_id)
        Ai::AguiSession.where(account_id: @account.id).find(session_id)
      end

      def list_sessions(filters = {})
        scope = Ai::AguiSession.where(account_id: @account.id)
        scope = scope.where(status: filters[:status]) if filters[:status].present?
        scope = scope.by_thread(filters[:thread_id]) if filters[:thread_id].present?
        scope = scope.for_agent(filters[:agent_id]) if filters[:agent_id].present?
        scope.recent
      end

      def destroy_session(session_id)
        session = get_session(session_id)
        session.cancel_run! if session.active?
        session.destroy!
        true
      end

      # ==========================================
      # Run Management
      # ==========================================

      def run_agent(session:, input:)
        Rails.logger.info "[AG-UI] Starting run for session: #{session.id}"

        run_id = "run_#{SecureRandom.hex(12)}"
        session.start_run!(run_id: run_id)

        emit_event(session: session, event_type: "RUN_STARTED", run_id: run_id)

        begin
          # Emit initial text message with agent response
          message_id = "msg_#{SecureRandom.hex(8)}"
          emit_text_stream(session: session, message_id: message_id, delta: "Processing: #{input.to_s.truncate(200)}")

          session.complete_run!
          emit_event(session: session, event_type: "RUN_FINISHED", run_id: run_id)

          { session: session, run_id: run_id, status: "completed" }
        rescue StandardError => e
          Rails.logger.error "[AG-UI] Run error for session #{session.id}: #{e.message}"
          session.error_run!
          emit_event(
            session: session,
            event_type: "RUN_ERROR",
            run_id: run_id,
            content: e.message,
            metadata: { error_class: e.class.name }
          )
          { session: session, run_id: run_id, status: "error", error: e.message }
        end
      end

      def cancel_run(session:)
        Rails.logger.info "[AG-UI] Cancelling run for session: #{session.id}"

        unless session.status == "running"
          return { success: false, error: "Session is not running" }
        end

        run_id = session.run_id
        session.cancel_run!
        emit_event(session: session, event_type: "RUN_FINISHED", run_id: run_id,
                   metadata: { cancelled: true })

        { success: true, session: session, message: "Run cancelled" }
      end

      # ==========================================
      # Text Message Events
      # ==========================================

      def emit_text_stream(session:, message_id:, delta:)
        emit_event(
          session: session,
          event_type: "TEXT_MESSAGE_START",
          message_id: message_id,
          role: "assistant"
        )

        emit_event(
          session: session,
          event_type: "TEXT_MESSAGE_CONTENT",
          message_id: message_id,
          content: delta
        )

        emit_event(
          session: session,
          event_type: "TEXT_MESSAGE_END",
          message_id: message_id
        )
      end

      # ==========================================
      # Tool Call Events
      # ==========================================

      def emit_tool_call(session:, tool_call_id:, tool_name:, args_delta:)
        emit_event(
          session: session,
          event_type: "TOOL_CALL_START",
          tool_call_id: tool_call_id,
          metadata: { tool_name: tool_name }
        )

        emit_event(
          session: session,
          event_type: "TOOL_CALL_ARGS",
          tool_call_id: tool_call_id,
          content: args_delta.is_a?(String) ? args_delta : args_delta.to_json
        )

        emit_event(
          session: session,
          event_type: "TOOL_CALL_END",
          tool_call_id: tool_call_id
        )
      end

      def emit_tool_result(session:, message_id:, tool_call_id:, content:)
        emit_event(
          session: session,
          event_type: "TOOL_CALL_RESULT",
          message_id: message_id,
          tool_call_id: tool_call_id,
          content: content.is_a?(String) ? content : content.to_json
        )
      end

      # ==========================================
      # State Events
      # ==========================================

      def emit_state_delta(session:, delta:)
        emit_event(
          session: session,
          event_type: "STATE_DELTA",
          delta: delta
        )
      end

      def emit_state_snapshot(session:, snapshot:)
        emit_event(
          session: session,
          event_type: "STATE_SNAPSHOT",
          delta: snapshot
        )
      end

      # ==========================================
      # Activity Events
      # ==========================================

      def emit_activity(session:, message_id:, activity_type:, content:)
        event_type = activity_type == "snapshot" ? "ACTIVITY_SNAPSHOT" : "ACTIVITY_DELTA"

        emit_event(
          session: session,
          event_type: event_type,
          message_id: message_id,
          content: content.is_a?(String) ? content : content.to_json,
          metadata: { activity_type: activity_type }
        )
      end

      # ==========================================
      # Step Events
      # ==========================================

      def emit_step(session:, step_id:, status:)
        event_type = status == "started" ? "STEP_STARTED" : "STEP_FINISHED"

        emit_event(
          session: session,
          event_type: event_type,
          step_id: step_id,
          metadata: { step_status: status }
        )
      end

      # ==========================================
      # Event Retrieval
      # ==========================================

      def get_events(session_id:, after_sequence: nil, limit: 100)
        session = get_session(session_id)
        scope = session.agui_events.ordered

        scope = scope.after_sequence(after_sequence) if after_sequence.present?
        scope.limit(limit)
      end

      private

      # ==========================================
      # Core Event Emission
      # ==========================================

      def emit_event(session:, event_type:, **data)
        sequence = session.increment_sequence!

        event = Ai::AguiEvent.create!(
          session: session,
          account: @account,
          event_type: event_type,
          sequence_number: sequence,
          message_id: data[:message_id],
          tool_call_id: data[:tool_call_id],
          role: data[:role],
          content: data[:content],
          delta: data[:delta] || {},
          metadata: data[:metadata] || {},
          run_id: data[:run_id] || session.run_id,
          step_id: data[:step_id]
        )

        session.update_column(:last_event_at, Time.current)

        Rails.logger.debug "[AG-UI] Event emitted: #{event_type} (seq: #{sequence}) for session: #{session.id}"
        event
      end
    end
  end
end
