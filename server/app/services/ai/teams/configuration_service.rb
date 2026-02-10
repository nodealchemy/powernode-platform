# frozen_string_literal: true

module Ai
  module Teams
    class ConfigurationService
      IDEAL_ROLE_DISTRIBUTION = {
        "lead" => 1,
        "worker" => 3,
        "reviewer" => 1,
        "specialist" => 2
      }.freeze

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # ============================================================================
      # ROLE MANAGEMENT
      # ============================================================================

      def list_roles(team_id)
        team = find_team(team_id)
        team.ai_team_roles.ordered_by_priority
      end

      def create_role(team_id, params)
        team = find_team(team_id)

        Ai::TeamRole.create!(
          account: account,
          agent_team: team,
          role_name: params[:role_name],
          role_type: params[:role_type] || "worker",
          role_description: params[:role_description],
          responsibilities: params[:responsibilities],
          goals: params[:goals],
          capabilities: params[:capabilities] || [],
          constraints: params[:constraints] || [],
          tools_allowed: params[:tools_allowed] || [],
          priority_order: params[:priority_order] || 0,
          can_delegate: params[:can_delegate] || false,
          can_escalate: params[:can_escalate] || true,
          max_concurrent_tasks: params[:max_concurrent_tasks] || 1,
          context_access: params[:context_access] || {},
          ai_agent_id: params[:agent_id]
        )
      end

      def update_role(team_id, role_id, params)
        team = find_team(team_id)
        role = team.ai_team_roles.find(role_id)
        role.update!(params.slice(
          :role_name, :role_type, :role_description, :responsibilities,
          :goals, :capabilities, :constraints, :tools_allowed, :priority_order,
          :can_delegate, :can_escalate, :max_concurrent_tasks, :context_access
        ))
        role
      end

      def assign_agent_to_role(team_id, role_id, agent_id)
        team = find_team(team_id)
        role = team.ai_team_roles.find(role_id)
        agent = account.ai_agents.find(agent_id)
        role.update!(ai_agent: agent)
        role
      end

      def delete_role(team_id, role_id)
        team = find_team(team_id)
        role = team.ai_team_roles.find(role_id)
        role.destroy!
      end

      # ============================================================================
      # CHANNEL MANAGEMENT
      # ============================================================================

      def list_channels(team_id)
        team = find_team(team_id)
        team.ai_team_channels
      end

      def create_channel(team_id, params)
        team = find_team(team_id)

        if params[:participant_roles].present?
          params[:participant_roles].each do |role_id|
            team.ai_team_roles.find(role_id)  # Raises RecordNotFound if invalid
          end
        end

        Ai::TeamChannel.create!(
          agent_team: team,
          name: params[:name],
          channel_type: params[:channel_type] || "broadcast",
          description: params[:description],
          participant_roles: params[:participant_roles] || [],
          message_schema: params[:message_schema] || {},
          is_persistent: params[:is_persistent] != false,
          message_retention_hours: params[:message_retention_hours],
          routing_rules: params[:routing_rules] || {}
        )
      end

      def get_channel(team_id, channel_id)
        team = find_team(team_id)
        team.ai_team_channels.find(channel_id)
      end

      def update_channel(team_id, channel_id, params)
        team = find_team(team_id)
        channel = team.ai_team_channels.find(channel_id)

        if params[:participant_roles].present?
          params[:participant_roles].each do |role_id|
            team.ai_team_roles.find(role_id)
          end
        end

        channel.update!(
          name: params[:name] || channel.name,
          channel_type: params[:channel_type] || channel.channel_type,
          description: params.key?(:description) ? params[:description] : channel.description,
          participant_roles: params.key?(:participant_roles) ? params[:participant_roles] : channel.participant_roles,
          message_schema: params.key?(:message_schema) ? params[:message_schema] : channel.message_schema,
          is_persistent: params.key?(:is_persistent) ? params[:is_persistent] : channel.is_persistent,
          message_retention_hours: params.key?(:message_retention_hours) ? params[:message_retention_hours] : channel.message_retention_hours,
          routing_rules: params.key?(:routing_rules) ? params[:routing_rules] : channel.routing_rules
        )

        channel
      end

      def delete_channel(team_id, channel_id)
        team = find_team(team_id)
        channel = team.ai_team_channels.find(channel_id)
        channel.destroy!
        channel
      end

      # ============================================================================
      # TEMPLATES
      # ============================================================================

      def list_templates(filters = {})
        templates = Ai::TeamTemplate.all
        templates = templates.public_templates if filters[:public_only]
        templates = templates.system_templates if filters[:system_only]
        templates = templates.by_category(filters[:category]) if filters[:category].present?
        templates = templates.by_topology(filters[:topology]) if filters[:topology].present?
        templates = templates.order(usage_count: :desc)
        templates = templates.page(filters[:page]).per(filters[:per_page]) if filters[:page].present?
        templates
      end

      def get_template(template_id)
        Ai::TeamTemplate.find(template_id)
      end

      def create_template(params, user: nil)
        Ai::TeamTemplate.create!(
          account: account,
          name: params[:name],
          description: params[:description],
          category: params[:category],
          team_topology: params[:team_topology] || "hierarchical",
          role_definitions: params[:role_definitions] || [],
          channel_definitions: params[:channel_definitions] || [],
          workflow_pattern: params[:workflow_pattern] || {},
          default_config: params[:default_config] || {},
          is_public: params[:is_public] || false,
          tags: params[:tags] || [],
          created_by: user
        )
      end

      def publish_template(template_id)
        template = account.ai_team_templates.find(template_id)
        template.publish!
        template
      end

      # ============================================================================
      # TEAM ASSEMBLY (absorbed from TeamAssemblyService)
      # ============================================================================

      def create_team_for_task(requesting_agent:, task_description:, team_type: "hierarchical")
        validate_creation_allowed!

        team = account.ai_agent_teams.create!(
          name: "Auto: #{task_description.truncate(60)}",
          description: "Agent-created team for: #{task_description}",
          team_type: team_type,
          coordination_strategy: "consensus",
          status: "active"
        )

        team.add_member(
          agent: requesting_agent,
          role: "manager",
          capabilities: requesting_agent.respond_to?(:skill_slugs) ? requesting_agent.skill_slugs : [],
          is_lead: true
        )

        analyzer = Ai::Discovery::TaskAnalyzerService.new(account: account)
        analysis = analyzer.analyze(task_description)

        Rails.logger.info "[TeamAssembly] Created team '#{team.name}' with lead #{requesting_agent.name}"

        {
          team: team,
          required_skills: analysis[:required_capabilities] || [],
          recommendations: analysis[:recommendation]
        }
      end

      def discover_resources(requesting_agent:, required_skills:, limit: 10)
        a2a = Ai::A2a::Service.new(account: account)
        all_agents = []
        all_recommendations = []

        required_skills.each do |skill|
          discovered = a2a.discover_agents(skill: skill)
          all_agents.concat(discovered) if discovered.is_a?(Array)
        rescue StandardError => e
          Rails.logger.warn "[TeamAssembly] Discovery failed for skill '#{skill}': #{e.message}"
        end

        unique_agents = all_agents.uniq { |a| a.respond_to?(:id) ? a.id : a.to_s }
                                  .first(limit)

        analyzer = Ai::Discovery::TaskAnalyzerService.new(account: account)
        recommendation = analyzer.recommend_team(required_skills, unique_agents)
        all_recommendations << recommendation if recommendation

        {
          agents: unique_agents,
          tools: [],
          recommendations: all_recommendations
        }
      end

      def recruit_member(requesting_agent:, team:, agent:, role:, capabilities: [])
        validate_team_capacity!(team)

        member = team.add_member(
          agent: agent,
          role: role,
          capabilities: capabilities
        )

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

      def configure_member_authority(requesting_agent:, team:, member:, role: nil, capabilities: nil, can_delegate: false, can_escalate: true)
        authority = Ai::TeamAuthorityService.new(team: team)

        actor_member = team.members.find_by(ai_agent_id: requesting_agent.id)
        changes = {}
        changes[:role] = role if role.present?
        changes[:capabilities] = capabilities if capabilities.present?

        authority.authorize_authority_change!(actor_member, member, changes)

        updates = {}
        updates[:role] = role if role.present?
        updates[:capabilities] = capabilities if capabilities.present?
        member.update!(updates) if updates.any?

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

      # ============================================================================
      # COMPOSITION OPTIMIZATION (absorbed from TeamCompositionOptimizerService)
      # ============================================================================

      def analyze_composition(team)
        members = team.members.includes(:agent)
        agents = members.map(&:agent).compact

        skills = collect_team_skills(agents)
        roles = collect_team_roles(members)

        skill_coverage = calculate_skill_coverage(skills)
        role_balance = calculate_role_balance(roles, members.size)
        redundancies = find_redundancies(agents)
        gaps = find_skill_gaps(team, skills)

        coverage_score = calculate_coverage_score(skill_coverage, role_balance)

        {
          team_id: team.id,
          team_name: team.name,
          members_count: members.size,
          skill_coverage: skill_coverage,
          role_balance: role_balance,
          redundancies: redundancies,
          gaps: gaps,
          coverage_score: coverage_score,
          health: coverage_score >= 0.7 ? "healthy" : (coverage_score >= 0.4 ? "needs_attention" : "critical")
        }
      end

      def recommend_agents(team, task_description)
        analyzer = Ai::Discovery::TaskAnalyzerService.new(account: account)
        analysis = analyzer.analyze(task_description)
        current_analysis = analyze_composition(team)

        add_recommendations = []
        remove_recommendations = []

        analysis[:recommendation].each do |rec|
          next unless rec[:gap]

          available = Ai::Agent.where(account: account)
                                .where.not(id: team.ai_agent_team_members.pluck(:ai_agent_id))

          best_match = available.detect do |agent|
            analyzer.send(:score_agent_for_capability, agent, rec[:capability]) > 0
          end

          if best_match
            add_recommendations << {
              action: "add",
              agent_id: best_match.id,
              agent_name: best_match.name,
              reason: "Fills gap in #{rec[:capability]}"
            }
          end
        end

        current_analysis[:redundancies].each do |redundancy|
          next unless redundancy[:agents].size > 2

          least_active = redundancy[:agents].min_by { |a| a[:activity_score] }
          remove_recommendations << {
            action: "remove",
            agent_id: least_active[:id],
            agent_name: least_active[:name],
            reason: "Redundant capability: #{redundancy[:skill]}"
          }
        end

        {
          add: add_recommendations,
          remove: remove_recommendations,
          current_coverage: current_analysis[:coverage_score],
          projected_coverage: project_coverage(current_analysis, add_recommendations, remove_recommendations)
        }
      end

      def auto_optimize(team)
        analysis = analyze_composition(team)
        return { status: "optimal", changes: [] } if analysis[:health] == "healthy"

        guardrails = Ai::GuardrailConfig.where(account: account).active
        autonomy_service = Ai::AgentAutonomyService.new(account: account)
        changes = []

        if analysis[:role_balance][:missing_roles]&.include?("lead")
          lead = autonomy_service.auto_assign_lead(team)
          changes << { action: "assigned_lead", agent: lead.name } if lead
        end

        max_size = guardrails.pick(:configuration)&.dig("max_agents_per_team") || 10
        if analysis[:members_count] > max_size
          Rails.logger.warn("Team #{team.name} exceeds max size #{max_size}")
          changes << { action: "warning", message: "Team exceeds recommended size of #{max_size}" }
        end

        {
          status: changes.any? ? "optimized" : "no_changes",
          analysis: analysis,
          changes: changes
        }
      end

      private

      def find_team(team_id)
        account.ai_agent_teams.find(team_id)
      end

      # Assembly validations

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

      # Composition analysis helpers

      def collect_team_skills(agents)
        skills = Hash.new { |h, k| h[k] = [] }

        agents.each do |agent|
          next unless agent.respond_to?(:ai_agent_skills)

          agent.ai_agent_skills.each do |skill|
            skills[skill.name.downcase] << agent.id
          end
        end

        skills
      end

      def collect_team_roles(members)
        members.each_with_object(Hash.new(0)) do |member, counts|
          role = member.respond_to?(:role) ? (member.role || "worker") : "worker"
          counts[role] += 1
        end
      end

      def calculate_skill_coverage(skills)
        total_skills = skills.keys.size
        multi_covered = skills.count { |_, agents| agents.size > 1 }

        {
          total_skills: total_skills,
          multi_covered_skills: multi_covered,
          unique_skills: total_skills - multi_covered,
          skills: skills.transform_values(&:size)
        }
      end

      def calculate_role_balance(roles, team_size)
        missing_roles = []
        overstaffed_roles = []

        IDEAL_ROLE_DISTRIBUTION.each do |role, ideal_count|
          actual = roles[role] || 0
          ideal_for_size = [(ideal_count.to_f / 7 * team_size).ceil, 1].max

          missing_roles << role if actual.zero? && team_size >= 3
          overstaffed_roles << role if actual > ideal_for_size * 2
        end

        {
          distribution: roles,
          missing_roles: missing_roles,
          overstaffed_roles: overstaffed_roles,
          balanced: missing_roles.empty? && overstaffed_roles.empty?
        }
      end

      def find_redundancies(agents)
        skill_agents = Hash.new { |h, k| h[k] = [] }

        agents.each do |agent|
          next unless agent.respond_to?(:ai_agent_skills)

          agent.ai_agent_skills.each do |skill|
            skill_agents[skill.name.downcase] << {
              id: agent.id,
              name: agent.name,
              activity_score: calculate_activity_score(agent)
            }
          end
        end

        skill_agents.select { |_, a| a.size > 1 }.map do |skill, agent_list|
          { skill: skill, agents: agent_list, count: agent_list.size }
        end
      end

      def find_skill_gaps(team, current_skills)
        team_type = team.respond_to?(:team_type) ? team.team_type : "general"

        required = case team_type
                   when "development"
                     %w[code_review testing deployment]
                   when "operations"
                     %w[monitoring deployment security]
                   when "research"
                     %w[data_analysis documentation]
                   else
                     %w[code_review testing]
                   end

        required.reject { |skill| current_skills.keys.any? { |k| k.include?(skill) } }
      end

      def calculate_coverage_score(skill_coverage, role_balance)
        skill_score = skill_coverage[:total_skills] > 0 ? [skill_coverage[:total_skills] / 5.0, 1.0].min : 0
        role_score = role_balance[:balanced] ? 1.0 : 0.5
        role_score -= 0.2 * role_balance[:missing_roles].size

        ((skill_score * 0.6 + [role_score, 0].max * 0.4)).round(2)
      end

      def calculate_activity_score(agent)
        return 0 unless agent.respond_to?(:ai_agent_executions)

        recent = agent.ai_agent_executions
                      .where("created_at > ?", 7.days.ago)
                      .count
        [recent / 10.0, 1.0].min.round(2)
      rescue StandardError
        0
      end

      def project_coverage(current, additions, removals)
        adjustment = additions.size * 0.1 - removals.size * 0.05
        [(current[:coverage_score] + adjustment).round(2), 1.0].min
      end
    end
  end
end
