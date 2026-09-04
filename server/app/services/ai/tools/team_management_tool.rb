# frozen_string_literal: true

module Ai
  module Tools
    class TeamManagementTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.execute"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "add_team_member", mutating: true
      declare_action "create_team", mutating: true
      declare_action "delete_team", mutating: true
      declare_action "execute_team", mutating: true
      declare_action "get_team", mutating: false
      declare_action "list_teams", mutating: false
      declare_action "remove_team_member", mutating: true
      declare_action "update_team", mutating: true

      # HIER-P4 — a CANONICAL team (the account's materialisation of a global
      # Ai::TeamTemplate, Ai::AgentTeam#canonical?) is read-only through these
      # verbs, like a canonical agent: list/get show it flagged, every mutating
      # verb answers a result envelope that names the clone path. Its
      # membership is repaired by Ai::Teams::CanonicalTeamReconciler.
      # The wording lives on the model (Ai::AgentTeam::READ_ONLY_MESSAGE) so the
      # MCP envelope, the REST 403 and Ai::Teams::CrudService cannot drift.

      def self.definition
        {
          name: "team_management",
          description: "Create, list, get, update, delete teams; add/remove members; or execute team workflows",
          parameters: {
            action: { type: "string", required: true, description: "Action: create_team, list_teams, get_team, update_team, delete_team, add_team_member, remove_team_member, execute_team" },
            team_id: { type: "string", required: false },
            name: { type: "string", required: false },
            team_type: { type: "string", required: false },
            agent_id: { type: "string", required: false },
            role: { type: "string", required: false },
            input: { type: "object", required: false },
            description: { type: "string", required: false, description: "Team description" },
            status: { type: "string", required: false, description: "Team status: active, paused, archived" },
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
            description: "List all active AI agent teams in the current account. A team flagged canonical is the account's materialisation of a global team template (read-only; clone the template to customise)",
            parameters: {}
          },
          "get_team" => {
            description: "Get detailed information about a specific team including its members. A canonical team (flag `canonical`, `source_key`) is read-only through the mutating verbs",
            parameters: {
              team_id: { type: "string", required: true, description: "Team UUID or exact team name" }
            }
          },
          "update_team" => {
            description: "Update an existing team's configuration. Refused on a canonical team",
            parameters: {
              team_id: { type: "string", required: true, description: "Team UUID or exact team name" },
              name: { type: "string", required: false, description: "New team name" },
              description: { type: "string", required: false, description: "New team description" },
              status: { type: "string", required: false, description: "Team status: active, paused, archived" },
              coordination_strategy: { type: "string", required: false, description: "Coordination strategy" },
              team_config: { type: "object", required: false, description: "Team configuration to merge" },
              review_config: { type: "object", required: false, description: "Review configuration to merge" }
            }
          },
          "delete_team" => {
            description: "Hard-destroy a team. Cascades: members + channels + executions :destroy; conversations + learnings :nullify. Irreversible. Refused on a canonical team.",
            parameters: {
              team_id: { type: "string", required: true, description: "Team UUID or exact team name" }
            }
          },
          "add_team_member" => {
            description: "Add an AI agent as a member of a team. Refused on a canonical team",
            parameters: {
              team_id: { type: "string", required: true, description: "Team UUID or exact team name" },
              agent_id: { type: "string", required: true, description: "Agent UUID, slug, or exact name" },
              role: { type: "string", required: false, description: "Member role (default: worker)" }
            }
          },
          "remove_team_member" => {
            description: "Remove an AI agent from a team. Destroys the AgentTeamMember row and the backing TeamRole if present. Refused on a canonical team.",
            parameters: {
              team_id: { type: "string", required: true, description: "Team UUID or exact team name" },
              agent_id: { type: "string", required: true, description: "Agent UUID, slug, or exact name" }
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
        when "delete_team" then delete_team(params)
        when "add_team_member" then add_team_member(params)
        when "remove_team_member" then remove_team_member(params)
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
        return canonical_refusal(team) if team.canonical?

        agent = resolve_agent(params[:agent_id])
        role_type = Ai::AgentTeamMember.role_type_for(params[:role] || "worker")

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
        input = params[:input] || {}
        input = input.stringify_keys if input.respond_to?(:stringify_keys)
        triggered_by = user || account.users.first

        WorkerJobService.enqueue_ai_team_execution(
          team_id: team.id,
          user_id: triggered_by&.id,
          input: input,
          context: { "source" => "mcp_tool", "triggered_at" => Time.current.iso8601 }
        )

        { success: true, team_id: team.id, status: "execution_dispatched", message: "Team execution dispatched to worker" }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Team not found" }
      rescue WorkerJobService::WorkerServiceError => e
        { success: false, error: "Failed to dispatch team execution: #{e.message}" }
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
            canonical: team.canonical?,
            template_id: team.template_id,
            source_key: team.canonical? ? team.team_config["source_key"] : nil,
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
            { id: t.id, name: t.name, team_type: t.team_type, coordination_strategy: t.coordination_strategy,
              member_count: t.members.count, canonical: t.canonical?, template_id: t.template_id }
          }
        }
      end

      def update_team(params)
        team = resolve_team(params[:team_id])
        return canonical_refusal(team) if team.canonical?

        attrs = {}
        attrs[:name] = params[:name] if params[:name].present?
        attrs[:description] = params[:description] if params[:description].present?
        attrs[:status] = params[:status] if params[:status].present?
        attrs[:coordination_strategy] = params[:coordination_strategy] if params[:coordination_strategy].present?
        if params[:team_config].present?
          attrs[:team_config] = (team.team_config || {}).merge(params[:team_config])
        end
        if params[:review_config].present?
          attrs[:review_config] = (team.review_config || {}).merge(params[:review_config])
        end
        team.update!(attrs)
        { success: true, team_id: team.id, name: team.name, status: team.status }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Team not found" }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def delete_team(params)
        team = resolve_team(params[:team_id])
        return canonical_refusal(team) if team.canonical?

        name = team.name
        member_count = team.members.count
        team.destroy!
        { success: true, deleted: true, team_id: params[:team_id], name: name, members_cascaded: member_count }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Team not found" }
      rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
        { success: false, error: "Failed to delete team: #{e.message}" }
      end

      def remove_team_member(params)
        team = resolve_team(params[:team_id])
        return canonical_refusal(team) if team.canonical?

        agent = resolve_agent(params[:agent_id])
        member = team.members.find_by(ai_agent_id: agent.id)
        return { success: false, error: "Agent #{agent.name} is not a member of team #{team.name}" } unless member

        team.ai_team_roles.where(ai_agent_id: agent.id).destroy_all
        member.destroy!
        { success: true, removed: true, team_id: team.id, agent_id: agent.id }
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      end

      def canonical_refusal(team)
        {
          success: false,
          canonical: true,
          team_id: team.id,
          template_id: team.template_id,
          error: team.canonical_read_only_message
        }
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
