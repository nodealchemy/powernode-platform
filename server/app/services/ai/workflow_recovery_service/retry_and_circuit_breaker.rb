# frozen_string_literal: true

class Ai::WorkflowRecoveryService
  module RetryAndCircuitBreaker
    extend ActiveSupport::Concern

    # Implement retry with exponential backoff
    def retry_with_backoff(node_execution, max_attempts: 3, backoff_strategy: :exponential)
      attempt = 0
      delay = 1 # Start with 1 second

      while attempt < max_attempts
        attempt += 1

        @logger.info "[RECOVERY] Retry attempt #{attempt}/#{max_attempts} for node #{node_execution.node_id}"

        begin
          # Retry execution
          result = execute_node_retry(node_execution)

          if result.status == "completed"
            @logger.info "[RECOVERY] Retry successful for node #{node_execution.node_id}"
            return result
          end

        rescue StandardError => e
          @logger.warn "[RECOVERY] Retry attempt #{attempt} failed: #{e.message}"

          if attempt < max_attempts
            # Calculate backoff delay
            sleep_time = case backoff_strategy
            when :linear
                           delay * attempt
            when :exponential
                           delay * (2 ** (attempt - 1))
            else
                           delay
            end

            @logger.info "[RECOVERY] Waiting #{sleep_time}s before next retry"
            sleep(sleep_time)
          end
        end
      end

      # All retries exhausted
      @logger.error "[RECOVERY] All retry attempts exhausted for node #{node_execution.node_id}"
      node_execution.tap do |ne|
        ne.update!(status: "failed") unless ne.status == "failed"
      end
    end

    # Execute node retry (called by retry_with_backoff)
    def execute_node_retry(node_execution)
      # Reset node execution status
      node_execution.update!(
        status: "running",
        retry_count: node_execution.retry_count + 1,
        metadata: node_execution.metadata.merge("retry_attempt" => node_execution.retry_count + 1)
      )

      # Execute the node
      execute_node_with_recovery(node_execution)

      # Return the updated node execution
      node_execution.reload
    end

    # Implement circuit breaker pattern
    def with_circuit_breaker(node_id, &block)
      circuit_state = get_circuit_state(node_id)

      case circuit_state[:status]
      when "open"
        # Circuit is open, don't attempt execution
        @logger.warn "[RECOVERY] Circuit breaker OPEN for node #{node_id}"
        { success: false, error: "Circuit breaker is open" }

      when "half_open"
        # Try execution with caution
        @logger.info "[RECOVERY] Circuit breaker HALF-OPEN for node #{node_id}, attempting execution"

        begin
          result = yield
          if result[:success]
            reset_circuit_breaker(node_id)
          else
            trip_circuit_breaker(node_id)
          end
          result
        rescue StandardError => e
          trip_circuit_breaker(node_id)
          raise e
        end

      else # 'closed'
        # Normal execution
        begin
          result = yield
          record_circuit_success(node_id) if result[:success]
          result
        rescue StandardError => e
          record_circuit_failure(node_id)
          raise e
        end
      end
    end

    private

    def get_circuit_state(node_id)
      redis_key = "circuit_breaker:#{node_id}"
      state = Rails.cache.read(redis_key) || { status: "closed", failure_count: 0 }

      # Check if circuit should transition states
      if state[:status] == "open" && state[:opened_at]
        # Check if enough time has passed to try half-open
        if Time.current - Time.parse(state[:opened_at]) > 30.seconds
          state[:status] = "half_open"
          Rails.cache.write(redis_key, state, expires_in: 5.minutes)
        end
      end

      state
    end

    def trip_circuit_breaker(node_id)
      @logger.warn "[RECOVERY] Tripping circuit breaker for node #{node_id}"

      state = {
        status: "open",
        opened_at: Time.current.iso8601,
        failure_count: 0
      }

      Rails.cache.write("circuit_breaker:#{node_id}", state, expires_in: 5.minutes)
    end

    def reset_circuit_breaker(node_id)
      @logger.info "[RECOVERY] Resetting circuit breaker for node #{node_id}"
      Rails.cache.delete("circuit_breaker:#{node_id}")
    end

    def record_circuit_failure(node_id)
      state = get_circuit_state(node_id)
      state[:failure_count] = (state[:failure_count] || 0) + 1

      # Trip circuit if threshold exceeded
      if state[:failure_count] >= 5
        trip_circuit_breaker(node_id)
      else
        Rails.cache.write("circuit_breaker:#{node_id}", state, expires_in: 5.minutes)
      end
    end

    def record_circuit_success(node_id)
      state = get_circuit_state(node_id)
      state[:failure_count] = [ 0, (state[:failure_count] || 0) - 1 ].max
      Rails.cache.write("circuit_breaker:#{node_id}", state, expires_in: 5.minutes)
    end
  end
end
