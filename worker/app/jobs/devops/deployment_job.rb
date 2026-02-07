# frozen_string_literal: true

require "shellwords"

module Devops
  # AI-assisted deployment with validation
  # Queue: devops_high
  # Retry: 1
  class DeploymentJob < BaseJob
    sidekiq_options queue: "devops_high", retry: 1

    # Execute deployment with AI assistance
    # @param deployment_id [String] The deployment ID
    def execute(deployment_id)
      log_info "Starting deployment", deployment_id: deployment_id

      # Fetch deployment config
      deployment = fetch_deployment(deployment_id)

      # Update status to in_progress
      update_deployment(deployment_id, status: "in_progress", started_at: Time.current.iso8601)

      # Run pre-deployment AI review
      pre_deploy_result = run_pre_deployment_review(deployment)

      unless pre_deploy_result[:approved]
        log_warn "Pre-deployment review rejected deployment",
                 deployment_id: deployment_id,
                 reason: pre_deploy_result[:reason]

        update_deployment(
          deployment_id,
          status: "rejected",
          completed_at: Time.current.iso8601,
          notes: pre_deploy_result[:reason]
        )
        return
      end

      # Execute deployment steps
      execute_deployment(deployment)

      # Run post-deployment validation
      validation_result = run_post_deployment_validation(deployment)

      # Update final status
      final_status = validation_result[:healthy] ? "success" : "validation_failed"

      update_deployment(
        deployment_id,
        status: final_status,
        completed_at: Time.current.iso8601,
        validation_results: validation_result
      )

      log_info "Deployment completed",
               deployment_id: deployment_id,
               status: final_status
    rescue StandardError => e
      log_error "Deployment failed", e, deployment_id: deployment_id

      update_deployment(
        deployment_id,
        status: "failed",
        completed_at: Time.current.iso8601,
        error_message: e.message
      )

      raise
    end

    private

    def fetch_deployment(deployment_id)
      response = api_client.get("/api/v1/internal/devops/deployments/#{deployment_id}")
      response.dig("data", "deployment")
    end

    def update_deployment(deployment_id, **attributes)
      api_client.patch("/api/v1/internal/devops/deployments/#{deployment_id}", {
        deployment: attributes
      })
    end

    def run_pre_deployment_review(deployment)
      environment = deployment["environment"]
      changes = deployment["changes_summary"]

      prompt = <<~PROMPT
        Review this deployment for the #{environment} environment:

        Changes:
        #{changes}

        Evaluate:
        1. Breaking changes that could cause downtime
        2. Database migrations required
        3. Configuration changes needed
        4. Rollback complexity
        5. Performance impact

        Respond with JSON:
        {
          "approved": true/false,
          "risk_level": "LOW/MEDIUM/HIGH/CRITICAL",
          "reason": "explanation if not approved",
          "warnings": ["list of concerns"],
          "recommended_actions": ["pre-deploy steps"]
        }
      PROMPT

      result = execute_claude(prompt, deployment)
      parse_review_result(result[:output])
    rescue StandardError => e
      log_warn "Pre-deployment review failed, proceeding with caution", exception: e.message
      { approved: true, risk_level: "UNKNOWN", warnings: ["Review failed: #{e.message}"] }
    end

    BLOCKED_COMMAND_PATTERNS = [
      /sudo/i,
      /rm\s+-rf/i,
      /rm\s+\//i,
      /dd\s+if=/i,
      /mkfs/i,
      /chmod\s+777/i,
      /:\(\)\{:\|:&\}/i,
      /eval\s/i,
      /`[^`]+`/,
      /\$\([^)]+\)/,
      />\s*\/dev\/sd/i,
      /&&\s*rm\b/i,
      /;\s*rm\b/i,
      /\|\s*sh\b/i,
      /\|\s*bash\b/i,
    ].freeze

    def execute_deployment(deployment)
      environment = deployment["environment"]
      deploy_command = deployment["deploy_command"]

      log_info "Executing deployment", environment: environment

      # Execute the deployment command
      if deploy_command.present?
        validate_deploy_command!(deploy_command)
        result = execute_shell_command(deploy_command, deployment["working_directory"])

        unless result[:success]
          raise StandardError, "Deployment command failed: #{result[:error]}"
        end
      else
        # Default deployment via script
        script_path = deployment.dig("config", "script_path") || "./scripts/deploy.sh"
        validate_deploy_command!(script_path)
        sanitized_env = Shellwords.shellescape(environment)
        result = execute_shell_command("#{script_path} #{sanitized_env}", deployment["working_directory"])

        unless result[:success]
          raise StandardError, "Deployment script failed: #{result[:error]}"
        end
      end
    end

    def validate_deploy_command!(command)
      BLOCKED_COMMAND_PATTERNS.each do |pattern|
        if command.match?(pattern)
          raise StandardError, "Deployment command blocked by security policy: matches dangerous pattern"
        end
      end
    end

    def run_post_deployment_validation(deployment)
      environment = deployment["environment"]
      health_url = deployment.dig("config", "health_url")
      validation_script = deployment.dig("config", "validation_script")

      results = {
        healthy: true,
        checks: []
      }

      # Run health check if URL provided
      if health_url.present?
        health_result = check_health_endpoint(health_url)
        results[:checks] << health_result
        results[:healthy] &&= health_result[:passed]
      end

      # Run validation script if provided
      if validation_script.present?
        script_result = execute_shell_command(validation_script, deployment["working_directory"])
        results[:checks] << {
          name: "validation_script",
          passed: script_result[:success],
          output: script_result[:output],
          error: script_result[:error]
        }
        results[:healthy] &&= script_result[:success]
      end

      # Run AI validation if configured
      if deployment.dig("config", "ai_validation")
        ai_result = run_ai_validation(deployment)
        results[:checks] << ai_result
        results[:healthy] &&= ai_result[:passed]
      end

      results
    end

    def check_health_endpoint(url)
      require "net/http"

      uri = URI(url)
      response = Net::HTTP.get_response(uri)

      {
        name: "health_check",
        url: url,
        passed: response.code.to_i == 200,
        status_code: response.code.to_i,
        response_time: nil # Could add timing
      }
    rescue StandardError => e
      {
        name: "health_check",
        url: url,
        passed: false,
        error: e.message
      }
    end

    def run_ai_validation(deployment)
      environment = deployment["environment"]
      deploy_url = deployment.dig("config", "deploy_url")

      prompt = <<~PROMPT
        Validate the deployment at #{deploy_url}:

        1. Check critical endpoints are responding
        2. Verify authentication flows
        3. Test core functionality
        4. Check for error patterns in responses
        5. Validate API response times

        Respond with JSON:
        {
          "healthy": true/false,
          "issues": ["list of issues found"],
          "performance": {
            "response_time_avg_ms": 123,
            "endpoints_tested": 5
          }
        }
      PROMPT

      result = execute_claude(prompt, deployment)
      parsed = parse_validation_result(result[:output])

      {
        name: "ai_validation",
        passed: parsed[:healthy],
        details: parsed
      }
    rescue StandardError => e
      log_warn "AI validation failed", exception: e.message
      {
        name: "ai_validation",
        passed: true, # Don't fail deployment on AI validation errors
        error: e.message
      }
    end

    def execute_claude(prompt, deployment)
      options = {
        model: deployment.dig("config", "ai_model"),
        working_directory: deployment["working_directory"]
      }

      cmd = ["claude", "--print"]
      cmd << "--model" << options[:model] if options[:model]

      output = nil
      error_output = nil

      Open3.popen3(*cmd, chdir: options[:working_directory] || Dir.pwd) do |stdin, stdout, stderr, wait_thr|
        stdin.write(prompt)
        stdin.close

        Timeout.timeout(300) do
          output = stdout.read
          error_output = stderr.read
        end
      end

      { output: output, error: error_output }
    end

    def execute_shell_command(command, working_directory = nil)
      output, error, status = Open3.capture3(
        command,
        chdir: working_directory || Dir.pwd
      )

      {
        success: status.success?,
        output: output,
        error: error,
        exit_code: status.exitstatus
      }
    end

    def parse_review_result(output)
      json_match = output.match(/\{[\s\S]*"approved"[\s\S]*\}/)

      if json_match
        JSON.parse(json_match[0]).deep_symbolize_keys
      else
        { approved: true, warnings: ["Could not parse review result"] }
      end
    rescue JSON::ParserError
      { approved: true, warnings: ["Could not parse review result"] }
    end

    def parse_validation_result(output)
      json_match = output.match(/\{[\s\S]*"healthy"[\s\S]*\}/)

      if json_match
        JSON.parse(json_match[0]).deep_symbolize_keys
      else
        { healthy: true, warnings: ["Could not parse validation result"] }
      end
    rescue JSON::ParserError
      { healthy: true, warnings: ["Could not parse validation result"] }
    end
  end
end
