# frozen_string_literal: true

module Ai
  module Codebase
    class ClusteringService
      MIN_K = 3
      MAX_K = 12
      MIN_NODES_FOR_CLUSTERING = 10
      MAX_CLUSTER_NODES = 500 # Sample limit to keep clustering fast

      def initialize(account:, knowledge_base:)
        @account = account
        @knowledge_base = knowledge_base
      end

      # Cluster code entities by semantic similarity.
      # Uses pgvector nearest-neighbor seeding + greedy assignment for speed.
      # @param entity_types [Array|nil] Filter to specific entity types
      # @param k [Integer|nil] Number of clusters (auto-selected if nil)
      # @return [Hash] Clusters with labels, members, and representatives
      def cluster(entity_types: nil, k: nil)
        total_count = count_nodes(entity_types)

        if total_count < MIN_NODES_FOR_CLUSTERING
          return {
            success: true,
            clusters: [],
            message: "Not enough nodes for clustering (#{total_count} < #{MIN_NODES_FOR_CLUSTERING})"
          }
        end

        # Sample nodes if too many (keep clustering fast)
        nodes = load_nodes(entity_types, limit: MAX_CLUSTER_NODES)
        return { success: true, clusters: [], message: "No nodes with embeddings" } if nodes.empty?

        target_k = k || auto_select_k(nodes.size)

        # Use pgvector-seeded clustering: pick k seed nodes spread apart,
        # then assign all nodes to nearest seed via SQL
        clusters = pgvector_cluster(nodes, target_k)

        {
          success: true,
          clusters: clusters,
          total_nodes: nodes.size,
          total_in_index: total_count,
          k: target_k
        }
      end

      private

      def count_nodes(entity_types)
        scope = @knowledge_base.knowledge_graph_nodes
                                .where(account: @account, node_type: "code_entity", status: "active")
                                .with_embeddings

        scope = scope.where(entity_type: entity_types) if entity_types.present?
        scope.count
      end

      def load_nodes(entity_types, limit:)
        scope = @knowledge_base.knowledge_graph_nodes
                                .where(account: @account, node_type: "code_entity", status: "active")
                                .with_embeddings

        scope = scope.where(entity_type: entity_types) if entity_types.present?

        # Sample by taking evenly spaced nodes ordered by name
        total = scope.count
        if total > limit
          # Use database-side sampling
          scope.order(:name).limit(limit).to_a
        else
          scope.order(:name).to_a
        end
      end

      def auto_select_k(n)
        k = Math.sqrt(n / 2.0).round
        k.clamp(MIN_K, MAX_K)
      end

      # Fast clustering using pgvector nearest-neighbor queries.
      # 1. Pick k seed nodes spread apart (greedy farthest-first)
      # 2. Assign each node to its nearest seed using pgvector cosine distance
      def pgvector_cluster(nodes, k)
        return [] if nodes.empty?

        # Step 1: Pick seed nodes using farthest-first traversal
        seeds = pick_seeds(nodes, k)

        # Step 2: Assign each node to nearest seed using pgvector
        assignments = {}
        seeds.each_with_index do |seed, cluster_id|
          assignments[seed.id] = cluster_id
        end

        # For each non-seed node, find which seed is closest
        node_ids = nodes.map(&:id)
        seed_ids = seeds.map(&:id)
        non_seed_ids = node_ids - seed_ids

        non_seed_nodes = nodes.select { |n| non_seed_ids.include?(n.id) }
        non_seed_nodes.each do |node|
          nearest_cluster = 0
          min_dist = Float::INFINITY

          seeds.each_with_index do |seed, idx|
            dist = cosine_distance_pgvector(node, seed)
            if dist < min_dist
              min_dist = dist
              nearest_cluster = idx
            end
          end

          assignments[node.id] = nearest_cluster
        end

        # Step 3: Build cluster results
        build_clusters_from_assignments(nodes, assignments, seeds, k)
      end

      # Greedy farthest-first seed selection — O(n*k) but no full k-means needed
      def pick_seeds(nodes, k)
        seeds = [nodes.sample]

        while seeds.size < k && seeds.size < nodes.size
          # Find node farthest from all current seeds
          best_node = nil
          best_dist = -1

          # Sample a subset for speed
          candidates = nodes.size > 200 ? nodes.sample(200) : nodes
          candidates.each do |node|
            next if seeds.any? { |s| s.id == node.id }

            min_seed_dist = seeds.map { |s| cosine_distance_pgvector(node, s) }.min
            if min_seed_dist > best_dist
              best_dist = min_seed_dist
              best_node = node
            end
          end

          break unless best_node
          seeds << best_node
        end

        seeds
      end

      # Compute cosine distance between two nodes using their embedding vectors
      def cosine_distance_pgvector(node_a, node_b)
        emb_a = node_a.embedding
        emb_b = node_b.embedding
        return 1.0 unless emb_a && emb_b

        a = emb_a.is_a?(String) ? JSON.parse(emb_a) : emb_a.to_a
        b = emb_b.is_a?(String) ? JSON.parse(emb_b) : emb_b.to_a

        dot = 0.0
        mag_a = 0.0
        mag_b = 0.0
        a.size.times do |i|
          dot += a[i] * b[i]
          mag_a += a[i] * a[i]
          mag_b += b[i] * b[i]
        end

        mag_a = Math.sqrt(mag_a)
        mag_b = Math.sqrt(mag_b)
        return 1.0 if mag_a.zero? || mag_b.zero?

        1.0 - (dot / (mag_a * mag_b))
      end

      def build_clusters_from_assignments(nodes, assignments, seeds, k)
        clusters = []
        node_map = nodes.index_by(&:id)

        k.times do |cluster_id|
          member_ids = assignments.select { |_, v| v == cluster_id }.keys
          members = member_ids.filter_map { |id| node_map[id] }
          next if members.empty?

          member_data = members.map do |m|
            {
              id: m.id,
              simple_name: m.properties&.dig("simple_name") || m.name,
              entity_type: m.entity_type
            }
          end

          label = generate_label(member_data)

          representatives = member_data
                              .sort_by { |m| m[:simple_name].length }
                              .first(3)
                              .map { |m| { id: m[:id], name: m[:simple_name], entity_type: m[:entity_type] } }

          clusters << {
            cluster_id: cluster_id,
            label: label,
            member_count: members.size,
            seed: { id: seeds[cluster_id]&.id, name: seeds[cluster_id]&.properties&.dig("simple_name") || seeds[cluster_id]&.name },
            representative_symbols: representatives,
            entity_type_breakdown: member_data.group_by { |m| m[:entity_type] }.transform_values(&:size),
            members: member_data.map { |m| { id: m[:id], name: m[:simple_name], entity_type: m[:entity_type] } }
          }
        end

        clusters.sort_by { |c| -c[:member_count] }
      end

      def generate_label(members)
        terms = members.flat_map do |m|
          name = m[:simple_name]
          name.gsub(/([a-z])([A-Z])/, '\1_\2')
              .split(/[_\-\/.:# ]/)
              .map(&:downcase)
              .reject { |t| t.length < 3 || %w[app src lib get set new def end nil true false self class module].include?(t) }
        end

        top_terms = terms.tally.sort_by { |_, count| -count }.first(3).map(&:first)
        top_terms.empty? ? "Cluster" : top_terms.map(&:capitalize).join(" / ")
      end
    end
  end
end
