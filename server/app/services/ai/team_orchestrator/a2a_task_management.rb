# frozen_string_literal: true

class Ai::AgentTeamOrchestrator
  module A2aTaskManagement
    extend ActiveSupport::Concern

    private

    def execute_member_via_a2a(member, input)
      task = submit_member_task(member, input)
      wait_for_task_completion(task)
    end

    def submit_member_task(member, input)
      # Check if team has Swarm infrastructure bindings for containerized execution
      if swarm_bound? && member.agent.mcp_metadata&.dig("container_execution")
        return submit_containerized_task(member, input)
      end

      # Get or create agent card for the member's agent
      agent_card = find_or_create_agent_card(member.agent)

      @a2a_service.submit_task(
        from_agent: nil, # Team orchestrator
        to_agent_card: agent_card,
        message: build_task_message(member, input),
        metadata: {
          team_id: team.id,
          member_id: member.id,
          role: member.role,
          capabilities: member.capabilities
        }
      )
    end

    def submit_delegation_task(from_member:, to_member:, instructions:, input:)
      # Enforce authority: delegation must flow downward
      @authority.authorize_delegation!(from_member, to_member)

      from_card = find_or_create_agent_card(from_member.agent)
      to_card = find_or_create_agent_card(to_member.agent)

      @a2a_service.submit_task(
        from_agent: from_member.agent,
        to_agent_card: to_card,
        message: {
          role: "user",
          parts: [
            { type: "text", text: instructions },
            { type: "data", data: input }
          ]
        },
        metadata: {
          team_id: team.id,
          delegation: true,
          from_member_id: from_member.id,
          to_member_id: to_member.id
        }
      )
    end

    def wait_for_task_completion(task, timeout: 300)
      start_time = Time.current

      loop do
        task.reload

        case task.status
        when "completed"
          return {
            task_id: task.task_id,
            output: task.output,
            artifacts: task.artifacts,
            success: true
          }
        when "failed"
          return {
            task_id: task.task_id,
            error: task.error_message,
            success: false
          }
        when "cancelled"
          return {
            task_id: task.task_id,
            error: "Task was cancelled",
            success: false
          }
        end

        if Time.current - start_time > timeout
          task.cancel!("Timeout waiting for completion")
          return {
            task_id: task.task_id,
            error: "Task timeout",
            success: false
          }
        end

        sleep 0.5
      end
    end

    def find_or_create_agent_card(agent)
      Ai::AgentCard.find_or_create_by!(
        account_id: team.account_id,
        ai_agent_id: agent.id
      ) do |card|
        card.name = agent.name
        card.description = agent.description&.truncate(500)
        card.visibility = "private"
        card.status = "active"
        card.capabilities = { "skills" => agent.skill_slugs }
      end
    end

    def build_task_message(member, input)
      {
        role: "user",
        parts: [
          {
            type: "text",
            text: "Execute task as #{member.role} with capabilities: #{member.capabilities.join(', ')}"
          },
          {
            type: "data",
            data: input
          }
        ]
      }
    end
  end
end
