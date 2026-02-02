# frozen_string_literal: true

module A2a
  module Client
    # TaskClient - Sends tasks to external A2A agents
    class TaskClient
      include HTTParty
      default_timeout 60

      def initialize(external_agent)
        @agent = external_agent
        @card = external_agent.to_a2a_json
        @a2a_url = @card["url"]
      end

      # Send a message to the external agent
      def send_message(skill:, input:, metadata: {})
        request_id = SecureRandom.uuid

        payload = {
          jsonrpc: "2.0",
          id: request_id,
          method: "message/send",
          params: {
            skill: skill,
            message: build_message(input),
            input: input,
            metadata: metadata
          }
        }

        start_time = Time.current
        response = post_jsonrpc(payload)
        response_time = ((Time.current - start_time) * 1000).round(2)

        if response[:success]
          @agent.record_task_result!(success: true, response_time_ms: response_time)
          { success: true, task: response[:result], response_time_ms: response_time }
        else
          @agent.record_task_result!(success: false, response_time_ms: response_time)
          { success: false, error: response[:error] }
        end
      end

      # Get task status from external agent
      def get_task(task_id)
        payload = {
          jsonrpc: "2.0",
          id: SecureRandom.uuid,
          method: "tasks/get",
          params: { id: task_id }
        }

        response = post_jsonrpc(payload)

        if response[:success]
          { success: true, task: response[:result] }
        else
          { success: false, error: response[:error] }
        end
      end

      # Cancel a task on external agent
      def cancel_task(task_id, reason: nil)
        payload = {
          jsonrpc: "2.0",
          id: SecureRandom.uuid,
          method: "tasks/cancel",
          params: { id: task_id, reason: reason }.compact
        }

        response = post_jsonrpc(payload)

        if response[:success]
          { success: true, task: response[:result] }
        else
          { success: false, error: response[:error] }
        end
      end

      # Provide input for a waiting task
      def provide_input(task_id, input_data)
        # This might need to use a different endpoint depending on the agent
        payload = {
          jsonrpc: "2.0",
          id: SecureRandom.uuid,
          method: "message/send",
          params: {
            taskId: task_id,
            message: build_message(input_data),
            input: input_data
          }
        }

        response = post_jsonrpc(payload)

        if response[:success]
          { success: true, task: response[:result] }
        else
          { success: false, error: response[:error] }
        end
      end

      # Stream messages from external agent
      def stream_message(skill:, input:, &block)
        request_id = SecureRandom.uuid

        payload = {
          jsonrpc: "2.0",
          id: request_id,
          method: "message/stream",
          params: {
            skill: skill,
            message: build_message(input),
            input: input
          }
        }

        stream_url = "#{@a2a_url}/stream"
        headers = build_headers
        headers["Accept"] = "text/event-stream"

        # Stream SSE events
        stream_sse(stream_url, payload, headers, &block)
      end

      # Wait for a task to complete
      def wait_for_task(task_id, timeout: 300)
        deadline = Time.current + timeout

        loop do
          result = get_task(task_id)
          return result unless result[:success]

          task = result[:task]
          status = task["status"] || task.dig("state", "status")

          if %w[completed failed canceled].include?(status)
            return { success: true, task: task, completed: true }
          end

          if Time.current > deadline
            return { success: false, error: "Task timed out" }
          end

          sleep 1
        end
      end

      private

      def post_jsonrpc(payload)
        response = self.class.post(
          @a2a_url,
          body: payload.to_json,
          headers: build_headers,
          timeout: 60
        )

        if response.success?
          body = JSON.parse(response.body)

          if body["error"]
            { success: false, error: body["error"] }
          else
            { success: true, result: body["result"] }
          end
        else
          { success: false, error: "HTTP #{response.code}" }
        end
      rescue JSON::ParserError => e
        { success: false, error: "Invalid JSON response: #{e.message}" }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def build_headers
        headers = {
          "Content-Type" => "application/json",
          "User-Agent" => "Powernode-A2A/1.0"
        }

        auth = @agent.authentication || {}
        schemes = @card.dig("authentication", "schemes") || []

        if schemes.include?("bearer") && @agent.auth_token_encrypted.present?
          headers["Authorization"] = "Bearer #{@agent.auth_token_encrypted}"
        elsif schemes.include?("api_key") && auth["api_key"].present?
          header_name = @card.dig("authentication", "api_key", "name") || "X-API-Key"
          headers[header_name] = auth["api_key"]
        end

        headers
      end

      def build_message(input)
        if input.is_a?(String)
          { role: "user", parts: [ { type: "text", text: input } ] }
        elsif input.is_a?(Hash) && input["text"].present?
          { role: "user", parts: [ { type: "text", text: input["text"] } ] }
        else
          { role: "user", parts: [ { type: "data", data: input } ] }
        end
      end

      def stream_sse(url, payload, headers)
        # SSE streaming implementation
        uri = URI.parse(url)

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          request = Net::HTTP::Post.new(uri)
          headers.each { |k, v| request[k] = v }
          request.body = payload.to_json

          http.request(request) do |response|
            buffer = ""

            response.read_body do |chunk|
              buffer += chunk

              while (line_end = buffer.index("\n\n"))
                event_data = buffer[0...line_end]
                buffer = buffer[(line_end + 2)..]

                event = parse_sse_event(event_data)
                yield event if event && block_given?
              end
            end
          end
        end
      end

      def parse_sse_event(data)
        event = {}
        data.each_line do |line|
          if line.start_with?("event:")
            event[:type] = line.sub("event:", "").strip
          elsif line.start_with?("data:")
            json_data = line.sub("data:", "").strip
            event[:data] = JSON.parse(json_data) rescue json_data
          elsif line.start_with?("id:")
            event[:id] = line.sub("id:", "").strip
          end
        end
        event.presence
      end
    end
  end
end
