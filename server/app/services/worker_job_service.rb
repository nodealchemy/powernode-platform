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

    # Enqueue an alert / notification email send (security alerts, review
    # notifications, ...). The server owns the EmailDelivery ledger; the worker
    # renders + delivers via SMTP and POSTs the outcome back to the internal
    # /emails/:id/delivered callback. Pattern B — model/DB access stays on the
    # server. `payload` carries email_delivery_id (the pending ledger row),
    # recipient, subject, heading, body, and optional details.
    def enqueue_alert_email(payload)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Notifications::AlertEmailJob",
        "args" => [ payload.deep_stringify_keys ],
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

    # Enqueue workspace response job for a non-primary team member agent
    def enqueue_workspace_response(conversation_id, message_id, agent_id, account_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiWorkspaceResponseJob",
        "args" => [ conversation_id, message_id, agent_id, account_id ],
        "queue" => "ai_conversations"
      })
    end

    # Enqueue A2A task execution job
    def enqueue_ai_a2a_task_execution(task_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiA2aTaskExecutionJob",
        "args" => [ task_id ],
        "queue" => "ai_agents",
        "options" => { "retry" => 3 }
      })
    end

    # Enqueue A2A external task job
    def enqueue_ai_a2a_external_task(task_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiA2aExternalTaskJob",
        "args" => [ task_id ],
        "queue" => "ai_agents",
        "options" => { "retry" => 3 }
      })
    end

    # Enqueue external A2A agent-card fetch. The worker performs the slow
    # external HTTP GET of agent_card_url, then posts the raw outcome back to
    # the internal card_result endpoint (server does the A2A parse/validate/
    # persist). Pattern B: keep all model/DB access on the server.
    def enqueue_external_agent_card_fetch(external_agent)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "ExternalAgentCardFetchJob",
        "args" => [ external_agent.id, external_agent.agent_card_url ],
        "queue" => "default"
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

    # Enqueue AI agent-execution webhook delivery. The API server runs no Sidekiq,
    # so the outbound webhook fan-out is owned by the standalone worker's
    # AiWebhookDeliveryJob (queue: ai_agents, retry: 2), which fetches the
    # execution + webhook URLs back from the server and POSTs the completion
    # payload. Called from Ai::AgentExecution#trigger_webhook / #retry_webhook!.
    def enqueue_ai_webhook_delivery(agent_execution_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiWebhookDeliveryJob",
        "args" => [ agent_execution_id ],
        "queue" => "ai_agents",
        "options" => { "retry" => 2 }
      })
    end

    # Enqueue AI team execution job.
    # Resolve the owning account_id from the team record and thread it into the
    # payload so the worker can honor the per-account kill switch. Falls back
    # to nil when unresolvable (the worker bail no-ops on nil — fail-open).
    def enqueue_ai_team_execution(team_id:, user_id:, input: {}, context: {})
      account_id = Ai::AgentTeam.find_by(id: team_id)&.account_id
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiTeamExecutionJob",
        "args" => [ {
          "team_id" => team_id,
          "user_id" => user_id,
          "input" => input,
          "context" => context,
          "account_id" => account_id
        } ],
        "queue" => "ai_agents",
        "options" => { "retry" => 3 }
      })
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

    # Enqueue delivery of the operator-configured MCP monitoring webhook.
    # The API server runs no Sidekiq, so the ad-hoc (url, payload) POST is owned
    # by the standalone worker's Webhooks::MonitoringWebhookDeliveryJob. `payload`
    # is the pre-serialized JSON body. Called from Mcp::BroadcastService.
    def enqueue_mcp_monitoring_webhook(webhook_url, payload)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Webhooks::MonitoringWebhookDeliveryJob",
        "args" => [ webhook_url, payload ],
        "queue" => "webhooks"
      })
    end

    # ==========================================
    # AI Skills Jobs
    # ==========================================

    # Enqueue system skills seeding job
    def enqueue_ai_skill_seed
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiSkillSyncJob",
        "args" => [ { "action" => "seed" } ],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue skill connector refresh job
    def enqueue_ai_skill_refresh_connectors(skill_id, account_id: nil)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiSkillSyncJob",
        "args" => [ { "action" => "refresh_connectors", "skill_id" => skill_id, "account_id" => account_id } ],
        "queue" => "ai_orchestration"
      })
    end

    # ==========================================
    # Knowledge Event-Driven Jobs
    # ==========================================

    # Enqueue learning promotion when access_count crosses threshold
    def enqueue_ai_promote_learning(learning_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiPromoteLearningJob",
        "args" => [ learning_id ],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue STM entry consolidation to LTM
    def enqueue_ai_consolidate_memory_entry(entry_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiConsolidateMemoryEntryJob",
        "args" => [ entry_id ],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue dedup check after learning creation
    def enqueue_ai_dedup_learning(learning_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiDedupLearningJob",
        "args" => [ learning_id ],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue experience replay capture after a successful execution
    def enqueue_ai_experience_replay_capture(execution_id, trajectory_id = nil)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiExperienceReplayCaptureJob",
        "args" => [ execution_id, trajectory_id ].compact,
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue LLM-based reflexion analysis for a failed execution
    def enqueue_ai_reflexion(execution_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiReflexionJob",
        "args" => [ execution_id ],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue KG node recalculation after learning verification/disproval
    def enqueue_ai_update_graph_node(node_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiUpdateGraphNodeJob",
        "args" => [ node_id ],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue AI conversation response job
    def enqueue_ai_conversation_response(conversation_id, message_id, user_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiConversationResponseJob",
        "args" => [ conversation_id, message_id, user_id ],
        "queue" => "ai_conversations"
      })
    end

    # Enqueue AI self-healing monitor job
    def enqueue_ai_self_healing_monitor
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiSelfHealingMonitorJob",
        "args" => [],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue AI trajectory analysis job
    def enqueue_ai_trajectory_analysis
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiTrajectoryAnalysisJob",
        "args" => [],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue AI ralph loop run-all job
    def enqueue_ai_ralph_loop_run_all(ralph_loop_id, stop_on_error: false)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiRalphLoopRunAllJob",
        "args" => [ ralph_loop_id, { "stop_on_error" => stop_on_error } ],
        "queue" => "ai_execution"
      })
    end

    # Enqueue AI monitoring health check job
    def enqueue_ai_monitoring_health_check(account_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiMonitoringHealthCheckJob",
        "args" => [ account_id ],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue skill conflict check after skill creation/update
    def enqueue_ai_skill_conflict_check(skill_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiSkillConflictCheckJob",
        "args" => [ skill_id ],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue goal plan step execution for autonomous goal pursuit.
    # Resolve the owning account_id (via the step's goal plan) and thread it into
    # the payload so the worker can honor the per-account kill switch. Falls back
    # to nil when unresolvable (the worker bail no-ops on nil — fail-open).
    def enqueue_ai_goal_plan_step_execution(step_id)
      account_id = Ai::GoalPlanStep.find_by(id: step_id)&.plan&.account_id
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiGoalPlanExecutionJob",
        "args" => [ step_id, account_id ],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue skill mutation job
    def enqueue_ai_skill_mutation(skill_id, strategy)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiSkillMutationJob",
        "args" => [ skill_id, strategy ],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue self-challenge pipeline (generate → execute → validate → complete).
    # Resolve the owning account_id from the challenge record and thread it into
    # the payload so the worker can honor the per-account kill switch. Falls back
    # to nil when unresolvable (the worker bail no-ops on nil — fail-open).
    def enqueue_ai_self_challenge(challenge_id)
      account_id = Ai::SelfChallenge.find_by(id: challenge_id)&.account_id
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiSelfChallengeJob",
        "args" => [ challenge_id, account_id ],
        "queue" => "ai_orchestration"
      })
    end

    # Enqueue governance scan for an agent or account
    def enqueue_ai_governance_scan(account_id, agent_id = nil)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiGovernanceScanJob",
        "args" => [ account_id, agent_id ].compact,
        "queue" => "ai_orchestration"
      })
    end

    # ==========================================
    # Codebase Intelligence Jobs (long-running: AST parse + embeddings)
    # ==========================================

    # Enqueue codebase indexing. The worker drives the server's internal
    # /codebase/index endpoint (long-tolerant), keeping this off the MCP/user
    # request path so it never times out.
    def enqueue_ai_codebase_index(account_id:, base_path:, repository_id: nil, path: nil, incremental: true)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiCodebaseIndexJob",
        "args" => [ {
          "account_id" => account_id,
          "base_path" => base_path,
          "repository_id" => repository_id,
          "path" => path,
          "incremental" => incremental
        }.compact ],
        "queue" => "code_intel"
      })
    end

    # Enqueue a long-running codebase analysis (prune_stale).
    # The worker drives the server's internal /codebase/analyze endpoint, which
    # writes the result to the 'default' shared-memory pool under result_key.
    def enqueue_ai_code_analysis(operation:, account_id:, base_path:, result_key:, repository_id: nil, options: {})
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiCodeAnalysisJob",
        "args" => [ {
          "operation" => operation,
          "account_id" => account_id,
          "base_path" => base_path,
          "repository_id" => repository_id,
          "result_key" => result_key,
          "options" => options
        }.compact ],
        "queue" => "code_intel"
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

    # Enqueue an isolated test-execution run for a Ralph loop iteration.
    # The worker checks out the branch, runs the detected test command, and
    # POSTs the raw result back to the iteration's test_results callback, which
    # parses + gates task.pass!. Part of the in-platform sandbox engine
    # (Phase A); the loop only dispatches this when the loop's configuration
    # enables real_test_execution.
    def enqueue_ai_test_execution(ralph_loop_id:, ralph_iteration_id:, repository:, branch:, command:, framework: nil, timeout_seconds: 600)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiTestExecutionJob",
        "args" => [ {
          "ralph_loop_id" => ralph_loop_id,
          "ralph_iteration_id" => ralph_iteration_id,
          "repository" => repository,
          "branch" => branch,
          "command" => command,
          "framework" => framework,
          "timeout_seconds" => timeout_seconds
        } ],
        "queue" => "ai_execution"
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

    # ==========================================
    # AI Git/Worktree Jobs
    # ==========================================

    # Enqueue worktree provisioning job
    def enqueue_ai_worktree_provisioning(session_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiWorktreeProvisioningJob",
        "args" => [ session_id ],
        "queue" => "ai_execution"
      })
    end

    # Enqueue worktree cleanup job
    def enqueue_ai_worktree_cleanup(session_id, delay: nil)
      payload = {
        "job_class" => "AiWorktreeCleanupJob",
        "args" => [ session_id ],
        "queue" => "ai_execution"
      }
      payload["delay"] = delay if delay
      new.make_worker_request("POST", "/api/v1/jobs", payload)
    end

    # Enqueue worktree push and PR creation job
    def enqueue_ai_worktree_push_and_pr(session_id, options = {})
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiWorktreePushAndPrJob",
        "args" => [ session_id, options ],
        "queue" => "ai_execution"
      })
    end

    # Enqueue worktree timeout check job
    def enqueue_ai_worktree_timeout
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiWorktreeTimeoutJob",
        "args" => [],
        "queue" => "ai_execution"
      })
    end

    # Enqueue merge execution job
    def enqueue_ai_merge_execution(session_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiMergeExecutionJob",
        "args" => [ session_id ],
        "queue" => "ai_execution"
      })
    end

    # Enqueue conflict detection job
    def enqueue_ai_conflict_detection(session_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiConflictDetectionJob",
        "args" => [ session_id ],
        "queue" => "ai_execution"
      })
    end

    # Enqueue runner dispatch poll job
    def enqueue_ai_runner_dispatch_poll(session_id, poll_count: 0)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "AiRunnerDispatchPollJob",
        "args" => [ session_id, { "poll_count" => poll_count } ],
        "queue" => "default"
      })
    end

    # ==========================================
    # Chat Attachment Processing (malware scan + transcription)
    # ==========================================

    # Enqueue a malware scan for a chat attachment. The worker downloads the
    # file, runs ClamAV, and posts the verdict back to the internal scan_result
    # endpoint (server marks scanned / quarantines). Pattern B — model/DB access
    # stays on the server. Called from Chat::MessageAttachment#enqueue_malware_scan.
    def enqueue_chat_attachment_scan(attachment_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Chat::AttachmentScanJob",
        "args" => [ attachment_id ],
        "queue" => "file_processing"
      })
    end

    # Enqueue transcription for an audio chat attachment. The worker triggers the
    # server transcription seam off the request path (the server owns the AI
    # providers). Called from Chat::MessageAttachment#enqueue_transcription.
    def enqueue_chat_transcription(attachment_id)
      new.make_worker_request("POST", "/api/v1/jobs", {
        "job_class" => "Chat::AttachmentTranscriptionJob",
        "args" => [ attachment_id ],
        "queue" => "file_processing"
      })
    end

    # Fetch the worker's live Sidekiq job-processing stats (queues, processed,
    # failed, scheduled, retries, dead, workers). The Rails API runs no
    # in-process Sidekiq, so the real fleet job metrics live on the standalone
    # worker — this GETs the worker's existing /api/sidekiq/stats endpoint.
    # Raises WorkerServiceError when the worker is unreachable; callers surface
    # an honest available:false rather than fabricating healthy numbers.
    def fetch_sidekiq_stats
      new.make_worker_request("GET", "/api/sidekiq/stats")
    end
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

      # Authenticate as system worker using JWT (token derived from database)
      request["Authorization"] = "Bearer #{system_worker_jwt}"

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

  # Mint a short-lived JWT for the system worker, derived from the database record.
  # Cached per-thread for 4 minutes (JWT expires in 5 minutes) to avoid DB lookups on every request.
  # Class method so controllers can also use it for outgoing worker calls.
  def self.system_worker_jwt
    cached = Thread.current[:_system_worker_jwt]
    if cached && cached[:expires_at] > Time.current
      return cached[:token]
    end

    worker = Worker.system_worker
    raise WorkerServiceError, "No active system worker found in database" unless worker&.active?

    token = Security::JwtService.encode(
      { type: "worker", sub: worker.id },
      5.minutes.from_now
    )

    Thread.current[:_system_worker_jwt] = { token: token, expires_at: 4.minutes.from_now }
    token
  end

  private

  def system_worker_jwt
    self.class.system_worker_jwt
  end

  # Custom exception for worker service errors
  class WorkerServiceError < StandardError; end
end
