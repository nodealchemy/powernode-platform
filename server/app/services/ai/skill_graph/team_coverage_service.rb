# frozen_string_literal: true

module Ai
  module SkillGraph
    class TeamCoverageService
      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Map team agents' skills to KG nodes → coverage metrics
      def analyze_coverage(team)
        team_skills = collect_team_skills(team)
        all_skill_nodes = account.ai_knowledge_graph_nodes.skill_nodes.active

        total_skill_count = all_skill_nodes.count
        covered_node_ids = team_skills.filter_map { |s| s[:node_id] }
        coverage_ratio = total_skill_count.positive? ? (covered_node_ids.uniq.size.to_f / total_skill_count).round(4) : 0.0

        # Category breakdown
        category_breakdown = build_category_breakdown(team_skills, all_skill_nodes)

        # Connectivity score — how well connected are the team's skill nodes
        connectivity_score = calculate_connectivity(covered_node_ids)

        # Uncovered skills
        uncovered = all_skill_nodes.where.not(id: covered_node_ids).map do |node|
          { node_id: node.id, name: node.name, skill_id: node.ai_skill_id, category: node.properties&.dig("category") }
        end

        {
          team_id: team.id,
          team_name: team.name,
          total_skills: total_skill_count,
          covered_skills: covered_node_ids.uniq.size,
          coverage_ratio: coverage_ratio,
          category_breakdown: category_breakdown,
          connectivity_score: connectivity_score,
          uncovered_skills: uncovered,
          agent_skill_map: team_skills.group_by { |s| s[:agent_name] }
        }
      end

      # Auto-traverse for task → compare needed vs team skills → gaps
      def find_task_gaps(team, task_context:)
        # Get needed skills from traversal
        traversal = traversal_service.traverse(task_context: task_context, mode: :auto)
        needed_skills = traversal[:discovered_skills]

        # Get team's current skills
        team_skills = collect_team_skills(team)
        team_skill_ids = team_skills.map { |s| s[:skill_id] }.compact.uniq

        # Find gaps
        gaps = needed_skills.reject { |s| team_skill_ids.include?(s[:skill_id]) }
        covered = needed_skills.select { |s| team_skill_ids.include?(s[:skill_id]) }

        {
          team_id: team.id,
          needed_skills: needed_skills.size,
          covered_count: covered.size,
          gap_count: gaps.size,
          gaps: gaps.map { |g| { skill_id: g[:skill_id], name: g[:name], category: g[:category], relevance: g[:score] } },
          covered: covered.map { |c| { skill_id: c[:skill_id], name: c[:name], category: c[:category] } }
        }
      end

      # Find agents NOT in team that cover gap skills
      def suggest_agents_for_gaps(team, task_context:)
        gap_result = find_task_gaps(team, task_context: task_context)
        gap_skill_ids = gap_result[:gaps].map { |g| g[:skill_id] }.compact

        return { suggestions: [], gap_count: 0 } if gap_skill_ids.empty?

        team_agent_ids = team.members.pluck(:ai_agent_id)

        # Find agents with these skills who are NOT in the team
        candidates = Ai::AgentSkill
          .where(ai_skill_id: gap_skill_ids)
          .where.not(ai_agent_id: team_agent_ids)
          .includes(:agent, :skill)

        # Group by agent, count how many gaps each covers
        agent_scores = {}
        candidates.each do |as|
          agent = as.agent
          next unless agent&.status == "active"

          agent_scores[agent.id] ||= {
            agent_id: agent.id,
            agent_name: agent.name,
            covers_skills: [],
            gap_coverage: 0
          }
          agent_scores[agent.id][:covers_skills] << { skill_id: as.ai_skill_id, skill_name: as.skill&.name }
          agent_scores[agent.id][:gap_coverage] += 1
        end

        suggestions = agent_scores.values.sort_by { |a| -a[:gap_coverage] }

        {
          suggestions: suggestions,
          gap_count: gap_skill_ids.size,
          gaps: gap_result[:gaps]
        }
      end

      # Greedy set-cover: compose a team suggestion from scratch
      def compose_team_suggestion(task_context:, max_members: 5)
        traversal = traversal_service.traverse(task_context: task_context, mode: :auto)
        needed_skills = traversal[:discovered_skills]
        needed_skill_ids = needed_skills.map { |s| s[:skill_id] }.compact.uniq

        return { members: [], uncovered: needed_skill_ids } if needed_skill_ids.empty?

        # Build agent → skill coverage map
        coverage_map = {}
        Ai::AgentSkill
          .where(ai_skill_id: needed_skill_ids)
          .includes(:agent)
          .each do |as|
            agent = as.agent
            next unless agent&.status == "active"

            coverage_map[agent.id] ||= { agent: agent, skill_ids: Set.new }
            coverage_map[agent.id][:skill_ids] << as.ai_skill_id
          end

        # Greedy set-cover
        selected = []
        remaining = needed_skill_ids.to_set

        max_members.times do
          break if remaining.empty?

          # Pick agent covering most remaining skills
          best = coverage_map.max_by { |_id, data| (data[:skill_ids] & remaining).size }
          break unless best

          agent_id, data = best
          covered = data[:skill_ids] & remaining
          break if covered.empty?

          selected << {
            agent_id: data[:agent].id,
            agent_name: data[:agent].name,
            covers: covered.to_a,
            covers_count: covered.size
          }

          remaining -= covered
          coverage_map.delete(agent_id)
        end

        {
          members: selected,
          total_needed: needed_skill_ids.size,
          total_covered: needed_skill_ids.size - remaining.size,
          uncovered_skill_ids: remaining.to_a
        }
      end

      private

      def collect_team_skills(team)
        team.members.includes(agent: :skills).flat_map do |member|
          member.agent.skills.active.map do |skill|
            node = skill.knowledge_graph_node
            {
              agent_id: member.ai_agent_id,
              agent_name: member.agent.name,
              skill_id: skill.id,
              skill_name: skill.name,
              category: skill.category,
              node_id: node&.id
            }
          end
        end
      end

      def build_category_breakdown(team_skills, all_skill_nodes)
        all_categories = all_skill_nodes.joins("LEFT JOIN ai_skills ON ai_skills.id = ai_knowledge_graph_nodes.ai_skill_id")
          .where.not("ai_skills.category": nil)
          .group("ai_skills.category")
          .count

        team_categories = team_skills.group_by { |s| s[:category] }.transform_values(&:size)

        all_categories.map do |category, total|
          covered = team_categories[category] || 0
          {
            category: category,
            total: total,
            covered: covered,
            ratio: total.positive? ? (covered.to_f / total).round(4) : 0.0
          }
        end
      end

      def calculate_connectivity(node_ids)
        return 0.0 if node_ids.size < 2

        # Count edges between covered nodes
        edge_count = account.ai_knowledge_graph_edges
          .active
          .skill_relations
          .where(source_node_id: node_ids, target_node_id: node_ids)
          .count

        # Max possible edges
        n = node_ids.uniq.size
        max_edges = n * (n - 1)
        return 0.0 if max_edges.zero?

        (edge_count.to_f / max_edges).round(4)
      end

      def traversal_service
        @traversal_service ||= Ai::SkillGraph::TraversalService.new(account)
      end
    end
  end
end
