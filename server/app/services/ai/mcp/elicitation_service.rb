# frozen_string_literal: true

module Ai
  module Mcp
    class ElicitationService
      ELICITATION_TIMEOUT = 300
      PENDING_TTL = 600

      class ElicitationError < StandardError; end
      class ElicitationTimeoutError < ElicitationError; end
      class ElicitationDeniedError < ElicitationError; end

      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      def create_request(tool_execution_id:, message:, schema: nil, metadata: {})
        request_id = SecureRandom.uuid

        request = {
          id: request_id,
          tool_execution_id: tool_execution_id,
          account_id: @account.id,
          user_id: @user&.id,
          message: message,
          schema: schema,
          metadata: metadata,
          status: "pending",
          created_at: Time.current.iso8601
        }

        store_request(request)
        broadcast_elicitation_request(request)

        request
      end

      def respond(request_id:, response:, approved: true)
        request = fetch_request(request_id)
        raise ElicitationError, "Elicitation request not found: #{request_id}" unless request

        unless request["status"] == "pending"
          raise ElicitationError, "Request already #{request["status"]}"
        end

        if approved
          validate_response(response, request["schema"]) if request["schema"]

          update_request(request_id, {
            status: "responded",
            response: response,
            responded_at: Time.current.iso8601,
            responded_by: @user&.id
          })

          { accepted: true, response: response }
        else
          update_request(request_id, {
            status: "denied",
            denied_at: Time.current.iso8601,
            denied_by: @user&.id
          })

          raise ElicitationDeniedError, "Elicitation denied by user"
        end
      end

      def wait_for_response(request_id:, timeout: ELICITATION_TIMEOUT)
        deadline = Time.current + timeout

        loop do
          request = fetch_request(request_id)
          return nil unless request

          case request["status"]
          when "responded"
            return request["response"]
          when "denied"
            raise ElicitationDeniedError, "Elicitation denied"
          when "expired"
            raise ElicitationTimeoutError, "Elicitation expired"
          end

          if Time.current > deadline
            update_request(request_id, { status: "expired" })
            raise ElicitationTimeoutError, "Elicitation timed out after #{timeout}s"
          end

          sleep 1
        end
      end

      def pending_requests(tool_execution_id: nil)
        pattern = if tool_execution_id
                    "mcp_elicitation:#{@account.id}:#{tool_execution_id}:*"
                  else
                    "mcp_elicitation:#{@account.id}:*"
                  end

        keys = redis.keys(pattern)
        keys.map { |k| JSON.parse(redis.get(k)) }
            .select { |r| r["status"] == "pending" }
            .sort_by { |r| r["created_at"] }
      rescue StandardError
        []
      end

      private

      def store_request(request)
        key = request_key(request[:id], request[:tool_execution_id])
        redis.setex(key, PENDING_TTL, request.to_json)
      end

      def fetch_request(request_id)
        pattern = "mcp_elicitation:#{@account.id}:*:#{request_id}"
        keys = redis.keys(pattern)
        return nil if keys.empty?

        data = redis.get(keys.first)
        data ? JSON.parse(data) : nil
      rescue JSON::ParserError
        nil
      end

      def update_request(request_id, updates)
        request = fetch_request(request_id)
        return unless request

        updated = request.merge(updates.stringify_keys)
        key = request_key(request_id, request["tool_execution_id"])
        redis.setex(key, PENDING_TTL, updated.to_json)

        broadcast_elicitation_update(updated)
      end

      def validate_response(response, schema)
        return unless schema.is_a?(Hash)

        required = schema["required"] || []
        properties = schema["properties"] || {}

        required.each do |field|
          unless response.key?(field) || response.key?(field.to_sym)
            raise ElicitationError, "Missing required field: #{field}"
          end
        end

        properties.each do |field, field_schema|
          value = response[field] || response[field.to_sym]
          next unless value

          expected_type = field_schema["type"]
          next unless expected_type

          valid = case expected_type
                  when "string" then value.is_a?(String)
                  when "number", "integer" then value.is_a?(Numeric)
                  when "boolean" then [true, false].include?(value)
                  when "array" then value.is_a?(Array)
                  when "object" then value.is_a?(Hash)
                  else true
                  end

          raise ElicitationError, "Field #{field} must be #{expected_type}" unless valid
        end
      end

      def broadcast_elicitation_request(request)
        ActionCable.server.broadcast(
          "mcp_elicitation_#{@account.id}",
          { type: "elicitation_request", data: request }
        )
      rescue StandardError => e
        Rails.logger.warn "[ElicitationService] Broadcast failed: #{e.message}"
      end

      def broadcast_elicitation_update(request)
        ActionCable.server.broadcast(
          "mcp_elicitation_#{@account.id}",
          { type: "elicitation_update", data: request }
        )
      rescue StandardError => e
        Rails.logger.warn "[ElicitationService] Broadcast update failed: #{e.message}"
      end

      def request_key(request_id, tool_execution_id)
        "mcp_elicitation:#{@account.id}:#{tool_execution_id}:#{request_id}"
      end

      def redis
        @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
      end
    end
  end
end
