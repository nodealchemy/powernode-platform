# frozen_string_literal: true

module Ai
  module Autonomy
    module Sensors
      class PlatformHealthSensor < Base
        def sensor_type
          "platform_health"
        end

        def collect
          observations = []

          # Check circuit breaker states
          open_breakers = open_circuit_breakers
          if open_breakers.any?
            obs = build_observation(
              title: "#{open_breakers.size} circuit breakers open",
              observation_type: "alert",
              severity: "warning",
              data: { open_breakers: open_breakers },
              requires_action: true,
              expires_in: 1.hour
            )
            observations << obs if obs
          end

          # Check failed executions rate
          failure_rate = recent_failure_rate
          if failure_rate > 0.3
            obs = build_observation(
              title: "High execution failure rate: #{(failure_rate * 100).round(1)}%",
              observation_type: "anomaly",
              severity: failure_rate > 0.5 ? "critical" : "warning",
              data: { failure_rate: failure_rate, threshold: 0.3 },
              requires_action: true,
              expires_in: 2.hours
            )
            observations << obs if obs
          end

          # Check provider health
          degraded_providers = check_degraded_providers
          degraded_providers.each do |provider|
            obs = build_observation(
              title: "Provider #{provider[:name]} degraded (#{provider[:reason]})",
              observation_type: "degradation",
              severity: "warning",
              data: provider,
              requires_action: false,
              expires_in: 1.hour
            )
            observations << obs if obs
          end

          observations.compact
        end

        private

        def open_circuit_breakers
          breaker_service = Ai::Autonomy::CircuitBreakerService.new(account: account)
          account.ai_providers.filter_map do |provider|
            name = "ai_provider_#{provider.name}"
            state = breaker_service.check(name)
            { name: provider.name, state: state.to_s } if state == :open
          end
        rescue StandardError
          []
        end

        def recent_failure_rate
          window = 1.hour.ago
          total = Ai::AgentExecution.where(account_id: account.id).where("created_at >= ?", window).count
          return 0.0 if total == 0

          failed = Ai::AgentExecution.where(account_id: account.id, status: "failed").where("created_at >= ?", window).count
          failed.to_f / total
        rescue StandardError
          0.0
        end

        def check_degraded_providers
          account.ai_providers.where(status: "active").filter_map do |provider|
            recent = Ai::AgentExecution
              .where(account_id: account.id, ai_provider_id: provider.id)
              .where("created_at >= ?", 30.minutes.ago)

            total = recent.count
            next if total < 5

            failed = recent.where(status: "failed").count
            rate = failed.to_f / total

            if rate > 0.2
              { name: provider.name, provider_id: provider.id, failure_rate: rate, reason: "#{(rate * 100).round}% failures in last 30min" }
            end
          end
        rescue StandardError
          []
        end
      end
    end
  end
end
