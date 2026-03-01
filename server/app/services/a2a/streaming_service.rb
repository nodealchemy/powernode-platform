# frozen_string_literal: true

module A2a
  # StreamingService - Handles A2A SSE streaming protocol
  # Implements Server-Sent Events for real-time task updates
  class StreamingService
    def initialize(account:)
      @account = account
    end

    # Stream task events to a client
    def stream_task_events(task, stream)
      # Send initial task status
      write_event(stream, "task.status", task.to_a2a_json)

      # If task is not terminal, subscribe to updates
      if task.terminal?
        write_event(stream, "task.complete", { status: task.a2a_status })
        return
      end

      # Poll for updates (in production, use ActionCable or Redis pub/sub)
      deadline = Time.current + 300 # 5 minute timeout

      loop do
        task.reload
        events = task.events.where("created_at > ?", Time.current - 1.second)

        events.each do |event|
          write_event(stream, event.event_type, event.to_a2a_json)
        end

        if task.terminal?
          write_event(stream, "task.complete", { status: task.a2a_status })
          break
        end

        break if Time.current > deadline

        sleep 0.5
      end
    end

    # Stream skill execution with progress updates
    def stream_skill_execution(skill, task, params, stream, &block)
      write_event(stream, "task.started", { task_id: task.task_id })

      handler_class, handler_method = skill[:handler].to_s.split(".")
      handler = handler_class.constantize.new(account: @account)

      if handler.respond_to?("#{handler_method}_streaming")
        handler.public_send("#{handler_method}_streaming", params, task) do |event|
          write_event(stream, event[:type], event[:data])
          block&.call(event)
        end
      else
        # Non-streaming execution with progress simulation
        write_event(stream, "task.progress", { current: 0, total: 100, message: "Starting..." })

        result = handler.public_send(handler_method, params, task)

        write_event(stream, "task.progress", { current: 100, total: 100, message: "Complete" })
        write_event(stream, "task.output", result)
      end

      task.reload
      write_event(stream, "task.complete", task.to_a2a_json)
    rescue StandardError => e
      write_event(stream, "task.error", { error: e.message, code: e.class.name })
      raise
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
