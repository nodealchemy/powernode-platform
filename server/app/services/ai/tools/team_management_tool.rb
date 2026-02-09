# frozen_string_literal: true

module Ai
  module Tools
    class TeamManagementTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.execute"

      def self.definition
        {
          name: "team_management",
          description: "Create teams, add members, or execute team workflows",
          parameters: {
            action: { type: "string", required: true, description: "Action: create_team, add_team_member, execute_team" },
            team_id: { type: "string", required: false },
            name: { type: "string", required: false },
            team_type: { type: "string", required: false },
            agent_id: { type: "string", required: false },
            role: { type: "string", required: false },
            input: { type: "object", required: false }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "create_team" then create_team(params)
        when "add_team_member" then add_team_member(params)
        when "execute_team" then execute_team(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def create_team(params)
        team = account.ai_agent_teams.create!(
          name: params[:name],
          team_type: params[:team_type] || "sequential",
          status: "active"
        )
        { success: true, team_id: team.id, name: team.name }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def add_team_member(params)
        team = account.ai_agent_teams.find(params[:team_id])
        agent = account.ai_agents.find(params[:agent_id])
        member = team.members.create!(
          ai_agent: agent,
          role: params[:role] || "worker",
          status: "active"
        )
        { success: true, member_id: member.id }
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      end

      def execute_team(params)
        team = account.ai_agent_teams.find(params[:team_id])
        { success: true, team_id: team.id, status: "execution_queued", message: "Team execution queued" }
      rescue ActiveRecord::RecordNotFound
        { success: false, error: "Team not found" }
      end
    end
  end
end
