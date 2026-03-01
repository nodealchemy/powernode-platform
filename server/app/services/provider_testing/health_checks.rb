# frozen_string_literal: true

module ProviderTesting
  module HealthChecks
    def start_continuous_health_check(interval:, duration:)
      end_time = Time.current + duration

      while Time.current < end_time
        result = test_connection
        @health_check_results << {
          timestamp: Time.current,
          success: result[:success],
          response_time_ms: result[:response_time_ms],
          health_score: result[:success] ? 0.9 : 0.0
        }
        sleep(interval)
      end

      @health_check_results
    end

    def get_health_check_history
      @health_check_results
    end

    def detect_performance_degradation
      return { degradation_detected: false } if @health_check_results.size < 2

      half = [ @health_check_results.size / 2, 1 ].max
      older_times = @health_check_results.first(half).map { |r| r[:response_time_ms] || 0 }
      recent_times = @health_check_results.last(half).map { |r| r[:response_time_ms] || 0 }

      avg_older = older_times.sum / older_times.size.to_f
      avg_recent = recent_times.sum / recent_times.size.to_f

      degradation = avg_older > 0 && avg_recent > avg_older * 1.5

      {
        degradation_detected: degradation,
        recent_avg_response_time: avg_recent,
        baseline_avg_response_time: avg_older
      }
    end

    def analyze_health_trends
      return {} if @health_check_results.empty?

      response_times = @health_check_results.map { |r| r[:response_time_ms] || 0 }
      successes = @health_check_results.count { |r| r[:success] }

      {
        trend_direction: response_times.last > response_times.first ? "degrading" : "stable",
        average_response_time: response_times.sum / response_times.size.to_f,
        success_rate_trend: successes.to_f / @health_check_results.size,
        stability_score: calculate_stability_score(response_times)
      }
    end
  end
end
