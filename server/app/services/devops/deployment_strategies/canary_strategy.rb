# frozen_string_literal: true

module Devops
  module DeploymentStrategies
    class CanaryStrategy
      DEFAULT_STEPS = [
        { weight: 5, pause_seconds: 120 },
        { weight: 25, pause_seconds: 300 },
        { weight: 50, pause_seconds: 300 },
        { weight: 100, pause_seconds: 0 }
      ].freeze

      def initialize(account:, pipeline_run: nil)
        @account = account
        @pipeline_run = pipeline_run
      end

      def execute(config:, context: {})
        steps = config["steps"] || DEFAULT_STEPS
        health_check_url = config["health_check_url"]
        error_threshold = config["error_threshold"] || 5.0
        rollback_on_failure = config["rollback_on_failure"] != false

        results = []

        steps.each_with_index do |step, index|
          weight = step["weight"] || step[:weight]
          pause = step["pause_seconds"] || step[:pause_seconds] || 0

          result = execute_step(
            step_index: index,
            weight: weight,
            config: config,
            context: context
          )

          results << result

          unless result[:success]
            if rollback_on_failure
              rollback_result = rollback(config: config, context: context)
              return build_result(results: results, status: :rolled_back, rollback: rollback_result)
            else
              return build_result(results: results, status: :failed)
            end
          end

          next if pause.zero? || index == steps.size - 1

          health = monitor_health(
            duration: pause,
            health_check_url: health_check_url,
            error_threshold: error_threshold,
            config: config
          )

          results << { type: :health_check, step: index, health: health }

          next unless health[:should_rollback]

          if rollback_on_failure
            rollback_result = rollback(config: config, context: context)
            return build_result(results: results, status: :rolled_back, rollback: rollback_result)
          else
            return build_result(results: results, status: :unhealthy)
          end
        end

        build_result(results: results, status: :completed)
      end

      def rollback(config:, context: {})
        Rails.logger.info "[CanaryStrategy] Rolling back deployment"

        {
          rolled_back: true,
          rolled_back_at: Time.current.iso8601,
          previous_version: context[:previous_version]
        }
      end

      private

      def execute_step(step_index:, weight:, config:, context:)
        Rails.logger.info "[CanaryStrategy] Step #{step_index}: routing #{weight}% traffic to canary"

        {
          success: true,
          step: step_index,
          weight: weight,
          executed_at: Time.current.iso8601
        }
      end

      def monitor_health(duration:, health_check_url:, error_threshold:, config:)
        return { healthy: true, should_rollback: false } unless health_check_url

        checks = []
        interval = [duration / 3, 30].min
        check_count = [duration / [interval, 1].max, 1].max

        check_count.to_i.times do |i|
          check = perform_health_check(health_check_url)
          checks << check

          if check[:error_rate] && check[:error_rate] > error_threshold
            return {
              healthy: false,
              should_rollback: true,
              reason: "Error rate #{check[:error_rate]}% exceeds threshold #{error_threshold}%",
              checks: checks
            }
          end
        end

        {
          healthy: true,
          should_rollback: false,
          checks: checks
        }
      end

      def perform_health_check(url)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 10

        response = http.get(uri.path.presence || "/health")

        {
          status: response.code.to_i,
          healthy: response.code.to_i == 200,
          checked_at: Time.current.iso8601
        }
      rescue StandardError => e
        {
          status: 0,
          healthy: false,
          error: e.message,
          error_rate: 100.0,
          checked_at: Time.current.iso8601
        }
      end

      def build_result(results:, status:, rollback: nil)
        {
          strategy: "canary",
          status: status,
          steps_completed: results.count { |r| r[:type] != :health_check && r[:success] },
          total_steps: results.count { |r| r[:type] != :health_check },
          results: results,
          rollback: rollback,
          completed_at: Time.current.iso8601
        }
      end
    end
  end
end
