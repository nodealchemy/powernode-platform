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
    # Enqueue a notification email job
    def enqueue_notification_email(template_type, data = {})
      new.make_worker_request("POST", "/notifications/email", {
        template_type: template_type,
        data: data
      })
    end

    # Enqueue a billing job
    def enqueue_billing_job(job_type, data = {})
      new.make_worker_request("POST", "/billing/jobs", {
        job_type: job_type,
        data: data
      })
    end

    # Enqueue an analytics job
    def enqueue_analytics_job(job_type, data = {})
      new.make_worker_request("POST", "/analytics/jobs", {
        job_type: job_type,
        data: data
      })
    end

    # Enqueue a report generation job
    def enqueue_report_job(report_type, data = {})
      new.make_worker_request("POST", "/reports/generate", {
        report_type: report_type,
        data: data
      })
    end

    # Enqueue password reset email job
    def enqueue_password_reset_email(user_id)
      new.make_worker_request("POST", "/notifications/password_reset", {
        user_id: user_id
      })
    end

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
      job_args = [job_args] unless job_args.is_a?(Array)

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
    # CI/CD Jobs
    # ==========================================

    # Enqueue CI/CD step execution job
    def enqueue_ci_cd_step_execution(step_execution_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "CiCd::StepExecutionJob",
        "args" => [step_execution_id],
        "queue" => "ci_cd_default"
      })
    end

    # Enqueue CI/CD pipeline execution job
    def enqueue_ci_cd_pipeline_execution(pipeline_run_id, options = {})
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "CiCd::PipelineExecutionJob",
        "args" => [pipeline_run_id, options],
        "queue" => "ci_cd_high"
      })
    end

    # Enqueue CI/CD approval notification job
    def enqueue_ci_cd_approval_notification(step_execution_id, recipients)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "CiCd::ApprovalNotificationJob",
        "args" => [step_execution_id, recipients],
        "queue" => "email"
      })
    end
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
