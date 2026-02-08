# frozen_string_literal: true

module Ai
  class TeamAssemblyService
    attr_reader :account, :requesting_agent

    def initialize(account:, requesting_agent:)
      @account = account
      @requesting_agent = requesting_agent
    end

    # Agent creates a new team for a task, becoming lead automatically
    def create_team_for_task(task_description:, team_type: "hierarchical")
      validate_creation_allowed!

      # Create team
      team = account.ai_agent_teams.create!(
        name: "Auto: #{task_description.truncate(60)}",
        description: "Agent-created team for: #{task_description}",
        team_type: team_type,
        coordination_strategy: "consensus",
        status: "active"
      )

      # Add requesting agent as lead
      team.add_member(
        agent: requesting_agent,
        role: "manager",
        capabilities: requesting_agent.respond_to?(:skill_slugs) ? requesting_agent.skill_slugs : [],
        is_lead: true
      )

      # Analyze task for required capabilities
      analyzer = Ai::Discovery::TaskAnalyzerService.new(account: account)
      analysis = analyzer.analyze(task_description)

      Rails.logger.info "[TeamAssembly] Created team '#{team.name}' with lead #{requesting_agent.name}"

      {
        team: team,
        required_skills: analysis[:required_capabilities] || [],
        recommendations: analysis[:recommendation]
      }
    end

    # Discover available agents and tools matching required skills
    def discover_resources(required_skills:, limit: 10)
      a2a = Ai::A2a::Service.new(account: account)
      all_agents = []
      all_recommendations = []

      required_skills.each do |skill|
        discovered = a2a.discover_agents(skill: skill)
        all_agents.concat(discovered) if discovered.is_a?(Array)
      rescue StandardError => e
        Rails.logger.warn "[TeamAssembly] Discovery failed for skill '#{skill}': #{e.message}"
      end

      # Deduplicate by agent id
      unique_agents = all_agents.uniq { |a| a.respond_to?(:id) ? a.id : a.to_s }
                                .first(limit)

      # Get team recommendations
      analyzer = Ai::Discovery::TaskAnalyzerService.new(account: account)
      recommendation = analyzer.recommend_team(required_skills, unique_agents)
      all_recommendations << recommendation if recommendation

      {
        agents: unique_agents,
        tools: [],
        recommendations: all_recommendations
      }
    end

    # Add a discovered agent to a team with capacity check
    def recruit_member(team:, agent:, role:, capabilities: [])
      validate_team_capacity!(team)

      member = team.add_member(
        agent: agent,
        role: role,
        capabilities: capabilities
      )

      # Record the connection
      Ai::AgentConnection.create(
        account: account,
        source_type: "Ai::Agent",
        source_id: requesting_agent.id,
        target_type: "Ai::Agent",
        target_id: agent.id,
        connection_type: "team_membership",
        status: "active",
        strength: 0.8,
        metadata: {
          "team_id" => team.id,
          "role" => role,
          "discovered_by" => requesting_agent.id
        }
      )

      Rails.logger.info "[TeamAssembly] Recruited #{agent.name} as #{role} into team #{team.name}"

      member
    end

    # Leader configures a team member's authority settings
    def configure_member_authority(team:, member:, role: nil, capabilities: nil, can_delegate: false, can_escalate: true)
      authority = Ai::TeamAuthorityService.new(team: team)

      # Find requesting agent's membership to verify authority
      actor_member = team.members.find_by(ai_agent_id: requesting_agent.id)
      changes = {}
      changes[:role] = role if role.present?
      changes[:capabilities] = capabilities if capabilities.present?

      authority.authorize_authority_change!(actor_member, member, changes)

      # Update member
      updates = {}
      updates[:role] = role if role.present?
      updates[:capabilities] = capabilities if capabilities.present?
      member.update!(updates) if updates.any?

      # Update TeamRole if one exists for this member
      team_role = team.respond_to?(:ai_team_roles) && team.ai_team_roles.find_by(ai_agent_id: member.ai_agent_id)
      if team_role
        role_updates = {}
        role_updates[:can_delegate] = can_delegate
        role_updates[:can_escalate] = can_escalate
        role_updates[:role_type] = role if role.present? && Ai::TeamRole::ROLE_TYPES.include?(role)
        team_role.update!(role_updates) if role_updates.any?
      end

      Rails.logger.info "[TeamAssembly] Configured authority for #{member.agent_name} in team #{team.name}"

      member.reload
    end

    private

    def validate_creation_allowed!
      guardrails = Ai::GuardrailConfig.where(account: account).active

      guardrails.find_each do |config|
        autonomy = config.autonomy_level
        allow_creation = config.allow_agent_creation

        if autonomy == "supervised" && !allow_creation
          raise AiExceptions::AuthorizationError.new(
            "Agent team creation is not allowed under current guardrail configuration (supervised mode, agent creation disabled)"
          )
        end
      end
    end

    def validate_team_capacity!(team)
      guardrails = Ai::GuardrailConfig.where(account: account).active
      max_agents = guardrails.pick(:max_agents_per_team)
      return unless max_agents

      current_count = team.members.count
      if current_count >= max_agents
        raise AiExceptions::ValidationError.new(
          "Team #{team.name} has reached maximum capacity of #{max_agents} agents"
        )
      end
    end
  end
end
