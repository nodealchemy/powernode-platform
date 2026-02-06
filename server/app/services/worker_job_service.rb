# frozen_string_literal: true

require "net/http"
require "timeout"

# API client service for delegating async operations to the external worker service
# The Rails server contains NO worker functionality - all async ops handled by separate worker service
class WorkerJobService
  # Base URL for worker service API calls
  def self.worker_api_base
    Rails.application.config.worker_url
  end

  class << self
    # Enqueue email settings refresh job
    def enqueue_refresh_email_settings
      new.make_worker_request("POST", "/api/v1/jobs", {
        job_class: "RefreshEmailSettingsJob",
        args: []
      })
    end

    # Enqueue test email job
    def enqueue_test_email(email_address, account_id = nil)
      args = account_id ? [ email_address, account_id ] : [ email_address ]

      new.make_worker_request("POST", "/api/v1/jobs", {
        job_class: "TestEmailJob",
        args: args
      })
    end

    # Enqueue notification email job (email verification, welcome emails, etc.)
    # @param notification_type [String] Type of notification (e.g., 'email_verification')
    # @param options [Hash] Email options containing:
    #   - user_id: The user UUID
    #   - email: The recipient email address
    #   - verification_token: Token for verification emails
    #   - user_name: User's display name
    #   - smtp_settings: SMTP configuration from system settings
    def enqueue_notification_email(notification_type, options = {})
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "NotificationEmailJob",
        "args" => [ notification_type, options ],
        "queue" => "email"
      })
    end

    # Enqueue password reset email job
    # @param user_id [String] The user UUID requesting password reset
    def enqueue_password_reset_email(user_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "PasswordResetEmailJob",
        "args" => [ user_id ],
        "queue" => "email"
      })
    end

    # Enqueue test worker job
    def enqueue_test_worker_job(worker_id, worker_name)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "TestWorkerJob",
        "args" => [ worker_id, worker_name, {
          "test_type" => "worker_connectivity_test",
          "worker_id" => worker_id,
          "timestamp" => Time.current.to_i
        } ]
      })
    end

    # Enqueue AI workflow execution job
    def enqueue_ai_workflow_execution(run_id, job_options = {})
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiWorkflowExecutionJob",
        "args" => [ run_id, job_options ],
        "queue" => "ai_workflows",
        "options" => { "retry" => 3 }
      })
    end

    # Enqueue AI agent execution job
    def enqueue_ai_agent_execution(agent_execution_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiAgentExecutionJob",
        "args" => [ agent_execution_id ],
        "queue" => "ai_agents",
        "options" => { "retry" => 3 }
      })
    end

    # Enqueue billing automation job
    def enqueue_billing_automation(subscription_id = nil, delay: 0)
      payload = {
        "job_class" => "Billing::BillingAutomationJob",
        "args" => subscription_id ? [ subscription_id ] : [],
        "queue" => "billing"
      }
      payload["at"] = (Time.current + delay).to_i if delay.positive?

      new.make_worker_request("POST", "/api/v1/jobs", payload)
    end

    # Enqueue billing scheduler job
    def enqueue_billing_scheduler(date, delay: 0)
      payload = {
        "job_class" => "Billing::BillingSchedulerJob",
        "args" => [ date ],
        "queue" => "billing"
      }
      payload["at"] = (Time.current + delay).to_i if delay.positive?

      new.make_worker_request("POST", "/api/v1/jobs", payload)
    end

    # Enqueue billing cleanup job
    def enqueue_billing_cleanup(delay: 0)
      payload = {
        "job_class" => "Billing::BillingCleanupJob",
        "args" => [],
        "queue" => "billing"
      }
      payload["at"] = (Time.current + delay).to_i if delay.positive?

      new.make_worker_request("POST", "/api/v1/jobs", payload)
    end

    # Enqueue payment retry job
    def enqueue_payment_retry(payment_id, reason, retry_attempt)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Billing::PaymentRetryJob",
        "args" => [ payment_id, reason, retry_attempt ],
        "queue" => "billing"
      })
    end

    # Enqueue subscription lifecycle job
    # @param action [String] The lifecycle action: 'trial_ending_reminder', 'trial_ended', 'renewal_reminder'
    # @param subscription_id [String] The subscription UUID
    # @param options [Hash] Additional options
    # @option options [Integer] :delay Delay in seconds before job runs
    # @option options [Time] :run_at Time to run the job
    def enqueue_subscription_lifecycle(action, subscription_id, **options)
      delay = options.delete(:delay) || 0
      run_at = options.delete(:run_at)

      payload = {
        "job_class" => "Billing::SubscriptionLifecycleJob",
        "args" => [ action, subscription_id, options ],
        "queue" => "billing"
      }

      if run_at.present?
        payload["at"] = run_at.to_i
      elsif delay.positive?
        payload["at"] = (Time.current + delay).to_i
      end

      new.make_worker_request("POST", "/api/v1/jobs", payload)
    end

    # Enqueue node execution retry job
    def enqueue_node_execution_retry(node_execution_id, delay_ms: 0)
      payload = {
        "job_class" => "AiWorkflowNodeExecutionJob",
        "args" => [ node_execution_id ],
        "queue" => "ai_workflows"
      }
      payload["at"] = (Time.current + (delay_ms / 1000.0)).to_i if delay_ms.positive?

      new.make_worker_request("POST", "/api/v1/jobs", payload)
    end

    # Generic enqueue job method
    # @param job_class [String] The job class name
    # @param options [Hash] Job options:
    #   - args: [Array] Arguments to pass to the job
    #   - queue: [String] Queue name (default: "default")
    #   - delay: [Integer] Delay in seconds before running (default: 0)
    def enqueue_job(job_class, options = {})
      options = options.with_indifferent_access
      job_args = options.delete(:args) || []
      queue = options.delete(:queue) || "default"
      delay = options.delete(:delay) || 0

      # Ensure args is always an array
      job_args = [ job_args ] unless job_args.is_a?(Array)

      payload = {
        "job_class" => job_class,
        "args" => job_args,
        "queue" => queue
      }
      payload["at"] = (Time.current + delay).to_i if delay.positive?

      new.make_worker_request("POST", "/api/v1/jobs", payload)
    end

    # ==========================================
    # MCP (Model Context Protocol) Jobs
    # ==========================================

    # Enqueue MCP server connection job
    def enqueue_mcp_server_connection(server_id, action: "connect")
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Mcp::McpServerConnectionJob",
        "args" => [ server_id, { "action" => action } ],
        "queue" => "mcp"
      })
    end

    # Enqueue MCP tool execution job
    def enqueue_mcp_tool_execution(execution_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Mcp::McpToolExecutionJob",
        "args" => [ execution_id ],
        "queue" => "mcp"
      })
    end

    # Enqueue MCP tool discovery job
    def enqueue_mcp_tool_discovery(server_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Mcp::McpToolDiscoveryJob",
        "args" => [ server_id ],
        "queue" => "mcp"
      })
    end

    # Enqueue MCP server health check job
    def enqueue_mcp_health_check(server_id = nil)
      args = server_id ? [ server_id ] : []
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Mcp::McpServerHealthCheckJob",
        "args" => args,
        "queue" => "mcp"
      })
    end

    # Enqueue MCP tool cache refresh job
    def enqueue_mcp_cache_refresh
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Mcp::McpToolCacheRefreshJob",
        "args" => [],
        "queue" => "mcp"
      })
    end

    # ==========================================
    # AI Skills Jobs
    # ==========================================

    # Enqueue system skills seeding job
    def enqueue_ai_skill_seed
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiSkillSyncJob",
        "args" => [{ "action" => "seed" }],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue skill usage tracking job
    def enqueue_ai_skill_usage(skill_id, account_id: nil)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiSkillSyncJob",
        "args" => [{ "action" => "increment_usage", "skill_id" => skill_id, "account_id" => account_id }],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue skill connector refresh job
    def enqueue_ai_skill_refresh_connectors(skill_id, account_id: nil)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiSkillSyncJob",
        "args" => [{ "action" => "refresh_connectors", "skill_id" => skill_id, "account_id" => account_id }],
        "queue" => "ai_orchestration"
      })
    end

    # ==========================================
    # DevOps Jobs (CI/CD Pipelines, Integrations)
    # ==========================================

    # Enqueue DevOps step execution job
    def enqueue_devops_step_execution(step_execution_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Devops::StepExecutionJob",
        "args" => [ step_execution_id ],
        "queue" => "devops_default"
      })
    end

    # Enqueue DevOps pipeline execution job
    def enqueue_devops_pipeline_execution(pipeline_run_id, options = {})
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Devops::PipelineExecutionJob",
        "args" => [ pipeline_run_id, options ],
        "queue" => "devops_high"
      })
    end

    # Enqueue DevOps approval notification job
    def enqueue_devops_approval_notification(step_execution_id, recipients)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Devops::ApprovalNotificationJob",
        "args" => [ step_execution_id, recipients ],
        "queue" => "email"
      })
    end

    # Enqueue DevOps provider sync job
    def enqueue_devops_provider_sync(provider_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Devops::ProviderSyncJob",
        "args" => [ provider_id ],
        "queue" => "devops_default"
      })
    end

    # Enqueue DevOps integration execution job
    def enqueue_devops_integration_execution(execution_id, input = {}, context = {})
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Devops::IntegrationExecutionJob",
        "args" => [ { execution_id: execution_id, input: input, context: context } ],
        "queue" => "integrations"
      })
    end

    # Legacy aliases for backwards compatibility
    alias_method :enqueue_ci_cd_step_execution, :enqueue_devops_step_execution
    alias_method :enqueue_ci_cd_pipeline_execution, :enqueue_devops_pipeline_execution
    alias_method :enqueue_ci_cd_approval_notification, :enqueue_devops_approval_notification
  end

  # Instance methods for compatibility
  def queue_ai_workflow_execution(run_id)
    self.class.enqueue_ai_workflow_execution(run_id)
  end

  def make_worker_request(method, path, payload = {})
      uri = URI("#{self.class.worker_api_base}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 10
      http.open_timeout = 5

      request = case method.upcase
      when "GET"
                  Net::HTTP::Get.new(uri)
      when "POST"
                  Net::HTTP::Post.new(uri)
      when "PUT"
                  Net::HTTP::Put.new(uri)
      when "DELETE"
                  Net::HTTP::Delete.new(uri)
      else
                  raise ArgumentError, "Unsupported HTTP method: #{method}"
      end

      # Set headers
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"

      # Add worker service authentication
      worker_token = Rails.application.config.worker_token
      request["Authorization"] = "Bearer #{worker_token}" if worker_token

      # Set body for requests that support it
      if %w[POST PUT PATCH].include?(method.upcase) && payload.present?
        request.body = payload.to_json
      end

      begin
        response = http.request(request)

        case response.code.to_i
        when 200..299
          Rails.logger.info "Worker job enqueued successfully: #{method} #{path}"
          JSON.parse(response.body) if response.body.present?
        when 400..499
          error_body = JSON.parse(response.body) rescue { error: response.body }
          Rails.logger.warn "Worker service client error (#{response.code}): #{error_body}"
          raise WorkerServiceError, "Client error: #{error_body['error'] || response.body}"
        when 500..599
          error_body = JSON.parse(response.body) rescue { error: response.body }
          Rails.logger.error "Worker service server error (#{response.code}): #{error_body}"
          raise WorkerServiceError, "Server error: #{error_body['error'] || response.body}"
        else
          Rails.logger.warn "Unexpected response from worker service (#{response.code}): #{response.body}"
          raise WorkerServiceError, "Unexpected response: #{response.code}"
        end
      rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
        Rails.logger.error "Worker service timeout: #{e.message}"
        raise WorkerServiceError, "Worker service timeout: #{e.message}"
      rescue Errno::ECONNREFUSED, SocketError => e
        Rails.logger.error "Worker service connection error: #{e.message}"
        raise WorkerServiceError, "Worker service unavailable: #{e.message}"
      rescue JSON::ParserError => e
        Rails.logger.error "Invalid JSON response from worker service: #{e.message}"
        raise WorkerServiceError, "Invalid response format from worker service"
      end
    end

  # Custom exception for worker service errors
  class WorkerServiceError < StandardError; end
end
