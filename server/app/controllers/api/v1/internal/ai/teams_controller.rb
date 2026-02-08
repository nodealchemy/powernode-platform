# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Ai
        class TeamsController < InternalBaseController
          # GET /api/v1/internal/ai/teams/:team_id
          def show
            team = ::Ai::AgentTeam.includes(members: :agent).find(params[:team_id])
            render_success({
              id: team.id,
              name: team.name,
              team_type: team.team_type,
              coordination_strategy: team.coordination_strategy,
              status: team.status,
              team_config: team.team_config,
              members: team.members.order(:priority_order).map { |m|
                {
                  id: m.id,
                  agent_id: m.ai_agent_id,
                  agent_name: m.ai_agent_name,
                  role: m.role,
                  capabilities: m.capabilities,
                  priority_order: m.priority_order,
                  is_lead: m.is_lead
                }
              }
            })
          rescue ActiveRecord::RecordNotFound
            render_not_found("Agent Team")
          end

          # GET /api/v1/internal/ai/agents
          def agents
            account = Account.find(params[:account_id])
            agents = account.ai_agents.map do |a|
              { id: a.id, name: a.name, capabilities: a.capabilities, status: a.status }
            end
            render_success(agents)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Account")
          end

          # POST /api/v1/internal/ai/teams/:team_id/optimization_results
          def optimization_results
            team = ::Ai::AgentTeam.find(params[:team_id])
            team.update!(
              team_config: team.team_config.merge(
                "last_optimization" => {
                  "recommendations" => params[:recommendations],
                  "optimized_at" => Time.current.iso8601,
                  "skill_coverage" => params[:skill_coverage],
                  "gaps" => params[:gaps]
                }
              )
            )

            render_success({ message: "Optimization results saved" })
          rescue ActiveRecord::RecordNotFound
            render_not_found("Agent Team")
          end
        end
      end
    end
  end
end
