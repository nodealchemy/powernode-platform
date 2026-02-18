# frozen_string_literal: true

module Ai
  module SkillGraph
    class TraversalService
      SKILL_RELATION_TYPES = %w[requires enhances composes succeeds].freeze
      MAX_DEPTH = 3
      DEFAULT_TOKEN_BUDGET = 2000
      SEED_DISTANCE_THRESHOLD = 0.6
      DEPTH_PENALTY = 0.15
      CONTENT_BONUS = 0.1

      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Dual-mode traversal entry point
      def traverse(task_context: nil, agent: nil, mode: :auto, token_budget: DEFAULT_TOKEN_BUDGET)
        case mode.to_sym
        when :auto
          auto_traverse(task_context: task_context, token_budget: token_budget)
        when :manifest
          manifest_traverse(agent: agent)
        else
          raise ArgumentError, "Unknown traversal mode: #{mode}. Use :auto or :manifest"
        end
      end

      private

      # Auto-traverse: embedding-seeded expansion for task context
      def auto_traverse(task_context:, token_budget:)
        return empty_auto_result("No task context provided") if task_context.blank?

        # Generate embedding from task context
        embedding = embedding_service.generate(task_context)

        # Find seed skill nodes via pgvector
        seeds = if embedding.present?
          find_seed_nodes(embedding)
        else
          keyword_fallback(task_context)
        end

        return empty_auto_result("No relevant skills found") if seeds.empty?

        # Expand via graph neighbors
        discovered = expand_seeds(seeds, token_budget)

        {
          discovered_skills: discovered,
          paths: build_paths(seeds, discovered),
          seed_count: seeds.size,
          token_estimate: estimate_tokens(discovered)
        }
      end

      # Manifest: agent skill adjacency map
      def manifest_traverse(agent:)
        return empty_manifest_result("No agent provided") if agent.nil?

        skills = agent.skills.active
        return empty_manifest_result("Agent has no active skills") if skills.empty?

        navigation_map = {}
        total_skill_nodes = 0

        skills.each do |skill|
          node = skill.knowledge_graph_node
          next unless node&.status == "active"

          total_skill_nodes += 1
          neighbors = graph_service.find_neighbors(
            node: node,
            depth: 2,
            relation_types: SKILL_RELATION_TYPES
          )

          # Only include skill-type neighbors
          skill_neighbors = neighbors.select { |n| n[:entity_type] == "skill" }

          navigation_map[skill.name] = {
            skill_id: skill.id,
            node_id: node.id,
            category: skill.category,
            adjacent_skills: skill_neighbors.map do |n|
              {
                name: n[:name],
                node_id: n[:id],
                depth: n[:depth],
                confidence: n[:confidence]
              }
            end
          }
        end

        recommendations = generate_recommendations(navigation_map)

        {
          navigation_map: navigation_map,
          recommendations: recommendations,
          total_skill_nodes: total_skill_nodes
        }
      end

      def find_seed_nodes(embedding)
        candidates = account.ai_knowledge_graph_nodes
          .skill_nodes
          .active
          .with_embeddings
          .nearest_neighbors(:embedding, embedding, distance: "cosine")
          .first(10)

        # Filter by distance threshold in Ruby (neighbor_distance is virtual)
        candidates.select { |c| c.neighbor_distance <= SEED_DISTANCE_THRESHOLD }
      end

      def keyword_fallback(task_context)
        keywords = task_context.split(/\s+/).select { |w| w.length > 3 }.first(5)
        return [] if keywords.empty?

        nodes = account.ai_knowledge_graph_nodes.skill_nodes.active
        results = []

        keywords.each do |keyword|
          matches = nodes.search_by_name(keyword).limit(3)
          results.concat(matches.to_a)
        end

        results.uniq(&:id)
      end

      def expand_seeds(seeds, token_budget)
        discovered = {}
        tokens_used = 0

        # Score and add seeds first
        seeds.each do |seed|
          similarity = seed.respond_to?(:neighbor_distance) ? (1.0 - seed.neighbor_distance) : 0.8
          score = similarity

          skill = Ai::Skill.find_by(id: seed.ai_skill_id)
          next unless skill

          entry = build_skill_entry(skill, seed, score, 0)
          entry_tokens = estimate_entry_tokens(entry)
          break if tokens_used + entry_tokens > token_budget

          discovered[seed.id] = entry
          tokens_used += entry_tokens
        end

        # Expand each seed via neighbors
        seeds.each do |seed|
          break if tokens_used >= token_budget

          neighbors = graph_service.find_neighbors(
            node: seed,
            depth: MAX_DEPTH,
            relation_types: SKILL_RELATION_TYPES
          )

          neighbors.each do |neighbor|
            break if tokens_used >= token_budget
            next if discovered.key?(neighbor[:id])
            next unless neighbor[:entity_type] == "skill"

            # Score: seed_similarity × depth_penalty + content_bonus
            seed_similarity = seed.respond_to?(:neighbor_distance) ? (1.0 - seed.neighbor_distance) : 0.8
            depth = neighbor[:depth] || 1
            score = seed_similarity * (1.0 - DEPTH_PENALTY * depth)

            # Content bonus if neighbor has description
            score += CONTENT_BONUS if neighbor[:description].present?

            node_record = account.ai_knowledge_graph_nodes.find_by(id: neighbor[:id])
            skill = Ai::Skill.find_by(id: node_record&.ai_skill_id)
            next unless skill

            entry = build_skill_entry(skill, node_record, score, depth)
            entry_tokens = estimate_entry_tokens(entry)
            break if tokens_used + entry_tokens > token_budget

            discovered[neighbor[:id]] = entry
            tokens_used += entry_tokens
          end
        end

        # Return sorted by score desc
        discovered.values.sort_by { |e| -e[:score] }
      end

      def build_skill_entry(skill, node, score, depth)
        {
          skill_id: skill.id,
          node_id: node.id,
          name: skill.name,
          category: skill.category,
          description: skill.description,
          system_prompt: skill.system_prompt,
          score: score.round(4),
          depth: depth,
          tags: skill.tags
        }
      end

      def build_paths(seeds, discovered)
        seeds.map do |seed|
          {
            seed_node_id: seed.id,
            seed_name: seed.name,
            expanded_to: discovered.count { |d| d[:depth].positive? }
          }
        end
      end

      def estimate_entry_tokens(entry)
        text = "#{entry[:name]} #{entry[:category]} #{entry[:description]} #{entry[:system_prompt]}"
        (text.to_s.length / 4.0).ceil
      end

      def estimate_tokens(discovered)
        discovered.sum { |d| estimate_entry_tokens(d) }
      end

      def generate_recommendations(navigation_map)
        recs = []

        # Find isolated skills (no adjacent skills)
        navigation_map.each do |name, data|
          if data[:adjacent_skills].empty?
            recs << { type: "isolated_skill", skill: name, message: "#{name} has no skill graph connections — consider linking related skills" }
          end
        end

        # Find highly connected skills
        navigation_map.each do |name, data|
          if data[:adjacent_skills].size >= 5
            recs << { type: "hub_skill", skill: name, message: "#{name} is a hub with #{data[:adjacent_skills].size} connections" }
          end
        end

        recs
      end

      def empty_auto_result(reason)
        { discovered_skills: [], paths: [], seed_count: 0, token_estimate: 0, message: reason }
      end

      def empty_manifest_result(reason)
        { navigation_map: {}, recommendations: [], total_skill_nodes: 0, message: reason }
      end

      def graph_service
        @graph_service ||= Ai::KnowledgeGraph::GraphService.new(account)
      end

      def embedding_service
        @embedding_service ||= Ai::Memory::EmbeddingService.new(account: account)
      end
    end
  end
end
