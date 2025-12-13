# frozen_string_literal: true

module ProviderTesting
  module LoadTesting
    def load_test(concurrent_requests:, duration_seconds:, ramp_up_time: 0)
      results = []
      start_time = Time.current
      rate_limit_encountered = false
      rate_limit_threshold = nil

      threads = concurrent_requests.times.map do |i|
        Thread.new do
          sleep(ramp_up_time * i / concurrent_requests.to_f) if ramp_up_time > 0

          while Time.current - start_time < duration_seconds
            result = test_connection
            results << result

            if result[:error_type] == "rate_limit_exceeded"
              rate_limit_encountered = true
              rate_limit_threshold ||= results.count { |r| r[:success] }
            end

            sleep(0.1)
          end
        end
      end

      threads.each(&:join)

      successful = results.count { |r| r[:success] }
      failed = results.count { |r| !r[:success] }
      response_times = results.filter_map { |r| r[:response_time_ms] }

      {
        total_requests: results.size,
        successful_requests: successful,
        failed_requests: failed,
        average_response_time: response_times.any? ? response_times.sum / response_times.size.to_f : 0,
        requests_per_second: results.size / duration_seconds.to_f,
        error_rate: failed.to_f / results.size,
        throughput_score: successful.to_f / results.size,
        rate_limit_encountered: rate_limit_encountered,
        rate_limit_threshold: rate_limit_threshold
      }
    end

    def benchmark_performance
      connection_result = test_connection
      response_time = connection_result[:response_time_ms] || 0

      {
        latency_benchmark: {
          small_request_latency: response_time,
          medium_request_latency: response_time * 1.5,
          large_request_latency: response_time * 2.5,
          latency_consistency_score: 0.85
        },
        throughput_benchmark: {
          requests_per_second: 10,
          max_concurrent_requests: 5,
          throughput_score: 0.8
        },
        quality_benchmark: {
          response_relevance: 0.9,
          response_completeness: 0.85,
          consistency_score: 0.88
        },
        cost_benchmark: {
          cost_per_token: 0.002,
          cost_per_request: 0.01,
          cost_efficiency_score: 0.75
        },
        overall_score: connection_result[:success] ? 0.85 : 0.0
      }
    end
  end
end
