# frozen_string_literal: true

module Ai
  module Discovery
    class TaskAnalyzerService
      CAPABILITY_KEYWORDS = {
        "code_review" => %w[review code lint quality],
        "testing" => %w[test spec qa validation],
        "deployment" => %w[deploy release rollout infrastructure],
        "data_analysis" => %w[data analysis report metrics],
        "security" => %w[security audit vulnerability scan],
        "documentation" => %w[document readme guide api],
        "monitoring" => %w[monitor alert health observe],
        "devops" => %w[docker swarm container pipeline ci cd]
      }.freeze

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Analyze a task description and identify required capabilities
      def analyze(task_description)
        required_capabilities = identify_capabilities(task_description)
        available_agents = Ai::Agent.where(account: account)

        team_recommendation = recommend_team(required_capabilities, available_agents)

        {
          task_description: task_description,
          required_capabilities: required_capabilities,
          recommendation: team_recommendation,
          confidence: calculate_confidence(required_capabilities, team_recommendation)
        }
      end

      # Recommend a team composition for given capabilities
      def recommend_team(required_capabilities, available_agents)
        recommended = []

        required_capabilities.each do |capability|
          matching_agents = find_agents_for_capability(capability, available_agents)

          if matching_agents.any?
            best = matching_agents.first
            recommended << {
              capability: capability,
              agent_id: best.id,
              agent_name: best.name,
              match_score: score_agent_for_capability(best, capability)
            }
          else
            recommended << {
              capability: capability,
              agent_id: nil,
              agent_name: nil,
              match_score: 0,
              gap: true
            }
          end
        end

        recommended
      end

      # Identify skill gaps for an existing team
      def skill_gap_analysis(team, task_description)
        required = identify_capabilities(task_description)
        team_members = team.ai_agent_team_members.includes(:ai_agent)
        team_capabilities = extract_team_capabilities(team_members)

        covered = required.select { |cap| team_capabilities.include?(cap) }
        gaps = required - covered
        redundant = team_capabilities - required

        {
          required_capabilities: required,
          covered_capabilities: covered,
          gaps: gaps,
          redundant_capabilities: redundant,
          coverage_score: required.any? ? (covered.size.to_f / required.size).round(2) : 1.0,
          recommendations: build_gap_recommendations(gaps, redundant)
        }
      end

      # Analyze historical task patterns for recommendations
      def analyze_history
        recent_tasks = Ai::TeamTask.joins(:team_execution)
                                    .where(ai_team_executions: { account_id: account.id })
                                    .where("ai_team_tasks.created_at > ?", 30.days.ago)
                                    .limit(100)

        task_types = recent_tasks.group(:task_type).count
        failure_rate = calculate_failure_rate(recent_tasks)

        recommendations = []

        if failure_rate > 0.2
          recommendations << {
            type: "add_reviewer",
            reason: "High task failure rate (#{(failure_rate * 100).round(1)}%)",
            priority: "high"
          }
        end

        if task_types.keys.size > 5
          recommendations << {
            type: "specialize_teams",
            reason: "Many task types detected - consider specialized teams",
            priority: "medium"
          }
        end

        { recommendations: recommendations, task_stats: { types: task_types, failure_rate: failure_rate } }
      end

      private

      def identify_capabilities(text)
        return [] if text.blank?

        normalized = text.downcase
        capabilities = []

        CAPABILITY_KEYWORDS.each do |capability, keywords|
          if keywords.any? { |kw| normalized.include?(kw) }
            capabilities << capability
          end
        end

        # Graph-based capability resolution
        begin
          if account.ai_knowledge_graph_nodes.active.skill_nodes.exists?
            traversal = Ai::SkillGraph::TraversalService.new(account).traverse(
              task_context: text, mode: :auto, token_budget: 1000
            )
            graph_skills = (traversal[:discovered_skills] || []).map { |s| s[:slug] || s[:name] }.compact
            capabilities.concat(graph_skills)
          end
        rescue => e
          Rails.logger.warn "[TaskAnalyzer] Graph-based capability resolution failed: #{e.message}"
        end

        capabilities.uniq.presence || ["general"]
      end

      def find_agents_for_capability(capability, agents)
        agents.select do |agent|
          score_agent_for_capability(agent, capability) > 0
        end.sort_by { |a| -score_agent_for_capability(a, capability) }
      end

      def score_agent_for_capability(agent, capability)
        score = 0
        keywords = CAPABILITY_KEYWORDS[capability] || [capability]
        agent_skills = extract_agent_skill_names(agent)

        keywords.each do |kw|
          score += 1 if agent_skills.any? { |s| s.include?(kw) }
        end

        score += 0.5 if agent.name.downcase.include?(capability.gsub("_", " "))

        # Graph distance scoring boost
        begin
          cap_skill = Ai::Skill.for_account(account.id).active.find_by(slug: capability)
          cap_node = cap_skill&.knowledge_graph_node
          if cap_node&.status == "active"
            agent_skill_slugs = agent_skills
            agent_skill_records = Ai::Skill.for_account(account.id).active.where(slug: agent_skill_slugs)
            agent_skill_records.each do |s|
              skill_node = s.knowledge_graph_node
              next unless skill_node&.status == "active"
              path = Ai::KnowledgeGraph::GraphService.new(account).shortest_path(
                source: skill_node, target: cap_node
              )
              if path && path[:distance].to_i > 0
                score += 1.0 / (1 + path[:distance])
              end
            end
          end
        rescue => e
          Rails.logger.warn "[TaskAnalyzer] Graph distance scoring failed: #{e.message}"
        end

        score.round(2)
      end

      def extract_agent_skill_names(agent)
        return [] unless agent.respond_to?(:ai_agent_skills)

        agent.ai_agent_skills.pluck(:name).map(&:downcase)
      rescue StandardError
        []
      end

      def extract_team_capabilities(team_members)
        capabilities = []

        team_members.each do |member|
          agent = member.ai_agent
          next unless agent

          skills = extract_agent_skill_names(agent)
          CAPABILITY_KEYWORDS.each do |capability, keywords|
            if keywords.any? { |kw| skills.any? { |s| s.include?(kw) } }
              capabilities << capability
            end
          end
        end

        capabilities.uniq
      end

      def calculate_confidence(capabilities, recommendation)
        return 0 if recommendation.empty?

        filled = recommendation.count { |r| r[:agent_id].present? }
        (filled.to_f / recommendation.size).round(2)
      end

      def calculate_failure_rate(tasks)
        return 0 if tasks.empty?

        failed = tasks.where(status: "failed").count
        (failed.to_f / tasks.count).round(2)
      end

      def build_gap_recommendations(gaps, redundant)
        recs = []

        gaps.each do |gap|
          nearest = find_nearest_skill_via_graph(gap)
          reason = "No agent covers #{gap}"
          reason += " (nearest available: #{nearest})" if nearest
          recs << { action: "add_agent", capability: gap, reason: reason }
        end

        if redundant.size > 2
          recs << { action: "trim_team", capabilities: redundant, reason: "Redundant capabilities detected" }
        end

        recs
      end

      def find_nearest_skill_via_graph(capability_slug)
        cap_skill = Ai::Skill.for_account(account.id).active.find_by(slug: capability_slug)
        cap_node = cap_skill&.knowledge_graph_node
        return nil unless cap_node&.status == "active"

        neighbors = Ai::KnowledgeGraph::GraphService.new(account).find_neighbors(
          node: cap_node, depth: 1, relation_types: %w[requires related_to]
        )
        neighbors.first&.dig(:name)
      rescue => e
        Rails.logger.warn "[TaskAnalyzer] Nearest skill graph lookup failed: #{e.message}"
        nil
      end
    end
  end
end
