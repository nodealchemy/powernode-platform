# frozen_string_literal: true

require_relative "../deployment_service"

module CiCd
  module StepHandlers
    # Handles deployment steps
    # Supports multiple deployment strategies:
    # - workflow: Trigger git provider workflow/action
    # - webhook: Call deployment webhook URL
    # - api: Call deployment API endpoint
    # - command: Execute local command (legacy/fallback)
    class DeployHandler < Base
      # Execute deploy step
      # @param config [Hash] Step configuration
      # @param context [Hash] Execution context
      # @param previous_outputs [Hash] Outputs from previous steps
      # @return [Hash] Result with :outputs and :logs keys
      def execute(config:, context:, previous_outputs: {})
        logs = []
        logs << log_info("Starting deploy step")

        environment = config["environment"] || "staging"
        strategy = config["strategy"] || detect_strategy(config)

        logs << log_info("Deploying to environment", environment: environment, strategy: strategy)

        # Use API-driven deployment unless command strategy specified
        deploy_result = if strategy == "command"
                          deploy_via_command(config, context, previous_outputs, logs)
                        else
                          deploy_via_service(config, context, logs)
                        end

        unless deploy_result[:success]
          logs << log_error("Deployment failed", error: deploy_result[:error])
          raise StandardError, "Deployment failed: #{deploy_result[:error] || deploy_result[:message]}"
        end

        logs << log_info("Deployment completed", strategy: strategy)

        # Run health check if configured
        health_result = nil
        if config["health_check_url"].present?
          logs << log_info("Running health check", url: config["health_check_url"])
          health_result = run_health_check(config["health_check_url"], config)

          if health_result[:healthy]
            logs << log_info("Health check passed")
          else
            logs << log_warn("Health check failed", reason: health_result[:error])

            if config["fail_on_health_check"]
              raise StandardError, "Health check failed: #{health_result[:error]}"
            end
          end
        end

        # Run smoke tests if configured
        smoke_result = nil
        if config["smoke_test_command"].present?
          logs << log_info("Running smoke tests")
          smoke_result = execute_shell_command(
            config["smoke_test_command"],
            working_directory: workspace,
            timeout: 300
          )

          if smoke_result[:success]
            logs << log_info("Smoke tests passed")
          else
            logs << log_warn("Smoke tests failed")

            if config["fail_on_smoke_test"]
              raise StandardError, "Smoke tests failed: #{smoke_result[:error]}"
            end
          end
        end

        logs << log_info("Deploy step completed", environment: environment)

        {
          outputs: {
            environment: environment,
            deploy_output: deploy_result[:output],
            health_check: health_result,
            smoke_test: smoke_result ? { passed: smoke_result[:success] } : nil
          },
          logs: logs.join("\n") + "\n\n--- Deploy Output ---\n" + deploy_result[:output]
        }
      end

      private

      def detect_strategy(config)
        # Auto-detect strategy based on config
        return "workflow" if config["workflow"].present?
        return "webhook" if config["webhook_url"].present?
        return "api" if config["api_url"].present?
        return "command" if config["command"].present?

        # Default to workflow for API-driven deployment
        "workflow"
      end

      def deploy_via_service(config, context, logs)
        deployment_service = DeploymentService.new(api_client: api_client, logger: logger)

        # Enrich context with commit SHA and repository info
        enriched_context = context.merge(
          commit_sha: context.dig(:trigger_context, :head_sha) ||
                      context.dig(:trigger_context, :after),
          repository: {
            full_name: context.dig(:trigger_context, :repository) ||
                       context.dig(:pipeline_run, :repository)
          }
        )

        logs << log_info("Using deployment service", strategy: config["strategy"])
        deployment_service.deploy(config: config, context: enriched_context)
      end

      def deploy_via_command(config, context, previous_outputs, logs)
        workspace = previous_outputs.dig("checkout", :workspace) || Dir.pwd
        environment = config["environment"] || "staging"

        deploy_command = config["command"] || "./scripts/deploy.sh #{environment}"
        logs << log_info("Executing deployment command", command: deploy_command)

        result = execute_shell_command(
          deploy_command,
          working_directory: workspace,
          timeout: (config["timeout_minutes"]&.to_i || 15) * 60
        )

        {
          success: result[:success],
          strategy: "command",
          environment: environment,
          output: result[:output],
          error: result[:error],
          exit_code: result[:exit_code]
        }
      end

      def run_health_check(url, config)
        require "net/http"

        max_retries = config["health_check_retries"] || 3
        retry_delay = config["health_check_retry_delay"] || 10
        timeout = config["health_check_timeout"] || 30

        retries = 0

        loop do
          begin
            uri = URI(url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = uri.scheme == "https"
            http.open_timeout = timeout
            http.read_timeout = timeout

            response = http.get(uri.path.presence || "/")

            if response.code.to_i == 200
              return {
                healthy: true,
                status_code: response.code.to_i,
                response_time: nil # Could add timing
              }
            else
              return {
                healthy: false,
                status_code: response.code.to_i,
                error: "Unexpected status code: #{response.code}"
              }
            end
          rescue StandardError => e
            retries += 1

            if retries >= max_retries
              return {
                healthy: false,
                error: "Health check failed after #{max_retries} retries: #{e.message}"
              }
            end

            log_info("Health check attempt #{retries} failed, retrying in #{retry_delay}s")
            sleep(retry_delay)
          end
        end
      end
    end
  end
end
