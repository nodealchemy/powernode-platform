# frozen_string_literal: true

module Ai
  module SkillGraph
    class TraversalService
      SKILL_RELATION_TYPES = %w[requires enhances composes succeeds refines].freeze
      MAX_DEPTH = 3
      DEFAULT_TOKEN_BUDGET = 2000
      SEED_DISTANCE_THRESHOLD = 0.6
      DEPTH_PENALTY = 0.15
      CONTENT_BONUS = 0.1

      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Dual-mode traversal entry point.
      #
      # Optional selection facets (auto mode only), both read off a capability
      # skill's contract metadata (Ai::Skills::Contract):
      #   project_kind: keep only skills whose triggers.applies_to lists it or
      #                 "any" — so a skill for this platform's own repository is
      #                 not picked for a user's project, and vice versa.
      #   domains:      keep only skills in these domains (an agent's ceiling).
      # A skill that declares no facet (legacy) passes both filters.
      def traverse(task_context: nil, agent: nil, mode: :auto, token_budget: DEFAULT_TOKEN_BUDGET,
                   project_kind: nil, domains: nil)
        case mode.to_sym
        when :auto
          @facet_filter = { project_kind: project_kind.presence&.to_s, domains: Array(domains).map(&:to_s).presence }
          auto_traverse(task_context: task_context, agent: agent, token_budget: token_budget)
        when :manifest
          manifest_traverse(agent: agent)
        else
          raise ArgumentError, "Unknown traversal mode: #{mode}. Use :auto or :manifest"
        end
      end

      private

      # Auto-traverse: embedding-seeded expansion for task context
      def auto_traverse(task_context:, agent:, token_budget:)
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

        # Skills already attached to this agent are already fully embedded in its
        # system prompt (Ai::Agent#build_skill_system_prompts) — exclude them here
        # so the same skill's system_prompt isn't injected a second time via
        # ContextEnrichmentService#format_auto_context.
        excluded_skill_ids = attached_skill_ids(agent)

        # Expand via graph neighbors
        discovered = expand_seeds(seeds, token_budget, excluded_skill_ids)

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
          node = skill.knowledge_graph_node_for(account.id)
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

      # Skill ids already embedded verbatim in the agent's system prompt via
      # Ai::Agent#build_skill_system_prompts. Mirrors that method's predicate
      # (active join + active/enabled skill) so we only exclude skills that are
      # actually present in the system prompt, not merely attached.
      def attached_skill_ids(agent)
        return [] if agent.nil?

        agent.agent_skills.where(is_active: true)
          .joins(:skill)
          .where(ai_skills: { status: "active", is_enabled: true })
          .pluck(:ai_skill_id)
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

      def expand_seeds(seeds, token_budget, excluded_skill_ids = [])
        discovered = {}
        tokens_used = 0

        # Score and add seeds first
        seeds.each do |seed|
          nd = seed.respond_to?(:neighbor_distance) ? seed.neighbor_distance : nil
          similarity = nd ? (1.0 - nd) : 0.8
          score = similarity

          skill = Ai::Skill.find_by(id: seed.ai_skill_id)
          next unless selectable?(skill)
          next if excluded_skill_ids.include?(skill.id)

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

            # A skill reached THROUGH a seed never outranks that seed: with
            # requires/composes/refines edges seeded, the content bonus let a
            # depth-1 neighbour (0.85·s + 0.1) beat the matching skill itself
            # whenever s < 0.67, so the graph re-ordered what the task matched.
            score = [ score, seed_similarity - (0.001 * depth) ].min

            node_record = account.ai_knowledge_graph_nodes.find_by(id: neighbor[:id])
            skill = Ai::Skill.find_by(id: node_record&.ai_skill_id)
            next unless selectable?(skill)
            next if excluded_skill_ids.include?(skill.id)
            next unless expandable_refinement?(skill)

            entry = build_skill_entry(skill, node_record, score, depth)
            entry_tokens = estimate_entry_tokens(entry)
            break if tokens_used + entry_tokens > token_budget

            discovered[neighbor[:id]] = entry
            tokens_used += entry_tokens
          end
        end

        # Return sorted by score desc, one side of each refinement pair only.
        ranked = discovered.values.sort_by { |e| -e[:score] }
        metadata = Ai::Skill.where(id: ranked.map { |e| e[:skill_id] }).pluck(:id, :metadata).to_h
        ::Ai::Skills::SelectionFacets.resolve_refinements(ranked, (@facet_filter || {})[:project_kind]) do |entry|
          [ entry[:slug], metadata[entry[:skill_id]] ]
        end
      end

      # A KG node can outlive its skill's eligibility (a disabled or retired row
      # keeps its node until the next prune), so selection re-checks the row.
      def selectable?(skill)
        return false unless skill && skill.status == "active" && skill.is_enabled

        facets_match?(skill)
      end

      # Graph neighbours are found in both directions, so a generic parent seed
      # would otherwise pull in every child that `refines` it — e.g. a
      # repository-specific refinement surfacing for a customer's task. A
      # refining child is pulled THROUGH the graph only when the caller named a
      # project kind the child applies to; it can still be matched directly.
      def expandable_refinement?(skill)
        meta = skill.metadata.is_a?(Hash) ? skill.metadata : {}
        return true if Array(meta.dig("relations", "refines")).empty?

        kind = (@facet_filter || {})[:project_kind]
        return false if kind.nil?

        ::Ai::Skills::SelectionFacets.applies?(meta, kind)
      end

      def facets_match?(skill)
        filter = @facet_filter || {}
        meta = skill.metadata.is_a?(Hash) ? skill.metadata : {}
        return true unless ::Ai::Skills::Contract.applies_to?(meta)

        if filter[:domains] && !filter[:domains].include?(meta["domain"].to_s)
          return false
        end
        ::Ai::Skills::SelectionFacets.applies?(meta, filter[:project_kind])
      end

      def build_skill_entry(skill, node, score, depth)
        {
          skill_id: skill.id,
          node_id: node.id,
          # IMP-702d27f2d384 — discover_skills was the one MCP-facing surface
          # that dropped the slug entirely, so a caller who found a skill
          # here had no natural-key way to invoke get_skill on it. inputs /
          # requires_approval close the same finding's other half: a
          # third-party client picking a skill off this list previously had
          # no machine-readable way to know what to pass it or whether the
          # call gates on approval — both derived live off the executor (see
          # Ai::Skill#executor_input_contract / #executor_requires_approval?)
          # so they can't drift from what the executor actually accepts.
          slug: skill.slug,
          name: skill.name,
          category: skill.category,
          description: skill.description,
          system_prompt: skill.system_prompt,
          score: score.round(4),
          depth: depth,
          tags: skill.tags,
          inputs: skill.executor_input_contract,
          requires_approval: skill.executor_requires_approval?
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
