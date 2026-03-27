# frozen_string_literal: true

module Ai
  module Tools
    class CodeAnalysisTool < BaseTool
      include Concerns::CodebaseContextResolvable

      REQUIRED_PERMISSION = "ai.agents.read"

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
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "blast_radius" then blast_radius(params)
        when "static_analysis" then static_analysis(params)
        when "index_status" then index_status(params)
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
    end
  end
end
