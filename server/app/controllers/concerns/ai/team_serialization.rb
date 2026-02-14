# frozen_string_literal: true

module Ai
  module TeamSerialization
    extend ActiveSupport::Concern

    private

    def serialize_team(team)
      {
        id: team.id,
        name: team.name,
        description: team.description,
        team_type: team.team_type,
        coordination_strategy: team.coordination_strategy,
        status: team.status,
        member_count: team.members.count,
        has_lead: team.has_lead?,
        created_at: team.created_at,
        updated_at: team.updated_at
      }
    end

    def serialize_team_detail(team)
      serialize_team(team).merge(
        team_config: team.team_config,
        members: team.members.order(:priority_order).map { |m| serialize_member(m) },
        stats: team.team_stats
      )
    end

    def serialize_member(member)
      {
        id: member.id,
        agent_id: member.ai_agent_id,
        agent_name: member.ai_agent_name,
        role: member.role,
        capabilities: member.capabilities,
        priority_order: member.priority_order,
        is_lead: member.is_lead,
        created_at: member.created_at
      }
    end
  end
end
