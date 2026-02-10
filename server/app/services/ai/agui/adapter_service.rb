# frozen_string_literal: true

module Ai
  module Agui
    class AdapterService
      include Ai::Concerns::AccountScoped

      # Maps internal streaming event types to AG-UI event types
      STREAM_EVENT_MAP = {
        "text_start" => "TEXT_MESSAGE_START",
        "text_content" => "TEXT_MESSAGE_CONTENT",
        "text_end" => "TEXT_MESSAGE_END",
        "text_delta" => "TEXT_MESSAGE_CONTENT",
        "tool_start" => "TOOL_CALL_START",
        "tool_args" => "TOOL_CALL_ARGS",
        "tool_end" => "TOOL_CALL_END",
        "tool_result" => "TOOL_CALL_RESULT",
        "run_start" => "RUN_STARTED",
        "run_end" => "RUN_FINISHED",
        "run_error" => "RUN_ERROR",
        "step_start" => "STEP_STARTED",
        "step_end" => "STEP_FINISHED",
        "state_update" => "STATE_DELTA",
        "state_snapshot" => "STATE_SNAPSHOT",
        "activity" => "ACTIVITY_DELTA",
        "custom" => "CUSTOM",
        "raw" => "RAW"
      }.freeze

      # Convert an ActionCable stream chunk to AG-UI event format
      def convert_stream_chunk(chunk_data)
        chunk = normalize_chunk(chunk_data)
        event_type = STREAM_EVENT_MAP[chunk[:type]] || "CUSTOM"

        {
          type: event_type,
          message_id: chunk[:message_id],
          tool_call_id: chunk[:tool_call_id],
          role: chunk[:role] || "assistant",
          content: chunk[:content] || chunk[:delta],
          delta: chunk[:state_delta],
          metadata: chunk[:metadata] || {},
          run_id: chunk[:run_id],
          step_id: chunk[:step_id],
          timestamp: Time.current.iso8601
        }.compact
      end

      # Convert a tool call into an AG-UI tool call event sequence
      def convert_tool_call(tool_data)
        tool = normalize_chunk(tool_data)
        tool_call_id = tool[:tool_call_id] || "tc_#{SecureRandom.hex(8)}"

        events = []

        events << {
          type: "TOOL_CALL_START",
          tool_call_id: tool_call_id,
          metadata: { tool_name: tool[:tool_name] || tool[:name] }
        }

        if tool[:arguments].present?
          args_str = tool[:arguments].is_a?(String) ? tool[:arguments] : tool[:arguments].to_json
          events << {
            type: "TOOL_CALL_ARGS",
            tool_call_id: tool_call_id,
            content: args_str
          }
        end

        events << {
          type: "TOOL_CALL_END",
          tool_call_id: tool_call_id
        }

        if tool[:result].present?
          result_str = tool[:result].is_a?(String) ? tool[:result] : tool[:result].to_json
          events << {
            type: "TOOL_CALL_RESULT",
            tool_call_id: tool_call_id,
            content: result_str
          }
        end

        events
      end

      # Convert a state update to AG-UI STATE_DELTA or STATE_SNAPSHOT
      def convert_state_update(state_data)
        data = normalize_chunk(state_data)

        if data[:operations].present?
          # RFC 6902 JSON Patch operations => STATE_DELTA
          {
            type: "STATE_DELTA",
            delta: data[:operations],
            metadata: data[:metadata] || {}
          }
        else
          # Full state => STATE_SNAPSHOT
          {
            type: "STATE_SNAPSHOT",
            delta: data[:state] || data,
            metadata: data[:metadata] || {}
          }
        end
      end

      private

      def normalize_chunk(data)
        case data
        when Hash
          data.symbolize_keys
        when ActionController::Parameters
          data.to_unsafe_h.symbolize_keys
        when String
          JSON.parse(data).symbolize_keys
        else
          { content: data.to_s }
        end
      rescue JSON::ParserError
        { content: data.to_s }
      end
    end
  end
end
