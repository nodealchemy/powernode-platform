# frozen_string_literal: true

module Ai
  class AgentAutonomyService
    attr_reader :account

    def initialize(account:)
      @account = account
    end

    # Create an agent for a team, checking guardrails first
    def create_agent_for_team(team, agent_params, user)
      guardrails = active_guardrails
      validate_team_capacity!(team, guardrails)

      agent = Ai::Agent.new(
        account: account,
        name: agent_params[:name],
        description: agent_params[:description],
        status: "active"
      )

      # Apply guardrail constraints to agent config
      apply_guardrail_constraints!(agent, guardrails)
      agent.save!

      # Add to team
      team.members.create!(
        agent: agent,
        role: agent_params[:role] || "worker",
        status: "active"
      )

      Rails.logger.info("Created agent #{agent.name} for team #{team.name}")
      agent
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Failed to create agent for team: #{e.message}")
      raise
    end

    # Update an agent within a team with guardrail checks
    def update_agent_in_team(team, member, params, actor: nil)
      guardrails = active_guardrails

      # Enforce authority if role is being changed
      if params[:role].present? && params[:role] != member.role
        authority = Ai::TeamAuthorityService.new(team: team)
        authority.authorize_authority_change!(actor, member, { role: params[:role] })
      end

      agent = member.agent
      updatable = params.slice(:name, :description, :status)
      agent.update!(updatable)

      if params[:role].present?
        member.update!(role: params[:role])
      end

      Rails.logger.info("Updated agent #{agent.name} in team #{team.name}")
      agent
    end

    # Remove an agent from a team with cleanup
    def remove_agent_from_team(team, member, actor: nil)
      # Enforce authority for member removal
      authority = Ai::TeamAuthorityService.new(team: team)
      authority.authorize_member_management!(actor, :remove_member)

      agent = member.agent
      agent_name = agent.name

      # Clean up any pending tasks assigned to this agent
      if team.respond_to?(:ai_team_tasks)
        team.ai_team_tasks
            .where(assigned_agent_id: agent.id, status: %w[pending assigned])
            .update_all(status: "unassigned", assigned_agent_id: nil)
      end

      member.destroy!
      Rails.logger.info("Removed agent #{agent_name} from team #{team.name}")
      true
    end

    # Auto-assign the best lead for a team based on capabilities
    def auto_assign_lead(team)
      members = team.members.includes(:agent)
      return nil if members.empty?

      scored = members.map do |member|
        agent = member.agent
        next unless agent

        score = calculate_lead_score(agent)
        { member: member, agent: agent, score: score }
      end.compact

      best = scored.max_by { |s| s[:score] }
      return nil unless best

      # Demote current lead if exists
      members.where(role: "lead").update_all(role: "worker")

      best[:member].update!(role: "lead")
      Rails.logger.info("Auto-assigned lead: #{best[:agent].name} (score: #{best[:score]})")
      best[:agent]
    end

    # Share memory between agents with access control
    def share_memory_between_agents(source_agent, target_agent, memory_keys)
      # Find source agent's memory contexts
      source_contexts = Ai::PersistentContext.where(
        account: account,
        ai_agent_id: source_agent.id,
        context_type: "agent_memory"
      )

      shared_entries = []

      source_contexts.find_each do |context|
        memory_keys.each do |key|
          entry = context.context_entries.active.find_by(entry_key: key)
          next unless entry

          # Create or update shared entry for target agent
          target_context = Ai::ContextPersistenceService.get_agent_memory(
            account: account,
            agent: target_agent
          )

          shared_entry = Ai::ContextPersistenceService.add_entry(
            context: target_context,
            attributes: {
              key: "shared:#{source_agent.id}:#{key}",
              type: "shared_memory",
              content: entry.content.deep_dup,
              metadata: {
                shared_from_agent: source_agent.id,
                shared_from_key: key,
                shared_at: Time.current.iso8601
              }
            }
          )
          shared_entries << shared_entry
        end
      end

      Rails.logger.info("Shared #{shared_entries.size} memory entries from #{source_agent.name} to #{target_agent.name}")
      shared_entries
    end

    private

    def active_guardrails
      Ai::GuardrailConfig.where(account: account).active
    end

    def validate_team_capacity!(team, guardrails)
      max_agents = guardrails.pick(:configuration)&.dig("max_agents_per_team")
      return unless max_agents

      current_count = team.members.count
      if current_count >= max_agents
        raise ArgumentError, "Team #{team.name} has reached maximum capacity of #{max_agents} agents"
      end
    end

    def apply_guardrail_constraints!(agent, guardrails)
      guardrails.find_each do |config|
        effective = config.effective_config
        if effective[:max_output_tokens] && agent.respond_to?(:max_output_tokens=)
          agent.max_output_tokens = [agent.max_output_tokens || effective[:max_output_tokens], effective[:max_output_tokens]].min
        end
      end
    end

    def calculate_lead_score(agent)
      score = 0.0

      # More skills = better lead
      skills_count = agent.respond_to?(:ai_agent_skills) ? agent.ai_agent_skills.count : 0
      score += [skills_count * 0.2, 2.0].min

      # Agent with longer history is more experienced
      age_days = (Time.current - agent.created_at).to_f / 1.day
      score += [age_days / 30.0, 1.0].min

      # Active status preferred
      score += 0.5 if agent.respond_to?(:status) && agent.status == "active"

      score.round(2)
    end
  end
end
