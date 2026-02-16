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
    include Ai::TeamExecutionSupport::LlmIntegration
    include Ai::TeamExecutionSupport::TaskTracking
    include Ai::TeamExecutionSupport::ToolExecution

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
      @conversation_service = ::Ai::TeamConversationService.new(account: @team.account)

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

      # Auto-link conversation for activity posting
      if team_config["post_execution_activity"].present? || @team.coordinator_enabled?
        begin
          conversation = @conversation_service.find_or_create_conversation(@team, user: @user)
          @execution.update!(ai_conversation_id: conversation.id)
        rescue => e
          Rails.logger.warn("[AgentTeamExecutionJob] Failed to link conversation: #{e.message}")
        end
      end

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

      # Post execution started to conversation
      @conversation_service&.post_execution_started(@execution) rescue nil

      # Execute based on coordination strategy
      result = case @team.coordination_strategy
      when "sequential"
               execute_sequential(members)
      when "parallel"
               execute_parallel(members)
      when "hierarchical", "manager_led"
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

      # After collecting all results, try to synthesize if lead exists
      lead_member = members.find { |m| m.role.in?(%w[lead manager coordinator synthesizer]) }
      successful_results = successful.map { |r| { success: true, agent_name: r[:agent], role: r[:result][:output]&.dig(:role) || "worker", output: r[:result][:output] } }

      if lead_member && successful_results.size > 1
        synthesized = synthesize_results(lead_member.agent, successful_results, @input)
        if synthesized.present?
          log_execution("[Parallel] Lead #{lead_member.agent.name} synthesized #{successful_results.size} parallel outputs")
          return {
            success: true,
            output: {
              strategy: "parallel",
              synthesized_output: synthesized,
              individual_results: results.map { |r| { agent: r[:agent], success: r[:result][:success] } },
              total_agents: members.size,
              successful: successful.size
            }
          }
        end
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
      lead_member = members.find { |m| m.role.in?(%w[lead manager coordinator]) }
      workers = members.reject { |m| m == lead_member }

      unless lead_member
        log_execution("[Hierarchical] No lead agent found, falling back to sequential")
        return execute_sequential(members)
      end

      lead_agent = lead_member.agent
      log_execution("[Hierarchical] Lead: #{lead_agent.name}, Workers: #{workers.map { |m| m.agent.name }.join(', ')}")

      # Phase 1: Planning — reuse approved plan or generate new work plan
      work_plan = if @input[:plan_approval] && @input[:approved_plan].present?
                    log_execution("[Hierarchical] Using approved plan from previous execution")
                    reuse_approved_plan(@input[:approved_plan], workers)
                  else
                    generate_work_plan(lead_agent, workers, @input)
                  end

      if work_plan && work_plan["assignments"].present?
        log_execution("[Hierarchical] Work plan generated: #{work_plan['plan_summary']}")
        # Strip AR objects before serializing work plan
        @serialized_plan = {
          "plan_summary" => work_plan["plan_summary"],
          "assignments" => work_plan["assignments"].map { |a| a.except("member") },
          "synthesis_notes" => work_plan["synthesis_notes"]
        }
        plan_content = @serialized_plan
        record_team_message(
          message_type: "work_plan",
          content: plan_content,
          from_agent: lead_agent
        )

        # Phase 2: Delegation — execute workers with plan-specific instructions
        worker_results = []
        work_plan["assignments"].each do |assignment|
          check_control_signal!
          member = assignment["member"]
          next unless member

          agent = member.agent
          task = create_team_task(agent, assignment["instructions"], @input, priority: assignment["priority"] || "medium")
          start_team_task!(task) if task

          record_task_assignment(lead_agent, agent, assignment["instructions"])
          @conversation_service&.post_task_assignment(@execution, agent.name, assignment["instructions"].truncate(200)) rescue nil

          agent_input = build_planned_input(assignment, @input)
          result = execute_agent_with_retry(agent, agent_input, member.role)

          broadcast_progress("member_completed", {
            agent_name: agent.name,
            role: member.role,
            status: result[:success] ? "completed" : "failed"
          })

          member_duration = ((Time.current - (task&.started_at || Time.current)) * 1000).to_i

          if result[:success]
            complete_team_task!(task, result[:output], tokens: result[:tokens_used] || 0, cost: result[:cost_usd] || 0.0)
            output_text = result[:output].is_a?(Hash) ? (result[:output][:response] || result[:output].to_json) : result[:output].to_s
            record_task_result(agent, output_text.truncate(500))
            record_member_completed(agent.name, true, member_duration)
          else
            fail_team_task!(task, result[:error] || "unknown error")
            record_member_completed(agent.name, false, member_duration)
          end

          worker_results << result.merge(agent_name: agent.name, role: member.role)
        end
      else
        # Fallback: no work plan, use generic role-based delegation
        log_execution("[Hierarchical] Work plan generation failed, using generic delegation")
        worker_results = workers.map do |member|
          check_control_signal!
          agent = member.agent
          task_text = @input.is_a?(Hash) ? (@input[:task] || @input['task'] || @input.to_json) : @input.to_s
          delegated_input = { task: "As directed by #{lead_agent.name}: #{task_text}" }

          member_start = Time.current
          result = execute_agent_with_retry(agent, delegated_input, member.role)
          member_duration = ((Time.current - member_start) * 1000).to_i

          broadcast_progress("member_completed", {
            agent_name: agent.name,
            role: member.role,
            status: result[:success] ? "completed" : "failed"
          })

          record_member_completed(agent.name, result[:success], member_duration)
          result.merge(agent_name: agent.name, role: member.role)
        end
      end

      # Phase 3: Synthesis — ask lead to synthesize all results
      successful_results = worker_results.select { |r| r[:success] }

      if successful_results.size > 1
        synthesized = synthesize_results(lead_agent, successful_results, @input)
        if synthesized.present?
          log_execution("[Hierarchical] Lead synthesized #{successful_results.size} worker outputs")
          record_team_message(message_type: "synthesis", content: synthesized, from_agent: lead_agent)
          return {
            success: true,
            output: {
              strategy: "hierarchical",
              lead: lead_agent.name,
              synthesized_output: synthesized,
              work_plan: @serialized_plan,
              worker_results: worker_results.map { |r| { agent: r[:agent_name], role: r[:role], success: r[:success] } },
              total_workers: workers.size,
              successful: successful_results.size
            }
          }
        end
      end

      # Fallback: return raw results without synthesis
      {
        success: successful_results.any?,
        output: {
          strategy: "hierarchical",
          lead: lead_agent.name,
          work_plan: @serialized_plan,
          results: worker_results.map { |r| { agent: r[:agent_name], role: r[:role], output: r[:output], success: r[:success] } },
          total_workers: workers.size,
          successful: successful_results.size
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

        # Inject relevant compound learnings into system prompt
        if team_config["compound_learning_injection"] != false
          learnings_context = inject_relevant_learnings(agent, input)
          if learnings_context.present?
            system_content += "\n\n## Relevant Learnings from Past Executions\n#{learnings_context}"
          end
        end

        user_content = input[:task].presence || input[:prompt].presence || input.to_json

        messages = [
          { role: "system", content: system_content },
          { role: "user", content: user_content }
        ]

        model = agent.try(:model) || agent.mcp_tool_manifest&.dig("model")

        # Check for task-specific model override
        task_type = @input.is_a?(Hash) ? (@input[:task_type] || @input["task_type"]) : nil
        if task_type.present?
          task_override = agent.mcp_metadata&.dig("task_model_overrides", task_type)
          if task_override.present?
            Rails.logger.info("[AgentTeamExecutionJob] Using task override model '#{task_override}' for #{agent.name} (task_type: #{task_type})")
            model = task_override

            # Resolve credential for the override model if it belongs to a different provider
            override_credential = resolve_credential_for_model(model, agent, credential)
            if override_credential && override_credential.id != credential.id
              Rails.logger.info("[AgentTeamExecutionJob] Switching provider from #{credential.provider.name} to #{override_credential.provider.name} for model '#{model}'")
              credential = override_credential
            end
          end
        end

        max_tokens = agent.try(:max_tokens) || agent.mcp_tool_manifest&.dig("max_tokens") || 4096
        temperature = agent.try(:temperature) || agent.mcp_tool_manifest&.dig("temperature") || 0.7

        timeout_seconds = @team.try(:task_timeout_seconds) || team_config["task_timeout_seconds"] || 300

        # Build tool options for MCP platform tools
        tool_options = {}
        if tools_enabled?
          ptype = provider_type_for(agent)
          tool_defs = ptype == "anthropic" ? anthropic_tool_definitions(agent) : platform_tool_definitions(agent)
          tool_options[:tools] = tool_defs if tool_defs.any?
        end

        total_tool_calls = 0
        round = 0
        result = nil
        accumulated_usage = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }

        loop do
          round += 1
          result = Timeout.timeout(timeout_seconds) do
            client = Ai::ProviderClientService.new(credential)
            client.send_message(messages, model: model, max_tokens: max_tokens, temperature: temperature, **tool_options)
          end
          break unless result&.dig(:success)

          # Accumulate usage from this round
          round_usage = result.dig(:metadata, :usage) || {}
          accumulated_usage.each_key { |k| accumulated_usage[k] += (round_usage[k] || 0) }

          # Check for tool calls in the response
          ptype = provider_type_for(agent)
          tool_calls = extract_tool_calls(result[:response], ptype)
          break if tool_calls.empty?

          # Safety guardrails
          total_tool_calls += tool_calls.size
          if round > MAX_TOOL_ROUNDS || total_tool_calls > MAX_TOOL_CALLS_TOTAL
            log_execution("[ToolExecution] Safety limit reached: round=#{round} calls=#{total_tool_calls}")
            break
          end

          log_execution("[ToolExecution] #{agent.name} round #{round}: #{tool_calls.size} tool calls")

          # Append assistant message and tool results to conversation
          if ptype == "anthropic"
            messages << { role: "assistant", content: result[:response][:content] }
          else
            assistant_msg = result.dig(:response, :choices, 0, :message)
            messages << assistant_msg.deep_symbolize_keys if assistant_msg
          end

          tool_results = execute_tool_calls(tool_calls, agent)
          messages.concat(build_tool_result_messages(tool_results, ptype))
        end

        if result&.dig(:success)
          usage = accumulated_usage
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

          # Write result to short-term memory for subsequent agents
          write_to_short_term_memory(agent, role, output)

          @execution.add_tokens!(tokens) if tokens.positive?
          @execution.add_cost!(cost) if cost.positive?

          { success: true, output: output }
        else
          error_msg = result&.dig(:error) || "Provider returned unsuccessful response"
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

    def resolve_credential_for_model(model_name, agent, current_credential)
      # Check if the current provider already has this model
      current_models = agent.provider.supported_models || []
      has_model = current_models.any? do |m|
        m.is_a?(Hash) ? (m["id"] == model_name || m["name"] == model_name) : m.to_s == model_name
      end
      return current_credential if has_model

      # Find a provider that has this model in its supported_models
      target_provider = ::Ai::Provider.where(is_active: true).detect do |p|
        (p.supported_models || []).any? do |m|
          m.is_a?(Hash) ? (m["id"] == model_name || m["name"] == model_name) : m.to_s == model_name
        end
      end

      unless target_provider
        Rails.logger.warn("[AgentTeamExecutionJob] No provider found for model '#{model_name}', using agent's default provider")
        return current_credential
      end

      target_credential = target_provider.provider_credentials
                                         .where(is_active: true)
                                         .where(account_id: @team.account_id)
                                         .first

      unless target_credential
        Rails.logger.warn("[AgentTeamExecutionJob] No active credential for provider '#{target_provider.name}', using agent's default")
        return current_credential
      end

      target_credential
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
        if requires_plan_approval?
          handle_plan_approval(output, duration_ms)
          return
        end

        @execution.complete!(output || {})

        # Post execution summary to conversation
        summary_text = output.is_a?(Hash) ? (output[:synthesized_output] || output["synthesized_output"] || output[:response] || output["response"] || "Execution completed successfully.") : "Execution completed successfully."
        @conversation_service&.post_execution_summary(@execution, summary_text.to_s.truncate(4000)) rescue nil

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

        # Post error to conversation
        if @execution.conversation.present?
          @conversation_service&.post_execution_summary(
            @execution,
            "Execution failed: #{error.message.truncate(500)}"
          ) rescue nil
        end
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
        @conversation_service&.post_task_result(@execution, agent_name, "completed in #{duration_ms}ms") rescue nil
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

    def requires_plan_approval?
      team_config["require_plan_approval"] == true && !@input[:plan_approval]
    end

    def handle_plan_approval(output, duration_ms)
      # Store the output on the execution so the service can reference it
      @execution.update!(output_result: output || {})

      service = Ai::TeamConversationService.new(account: @team.account)
      service.post_plan_for_approval(@execution)

      Rails.logger.info(
        "[AgentTeamExecutionJob] Plan posted for approval: execution=#{@execution.execution_id} duration=#{duration_ms}ms"
      )
    rescue StandardError => e
      Rails.logger.error("[AgentTeamExecutionJob] Plan approval failed, completing normally: #{e.message}")
      # Fallback: complete normally if plan approval fails
      @execution.complete!(output || {})
      broadcast_event("execution_completed",
        execution_id: @execution.execution_id,
        result: output,
        duration_ms: duration_ms)
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

    def reuse_approved_plan(approved_output, workers)
      return nil unless approved_output.is_a?(Hash)

      worker_map = workers.index_by { |m| m.agent.name }

      # Primary: check for stored work_plan from Phase 1
      stored_plan = approved_output["work_plan"] || approved_output[:work_plan]
      if stored_plan.is_a?(Hash) && (stored_plan["assignments"] || stored_plan[:assignments]).present?
        raw_assignments = stored_plan["assignments"] || stored_plan[:assignments]
        assignments = raw_assignments.filter_map do |a|
          name = a["worker_name"] || a[:worker_name]
          member = worker_map[name] || workers.find { |m|
            m.agent.name.include?(name.to_s) || name.to_s.include?(m.agent.name)
          }
          next unless member

          a.merge("member" => member, "agent_id" => member.agent.id)
        end

        if assignments.any?
          log_execution("[ReusePlan] Found #{assignments.size} assignments from stored work_plan")
          return {
            "plan_summary" => stored_plan["plan_summary"] || stored_plan[:plan_summary] || "Executing approved plan",
            "assignments" => assignments,
            "synthesis_notes" => stored_plan["synthesis_notes"] || stored_plan[:synthesis_notes] || "Combine worker outputs"
          }
        end
      end

      # Fallback: try to extract from synthesized output text
      plan_text = extract_plan_text(approved_output)
      return nil if plan_text.blank?

      assignments = []

      # Try JSON format
      json_match = plan_text.match(/\{[\s\S]*"assignments"[\s\S]*\}/)
      if json_match
        begin
          parsed = JSON.parse(json_match.to_s)
          return parse_work_plan(json_match.to_s, workers) if parsed["assignments"]
        rescue JSON::ParserError
          # Continue
        end
      end

      nil
    end

    def extract_plan_text(output)
      return output if output.is_a?(String)
      return nil unless output.is_a?(Hash)

      # Check various locations where the plan text might be
      output["response"] || output[:response] ||
        output["synthesized_output"] || output[:synthesized_output] ||
        output.dig("results", 0, "output", "response") ||
        output.to_json
    end

    def build_planned_input(assignment, original_input)
      task_desc = original_input.is_a?(Hash) ? (original_input[:task] || original_input["task"] || original_input.to_json) : original_input.to_s

      {
        task: "#{assignment['instructions']}\n\nExpected Output: #{assignment['expected_output']}\n\nOriginal Task Context: #{task_desc}",
        assignment: assignment["instructions"],
        expected_output: assignment["expected_output"],
        priority: assignment["priority"]
      }
    end

    def inject_relevant_learnings(agent, input)
      learnings = Ai::CompoundLearning.where(account: @team.account, status: "active")
                                       .order(importance_score: :desc, effectiveness_score: :desc)
                                       .limit(5)

      # Filter by task relevance if possible
      task_type = @input.is_a?(Hash) ? (@input[:task_type] || @input["task_type"]) : nil
      if task_type.present?
        category_map = {
          "code" => %w[pattern anti_pattern best_practice],
          "review" => %w[review_finding best_practice],
          "documentation" => %w[best_practice fact discovery],
          "testing" => %w[pattern failure_mode],
          "devops" => %w[pattern performance_insight]
        }
        relevant_categories = category_map[task_type]
        if relevant_categories
          scoped = Ai::CompoundLearning.where(account: @team.account, status: "active", category: relevant_categories)
                                        .order(importance_score: :desc)
                                        .limit(5)
          learnings = scoped if scoped.any?
        end
      end

      return nil unless learnings.any?

      lines = learnings.map do |l|
        l.record_injection_outcome!(positive: nil) rescue nil
        "- [#{l.category}] #{l.content.to_s.truncate(200)}"
      end

      lines.join("\n").truncate(2000)
    rescue StandardError => e
      Rails.logger.warn("[AgentTeamExecutionJob] Learning injection failed: #{e.message}")
      nil
    end

    def write_to_short_term_memory(agent, role, output)
      return unless agent && @execution

      Ai::AgentShortTermMemory.create!(
        account: @team.account,
        agent: agent,
        memory_type: "observation",
        memory_key: "execution:#{@execution.id}:#{agent.id}",
        memory_value: {
          execution_id: @execution.id,
          role: role,
          output_summary: output[:response].to_s.truncate(500),
          tokens_used: output[:tokens_used],
          completed_at: Time.current.iso8601
        },
        session_id: @execution.id,
        ttl_seconds: 86_400,
        expires_at: 24.hours.from_now
      )
    rescue StandardError => e
      Rails.logger.warn("[AgentTeamExecutionJob] STM write failed: #{e.message}")
    end

    def log_execution(message)
      Rails.logger.info("[AgentTeamExecutionJob] #{message}")
    end

    def broadcast_progress(event_type, payload = {})
      broadcast_event(event_type, payload.merge(execution_id: @execution&.execution_id))
    end

    def job_id_string
      try(:provider_job_id) || try(:job_id) || object_id.to_s
    end

    def execution_timeout?
      Time.current - @started_at > MAX_EXECUTION_TIME
    end
  end
end
