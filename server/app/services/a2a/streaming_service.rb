# frozen_string_literal: true

module A2a
  # StreamingService - Handles A2A SSE streaming protocol
  # Implements Server-Sent Events for real-time task updates
  class StreamingService
    def initialize(account:)
      @account = account
    end

    # Format and send an SSE event
    def write_event(stream, event_type, data)
      event_id = SecureRandom.uuid

      message = ""
      message += "id: #{event_id}\n"
      message += "event: #{event_type}\n"
      message += "data: #{data.to_json}\n\n"

      stream.write(message)
    rescue IOError
      # Stream closed
      raise ActionController::Live::ClientDisconnected
    end

    # Subscribe to task updates via ActionCable
    def subscribe_to_task(task_id)
      channel_name = "a2a_task_#{task_id}"

      {
        channel: channel_name,
        subscription_id: SecureRandom.uuid,
        websocket_url: "/cable"
      }
    end
  end
end
