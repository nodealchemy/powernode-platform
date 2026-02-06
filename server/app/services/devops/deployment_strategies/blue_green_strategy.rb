# frozen_string_literal: true

module Devops
  module DeploymentStrategies
    class BlueGreenStrategy
      DEFAULT_HEALTH_CHECK_RETRIES = 3
      DEFAULT_HEALTH_CHECK_INTERVAL = 10

      def initialize(account:, pipeline_run: nil)
        @account = account
        @pipeline_run = pipeline_run
      end

      def execute(config:, context: {})
        health_check_url = config["health_check_url"]
        swap_timeout = config["swap_timeout"] || 300
        rollback_on_failure = config["rollback_on_failure"] != false

        active_env = context[:active_environment] || config["active_environment"] || "blue"
        inactive_env = active_env == "blue" ? "green" : "blue"

        steps = []

        # Step 1: Deploy to inactive environment
        deploy_result = deploy_to_environment(
          environment: inactive_env,
          config: config,
          context: context
        )
        steps << { step: :deploy, environment: inactive_env, result: deploy_result }

        unless deploy_result[:success]
          return build_result(steps: steps, status: :deploy_failed, active_env: active_env)
        end

        # Step 2: Health check on inactive environment
        if health_check_url
          inactive_health_url = config["#{inactive_env}_health_url"] || health_check_url
          health = verify_health(
            url: inactive_health_url,
            retries: config["health_check_retries"] || DEFAULT_HEALTH_CHECK_RETRIES,
            interval: config["health_check_interval"] || DEFAULT_HEALTH_CHECK_INTERVAL
          )
          steps << { step: :health_check, environment: inactive_env, result: health }

          unless health[:healthy]
            if rollback_on_failure
              cleanup_result = cleanup_environment(environment: inactive_env, config: config)
              steps << { step: :cleanup, environment: inactive_env, result: cleanup_result }
            end
            return build_result(steps: steps, status: :health_check_failed, active_env: active_env)
          end
        end

        # Step 3: Swap traffic
        swap_result = swap_traffic(
          from: active_env,
          to: inactive_env,
          config: config,
          context: context
        )
        steps << { step: :swap, from: active_env, to: inactive_env, result: swap_result }

        unless swap_result[:success]
          return build_result(steps: steps, status: :swap_failed, active_env: active_env)
        end

        # Step 4: Verify new active environment
        if health_check_url
          new_active_health_url = config["#{inactive_env}_health_url"] || health_check_url
          post_swap_health = verify_health(
            url: new_active_health_url,
            retries: DEFAULT_HEALTH_CHECK_RETRIES,
            interval: DEFAULT_HEALTH_CHECK_INTERVAL
          )
          steps << { step: :post_swap_health, environment: inactive_env, result: post_swap_health }

          unless post_swap_health[:healthy]
            if rollback_on_failure
              rollback_swap = swap_traffic(from: inactive_env, to: active_env, config: config, context: context)
              steps << { step: :rollback_swap, from: inactive_env, to: active_env, result: rollback_swap }
              return build_result(steps: steps, status: :rolled_back, active_env: active_env)
            end
          end
        end

        build_result(steps: steps, status: :completed, active_env: inactive_env)
      end

      def rollback(config:, context: {})
        current_env = context[:active_environment] || "green"
        previous_env = current_env == "blue" ? "green" : "blue"

        swap_result = swap_traffic(from: current_env, to: previous_env, config: config, context: context)

        {
          rolled_back: swap_result[:success],
          from: current_env,
          to: previous_env,
          rolled_back_at: Time.current.iso8601
        }
      end

      private

      def deploy_to_environment(environment:, config:, context:)
        Rails.logger.info "[BlueGreenStrategy] Deploying to #{environment} environment"

        {
          success: true,
          environment: environment,
          deployed_at: Time.current.iso8601
        }
      end

      def swap_traffic(from:, to:, config:, context:)
        Rails.logger.info "[BlueGreenStrategy] Swapping traffic from #{from} to #{to}"

        {
          success: true,
          from: from,
          to: to,
          swapped_at: Time.current.iso8601
        }
      end

      def verify_health(url:, retries:, interval:)
        retries.times do |attempt|
          result = check_health(url)
          return { healthy: true, attempts: attempt + 1, checked_at: Time.current.iso8601 } if result[:healthy]

          sleep(interval) if attempt < retries - 1
        end

        { healthy: false, attempts: retries, checked_at: Time.current.iso8601 }
      end

      def check_health(url)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 10
        http.read_timeout = 10

        response = http.get(uri.path.presence || "/health")
        { healthy: response.code.to_i == 200, status: response.code.to_i }
      rescue StandardError => e
        { healthy: false, error: e.message }
      end

      def cleanup_environment(environment:, config:)
        Rails.logger.info "[BlueGreenStrategy] Cleaning up #{environment} environment"
        { cleaned: true, environment: environment }
      end

      def build_result(steps:, status:, active_env:)
        {
          strategy: "blue_green",
          status: status,
          active_environment: active_env,
          steps: steps,
          completed_at: Time.current.iso8601
        }
      end
    end
  end
end
