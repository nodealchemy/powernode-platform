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

      Rails.logger.info(
        "[AgentTeamExecutionJob] Starting execution for team #{@team.id} (#{@team.name})"
      )

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
      # Note: Team status only supports active/inactive/archived, not execution states
      # Execution state tracking should be done via separate tracking mechanism

      # Get team members ordered by priority
      members = @team.members.includes(:agent).order(:priority_order)

      if members.empty?
        Rails.logger.warn("[AgentTeamExecutionJob] Team #{@team.id} has no members")
        complete_execution(success: false, error: "Team has no members")
        return
      end

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

      members.each do |member|
        break if execution_timeout?

        agent = member.agent
        Rails.logger.info("[AgentTeamExecutionJob] Executing agent: #{agent.name} (#{member.role})")

        result = execute_agent(agent, accumulated_context, member.role)

        if result[:success]
          # Pass output to next agent as context
          accumulated_context = accumulated_context.merge(
            previous_agent_output: result[:output],
            previous_agent: agent.name
          )
          final_output = result[:output]
        else
          return { success: false, error: "Agent #{agent.name} failed: #{result[:error]}" }
        end
      end

      { success: true, output: final_output }
    end

    def execute_parallel(members)
      Rails.logger.info("[AgentTeamExecutionJob] Executing #{members.count} agents in parallel")

      # For true parallel execution, we'd use threads or separate jobs
      # For now, simulate parallel by executing all and collecting results
      results = []

      members.each do |member|
        agent = member.agent
        result = execute_agent(agent, @input, member.role)
        results << { agent: agent.name, result: result }
      end

      # Aggregate results
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

      # Find the lead agent
      lead_member = members.find(&:is_lead) || members.first
      subordinate_members = members.reject { |m| m.id == lead_member.id }

      # Lead agent processes input first
      lead_result = execute_agent(lead_member.agent, @input, lead_member.role)

      unless lead_result[:success]
        return { success: false, error: "Lead agent failed: #{lead_result[:error]}" }
      end

      # Lead directs subordinates based on its output
      subordinate_results = subordinate_members.map do |member|
        context = @input.merge(
          lead_directive: lead_result[:output],
          assigned_role: member.role
        )
        result = execute_agent(member.agent, context, member.role)
        { agent: member.agent.name, result: result }
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

      # All agents process the same input
      results = members.map do |member|
        result = execute_agent(member.agent, @input, member.role)
        { agent: member.agent.name, role: member.role, result: result }
      end

      # Simple majority voting for success
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
      # Create an execution context for this agent
      execution = agent.executions.create!(
        account: @team.account,
        user: @user,
        status: "running",
        input_data: input,
        metadata: {
          team_id: @team.id,
          team_name: @team.name,
          role: role,
          started_at: Time.current.iso8601
        }
      )

      # Execute the agent (simplified - in production would call actual AI service)
      # This would integrate with the AI provider to get a response
      begin
        # Placeholder for actual agent execution
        # In production, this would call the AI service through the agent
        output = {
          agent_id: agent.id,
          agent_name: agent.name,
          role: role,
          processed_at: Time.current.iso8601,
          input_received: input.keys
        }

        execution.update!(
          status: "completed",
          output_data: output,
          completed_at: Time.current
        )

        { success: true, output: output }
      rescue StandardError => e
        execution.update!(
          status: "failed",
          error_message: e.message,
          completed_at: Time.current
        )
        { success: false, error: e.message }
      end
    end

    def complete_execution(success:, output: nil, error: nil)

      duration_ms = ((Time.current - @started_at) * 1000).to_i

      Rails.logger.info(
        "[AgentTeamExecutionJob] Completed: team=#{@team.id} success=#{success} duration=#{duration_ms}ms"
      )

      # Notify completion via API callback
      notify_completion(success: success, output: output, error: error, duration_ms: duration_ms)
    end

    def handle_execution_error(error)
      Rails.logger.error(
        "[AgentTeamExecutionJob] Execution failed: #{error.message}\n#{error.backtrace&.first(10)&.join("\n")}"
      )

      # Team status not changed - execution tracking should be separate

      # Notify failure
      notify_failure(error: error.message)
    end

    def notify_completion(success:, output:, error:, duration_ms:)
      # This would typically call back to the API or send a webhook
      # For now, just log the completion
      Rails.logger.info(
        "[AgentTeamExecutionJob] Notifying completion: team=#{@team.id} success=#{success}"
      )
    end

    def notify_failure(error:)
      Rails.logger.info(
        "[AgentTeamExecutionJob] Notifying failure: team=#{@team.id} error=#{error}"
      )
    end

    def execution_timeout?
      Time.current - @started_at > MAX_EXECUTION_TIME
    end
  end
end
