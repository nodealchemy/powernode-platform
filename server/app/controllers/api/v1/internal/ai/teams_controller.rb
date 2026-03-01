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

          # POST /api/v1/internal/ai/teams/:team_id/execute_strategy
          def execute_strategy
            team = ::Ai::AgentTeam.includes(members: :agent).find(params[:team_id])
            execution_id = params[:execution_id]
            input = params[:input]&.to_unsafe_h || {}
            context = params[:context]&.to_unsafe_h || {}

            execution = team.team_executions.find(execution_id) if execution_id.present?

            # Build and execute strategy
            strategy = ::Ai::TeamStrategies::StrategyFactory.build(
              team: team, execution: execution, account: team.account
            )

            results = strategy.execute(input: input)

            # Complete the execution with results
            if execution
              last_output = results[:outputs]&.last
              execution.update!(
                status: "completed",
                completed_at: Time.current,
                output_result: {
                  response: last_output&.dig(:output),
                  tasks_completed: results[:tasks_completed],
                  tasks_failed: results[:tasks_failed],
                  total_cost: results[:total_cost],
                  total_tokens: results[:total_tokens],
                  all_outputs: results[:outputs]
                },
                total_cost_usd: results[:total_cost],
                duration_ms: execution.started_at ? ((Time.current - execution.started_at) * 1000).to_i : 0
              )
            end

            render_success(results)
          rescue ActiveRecord::RecordNotFound
            render_not_found("Agent Team or Execution")
          rescue StandardError => e
            Rails.logger.error "[TeamsController] Strategy execution failed: #{e.message}"
            render_error("Strategy execution failed: #{e.message}", status: :unprocessable_entity)
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
