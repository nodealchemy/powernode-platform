# frozen_string_literal: true

# Jobs API controller for receiving job enqueue requests from the backend
class JobsController
  def self.call(env)
    new.call(env)
  end

  def call(env)
    request = Rack::Request.new(env)

    # Rack strips the mount prefix (/api/v1), so paths arrive relative.
    # Support both stripped and full paths for backward compatibility.
    path = request.path_info

    case [request.request_method, path]
    when ['POST', '/'], ['POST', ''], ['POST', '/jobs'], ['POST', '/api/v1/jobs']
      enqueue_job(request)
    when ['GET', '/sidekiq/stats'], ['GET', '/api/sidekiq/stats']
      sidekiq_stats(request)
    when ['POST', '/embeddings/generate'], ['POST', '/api/v1/embeddings/generate']
      generate_embedding(request)
    when ['POST', '/embeddings/batch'], ['POST', '/api/v1/embeddings/batch']
      generate_batch_embeddings(request)
    when ['POST', '/llm/complete'], ['POST', '/api/v1/llm/complete']
      llm_complete(request)
    when ['POST', '/llm/complete_with_tools'], ['POST', '/api/v1/llm/complete_with_tools']
      llm_complete_with_tools(request)
    when ['POST', '/llm/stream'], ['POST', '/api/v1/llm/stream']
      llm_stream(request)
    when ['POST', '/llm/complete_structured'], ['POST', '/api/v1/llm/complete_structured']
      llm_complete_structured(request)
    when ['POST', '/llm/execute_tool_loop'], ['POST', '/api/v1/llm/execute_tool_loop']
      llm_execute_tool_loop(request)
    else
      not_found_response
    end
  rescue StandardError => e
    PowernodeWorker.application.logger.error "Jobs API error: #{e.message}"
    error_response(500, 'Internal server error')
  end

  private

  def sidekiq_stats(request)
    # Verify authentication
    unless authenticated?(request)
      return error_response(401, 'Unauthorized')
    end

    begin
      stats = Sidekiq::Stats.new
      process_set = Sidekiq::ProcessSet.new

      # Get queue information
      queues = {}
      Sidekiq::Queue.all.each do |queue|
        queues[queue.name] = {
          size: queue.size,
          latency: queue.latency.round(2)
        }
      end

      success_response({
        processed: stats.processed,
        failed: stats.failed,
        enqueued: stats.enqueued,
        scheduled_size: stats.scheduled_size,
        retry_size: stats.retry_size,
        dead_size: stats.dead_size,
        default_queue_latency: stats.default_queue_latency&.round(2),
        workers_size: process_set.size,
        queues: queues,
        timestamp: Time.current.iso8601
      })
    rescue StandardError => e
      PowernodeWorker.application.logger.error "Failed to get Sidekiq stats: #{e.message}"
      error_response(500, "Failed to retrieve stats: #{e.message}")
    end
  end

  # POST /api/v1/embeddings/generate
  # Synchronous single embedding generation -- called by server's WorkerEmbeddingClient
  def generate_embedding(request)
    unless authenticated?(request)
      return error_response(401, 'Unauthorized')
    end

    begin
      body = request.body.read
      data = JSON.parse(body)
    rescue JSON::ParserError
      return error_response(400, 'Invalid JSON')
    end

    text = data['text']
    account_id = data['account_id']

    unless text.present? && account_id.present?
      return error_response(422, 'Missing text or account_id parameter')
    end

    begin
      service = build_embedding_service(account_id)
      embedding = service.generate(text)

      if embedding
        success_response({ embedding: embedding })
      else
        error_response(422, 'Failed to generate embedding')
      end
    rescue StandardError => e
      PowernodeWorker.application.logger.error "Embedding generation failed: #{e.message}"
      error_response(500, "Embedding generation failed: #{e.message}")
    end
  end

  # POST /api/v1/embeddings/batch
  # Synchronous batch embedding generation -- called by server's WorkerEmbeddingClient
  def generate_batch_embeddings(request)
    unless authenticated?(request)
      return error_response(401, 'Unauthorized')
    end

    begin
      body = request.body.read
      data = JSON.parse(body)
    rescue JSON::ParserError
      return error_response(400, 'Invalid JSON')
    end

    texts = data['texts']
    account_id = data['account_id']

    unless texts.is_a?(Array) && texts.any? && account_id.present?
      return error_response(422, 'Missing texts array or account_id parameter')
    end

    begin
      service = build_embedding_service(account_id)
      embeddings = service.generate_batch(texts)

      success_response({ embeddings: embeddings })
    rescue StandardError => e
      PowernodeWorker.application.logger.error "Batch embedding generation failed: #{e.message}"
      error_response(500, "Batch embedding generation failed: #{e.message}")
    end
  end

  # POST /api/v1/llm/complete
  # Synchronous LLM completion -- called by server's LLM proxy.
  # Accepts either agent_id (worker fetches provider config from server) or
  # credential_id + provider_type + provider_base_url (skips the callback).
  def llm_complete(request)
    unless authenticated?(request)
      return error_response(401, 'Unauthorized')
    end

    begin
      body = request.body.read
      data = JSON.parse(body)
    rescue JSON::ParserError
      return error_response(400, 'Invalid JSON')
    end

    messages = data['messages']
    agent_id = data['agent_id']
    credential_id = data['credential_id']

    unless (agent_id.present? || credential_id.present?) && messages.is_a?(Array) && messages.any?
      return error_response(422, 'Missing agent_id/credential_id or messages parameter')
    end

    begin
      client = build_llm_proxy_client
      opts = {}
      opts[:max_tokens] = data['max_tokens'] if data['max_tokens']
      opts[:temperature] = data['temperature'] if data['temperature']
      opts[:system_prompt] = data['system_prompt'] if data['system_prompt']

      llm_opts = { messages: messages, model: data['model'], **opts }
      if credential_id.present?
        llm_opts[:provider_config] = build_inline_provider_config(data)
      else
        llm_opts[:agent_id] = agent_id
      end

      result = client.complete(**llm_opts)
      success_response(result)
    rescue StandardError => e
      PowernodeWorker.application.logger.error "LLM complete failed: #{e.message}"
      error_response(500, "LLM complete failed: #{e.message}")
    end
  end

  # POST /api/v1/llm/complete_with_tools
  # Synchronous LLM completion with tool-calling -- called by server's LLM proxy.
  # Accepts either agent_id or credential_id + provider info (skips provider_config callback).
  def llm_complete_with_tools(request)
    unless authenticated?(request)
      return error_response(401, 'Unauthorized')
    end

    begin
      body = request.body.read
      data = JSON.parse(body)
    rescue JSON::ParserError
      return error_response(400, 'Invalid JSON')
    end

    messages = data['messages']
    agent_id = data['agent_id']
    credential_id = data['credential_id']

    unless (agent_id.present? || credential_id.present?) && messages.is_a?(Array) && messages.any?
      return error_response(422, 'Missing agent_id/credential_id or messages parameter')
    end

    begin
      client = build_llm_proxy_client
      opts = {}
      opts[:max_tokens] = data['max_tokens'] if data['max_tokens']
      opts[:temperature] = data['temperature'] if data['temperature']
      opts[:tool_choice] = data['tool_choice'] if data['tool_choice']

      llm_opts = { messages: messages, tools: data['tools'] || [], model: data['model'], **opts }
      if credential_id.present?
        llm_opts[:provider_config] = build_inline_provider_config(data)
      else
        llm_opts[:agent_id] = agent_id
      end

      result = client.complete_with_tools(**llm_opts)
      success_response(result)
    rescue StandardError => e
      PowernodeWorker.application.logger.error "LLM complete_with_tools failed: #{e.message}"
      error_response(500, "LLM complete_with_tools failed: #{e.message}")
    end
  end

  # POST /api/v1/llm/stream
  # Synchronous streaming LLM completion -- collects full stream and returns final result as JSON.
  # The server-side caller handles streaming to clients via ActionCable.
  # Accepts either agent_id or credential_id + provider info (skips provider_config callback).
  def llm_stream(request)
    unless authenticated?(request)
      return error_response(401, 'Unauthorized')
    end

    begin
      body = request.body.read
      data = JSON.parse(body)
    rescue JSON::ParserError
      return error_response(400, 'Invalid JSON')
    end

    messages = data['messages']
    agent_id = data['agent_id']
    credential_id = data['credential_id']

    unless (agent_id.present? || credential_id.present?) && messages.is_a?(Array) && messages.any?
      return error_response(422, 'Missing agent_id/credential_id or messages parameter')
    end

    begin
      client = build_llm_proxy_client
      opts = {}
      opts[:max_tokens] = data['max_tokens'] if data['max_tokens']
      opts[:temperature] = data['temperature'] if data['temperature']
      opts[:system_prompt] = data['system_prompt'] if data['system_prompt']

      # Use standard complete -- the worker collects the full response.
      # Streaming to the end user is handled server-side via ActionCable.
      llm_opts = { messages: messages, model: data['model'], **opts }
      if credential_id.present?
        llm_opts[:provider_config] = build_inline_provider_config(data)
      else
        llm_opts[:agent_id] = agent_id
      end

      result = client.complete(**llm_opts)
      success_response(result)
    rescue StandardError => e
      PowernodeWorker.application.logger.error "LLM stream failed: #{e.message}"
      error_response(500, "LLM stream failed: #{e.message}")
    end
  end

  # POST /api/v1/llm/complete_structured
  # Synchronous structured JSON output completion -- called by server's LLM proxy.
  # Accepts either agent_id or credential_id + provider info (skips provider_config callback).
  def llm_complete_structured(request)
    unless authenticated?(request)
      return error_response(401, 'Unauthorized')
    end

    begin
      body = request.body.read
      data = JSON.parse(body)
    rescue JSON::ParserError
      return error_response(400, 'Invalid JSON')
    end

    messages = data['messages']
    schema = data['schema']
    agent_id = data['agent_id']
    credential_id = data['credential_id']

    unless (agent_id.present? || credential_id.present?) && messages.is_a?(Array) && messages.any? && schema.is_a?(Hash)
      return error_response(422, 'Missing agent_id/credential_id, messages, or schema parameter')
    end

    begin
      client = build_llm_proxy_client
      opts = {}
      opts[:max_tokens] = data['max_tokens'] if data['max_tokens']

      llm_opts = { messages: messages, schema: schema, model: data['model'], **opts }
      if credential_id.present?
        llm_opts[:provider_config] = build_inline_provider_config(data)
      else
        llm_opts[:agent_id] = agent_id
      end

      result = client.complete_structured(**llm_opts
      )
      success_response(result)
    rescue StandardError => e
      PowernodeWorker.application.logger.error "LLM complete_structured failed: #{e.message}"
      error_response(500, "LLM complete_structured failed: #{e.message}")
    end
  end

  # POST /api/v1/llm/execute_tool_loop
  # Full agentic tool loop -- LLM calls happen locally, tool dispatch through server
  def llm_execute_tool_loop(request)
    unless authenticated?(request)
      return error_response(401, 'Unauthorized')
    end

    begin
      body = request.body.read
      data = JSON.parse(body)
    rescue JSON::ParserError
      return error_response(400, 'Invalid JSON')
    end

    agent_id = data['agent_id']
    messages = data['messages']

    unless agent_id.present? && messages.is_a?(Array) && messages.any?
      return error_response(422, 'Missing agent_id or messages parameter')
    end

    begin
      client = build_llm_proxy_client
      opts = {}
      opts[:max_iterations] = data['max_iterations'] if data['max_iterations']

      result = client.execute_tool_loop(
        agent_id: agent_id,
        messages: messages,
        model: data['model'],
        **opts
      )
      success_response(result)
    rescue StandardError => e
      PowernodeWorker.application.logger.error "LLM execute_tool_loop failed: #{e.message}"
      error_response(500, "LLM execute_tool_loop failed: #{e.message}")
    end
  end

  # Build a LlmProxyClient for direct LLM provider calls.
  # Uses BackendApiClient for server communication (credential resolution, tool dispatch).
  def build_llm_proxy_client
    @llm_proxy_client ||= LlmProxyClient.new(BackendApiClient.new.method(:post))
  end

  # Build provider config inline from request data, bypassing the provider_config
  # server callback. Used when the server sends credential_id + provider info directly.
  def build_inline_provider_config(data)
    {
      "provider_type" => data["provider_type"],
      "provider_credential_id" => data["credential_id"],
      "provider_base_url" => data["provider_base_url"],
      "provider_name" => data["provider_name"],
      "model" => data["model"]
    }
  end

  # Build an embedding service for an account.
  # Resolves the embedding provider config from the server.
  def build_embedding_service(account_id)
    @embedding_services ||= {}
    cached = @embedding_services[account_id]
    return cached if cached

    # Fetch embedding provider config from server
    # Server responds with { success: true, data: { provider_type:, credential_id:, ... } }
    api_client = BackendApiClient.new
    response = api_client.get("/api/v1/internal/ai/embedding_config?account_id=#{account_id}")
    config = response.is_a?(Hash) && response["data"] ? response["data"] : response

    service = Ai::EmbeddingService.new(
      api_post_method: api_client.method(:post),
      provider_type: config["provider_type"] || "openai",
      credential_id: config["credential_id"],
      account_id: account_id,
      ollama_url: config["ollama_url"],
      ollama_model: config["ollama_model"]
    )

    @embedding_services[account_id] = service
    service
  end

  def enqueue_job(request)
    # Verify authentication
    unless authenticated?(request)
      return error_response(401, 'Unauthorized')
    end

    # Parse request body
    begin
      body = request.body.read
      job_data = JSON.parse(body)
    rescue JSON::ParserError
      return error_response(400, 'Invalid JSON')
    end

    # Validate required fields
    unless job_data['job_class']
      return error_response(422, 'Missing job_class parameter')
    end

    job_class = job_data['job_class']
    args = job_data['args'] || []
    options = job_data['options'] || {}
    delay = job_data['delay']
    queue = job_data['queue']

    # Validate job class exists
    unless valid_job_class?(job_class)
      return error_response(422, "Invalid job class: #{job_class}")
    end

    begin
      # Get the actual job class
      klass = Object.const_get(job_class)

      # Debug logging for argument issues
      PowernodeWorker.application.logger.info "Enqueuing #{job_class} with args: #{args.inspect}"

      # Enqueue the job with proper queue handling
      # Separate Sidekiq options (like retry) from job arguments
      sidekiq_options = (options || {}).transform_keys(&:to_sym)

      # Build set options - always include at least an empty hash to avoid argument issues
      set_options = {}
      set_options[:queue] = queue if queue.present?
      set_options.merge!(sidekiq_options) if sidekiq_options.any?

      if delay
        # Parse delay (seconds, time string, or duration)
        delay_time = parse_delay(delay)
        if set_options.any?
          job = klass.set(set_options).perform_in(delay_time, *args)
        else
          job = klass.perform_in(delay_time, *args)
        end
      else
        if set_options.any?
          job = klass.set(set_options).perform_async(*args)
        else
          job = klass.perform_async(*args)
        end
      end

      PowernodeWorker.application.logger.info "Enqueued job #{job_class} with ID: #{job}"

      success_response({
        job_id: job,
        job_class: job_class,
        enqueued_at: Time.current.iso8601,
        delay: delay
      }.compact)

    rescue NameError => e
      PowernodeWorker.application.logger.error "Job class not found: #{job_class} - #{e.message}"
      error_response(422, "Job class not found: #{job_class}")
    rescue ArgumentError => e
      PowernodeWorker.application.logger.error "Invalid job arguments for #{job_class}: #{e.message}"
      error_response(422, "Invalid job arguments: #{e.message}")
    rescue StandardError => e
      PowernodeWorker.application.logger.error "Failed to enqueue job #{job_class}: #{e.message}"
      error_response(500, "Failed to enqueue job: #{e.message}")
    end
  end

  def authenticated?(request)
    auth_header = request.env['HTTP_AUTHORIZATION']
    return false unless auth_header

    token = auth_header.sub(/^Bearer /, '')
    return false if token.empty?

    # JWT-only authentication
    secret = jwt_secret_key
    return false unless secret

    begin
      decoded = JWT.decode(token, secret, true, algorithm: 'HS256')[0]
      decoded['type'] == 'worker' && decoded['sub'].present?
    rescue JWT::DecodeError
      false
    end
  end

  def valid_job_class?(job_class)
    # List of allowed job classes for security
    allowed_jobs = [
      # Billing jobs
      'Billing::BillingAutomationJob',
      'Billing::PaymentRetryJob',
      'Billing::SubscriptionLifecycleJob',
      'Billing::BillingSchedulerJob',
      'Billing::BillingCleanupJob',
      'Billing::SubscriptionRenewalJob',
      'Billing::DunningProcessJob',
      'Billing::PaymentReconciliationJob',
      # Report jobs
      'Reports::GenerateReportJob',
      'Reports::ScheduledReportJob',
      # Webhook jobs
      'Webhooks::ProcessWebhookJob',
      # Analytics jobs
      'Analytics::RecalculateAnalyticsJob',
      'Analytics::UpdateRevenueSnapshotsJob',
      # Email and notification jobs
      'SendNotificationEmailJob',
      'TestEmailJob',
      'TestWorkerJob',
      'RefreshEmailSettingsJob',
      'Notifications::EmailDeliveryJob',
      'Notifications::BulkEmailJob',
      'Notifications::TransactionalEmailJob',
      'Notifications::SmsDeliveryJob',
      'Notifications::PushNotificationJob',
      'Notifications::ReviewNotificationJob',
      # Service jobs
      'Services::TestPaymentGatewayConnectionJob',
      # AI/Workflow jobs
      'AiConversationProcessingJob',
      'AiAgentExecutionJob',
      'AiTeamExecutionJob',
      'AiWorkspaceResponseJob',
      'AiWorkflowExecutionJob',
      'AiWorkflowNodeExecutionJob',
      'WorkflowTimeoutJob',
      'WorkflowCleanupJob',
      'AiWorkflow::ApprovalExpiryJob',
      # File processing jobs
      'ThumbnailGenerationJob',
      'MetadataExtractionJob',
      'VideoProcessingJob',
      'AudioProcessingJob',
      # MCP (Model Context Protocol) jobs
      'Mcp::McpServerConnectionJob',
      'Mcp::McpServerHealthCheckJob',
      'Mcp::McpToolDiscoveryJob',
      'Mcp::McpToolExecutionJob',
      'Mcp::McpToolCacheRefreshJob',
      # Git integration jobs
      'Git::CredentialSetupJob',
      'Git::RepositorySyncJob',
      'Git::PipelineSyncJob',
      'Git::WebhookProcessingJob',
      'Git::JobLogsSyncJob',
      # DevOps pipeline jobs
      'Devops::ApprovalNotificationJob',
      'Devops::ApprovalExpiryJob',
      'Devops::StepExecutionJob',
      'Devops::PipelineExecutionJob',
      'Devops::ProviderSyncJob',
      'Devops::ScheduleTriggerJob',
      'Devops::SecurityScanJob',
      'Devops::DeploymentJob',
      'Devops::ClaudeInvokeJob',
      'Devops::WebhookHandlerJob',
      # Integration jobs
      'Integrations::IntegrationExecutionJob',
      'Integrations::IntegrationHealthCheckJob',
      'Integrations::CredentialRotationJob',
      # Compliance/GDPR jobs
      'Compliance::AccountTerminationJob',
      'Compliance::DataDeletionJob',
      'Compliance::DataExportJob',
      'Compliance::DataRetentionEnforcementJob',
      'Compliance::TerminationNotificationJob',
      'Compliance::TerminationReminderJob',
      'Compliance::DeletionNotificationJob',
      # Maintenance jobs
      'Maintenance::ScheduledBackupJob',
      'Maintenance::BackupCleanupJob',
      'Maintenance::DatabaseMaintenanceJob',
      'Maintenance::CacheCleanupJob',
      'Maintenance::LogRotationJob',
      # AI A2A (Agent-to-Agent) task jobs
      'AiA2aTaskExecutionJob',
      'AiA2aExternalTaskJob',
      # AI Knowledge event-driven jobs
      'AiPromoteLearningJob',
      'AiConsolidateMemoryEntryJob',
      'AiDedupLearningJob',
      'AiUpdateGraphNodeJob',
      'AiSkillConflictCheckJob',
      # AI Skills jobs
      'AiSkillSyncJob',
      # AI Mission jobs
      'AiMissionAnalyzeJob',
      'AiMissionPlanJob',
      'AiMissionExecuteJob',
      'AiMissionTestJob',
      'AiMissionReviewJob',
      'AiMissionDeployJob',
      'AiMissionMergeJob',
      'AiMissionCleanupJob',
      # AI remediation jobs (migrated from server)
      'AiConversationResponseJob',
      'AiSelfHealingMonitorJob',
      'AiTrajectoryAnalysisJob',
      'AiRalphLoopRunAllJob',
      'AiRalphLoopSchedulerJob',
      # AI Git/Worktree jobs (migrated from server)
      'AiWorktreeProvisioningJob',
      'AiWorktreeCleanupJob',
      'AiWorktreePushAndPrJob',
      'AiWorktreeTimeoutJob',
      'AiMergeExecutionJob',
      'AiConflictDetectionJob',
      'AiRunnerDispatchPollJob',
      # Supply chain jobs
      'SupplyChain::QuestionnaireNotificationJob'
    ]

    allowed_jobs.include?(job_class)
  end

  def parse_delay(delay)
    return 0 if delay.nil? || delay.to_s.strip.empty?
    return delay if delay.is_a?(Numeric)

    delay_str = delay.to_s.strip
    return delay_str.to_i if delay_str.match?(/\A\d+\z/)

    case delay_str
    when /\A(\d+)s\z/i then $1.to_i
    when /\A(\d+)m\z/i then $1.to_i * 60
    when /\A(\d+)h\z/i then $1.to_i * 3600
    when /\A(\d+)d\z/i then $1.to_i * 86400
    else
      raise ArgumentError, "Invalid delay format: #{delay_str}. Use integer seconds or format like '5m', '1h', '2d'"
    end
  end

  def success_response(data)
    [200, 
     {'content-type' => 'application/json'}, 
     [data.to_json]]
  end

  def error_response(status, message)
    [status, 
     {'content-type' => 'application/json'}, 
     [{error: message, timestamp: Time.current.iso8601}.to_json]]
  end

  def not_found_response
    error_response(404, 'Not found')
  end
  
  def jwt_secret_key
    ENV['JWT_SECRET_KEY']
  end
end