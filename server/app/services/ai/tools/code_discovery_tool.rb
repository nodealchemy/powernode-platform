# frozen_string_literal: true

module Ai
  module Tools
    class CodeDiscoveryTool < BaseTool
      include Concerns::CodebaseContextResolvable

      REQUIRED_PERMISSION = "ai.agents.read"

      def self.definition
        {
          name: "code_discovery",
          description: "Discover and navigate codebase structure: context trees, file skeletons, semantic code search, identifier search, semantic clustering, and feature hubs",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            repository_id: { type: "string", required: false, description: "Git repository ID, name, or full_name" },
            base_path: { type: "string", required: false, description: "Filesystem path to codebase root" },
            file_path: { type: "string", required: false, description: "File path relative to codebase root" },
            query: { type: "string", required: false, description: "Search query" },
            path: { type: "string", required: false, description: "Subdirectory path" },
            max_depth: { type: "integer", required: false, description: "Maximum tree depth (default 3)" },
            include_symbols: { type: "boolean", required: false, description: "Include symbols in context tree (default true)" },
            entity_types: { type: "array", required: false, description: "Filter by entity types" },
            top_k: { type: "integer", required: false, description: "Max results (default 10)" },
            cluster_id: { type: "integer", required: false, description: "Specific cluster to inspect" }
          }
        }
      end

      def self.action_definitions
        {
          "code_context_tree" => {
            description: "Get an AST-based structural tree of the codebase with file headers and symbol ranges. Dynamic pruning by depth.",
            parameters: {
              repository_id: { type: "string", required: false, description: "Git repository ID, name, or full_name" },
              base_path: { type: "string", required: false, description: "Filesystem path to codebase root" },
              path: { type: "string", required: false, description: "Subdirectory to scan (default: root)" },
              max_depth: { type: "integer", required: false, description: "Maximum tree depth (default 3)" },
              include_symbols: { type: "boolean", required: false, description: "Include parsed symbols (default true)" }
            }
          },
          "code_file_skeleton" => {
            description: "Get function signatures, class methods, and type definitions for a file — no function bodies, just the structure with line ranges.",
            parameters: {
              repository_id: { type: "string", required: false, description: "Git repository ID, name, or full_name" },
              base_path: { type: "string", required: false, description: "Filesystem path to codebase root" },
              file_path: { type: "string", required: true, description: "File path relative to codebase root" }
            }
          },
          "code_semantic_search" => {
            description: "Semantic search over code symbols using embeddings. Finds code by meaning, not just name.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              query: { type: "string", required: true, description: "Search query" },
              entity_types: { type: "array", required: false, description: "Filter by entity types (class, method, function, etc.)" },
              top_k: { type: "integer", required: false, description: "Max results (default 10)" }
            }
          },
          "code_identifier_search" => {
            description: "Search for identifiers (functions, classes, variables) by name or semantic meaning with usage counts.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              query: { type: "string", required: true, description: "Identifier name or description" },
              entity_types: { type: "array", required: false, description: "Filter by entity types" },
              top_k: { type: "integer", required: false, description: "Max results (default 10)" }
            }
          },
          "code_semantic_navigate" => {
            description: "Browse the codebase by meaning using semantic clustering. Groups related files and symbols into labeled clusters.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              query: { type: "string", required: false, description: "Optional focus query to filter clusters" },
              cluster_id: { type: "integer", required: false, description: "Specific cluster ID to inspect" }
            }
          },
          "code_feature_hub" => {
            description: "Obsidian-style feature navigation from markdown files with [[wikilinks]]. Discovers documentation structure and orphan files.",
            parameters: {
              repository_id: { type: "string", required: false, description: "Git repository ID, name, or full_name" },
              base_path: { type: "string", required: false, description: "Filesystem path to codebase root" },
              path: { type: "string", required: false, description: "Subdirectory to scan (default: docs/)" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "context_tree" then context_tree(params)
        when "file_skeleton" then file_skeleton(params)
        when "semantic_search" then semantic_search(params)
        when "identifier_search" then identifier_search(params)
        when "semantic_navigate" then semantic_navigate(params)
        when "feature_hub" then feature_hub(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      rescue ArgumentError => e
        { success: false, error: e.message }
      end

      private

      # ─── Context Tree ──────────────────────────────────────────────

      def context_tree(params)
        bp = resolve_base_path(params)
        target = params[:path] ? File.join(bp, params[:path]) : bp
        max_depth = (params[:max_depth] || 3).to_i
        include_symbols = params[:include_symbols] != false

        tree = build_tree(target, bp, max_depth, include_symbols, 0)
        { success: true, tree: tree, base_path: bp }
      end

      def build_tree(path, base_path, max_depth, include_symbols, current_depth)
        return nil if current_depth > max_depth

        name = File.basename(path)
        relative = Pathname.new(path).relative_path_from(Pathname.new(base_path)).to_s rescue path

        if File.directory?(path)
          children = Dir.children(path).sort.filter_map do |child|
            full = File.join(path, child)
            next if child.start_with?(".")
            next if Ai::Codebase::IndexingService::SKIP_DIRS.include?(child)

            build_tree(full, base_path, max_depth, include_symbols, current_depth + 1)
          end

          { name: name, path: relative, type: "directory", children: children }
        elsif File.file?(path)
          parser = Ai::Codebase::AstParserService.new
          entry = { name: name, path: relative, type: "file" }

          if include_symbols && parser.supported?(path)
            result = parser.parse(path)
            entry[:language] = result[:language].to_s
            entry[:symbols] = result[:symbols].map do |sym|
              { name: sym[:name], kind: sym[:kind].to_s, line: sym[:line_start], visibility: sym[:visibility].to_s, params: sym[:params] }
            end
          end

          entry
        end
      end

      # ─── File Skeleton ─────────────────────────────────────────────

      def file_skeleton(params)
        return { success: false, error: "file_path is required" } if params[:file_path].blank?

        bp = resolve_base_path(params)
        full_path = File.join(bp, params[:file_path])

        unless File.exist?(full_path)
          return { success: false, error: "File not found: #{params[:file_path]}" }
        end

        parser = Ai::Codebase::AstParserService.new
        result = parser.parse(full_path)

        {
          success: true,
          file: params[:file_path],
          language: result[:language].to_s,
          symbols: result[:symbols].map do |sym|
            {
              name: sym[:name],
              qualified_name: sym[:qualified_name],
              kind: sym[:kind].to_s,
              visibility: sym[:visibility].to_s,
              line_start: sym[:line_start],
              line_end: sym[:line_end],
              params: sym[:params],
              return_type: sym[:return_type],
              parent: sym[:parent],
              superclass: sym[:superclass]
            }
          end
        }
      end

      # ─── Semantic Search ───────────────────────────────────────────

      def semantic_search(params)
        return { success: false, error: "query is required" } if params[:query].blank?
        return { success: false, error: "repository_id is required" } if params[:repository_id].blank?

        # KB-only: this queries knowledge-graph rows, never the filesystem,
        # so it must not demand a repository local_path that exists on disk.
        _repo, kb, _bp = resolve_project_context(params, require_base_path: false)
        top_k = (params[:top_k] || 10).to_i
        entity_types = Array(params[:entity_types]).presence

        # Use embedding service for semantic search
        embedding_service = Ai::Memory::EmbeddingService.new(account: account)
        query_embedding = embedding_service.generate(params[:query])

        return { success: false, error: "Failed to generate query embedding" } unless query_embedding

        scope = kb.knowledge_graph_nodes
                   .where(account: account, node_type: "code_entity", status: "active")
                   .with_embeddings

        scope = scope.where(entity_type: entity_types) if entity_types

        results = scope.nearest_neighbors(:embedding, query_embedding, distance: "cosine")
                       .first(top_k)
                       .map do |node|
          {
            id: node.id,
            name: node.name,
            simple_name: node.properties&.dig("simple_name"),
            entity_type: node.entity_type,
            description: node.description,
            file_path: node.properties&.dig("file_path"),
            line_start: node.properties&.dig("line_start"),
            similarity: (1.0 - (node.neighbor_distance || 0)).round(4),
            mention_count: node.mention_count
          }
        end

        { success: true, results: results, count: results.size, query: params[:query] }
      end

      # ─── Identifier Search ────────────────────────────────────────

      def identifier_search(params)
        return { success: false, error: "query is required" } if params[:query].blank?
        return { success: false, error: "repository_id is required" } if params[:repository_id].blank?

        # KB-only: this queries knowledge-graph rows, never the filesystem,
        # so it must not demand a repository local_path that exists on disk.
        _repo, kb, _bp = resolve_project_context(params, require_base_path: false)
        top_k = (params[:top_k] || 10).to_i
        entity_types = Array(params[:entity_types]).presence

        scope = kb.knowledge_graph_nodes
                   .where(account: account, node_type: "code_entity", status: "active")

        scope = scope.where(entity_type: entity_types) if entity_types

        query = ActiveRecord::Base.sanitize_sql_like(params[:query])

        # Name-based search with ranking by mention_count
        results = scope.where("name ILIKE :q OR properties->>'simple_name' ILIKE :q",
                              q: "%#{query}%")
                       .order(mention_count: :desc)
                       .limit(top_k)
                       .map do |node|
          {
            id: node.id,
            name: node.name,
            simple_name: node.properties&.dig("simple_name"),
            entity_type: node.entity_type,
            description: node.description,
            file_path: node.properties&.dig("file_path"),
            line_start: node.properties&.dig("line_start"),
            visibility: node.properties&.dig("visibility"),
            params: node.properties&.dig("params"),
            mention_count: node.mention_count,
            connections: node.degree
          }
        end

        { success: true, results: results, count: results.size, query: params[:query] }
      end

      # ─── Semantic Navigate ────────────────────────────────────────

      def semantic_navigate(params)
        return { success: false, error: "repository_id is required" } if params[:repository_id].blank?

        # KB-only: this queries knowledge-graph rows, never the filesystem,
        # so it must not demand a repository local_path that exists on disk.
        _repo, kb, _bp = resolve_project_context(params, require_base_path: false)

        service = Ai::Codebase::ClusteringService.new(account: account, knowledge_base: kb)
        result = service.cluster

        return result unless result[:success]

        # If a specific cluster_id is requested, return only that cluster
        if params[:cluster_id].present?
          cluster = result[:clusters].find { |c| c[:cluster_id] == params[:cluster_id].to_i }
          return { success: false, error: "Cluster not found: #{params[:cluster_id]}" } unless cluster

          return { success: true, cluster: cluster }
        end

        # Return cluster overview (without full member lists to save tokens)
        overview = result[:clusters].map do |c|
          {
            cluster_id: c[:cluster_id],
            label: c[:label],
            member_count: c[:member_count],
            representative_symbols: c[:representative_symbols],
            entity_type_breakdown: c[:entity_type_breakdown]
          }
        end

        { success: true, clusters: overview, total_nodes: result[:total_nodes], k: result[:k] }
      end

      # ─── Feature Hub ───────────────────────────────────────────────

      def feature_hub(params)
        bp = resolve_base_path(params)
        path = params[:path] || "docs"

        service = Ai::Codebase::FeatureHubService.new(base_path: bp)
        service.scan(path: path)
      end
    end
  end
end
