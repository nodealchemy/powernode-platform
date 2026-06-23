# frozen_string_literal: true

module Ai
  module Codebase
    class SectionedAnalysisService
      MIN_SECTION_NODES = 5

      def initialize(account:, knowledge_base:)
        @account = account
        @knowledge_base = knowledge_base
      end

      # Auto-discover sections from the indexed codebase by directory structure.
      # Groups code entities by their top-level directory paths.
      # @param scope_path [String|nil] Limit discovery to a subtree (e.g. an extension dir under "extensions/")
      # @param depth [Integer] Directory depth for section grouping (default: auto)
      # @return [Hash] Available sections with node counts
      def list_sections(scope_path: nil, depth: nil)
        sections = discover_sections(scope_path, depth)

        {
          success: true,
          sections: sections.map { |s| s.except(:_path_prefix) },
          total_sections: sections.size,
          scope: scope_path || "(entire codebase)"
        }
      end

      # Analyze a specific section by path prefix.
      # @param section [String] Section path prefix or discovered section name
      # @param dead_code [Boolean] Run dead code detection (default: true)
      # @param min_dead_score [Float] Minimum deadness score (default: 0.5)
      # @return [Hash] Combined analysis results
      def analyze_section(section:, dead_code: true, min_dead_score: 0.5)
        scope_path = section
        node_count = count_nodes(scope_path)

        if node_count == 0
          return { success: false, error: "No indexed code found at path '#{scope_path}'" }
        end

        result = {
          success: true,
          section: File.basename(scope_path),
          path: scope_path,
          node_count: node_count
        }

        if dead_code
          dead_svc = DeadCodeDetectionService.new(account: @account, knowledge_base: @knowledge_base)
          result[:dead_code] = dead_svc.detect(
            scope_path: scope_path,
            min_score: min_dead_score,
            top_k: 30
          )
        end

        result
      end

      private

      # Auto-discover logical sections by grouping file nodes by directory.
      # Finds the deepest directory level where each group has a manageable number of nodes.
      def discover_sections(scope_path, target_depth)
        # Get all file nodes
        scope = @knowledge_base.knowledge_graph_nodes
                                .where(account: @account, node_type: "code_entity", entity_type: "file", status: "active")

        if scope_path.present?
          scope = scope.where("name LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(scope_path)}%")
        end

        file_paths = scope.pluck(:name)
        return [] if file_paths.empty?

        # Auto-detect good grouping depth if not specified
        depth = target_depth || auto_detect_depth(file_paths, scope_path)

        # Group by directory at the chosen depth
        groups = file_paths.group_by { |path| path_at_depth(path, depth, scope_path) }.compact

        # Build section list, filtering out tiny groups
        sections = groups.filter_map do |dir_path, files|
          next if dir_path.blank?

          total_nodes = count_nodes(dir_path)
          next if total_nodes < MIN_SECTION_NODES

          {
            name: readable_name(dir_path, scope_path),
            path: dir_path,
            file_count: files.size,
            node_count: total_nodes,
            _path_prefix: dir_path
          }
        end

        sections.sort_by { |s| -s[:node_count] }
      end

      # Find the directory depth that produces groups of 50-500 nodes.
      def auto_detect_depth(file_paths, scope_path)
        base_depth = scope_path ? scope_path.count("/") : 0

        (2..6).each do |depth|
          groups = file_paths.group_by { |p| path_at_depth(p, depth, scope_path) }.compact
          avg_size = groups.values.map(&:size).sum.to_f / [groups.size, 1].max

          # Sweet spot: 5-30 groups with avg 10-100 files each
          return base_depth + depth if groups.size.between?(3, 30) && avg_size.between?(5, 100)
        end

        base_depth + 3 # Default fallback
      end

      # Extract directory path at a given depth.
      def path_at_depth(full_path, depth, scope_path)
        parts = full_path.split("/")
        return nil if parts.size <= depth

        parts.first(depth).join("/")
      end

      # Generate a readable section name from a path.
      def readable_name(path, scope_path)
        if scope_path.present?
          relative = path.sub(/\A#{Regexp.escape(scope_path)}\/?/, "")
          relative.present? ? relative : File.basename(path)
        else
          # Use last 2-3 meaningful directory components
          parts = path.split("/").reject { |p| %w[app src server frontend].include?(p) }
          parts.last(3).join("/")
        end
      end

      def count_nodes(scope_path)
        @knowledge_base.knowledge_graph_nodes
                        .where(account: @account, node_type: "code_entity", status: "active")
                        .where("name LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(scope_path)}%")
                        .count
      end
    end
  end
end
