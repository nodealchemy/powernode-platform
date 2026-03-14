# frozen_string_literal: true

module Ai
  # AgentTeamExecutionJob - Background job for executing AI agent teams
  #
  # This job orchestrates the execution of an AI agent team, coordinating
  # multiple agents to work together on a task based on the team's
  # coordination strategy.
  #
  # Usage:
  #   Ai::AgentTeamExecutionJob.perform_later(
  #     team_id: team.id,
  #     user_id: user.id,
  #     input: { task: "...", context: "..." },
  #     context: { priority: "high" }
  #   )
  #
  class AgentTeamExecutionJob < ApplicationJob
    queue_as :ai_execution

    # Retry configuration
    retry_on StandardError, wait: 5.seconds, attempts: 3

    # Maximum execution time for a team (30 minutes)
    MAX_EXECUTION_TIME = 30.minutes

    # Support both perform_async (Sidekiq style) and perform_later (ActiveJob style)
    def self.perform_async(args = {})
      perform_later(args)
    end

    def perform(args = {})
      args = args.with_indifferent_access
      team_id = args[:team_id]
      user_id = args[:user_id]
      input = args[:input] || {}
      context = args[:context] || {}
      @team = ::Ai::AgentTeam.find(team_id)
      @user = User.find(user_id)
      @input = input.with_indifferent_access
      @context = context.with_indifferent_access
      @started_at = Time.current

      # Create TeamExecution record
      @execution = ::Ai::TeamExecution.create!(
        account: @team.account,
        agent_team: @team,
        triggered_by: @user,
        status: "pending",
        input_context: @input,
        objective: @input[:task] || @input[:prompt]
      )

      Rails.logger.info(
        "[AgentTeamExecutionJob] Starting execution #{@execution.execution_id} for team #{@team.id} (#{@team.name})"
      )

      @execution.start!

      broadcast_event("execution_started",
        execution_id: @execution.execution_id,
        job_id: job_id_string)

      audit_log("ai_agent_team.execution_started",
        team_name: @team.name,
        execution_id: @execution.execution_id)

      execute_team
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error("[AgentTeamExecutionJob] Record not found: #{e.message}")
      raise
    rescue StandardError => e
      handle_execution_error(e)
      raise
    end

    private

    def execute_team
      members = @team.members.includes(:agent).order(:priority_order)

      if members.empty?
        Rails.logger.warn("[AgentTeamExecutionJob] Team #{@team.id} has no members")
        complete_execution(success: false, error: "Team has no members")
        return
      end

      # Track member count for progress
      @members_total = members.count
      @members_completed = 0
      @members_failed = 0

      @execution.update!(tasks_total: @members_total)

      # Execute based on coordination strategy
      result = case @team.coordination_strategy
      when "sequential"
               execute_sequential(members)
      when "parallel"
               execute_parallel(members)
      when "hierarchical"
               execute_hierarchical(members)
      when "consensus"
               execute_consensus(members)
      else
               execute_sequential(members) # Default to sequential
      end

      complete_execution(success: result[:success], output: result[:output], error: result[:error])
    end

    def execute_sequential(members)
      Rails.logger.info("[AgentTeamExecutionJob] Executing #{members.count} agents sequentially")

      accumulated_context = @input.dup
      final_output = nil

      catch(:execution_halted) do
        members.each_with_index do |member, index|
          if execution_timeout?
            @execution.timeout!
            broadcast_event("execution_timeout", execution_id: @execution.execution_id)
            break
          end

          check_control_signal!

          agent = member.agent
          broadcast_member_progress(agent.name, member.role, index)

          member_start = Time.current
          result = execute_agent_with_retry(agent, accumulated_context, member.role)
          member_duration = ((Time.current - member_start) * 1000).to_i

          if result[:success]
            accumulated_context = accumulated_context.merge(
              previous_agent_output: result[:output],
              previous_agent: agent.name
            )
            final_output = result[:output]
            record_member_completed(agent.name, true, member_duration)
          else
            record_member_completed(agent.name, false, member_duration)
            if team_config["skip_on_member_failure"]
              Rails.logger.warn("[AgentTeamExecutionJob] Agent #{agent.name} failed but skip_on_member_failure is enabled, continuing")
              accumulated_context = accumulated_context.merge(
                previous_agent_output: { error: result[:error], skipped: true },
                previous_agent: agent.name
              )
            else
              return { success: false, error: "Agent #{agent.name} failed: #{result[:error]}" }
            end
          end
        end
      end # catch(:execution_halted)

      { success: true, output: final_output }
    end

    def execute_parallel(members)
      Rails.logger.info("[AgentTeamExecutionJob] Executing #{members.count} agents in parallel")

      results = []

      catch(:execution_halted) do
        members.each_with_index do |member, index|
          check_control_signal!

          agent = member.agent
          broadcast_member_progress(agent.name, member.role, index)

          member_start = Time.current
          result = execute_agent_with_retry(agent, @input, member.role)
          member_duration = ((Time.current - member_start) * 1000).to_i

          results << { agent: agent.name, result: result }
          record_member_completed(agent.name, result[:success], member_duration)
        end
      end

      successful = results.select { |r| r[:result][:success] }
      failed = results.reject { |r| r[:result][:success] }

      if failed.any?
        Rails.logger.warn("[AgentTeamExecutionJob] #{failed.count} agents failed in parallel execution")
      end

      {
        success: successful.any?,
        output: {
          successful_agents: successful.map { |r| r[:agent] },
          failed_agents: failed.map { |r| { agent: r[:agent], error: r[:result][:error] } },
          results: successful.map { |r| { agent: r[:agent], output: r[:result][:output] } }
        },
        error: failed.any? ? "#{failed.count} agent(s) failed" : nil
      }
    end

    def execute_hierarchical(members)
      Rails.logger.info("[AgentTeamExecutionJob] Executing hierarchically with lead agent")

      lead_member = members.find(&:is_lead) || members.first
      subordinate_members = members.reject { |m| m.id == lead_member.id }

      broadcast_member_progress(lead_member.agent.name, lead_member.role, 0)

      member_start = Time.current
      lead_result = execute_agent_with_retry(lead_member.agent, @input, lead_member.role)
      member_duration = ((Time.current - member_start) * 1000).to_i
      record_member_completed(lead_member.agent.name, lead_result[:success], member_duration)

      unless lead_result[:success]
        return { success: false, error: "Lead agent failed: #{lead_result[:error]}" }
      end

      subordinate_results = []
      catch(:execution_halted) do
        subordinate_members.each_with_index do |member, index|
          if execution_timeout?
            @execution.timeout!
            broadcast_event("execution_timeout", execution_id: @execution.execution_id)
            break
          end

          check_control_signal!

          context = @input.merge(
            lead_directive: lead_result[:output],
            assigned_role: member.role
          )

          broadcast_member_progress(member.agent.name, member.role, index + 1)

          member_start = Time.current
          result = execute_agent_with_retry(member.agent, context, member.role)
          member_duration_ms = ((Time.current - member_start) * 1000).to_i
          record_member_completed(member.agent.name, result[:success], member_duration_ms)

          subordinate_results << { agent: member.agent.name, result: result }
        end
      end

      {
        success: true,
        output: {
          lead_output: lead_result[:output],
          subordinate_outputs: subordinate_results.map { |r| { agent: r[:agent], output: r[:result][:output] } }
        }
      }
    end

    def execute_consensus(members)
      Rails.logger.info("[AgentTeamExecutionJob] Executing with consensus strategy")

      results = []
      catch(:execution_halted) do
        members.each_with_index do |member, index|
          if execution_timeout?
            @execution.timeout!
            broadcast_event("execution_timeout", execution_id: @execution.execution_id)
            break
          end

          check_control_signal!

          broadcast_member_progress(member.agent.name, member.role, index)

          member_start = Time.current
          result = execute_agent_with_retry(member.agent, @input, member.role)
          member_duration = ((Time.current - member_start) * 1000).to_i
          record_member_completed(member.agent.name, result[:success], member_duration)

          results << { agent: member.agent.name, role: member.role, result: result }
        end
      end # catch(:execution_halted)

      successful = results.count { |r| r[:result][:success] }
      consensus_reached = successful > (members.count / 2.0)

      {
        success: consensus_reached,
        output: {
          consensus_reached: consensus_reached,
          votes: {
            successful: successful,
            total: members.count
          },
          individual_results: results.map { |r|
            { agent: r[:agent], role: r[:role], success: r[:result][:success], output: r[:result][:output] }
          }
        },
        error: consensus_reached ? nil : "Consensus not reached"
      }
    end

    def execute_agent(agent, input, role)
      safe_input = input.presence || { task: "team_execution" }

      execution = agent.executions.create!(
        account: @team.account,
        user: @user,
        ai_provider_id: agent.ai_provider_id,
        status: "running",
        started_at: Time.current,
        input_parameters: safe_input,
        execution_context: {
          team_id: @team.id,
          team_name: @team.name,
          team_execution_id: @execution.id,
          role: role
        }
      )

      begin
        credential = agent.provider.provider_credentials
                          .where(is_active: true)
                          .where(account_id: @team.account_id)
                          .first

        unless credential
          raise "No active credential found for provider #{agent.provider.name}"
        end

        system_content = agent.system_prompt.presence ||
                         agent.mcp_tool_manifest&.dig("system_prompt").presence ||
                         "You are #{agent.name}, acting as #{role}."

        user_content = input[:task].presence || input[:prompt].presence || input.to_json

        messages = [
          { role: "system", content: system_content },
          { role: "user", content: user_content }
        ]

        model = agent.try(:model) || agent.mcp_tool_manifest&.dig("model")
        max_tokens = agent.try(:max_tokens) || agent.mcp_tool_manifest&.dig("max_tokens") || 4096
        temperature = agent.try(:temperature) || agent.mcp_tool_manifest&.dig("temperature") || 0.7

        timeout_seconds = @team.try(:task_timeout_seconds) || team_config["task_timeout_seconds"] || 300

        result = Timeout.timeout(timeout_seconds) do
          client = Ai::ProviderClientService.new(credential)
          client.send_message(messages, model: model, max_tokens: max_tokens, temperature: temperature)
        end

        if result[:success]
          usage = result.dig(:metadata, :usage) || { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
          tokens = usage[:total_tokens] || 0
          response_text = extract_response_text(result[:response])

          model_used = result.dig(:metadata, :model_used)
          cost = estimate_execution_cost(agent, model_used, usage)

          output = {
            agent_id: agent.id,
            agent_name: agent.name,
            role: role,
            processed_at: Time.current.iso8601,
            response: response_text,
            tokens_used: tokens,
            prompt_tokens: usage[:prompt_tokens],
            completion_tokens: usage[:completion_tokens],
            model_used: model_used,
            cost_usd: cost
          }

          now = Time.current
          duration = ((now - execution.started_at) * 1000).to_i

          execution.update!(
            status: "completed",
            output_data: output,
            completed_at: now,
            duration_ms: duration,
            tokens_used: tokens,
            cost_usd: cost
          )

          @execution.add_tokens!(tokens) if tokens.positive?
          @execution.add_cost!(cost) if cost.positive?

          { success: true, output: output }
        else
          error_msg = result[:error] || "Provider returned unsuccessful response"
          raise error_msg
        end
      rescue Timeout::Error
        now = Time.current
        duration = execution.started_at ? ((now - execution.started_at) * 1000).to_i : 0
        execution.update!(
          status: "failed",
          error_message: "Execution timed out after #{timeout_seconds}s",
          completed_at: now,
          duration_ms: duration
        )
        { success: false, error: "Agent #{agent.name} timed out after #{timeout_seconds}s" }
      rescue StandardError => e
        now = Time.current
        duration = execution.started_at ? ((now - execution.started_at) * 1000).to_i : 0
        execution.update!(
          status: "failed",
          error_message: e.message,
          completed_at: now,
          duration_ms: duration
        )
        { success: false, error: e.message }
      end
    end

    def execute_agent_with_retry(agent, input, role)
      max_retries = (team_config["max_member_retries"] || 2).to_i
      attempt = 0

      loop do
        result = execute_agent(agent, input, role)
        return result if result[:success]

        attempt += 1
        break result if attempt >= max_retries
        break result unless retryable_error?(result[:error])

        wait_time = [2**attempt * 2 * (0.5 + rand * 0.5), 30].min
        Rails.logger.info(
          "[AgentTeamExecutionJob] Retrying agent #{agent.name} (attempt #{attempt + 1}/#{max_retries}) after #{wait_time.round(1)}s"
        )
        sleep(wait_time)
      end
    end

    def complete_execution(success:, output: nil, error: nil)
      duration_ms = ((Time.current - @started_at) * 1000).to_i

      if success
        @execution.complete!(output || {})
        broadcast_event("execution_completed",
          execution_id: @execution.execution_id,
          result: output,
          duration_ms: duration_ms,
          tasks_total: @members_total,
          tasks_completed: @members_completed,
          tasks_failed: @members_failed)

        audit_log("ai_agent_team.execution_completed",
          execution_id: @execution.execution_id,
          duration_ms: duration_ms,
          tasks_completed: @members_completed,
          tasks_failed: @members_failed)
      else
        @execution.fail!(error || "Unknown error")
        broadcast_event("execution_failed",
          execution_id: @execution.execution_id,
          error: error,
          duration_ms: duration_ms,
          tasks_total: @members_total || 0,
          tasks_completed: @members_completed || 0,
          tasks_failed: @members_failed || 0)

        audit_log("ai_agent_team.execution_failed",
          execution_id: @execution.execution_id,
          error: error,
          duration_ms: duration_ms,
          severity: "high")
      end

      cleanup_execution_resources
      extract_compound_learnings

      Rails.logger.info(
        "[AgentTeamExecutionJob] Completed: team=#{@team.id} success=#{success} duration=#{duration_ms}ms"
      )
    end

    def handle_execution_error(error)
      Rails.logger.error(
        "[AgentTeamExecutionJob] Execution failed: #{error.message}\n#{error.backtrace&.first(10)&.join("\n")}"
      )

      if @execution
        @execution.fail!(error.message)
        broadcast_event("execution_failed",
          execution_id: @execution.execution_id,
          error: error.message)

        audit_log("ai_agent_team.execution_failed",
          execution_id: @execution.execution_id,
          error: error.message,
          severity: "high")
      end

      cleanup_execution_resources
    end

    def broadcast_member_progress(agent_name, role, member_index)
      progress = @members_total.to_i > 0 ? ((member_index.to_f / @members_total) * 100).round : 0

      broadcast_event("execution_progress",
        execution_id: @execution.execution_id,
        current_member: agent_name,
        current_role: role,
        progress: progress,
        member_index: member_index,
        tasks_total: @members_total,
        tasks_completed: @members_completed,
        tasks_failed: @members_failed)
    end

    def record_member_completed(agent_name, success, duration_ms)
      if success
        @members_completed += 1
      else
        @members_failed += 1
      end

      @execution.update!(
        tasks_completed: @members_completed,
        tasks_failed: @members_failed
      )

      broadcast_event("member_completed",
        execution_id: @execution.execution_id,
        member_name: agent_name,
        member_success: success,
        member_duration_ms: duration_ms,
        tasks_total: @members_total,
        tasks_completed: @members_completed,
        tasks_failed: @members_failed)
    end

    def broadcast_event(event_type, payload = {})
      TeamExecutionChannel.broadcast_to_team(@team.id, event_type, payload)
    rescue StandardError => e
      Rails.logger.warn("[AgentTeamExecutionJob] Broadcast failed: #{e.message}")
    end

    def audit_log(action, metadata = {})
      Audit::LoggingService.instance.log(
        action: action,
        resource: @team,
        user: @user,
        account: @team.account,
        metadata: metadata.merge(team_id: @team.id, team_name: @team.name)
      )
    rescue StandardError => e
      Rails.logger.warn("[AgentTeamExecutionJob] Audit log failed: #{e.message}")
    end

    def check_control_signal!
      @execution.reload
      signal = @execution.control_signal
      return if signal.blank?

      case signal
      when "cancel"
        @execution.cancel!("user_cancelled")
        broadcast_event("execution_cancelled", execution_id: @execution.execution_id)
        Rails.logger.info("[AgentTeamExecutionJob] Execution #{@execution.execution_id} cancelled by user")
        throw :execution_halted
      when "pause"
        @execution.update!(paused_at: Time.current)
        broadcast_event("execution_paused", execution_id: @execution.execution_id)
        Rails.logger.info("[AgentTeamExecutionJob] Execution #{@execution.execution_id} paused")

        # Poll until resumed or timeout (max 30 minutes paused)
        pause_timeout = 30.minutes
        pause_start = Time.current
        loop do
          sleep(2)
          @execution.reload
          break if @execution.control_signal != "pause"

          if Time.current - pause_start > pause_timeout
            @execution.timeout!
            broadcast_event("execution_timeout", execution_id: @execution.execution_id)
            Rails.logger.warn("[AgentTeamExecutionJob] Execution #{@execution.execution_id} timed out while paused")
            throw :execution_halted
          end
        end

        @execution.update!(resume_count: (@execution.resume_count || 0) + 1, paused_at: nil)
        broadcast_event("execution_resumed", execution_id: @execution.execution_id)
        Rails.logger.info("[AgentTeamExecutionJob] Execution #{@execution.execution_id} resumed")
      when "redirect"
        new_instructions = @execution.redirect_instructions || {}
        @input = @input.merge(new_instructions.with_indifferent_access)
        @execution.update!(control_signal: nil, redirect_instructions: {})
        broadcast_event("execution_redirected",
          execution_id: @execution.execution_id,
          new_instructions: new_instructions)
        Rails.logger.info("[AgentTeamExecutionJob] Execution #{@execution.execution_id} redirected")
      end
    end

    def team_config
      @team_config ||= (@team.team_config || {}).with_indifferent_access
    end

    def retryable_error?(error_msg)
      return false unless error_msg.is_a?(String)

      retryable_patterns = [/timeout/i, /rate.?limit/i, /429/, /503/, /temporarily unavailable/i, /circuit.?breaker/i]
      retryable_patterns.any? { |pattern| error_msg.match?(pattern) }
    end

    def estimate_execution_cost(agent, model, usage)
      return 0 unless usage[:total_tokens]&.positive?

      prompt_tokens = usage[:prompt_tokens] || 0
      completion_tokens = usage[:completion_tokens] || 0

      # Look up pricing from provider's supported_models (populated during sync)
      cost_info = agent.provider&.get_model_info(model)&.dig("cost_per_1k_tokens")
      input_rate = cost_info&.dig("input")&.to_f || 0.003
      output_rate = cost_info&.dig("output")&.to_f || 0.015

      (BigDecimal(prompt_tokens.to_s) / 1000 * BigDecimal(input_rate.to_s)) +
        (BigDecimal(completion_tokens.to_s) / 1000 * BigDecimal(output_rate.to_s))
    end

    # Extract the assistant's text content from provider response
    # Handles OpenAI (choices[].message.content), Anthropic (content[].text), and raw formats
    def extract_response_text(response)
      return response.to_s unless response.is_a?(Hash)

      # OpenAI / Grok format: { choices: [{ message: { content: "..." } }] }
      text = response.dig(:choices, 0, :message, :content)
      return text if text.is_a?(String)

      # Anthropic format: { content: [{ type: "text", text: "..." }] }
      content = response[:content]
      if content.is_a?(Array)
        texts = content.select { |c| c[:type] == "text" }.map { |c| c[:text] }
        return texts.join("\n") if texts.any?
      end

      # Direct content string
      return content if content.is_a?(String)

      # Fallback
      response[:text] || response.to_s
    end

    def extract_compound_learnings
      return unless @execution

      service = Ai::Learning::CompoundLearningService.new(account: @team.account)
      count = service.post_execution_extract(@execution)
      Rails.logger.info("[AgentTeamExecutionJob] Extracted #{count} compound learnings") if count.positive?
    rescue StandardError => e
      Rails.logger.warn("[AgentTeamExecutionJob] Compound learning extraction failed: #{e.message}")
    end

    def cleanup_execution_resources
      return unless @execution

      pools = Ai::MemoryPool.where(task_execution_id: @execution.id, persist_across_executions: false)
      count = pools.count
      pools.destroy_all if count.positive?
      Rails.logger.info("[AgentTeamExecutionJob] Cleaned up #{count} non-persistent memory pools") if count.positive?
    rescue StandardError => e
      Rails.logger.warn("[AgentTeamExecutionJob] Memory pool cleanup failed: #{e.message}")
    end

    def job_id_string
      try(:provider_job_id) || try(:job_id) || object_id.to_s
    end

    def execution_timeout?
      Time.current - @started_at > MAX_EXECUTION_TIME
    end
  end
end
