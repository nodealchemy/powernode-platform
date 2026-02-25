# frozen_string_literal: true

module Ai
  module Tools
    class TeamManagementTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.execute"

      def self.definition
        {
          name: "team_management",
          description: "Create, list, get, update teams, add members, or execute team workflows",
          parameters: {
            action: { type: "string", required: true, description: "Action: create_team, list_teams, get_team, update_team, add_team_member, execute_team" },
            team_id: { type: "string", required: false },
            name: { type: "string", required: false },
            team_type: { type: "string", required: false },
            agent_id: { type: "string", required: false },
            role: { type: "string", required: false },
            input: { type: "object", required: false },
            description: { type: "string", required: false, description: "Team description" },
            coordination_strategy: { type: "string", required: false, description: "Coordination strategy" },
            team_config: { type: "object", required: false, description: "Team configuration" },
            review_config: { type: "object", required: false, description: "Review configuration" }
          }
        }
      end

      def self.action_definitions
        {
          "create_team" => {
            description: "Create a new AI agent team with the specified configuration",
            parameters: {
              name: { type: "string", required: true, description: "Team name" },
              description: { type: "string", required: false, description: "Team description" },
              team_type: { type: "string", required: false, description: "Team type (default: sequential)" },
              coordination_strategy: { type: "string", required: false, description: "Coordination strategy (default: manager_led)" }
            }
          },
          "list_teams" => {
            description: "List all active AI agent teams in the current account",
            parameters: {}
          },
          "get_team" => {
            description: "Get detailed information about a specific team including its members",
            parameters: {
              team_id: { type: "string", required: true, description: "Team UUID or exact team name" }
            }
          },
          "update_team" => {
            description: "Update an existing team's configuration",
            parameters: {
              team_id: { type: "string", required: true, description: "Team UUID or exact team name" },
              name: { type: "string", required: false, description: "New team name" },
              description: { type: "string", required: false, description: "New team description" },
              coordination_strategy: { type: "string", required: false, description: "Coordination strategy" },
              team_config: { type: "object", required: false, description: "Team configuration to merge" },
              review_config: { type: "object", required: false, description: "Review configuration to merge" }
            }
          },
          "add_team_member" => {
            description: "Add an AI agent as a member of a team",
            parameters: {
              team_id: { type: "string", required: true, description: "Team UUID or exact team name" },
              agent_id: { type: "string", required: true, description: "Agent UUID, slug, or exact name" },
              role: { type: "string", required: false, description: "Member role (default: worker)" }
            }
          },
          "execute_team" => {
            description: "Queue execution of a team workflow",
            parameters: {
              team_id: { type: "string", required: true, description: "Team UUID or exact team name" },
              input: { type: "object", required: false, description: "Execution input" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "create_team" then create_team(params)
        when "list_teams" then list_teams(params)
        when "get_team" then get_team(params)
        when "update_team" then update_team(params)
        when "add_team_member" then add_team_member(params)
        when "execute_team" then execute_team(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def create_team(params)
        team = account.ai_agent_teams.create!(
          name: params[:name],
          description: params[:description],
          team_type: params[:team_type] || "sequential",
          coordination_strategy: params[:coordination_strategy] || "manager_led",
          status: "active"
        )
        { success: true, team_id: team.id, name: team.name }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def add_team_member(params)
        team = resolve_team(params[:team_id])
        agent = resolve_agent(params[:agent_id])
        role_type = map_member_role_to_type(params[:role] || "worker")

        member = team.members.create!(
          agent: agent,
          role: params[:role] || "worker",
          is_lead: role_type == "manager"
        )

        # Auto-create a backing TeamRole for orchestration/UI unification
        unless team.ai_team_roles.exists?(ai_agent_id: agent.id)
          Ai::TeamRole.create!(
            account: account,
            agent_team: team,
            role_name: agent.name,
            role_type: role_type,
            role_description: agent.description,
            ai_agent_id: agent.id,
            capabilities: member.capabilities || [],
            priority_order: member.priority_order
          )
        end

        { success: true, member_id: member.id }
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      end

      def execute_team(params)
        team = resolve_team(params[:team_id])
        { success: true, team_id: team.id, status: "execution_queued", message: "Team execution queued" }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Team not found" }
      end

      def get_team(params)
        team = resolve_team(params[:team_id])
        members = team.members.includes(:agent).map do |m|
          { agent_name: m.agent.name, role: m.role, is_lead: m.is_lead }
        end
        {
          success: true,
          team: {
            id: team.id,
            name: team.name,
            team_type: team.team_type,
            status: team.status,
            coordination_strategy: team.coordination_strategy,
            team_config: team.team_config,
            review_config: team.review_config,
            members: members
          }
        }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Team not found" }
      end

      def list_teams(params = {})
        teams = account.ai_agent_teams.where(status: "active").limit(50)
        {
          success: true,
          teams: teams.map { |t|
            { id: t.id, name: t.name, team_type: t.team_type, coordination_strategy: t.coordination_strategy, member_count: t.members.count }
          }
        }
      end

      def update_team(params)
        team = resolve_team(params[:team_id])
        attrs = {}
        attrs[:name] = params[:name] if params[:name].present?
        attrs[:description] = params[:description] if params[:description].present?
        attrs[:coordination_strategy] = params[:coordination_strategy] if params[:coordination_strategy].present?
        if params[:team_config].present?
          attrs[:team_config] = (team.team_config || {}).merge(params[:team_config])
        end
        if params[:review_config].present?
          attrs[:review_config] = (team.review_config || {}).merge(params[:review_config])
        end
        team.update!(attrs)
        { success: true, team_id: team.id, name: team.name }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Team not found" }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      # Map freeform member role strings to TeamRole::ROLE_TYPES
      def map_member_role_to_type(role)
        case role.to_s.downcase
        when "manager"                   then "manager"
        when "coordinator", "facilitator" then "coordinator"
        when "reviewer"                  then "reviewer"
        when "validator"                 then "validator"
        when "researcher", "writer", "analyst" then "specialist"
        else "worker"
        end
      end

      # Resolve an agent by UUID, slug, or exact name
      def resolve_agent(identifier)
        return nil if identifier.blank?

        scope = account.ai_agents
        scope.find_by(id: identifier) ||
          scope.find_by(slug: identifier) ||
          scope.find_by(name: identifier) ||
          raise(ActiveRecord::RecordNotFound, "Agent not found: #{identifier}")
      end

      # Resolve a team by UUID or by exact name (case-insensitive)
      def resolve_team(identifier)
        return account.ai_agent_teams.find(identifier) if uuid?(identifier)

        team = account.ai_agent_teams.find_by("LOWER(name) = LOWER(?)", identifier)
        raise ActiveRecord::RecordNotFound, "Team not found: #{identifier}" unless team

        team
      end

      def uuid?(value)
        value.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      end
    end
  end
end
