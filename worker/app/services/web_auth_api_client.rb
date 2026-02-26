# frozen_string_literal: true

require_relative 'backend_api_client'

# Web interface-specific API client with separate circuit breaker
# This prevents web authentication failures from affecting worker operations
class WebAuthApiClient < BackendApiClient
  def make_request(method, path, data = {})
    # Use separate circuit breaker for web authentication
    with_web_auth_circuit_breaker do
      start_time = Time.current

      begin
        response = @connection.send(method) do |req|
          req.url path
          req.headers['Authorization'] = "Bearer #{WorkerJwt.token}"
          req.headers['Content-Type'] = 'application/json'
          req.headers['Accept'] = 'application/json'
          req.headers['User-Agent'] = 'PowernodeWorker-WebAuth/1.0'

          case method
          when :get, :delete
            req.params = data if data.any?
          else
            req.body = data if data.any?
          end
        end

        duration = Time.current - start_time
        @logger.debug "[WebAuthAPI] #{method.upcase} #{path} completed in #{duration.round(3)}s"

        handle_response(response)

      rescue Faraday::TimeoutError => e
        @logger.error "[WebAuthAPI] Request timeout for #{method.upcase} #{path}: #{e.message}"
        raise ApiError.new("Request timeout: #{e.message}", 408)
      rescue Faraday::ConnectionFailed => e
        @logger.error "[WebAuthAPI] Connection failed for #{method.upcase} #{path}: #{e.message}"
        raise ApiError.new("Connection failed: #{e.message}", 503)
      rescue Faraday::Error => e
        @logger.error "[WebAuthAPI] Request failed for #{method.upcase} #{path}: #{e.message}"
        raise ApiError.new("Request failed: #{e.message}")
      end
    end
  rescue CircuitOpenError => e
    @logger.warn "[WebAuthAPI] Circuit breaker OPEN: #{e.message}"
    raise ApiError.new("Web auth service temporarily unavailable: #{e.message}", 503)
  end
end