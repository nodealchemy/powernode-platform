# frozen_string_literal: true

module Ai
  module Teams
    class ConfigurationService
      module TeamAnalysis
        extend ActiveSupport::Concern

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
end
