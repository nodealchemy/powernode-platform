# frozen_string_literal: true

module Ai
  module Tools
    class CodeAnalysisTool < BaseTool
      include Concerns::CodebaseContextResolvable

      REQUIRED_PERMISSION = "ai.agents.read"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "analyze_section", mutating: false
      declare_action "blast_radius", mutating: false
      declare_action "dead_code", mutating: false
      declare_action "find_duplicates", mutating: false
      declare_action "index_status", mutating: false
      declare_action "static_analysis", mutating: false

      def self.definition
        {
          name: "code_analysis",
          description: "Analyze codebase: trace blast radius of symbol changes, run static analysis (linters/compilers), and check index status",
          parameters: {
            action: { type: "string", required: true, description: "Action to perform" },
            repository_id: { type: "string", required: false, description: "Git repository ID, name, or full_name" },
            base_path: { type: "string", required: false, description: "Filesystem path to codebase root" },
            symbol_name: { type: "string", required: false, description: "Symbol name to trace" },
            node_id: { type: "string", required: false, description: "Knowledge graph node ID" },
            max_depth: { type: "integer", required: false, description: "Maximum traversal depth (default 3)" },
            path: { type: "string", required: false, description: "Subdirectory to analyze" },
            linters: { type: "array", required: false, description: "Specific linters to run" }
          }
        }
      end

      def self.action_definitions
        {
          "code_blast_radius" => {
            description: "Trace every file and line where a symbol is imported or used. Shows the impact radius of changing a function, class, or module.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              symbol_name: { type: "string", required: false, description: "Symbol name (qualified or simple)" },
              node_id: { type: "string", required: false, description: "Knowledge graph node ID" },
              max_depth: { type: "integer", required: false, description: "Maximum traversal depth (default 3, max 5)" }
            }
          },
          "code_static_analysis" => {
            description: "Run native linters and compilers (RuboCop, TypeScript, ESLint). Returns structured diagnostics with file, line, severity, and message.",
            parameters: {
              repository_id: { type: "string", required: false, description: "Git repository ID, name, or full_name" },
              base_path: { type: "string", required: false, description: "Filesystem path to codebase root" },
              path: { type: "string", required: false, description: "Subdirectory to analyze" },
              linters: { type: "array", required: false, description: "Linters to run: ruby, typescript, javascript_lint" }
            }
          },
          "code_index_status" => {
            description: "Show codebase indexing statistics: files indexed, symbols extracted, last indexed timestamp, stale files count.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" }
            }
          },
          "code_dead_code" => {
            description: "Detect dead code via language-native analyzers (ts-prune for TS, debride for Ruby) + grep verification + AI triage. Async — dispatched to the worker; the categorized result (real_dead / public_api / dynamic_dispatch / test_only / uncertain) is written to shared memory, retrieve via read_shared_memory.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              languages: { type: "array", required: false, description: "Subset of [typescript, ruby] (default: both)" },
              triage: { type: "boolean", required: false, description: "Run LLM triage of verified candidates (default: true)" },
              model: { type: "string", required: false, description: "Override the triage LLM model" }
            }
          },
          "code_find_duplicates" => {
            description: "Detect copy-paste code clones via jscpd (token-based) + AI triage. Async — dispatched to the worker; the categorized result (extract_candidate / acceptable / generated / coincidental, with suggested actions) is written to shared memory, retrieve via read_shared_memory.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              scope_paths: { type: "array", required: false, description: "Subdirs to scan (default: frontend/src, server/app, worker/app)" },
              min_tokens: { type: "integer", required: false, description: "Clone size floor in tokens (default: 50)" },
              triage: { type: "boolean", required: false, description: "Run LLM triage of clone groups (default: true)" },
              model: { type: "string", required: false, description: "Override the triage LLM model" }
            }
          },
          "code_analyze_section" => {
            description: "Run focused dead code + duplicate analysis on a codebase section. Omit section to auto-discover sections. Use scope_path to limit discovery to a subtree.",
            parameters: {
              repository_id: { type: "string", required: true, description: "Git repository ID, name, or full_name" },
              section: { type: "string", required: false, description: "Section path to analyze (e.g. 'server/app/models', 'frontend/src/features'). Omit to list available sections." },
              scope_path: { type: "string", required: false, description: "Limit section discovery to a subtree (e.g. 'server/app/services', 'frontend/src')" },
              dead_code: { type: "boolean", required: false, description: "Run dead code detection (default: true)" },
              duplicates: { type: "boolean", required: false, description: "Run duplicate detection (default: true)" },
              duplicate_threshold: { type: "number", required: false, description: "Similarity threshold for duplicates (default: 0.92)" },
              min_dead_score: { type: "number", required: false, description: "Minimum deadness score (default: 0.5)" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "blast_radius" then blast_radius(params)
        when "static_analysis" then static_analysis(params)
        when "index_status" then index_status(params)
        when "dead_code" then dead_code(params)
        when "find_duplicates" then find_duplicates(params)
        when "analyze_section" then analyze_section(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      rescue ActiveRecord::RecordNotFound => e
        { success: false, error: e.message }
      rescue ArgumentError => e
        { success: false, error: e.message }
      end

      private

      def blast_radius(params)
        return { success: false, error: "repository_id is required" } if params[:repository_id].blank?
        return { success: false, error: "symbol_name or node_id is required" } if params[:symbol_name].blank? && params[:node_id].blank?

        _repo, kb, _bp = resolve_project_context(params)
        max_depth = (params[:max_depth] || 3).to_i

        service = Ai::Codebase::BlastRadiusService.new(account: account, knowledge_base: kb)
        service.trace(
          node_id: params[:node_id],
          symbol_name: params[:symbol_name],
          max_depth: max_depth
        )
      end

      def static_analysis(params)
        bp = resolve_base_path(params)
        linters = params[:linters]&.map(&:to_s)

        service = Ai::Codebase::StaticAnalysisService.new(base_path: bp)
        service.analyze(path: params[:path], linters: linters)
      end

      def index_status(params)
        return { success: false, error: "repository_id is required" } if params[:repository_id].blank?

        _repo, kb, bp = resolve_project_context(params)

        code_nodes = kb.knowledge_graph_nodes.where(node_type: "code_entity", status: "active")
        file_nodes = code_nodes.where(entity_type: "file")

        # Check for stale files
        stale_count = 0
        if bp && File.directory?(bp)
          file_nodes.find_each(batch_size: 100) do |node|
            full_path = File.join(bp, node.name)
            if !File.exist?(full_path)
              stale_count += 1
            elsif node.metadata&.dig("file_mtime").present?
              current_mtime = File.mtime(full_path).iso8601
              stale_count += 1 if node.metadata["file_mtime"] != current_mtime
            end
          end
        end

        {
          success: true,
          knowledge_base: { id: kb.id, name: kb.name },
          files_indexed: file_nodes.count,
          symbols_extracted: code_nodes.where.not(entity_type: "file").count,
          total_code_nodes: code_nodes.count,
          nodes_with_embeddings: code_nodes.with_embeddings.count,
          stale_files: stale_count,
          last_indexed_at: kb.last_indexed_at&.iso8601,
          entity_type_breakdown: code_nodes.group(:entity_type).count,
          edge_counts: {
            contains: Ai::KnowledgeGraphEdge.where(account: account, relation_type: "contains", status: "active")
                                             .joins(:source_node).where(ai_knowledge_graph_nodes: { knowledge_base_id: kb.id }).count,
            imports: Ai::KnowledgeGraphEdge.where(account: account, relation_type: "imports", status: "active")
                                            .joins(:source_node).where(ai_knowledge_graph_nodes: { knowledge_base_id: kb.id }).count,
            defines: Ai::KnowledgeGraphEdge.where(account: account, relation_type: "defines", status: "active")
                                            .joins(:source_node).where(ai_knowledge_graph_nodes: { knowledge_base_id: kb.id }).count,
            inherits: Ai::KnowledgeGraphEdge.where(account: account, relation_type: "inherits", status: "active")
                                             .joins(:source_node).where(ai_knowledge_graph_nodes: { knowledge_base_id: kb.id }).count
          }
        }
      end

      def dead_code(params)
        return { success: false, error: "repository_id is required" } if params[:repository_id].blank?

        _repo, _kb, bp = resolve_project_context(params)
        result_key = "code_intel.dead_code.#{params[:repository_id]}"

        # Analyzer-driven (ts-prune/debride) + grep-verify + LLM triage is
        # long-running → dispatch to the worker. The categorized result is
        # written to the 'default' shared-memory pool under result_key.
        WorkerJobService.enqueue_ai_code_analysis(
          operation: "dead_code",
          account_id: account.id,
          base_path: bp,
          repository_id: params[:repository_id],
          result_key: result_key,
          options: {
            "languages" => params[:languages]&.map(&:to_s),
            "triage" => params[:triage] != false,
            "model" => params[:model]
          }.compact
        )

        {
          success: true,
          status: "enqueued",
          result_key: result_key,
          retrieve_via: "read_shared_memory(pool_id: 'default', key: '#{result_key}')",
          message: "Dead-code analysis (analyzers + AI triage) dispatched to the worker."
        }
      end

      def find_duplicates(params)
        return { success: false, error: "repository_id is required" } if params[:repository_id].blank?

        _repo, _kb, bp = resolve_project_context(params)
        result_key = "code_intel.find_duplicates.#{params[:repository_id]}"

        # jscpd clone detection + LLM triage is long-running → dispatch to the
        # worker. The categorized clone report is written to the 'default'
        # shared-memory pool under result_key.
        WorkerJobService.enqueue_ai_code_analysis(
          operation: "find_duplicates",
          account_id: account.id,
          base_path: bp,
          repository_id: params[:repository_id],
          result_key: result_key,
          options: {
            "scope_paths" => params[:scope_paths]&.map(&:to_s),
            "min_tokens" => params[:min_tokens],
            "triage" => params[:triage] != false,
            "model" => params[:model]
          }.compact
        )

        {
          success: true,
          status: "enqueued",
          result_key: result_key,
          retrieve_via: "read_shared_memory(pool_id: 'default', key: '#{result_key}')",
          message: "Duplicate (clone) detection (jscpd + AI triage) dispatched to the worker."
        }
      end

      def analyze_section(params)
        return { success: false, error: "repository_id is required" } if params[:repository_id].blank?

        _repo, kb, _bp = resolve_project_context(params)
        service = Ai::Codebase::SectionedAnalysisService.new(account: account, knowledge_base: kb)

        if params[:section].blank?
          return service.list_sections(scope_path: params[:scope_path])
        end

        service.analyze_section(
          section: params[:section],
          dead_code: params[:dead_code] != false,
          min_dead_score: (params[:min_dead_score] || 0.5).to_f
        )
      end
    end
  end
end
