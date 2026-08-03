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
            description: "Hybrid code search: embedding similarity fused with term matching (RRF). Finds code by meaning OR by wording — describe the behaviour or name the symbol. Each result reports matched_by: vector, lexical, or both.",
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

      # Hybrid retrieval: vector similarity fused with term-based lexical
      # matching via Reciprocal Rank Fusion.
      #
      # Measured 2026-08-03 (docs/operations/code-index-retrieval-quality.md):
      # pure vector search reliably answers identifier-shaped queries ("kill
      # switch emergency halt" -> 0.73) but not behavioural ones. "immediately
      # stop a runaway autonomous agent" did not return
      # KillSwitchService#emergency_halt! in the top TEN, even though that node
      # carries the doc "Coordinated emergency stop — halts ALL agentic
      # activity". Every candidate sat in a flat 0.51-0.56 band: the model does
      # not place a long question near a terse code-symbol fragment, and no
      # amount of enriching the corpus fixed it across three attempts.
      #
      # The lexical arm recovers exactly what the vector arm loses, because the
      # answer usually IS reachable by a word in the query ("stop", "halt",
      # "agent"). Note it cannot reuse #identifier_search: that matches the
      # WHOLE query as one ILIKE substring, so a behavioural sentence matches no
      # identifier at all and would contribute nothing to the fusion.
      #
      # RRF is used rather than score-blending because the two arms' scores are
      # not comparable (cosine similarity vs. a term count); only their
      # rankings are.
      RRF_K = 60
      LEXICAL_MAX_TERMS = 8

      # Words that appear in nearly every phrasing carry no retrieval signal and
      # would match huge swathes of the corpus.
      QUERY_STOPWORDS = %w[
        the a an of to from for any all and or in on with that this it is are be
        by at as not no we you do does how what when where which who why can
        could should would will may might must have has had its their our your
        then than there some such only same so too very just now also into out
        up down over under again once about after before while each other more
        most own but if per via use used using get set new
      ].to_set.freeze

      def semantic_search(params)
        return { success: false, error: "query is required" } if params[:query].blank?
        return { success: false, error: "repository_id is required" } if params[:repository_id].blank?

        # KB-only: this queries knowledge-graph rows, never the filesystem,
        # so it must not demand a repository local_path that exists on disk.
        _repo, kb, _bp = resolve_project_context(params, require_base_path: false)
        top_k = (params[:top_k] || 10).to_i
        entity_types = Array(params[:entity_types]).presence

        base = kb.knowledge_graph_nodes
                 .where(account: account, node_type: "code_entity", status: "active")
        base = base.where(entity_type: entity_types) if entity_types

        # Fuse over a deeper slice than we return: the whole point is to promote
        # a node ranked ~30th by one arm that the other arm ranks near the top.
        candidate_k = [ top_k * 3, 30 ].max

        # Best-effort: with embeddings down this degrades to lexical-only rather
        # than failing the query outright.
        query_embedding = Ai::Memory::EmbeddingService.new(account: account)
                                                     .generate_or_nil(params[:query], context: "code_semantic_search")

        vector_nodes = if query_embedding
          base.with_embeddings
              .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
              .first(candidate_k)
        else
          []
        end

        terms = query_terms(params[:query])
        lexical_nodes = lexical_candidates(base, terms, candidate_k)

        similarity_by_id = vector_nodes.to_h { |n| [ n.id, (1.0 - (n.neighbor_distance || 0)).round(4) ] }
        vector_rank      = vector_nodes.each_with_index.to_h { |n, i| [ n.id, i + 1 ] }
        lexical_rank     = lexical_nodes.each_with_index.to_h { |n, i| [ n.id, i + 1 ] }

        results = reciprocal_rank_fusion([ vector_nodes, lexical_nodes ], top_k).map do |node, fused|
          {
            id: node.id,
            name: node.name,
            simple_name: node.properties&.dig("simple_name"),
            entity_type: node.entity_type,
            description: node.description,
            file_path: node.properties&.dig("file_path"),
            line_start: node.properties&.dig("line_start"),
            similarity: similarity_by_id[node.id],
            fused_score: fused.round(5),
            # Which arm found it — an agent (and a human) can tell a meaning
            # match from a word match, which the old flat score never showed.
            matched_by: [ ("vector" if vector_rank[node.id]), ("lexical" if lexical_rank[node.id]) ].compact,
            vector_rank: vector_rank[node.id],
            lexical_rank: lexical_rank[node.id],
            mention_count: node.mention_count
          }
        end

        {
          success: true, results: results, count: results.size, query: params[:query],
          retrieval: {
            mode: query_embedding ? "hybrid" : "lexical_only",
            terms: terms,
            vector_candidates: vector_nodes.size,
            lexical_candidates: lexical_nodes.size
          }
        }
      end

      # Meaningful words from a natural-language query. Short tokens and
      # stopwords are dropped; the cap bounds how much SQL the scorer builds.
      def query_terms(query)
        query.to_s.downcase.scan(/[a-z0-9_]+/)
             .reject { |t| t.length < 3 || QUERY_STOPWORDS.include?(t) }
             .uniq
             .first(LEXICAL_MAX_TERMS)
      end

      # Rank by IDF-weighted term matches over identifier + description (where
      # the doc comment lives).
      #
      # A raw term COUNT is not good enough, and the first live run showed why:
      # for "immediately stop a runaway autonomous agent", PlatformResilience-
      # Executor outranked KillSwitchService#emergency_halt! purely because its
      # long doc happened to contain the ubiquitous words "action", "autonomous"
      # and "agent", while the precise short doc matched only "stop" and
      # "agent". Matching a rare word ("runaway", "halt") is strong evidence;
      # matching "agent" in an agent platform is almost none.
      #
      # So each term is weighted by log(N / df) and the total is damped by
      # description length, which is the part of BM25 that actually matters
      # here. Without both, the lexical arm just prefers whichever node has the
      # most text.
      DF_CACHE_TTL = 1.hour

      def lexical_candidates(scope, terms, limit)
        return [] if terms.empty?

        weights = term_idf_weights(scope, terms)
        return [] if weights.empty?

        scored = weights.map do |term, idf|
          ActiveRecord::Base.sanitize_sql_array(
            [ "(CASE WHEN #{LEXICAL_HAYSTACK} ILIKE ? THEN #{idf.round(4)} ELSE 0 END)",
             "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" ]
          )
        end.join(" + ")

        # Longer text has more chances to match by luck; damp it rather than
        # dividing outright, so a genuinely rich doc is not punished into
        # oblivion.
        rank = "(#{scored}) / (1 + ln(1 + char_length(#{LEXICAL_HAYSTACK}) / 300.0))"

        scope.select("ai_knowledge_graph_nodes.*, (#{rank}) AS lexical_score")
             .where("(#{scored}) > 0")
             .order(Arel.sql("(#{rank}) DESC, ai_knowledge_graph_nodes.mention_count DESC"))
             .limit(limit)
             .to_a
      end

      LEXICAL_HAYSTACK = "(COALESCE(ai_knowledge_graph_nodes.properties->>'simple_name','') || ' ' || " \
                         "COALESCE(ai_knowledge_graph_nodes.description,''))"

      # Document frequency per term, in one pass, cached: the corpus only moves
      # when the index is rebuilt, and this must not add a scan per query.
      def term_idf_weights(scope, terms)
        total = Rails.cache.fetch("code_idf:total:#{scope_cache_key(scope)}", expires_in: DF_CACHE_TTL) do
          scope.count
        end
        return {} if total.to_i.zero?

        terms.index_with do |term|
          df = Rails.cache.fetch("code_idf:df:#{scope_cache_key(scope)}:#{Digest::MD5.hexdigest(term)}",
                                 expires_in: DF_CACHE_TTL) do
            scope.where("#{LEXICAL_HAYSTACK} ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(term)}%").count
          end
          # +1 smoothing keeps a term that matches everything from going to zero
          # or negative, and an unseen term from dividing by zero.
          Math.log((total.to_f + 1) / (df.to_i + 1)) + 1.0
        end.reject { |_term, idf| idf <= 1.0 } # matched (nearly) everywhere ⇒ no signal
      end

      def scope_cache_key(scope)
        Digest::MD5.hexdigest(scope.to_sql)
      end

      # score(d) = Σ 1 / (K + rank_in_list) — standard RRF. K damps the top of
      # each list so one arm cannot dominate on its own first place alone.
      def reciprocal_rank_fusion(lists, top_k)
        scores = Hash.new(0.0)
        nodes  = {}

        lists.each do |list|
          list.each_with_index do |node, idx|
            scores[node.id] += 1.0 / (RRF_K + idx + 1)
            nodes[node.id] ||= node
          end
        end

        scores.sort_by { |id, score| [ -score, nodes[id].name.to_s ] }
              .first(top_k)
              .map { |id, score| [ nodes[id], score ] }
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
