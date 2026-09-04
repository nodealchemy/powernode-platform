# frozen_string_literal: true

module Ai
  module TeamSerialization
    extend ActiveSupport::Concern

    private

    def serialize_team(team)
      {
        id: team.id,
        account_id: team.account_id,
        name: team.name,
        description: team.description,
        team_type: team.team_type,
        coordination_strategy: team.coordination_strategy,
        status: team.status,
        member_count: team.members.count,
        has_lead: team.has_lead?,
        canonical: team.canonical?,
        template_id: team.template_id,
        created_at: team.created_at,
        updated_at: team.updated_at
      }
    end

    def serialize_team_detail(team)
      members = team.members
                    .order(:priority_order)
                    .includes(agent: :provider)
      serialize_team(team).merge(
        team_config: team.team_config,
        members: members.map { |m| serialize_member(m) },
        stats: team.team_stats
      )
    end

    def serialize_member(member)
      agent = member.agent
      base = {
        id: member.id,
        agent_id: member.ai_agent_id,
        agent_name: member.ai_agent_name,
        agent_slug: agent&.slug,
        agent_type: agent&.agent_type,
        agent_model: agent&.model,
        agent_provider: agent&.provider&.provider_type,
        role: member.role,
        capabilities: member.capabilities,
        priority_order: member.priority_order,
        is_lead: member.is_lead,
        created_at: member.created_at
      }

      # Surface model selection rationale (T3 — set by ConciergeService when
      # an agent is materialized from a designer-produced team spec).
      sel = agent&.mcp_metadata&.dig("model_selection")
      if sel.is_a?(Hash)
        base[:model_selection] = {
          provider_type: sel["provider_type"],
          model:         sel["model"],
          reason:        sel["reason"],
          selected_at:   sel["selected_at"]
        }.compact
      end

      # Empirical performance row keyed by this agent's (provider, model,
      # agent_type) tuple — populated by AgentExecution#record_model_performance.
      if agent && agent.ai_provider_id.present? && agent.model.present? && agent.agent_type.present?
        perf = ::Ai::AgentModelPerformance.find_by(
          account_id:     agent.account_id,
          ai_provider_id: agent.ai_provider_id,
          model:          agent.model,
          agent_type:     agent.agent_type
        )
        if perf
          base[:model_performance] = {
            total_runs:       perf.total_runs,
            successful_runs:  perf.successful_runs,
            failed_runs:      perf.failed_runs,
            success_rate:     perf.success_rate,
            avg_cost_usd:     perf.avg_cost_usd,
            avg_duration_ms:  perf.avg_duration_ms,
            last_run_at:      perf.last_run_at
          }
        end
      end

      base
    end
  end
end
