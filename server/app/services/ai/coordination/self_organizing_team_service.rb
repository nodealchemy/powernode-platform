# frozen_string_literal: true

module Ai
  module Coordination
    class SelfOrganizingTeamService
      LEADERSHIP_WEIGHTS = {
        success_rate: 0.30,
        trust: 0.25,
        peer_signals: 0.20,
        capability_breadth: 0.15,
        speed: 0.10
      }.freeze

      def initialize(account:)
        @account = account
      end

      def detect_capability_gap(team:, task_requirements:)
        team_capabilities = team.members.includes(:agent).flat_map do |m|
          (m.capabilities || []) + (m.agent.capabilities || [])
        end.uniq

        required = task_requirements.is_a?(Array) ? task_requirements : [task_requirements]
        missing = required - team_capabilities

        { missing_capabilities: missing, team_capabilities: team_capabilities, gap_detected: missing.any? }
      end

      def recruit_member!(team:, capability:, pool_scope: nil)
        # Find best-fit idle agent with the required capability
        scope = Ai::Agent.where(account: @account, status: "active")
        scope = scope.where("capabilities @> ?", [capability].to_json) if capability.present?

        # Exclude agents already on this team
        existing_ids = team.members.pluck(:ai_agent_id)
        scope = scope.where.not(id: existing_ids)

        candidate = scope.order(Arel.sql("RANDOM()")).first
        return { recruited: false, reason: "no_suitable_agent" } unless candidate

        member = team.members.create!(
          agent: candidate,
          role: "specialist",
          is_dynamic: true,
          recruited_at: Time.current,
          capabilities: [capability],
          member_config: { recruited_for: capability }
        )

        Ai::TeamRestructureEvent.create!(
          account: @account,
          team: team,
          agent: candidate,
          event_type: "member_recruited",
          new_state: { role: "specialist", capability: capability },
          rationale: { reason: "capability_gap", capability: capability }
        )

        { recruited: true, member_id: member.id, agent_id: candidate.id, agent_name: candidate.name }
      end

      def release_member!(team:, member:, reason:)
        member.update!(released_at: Time.current)

        Ai::TeamRestructureEvent.create!(
          account: @account,
          team: team,
          agent: member.agent,
          event_type: "member_released",
          previous_state: { role: member.role },
          rationale: { reason: reason }
        )

        { released: true, agent_id: member.ai_agent_id }
      end

      def reassign_role!(member:, new_role:, rationale:)
        old_role = member.role
        member.update!(role: new_role)

        Ai::TeamRestructureEvent.create!(
          account: @account,
          team: member.team,
          agent: member.agent,
          event_type: "role_change",
          previous_state: { role: old_role },
          new_state: { role: new_role },
          rationale: { reason: rationale }
        )

        { reassigned: true, old_role: old_role, new_role: new_role }
      end

      def evaluate_leader_emergence(team:)
        scores = team.members.includes(:agent).map do |member|
          agent = member.agent

          # Success rate from recent executions
          recent_execs = Ai::AgentExecution.where(ai_agent_id: agent.id).where("created_at >= ?", 30.days.ago)
          total = recent_execs.count
          succeeded = recent_execs.where(status: "completed").count
          success_rate = total.positive? ? succeeded.to_f / total : 0.0

          # Trust score
          trust = Ai::AgentTrustScore.find_by(agent_id: agent.id)
          trust_score = trust&.overall_score || 0.0

          # Peer signals (reinforcement count from stigmergic signals)
          peer_signals = Ai::StigmergicSignal.where(account: @account)
            .where("reinforcements @> ?", [{ "agent_id" => agent.id }].to_json)
            .count
          peer_score = [peer_signals / 10.0, 1.0].min

          # Capability breadth
          cap_count = (member.capabilities || []).size + (agent.capabilities || []).size
          capability_breadth = [cap_count / 10.0, 1.0].min

          # Speed (avg execution time, lower is better)
          avg_duration = recent_execs.where.not(duration_ms: nil).average(:duration_ms)&.to_f || 30_000
          speed = [1.0 - (avg_duration / 60_000.0), 0.0].max

          leadership_score = (
            success_rate * LEADERSHIP_WEIGHTS[:success_rate] +
            trust_score * LEADERSHIP_WEIGHTS[:trust] +
            peer_score * LEADERSHIP_WEIGHTS[:peer_signals] +
            capability_breadth * LEADERSHIP_WEIGHTS[:capability_breadth] +
            speed * LEADERSHIP_WEIGHTS[:speed]
          ).round(4)

          {
            member_id: member.id,
            agent_id: agent.id,
            agent_name: agent.name,
            leadership_score: leadership_score,
            breakdown: {
              success_rate: success_rate.round(3),
              trust: trust_score.round(3),
              peer_signals: peer_score.round(3),
              capability_breadth: capability_breadth.round(3),
              speed: speed.round(3)
            }
          }
        end

        scores.sort_by { |s| -s[:leadership_score] }
      end

      def optimize_team_composition!(team:)
        results = { gaps_detected: 0, recruited: 0, released: 0, reassigned: 0 }

        # Detect and fill capability gaps (if team has active task requirements)
        if team.respond_to?(:goal_description) && team.goal_description.present?
          # Simple extraction of requirements from goal description
          gap = detect_capability_gap(team: team, task_requirements: [])
          results[:gaps_detected] = gap[:missing_capabilities].size
        end

        # Evaluate leader emergence
        leader_scores = evaluate_leader_emergence(team: team)
        if leader_scores.any?
          top = leader_scores.first
          current_lead = team.members.find_by(is_lead: true)

          if current_lead && current_lead.id != top[:member_id] && top[:leadership_score] > 0.7
            # New leader emerged
            current_lead.update!(is_lead: false)
            new_lead_member = team.members.find(top[:member_id])
            new_lead_member.update!(is_lead: true)

            Ai::TeamRestructureEvent.create!(
              account: @account,
              team: team,
              agent: new_lead_member.agent,
              event_type: "leader_emerged",
              previous_state: { leader_agent_id: current_lead.ai_agent_id },
              new_state: { leader_agent_id: new_lead_member.ai_agent_id },
              rationale: { leadership_score: top[:leadership_score], breakdown: top[:breakdown] }
            )
            results[:reassigned] += 1
          end
        end

        results
      end
    end
  end
end
