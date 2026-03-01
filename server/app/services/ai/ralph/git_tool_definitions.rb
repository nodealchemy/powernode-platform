# frozen_string_literal: true

module Ai
  module Ralph
    class GitToolDefinitions
      CATEGORIES = {
        file_ops: %w[read_file write_file delete_file list_files],
        code_intel: %w[search_code get_file_info],
        repo_context: %w[get_repo_info list_branches get_branch_diff list_commits]
      }.freeze

      GIT_TOOL_NAMES = CATEGORIES.values.flatten.to_set.freeze

      TOOLS = [
        # === File Operations ===
        {
          name: "read_file",
          description: "Read the content of a file from the repository. Returns the decoded text content. Use this before modifying a file to understand its current state.",
          category: :file_ops,
          parameters: {
            type: "object",
            properties: {
              path: { type: "string", description: "File path relative to repository root (e.g. 'src/app.js')" }
            },
            required: ["path"]
          }
        },
        {
          name: "write_file",
          description: "Create or update a file in the repository. Automatically commits the change. Always provide the COMPLETE file content, not just a diff or partial update.",
          category: :file_ops,
          parameters: {
            type: "object",
            properties: {
              path: { type: "string", description: "File path relative to repository root" },
              content: { type: "string", description: "Complete file content to write" },
              message: { type: "string", description: "Git commit message describing the change" }
            },
            required: %w[path content message]
          }
        },
        {
          name: "delete_file",
          description: "Delete a file from the repository. Automatically commits the deletion.",
          category: :file_ops,
          parameters: {
            type: "object",
            properties: {
              path: { type: "string", description: "File path relative to repository root" },
              message: { type: "string", description: "Git commit message describing why the file is deleted" }
            },
            required: %w[path message]
          }
        },
        {
          name: "list_files",
          description: "List files and directories in the repository. Returns the tree structure with file paths, types, and sizes.",
          category: :file_ops,
          parameters: {
            type: "object",
            properties: {
              path: { type: "string", description: "Directory path to list (empty or '/' for root)" },
              recursive: { type: "boolean", description: "If true, list all files recursively. Default: false" }
            },
            required: []
          }
        },

        # === Code Intelligence ===
        {
          name: "search_code",
          description: "Search for text or patterns in the repository codebase. Returns matching file paths and snippets.",
          category: :code_intel,
          parameters: {
            type: "object",
            properties: {
              query: { type: "string", description: "Search query string or pattern" },
              path_filter: { type: "string", description: "Optional path prefix to limit search scope (e.g. 'src/')" }
            },
            required: ["query"]
          }
        },
        {
          name: "get_file_info",
          description: "Get metadata about a file (size, SHA, type) without downloading its content. Useful for checking if a file exists.",
          category: :code_intel,
          parameters: {
            type: "object",
            properties: {
              path: { type: "string", description: "File path relative to repository root" }
            },
            required: ["path"]
          }
        },

        # === Repository Context ===
        {
          name: "get_repo_info",
          description: "Get repository metadata including name, description, default branch, languages, and size.",
          category: :repo_context,
          parameters: {
            type: "object",
            properties: {},
            required: []
          }
        },
        {
          name: "list_branches",
          description: "List all branches in the repository with their latest commit SHAs.",
          category: :repo_context,
          parameters: {
            type: "object",
            properties: {},
            required: []
          }
        },
        {
          name: "get_branch_diff",
          description: "Compare the current working branch to a base branch. Shows commits ahead and changed files.",
          category: :repo_context,
          parameters: {
            type: "object",
            properties: {
              base_branch: { type: "string", description: "Base branch to compare against (e.g. 'main')" }
            },
            required: ["base_branch"]
          }
        },
        {
          name: "list_commits",
          description: "List recent commits on the current branch.",
          category: :repo_context,
          parameters: {
            type: "object",
            properties: {
              limit: { type: "integer", description: "Maximum number of commits to return. Default: 10" }
            },
            required: []
          }
        }
      ].freeze

      # Return tool definitions formatted for the given provider
      # @param provider_type [String] "anthropic" or "openai"/"ollama"
      # @param categories [Array<Symbol>] Filter by category, nil for all
      # @return [Array<Hash>]
      def self.for_provider(provider_type, categories: nil)
        tools = if categories
          category_names = Array(categories).flat_map { |c| CATEGORIES[c] || [] }.to_set
          TOOLS.select { |t| category_names.include?(t[:name]) }
        else
          TOOLS
        end

        tools.map { |t| format_for_provider(t, provider_type) }
      end

      def self.format_for_provider(tool, provider_type)
        case provider_type
        when "anthropic"
          {
            name: tool[:name],
            description: tool[:description],
            input_schema: tool[:parameters]
          }
        else
          # OpenAI / Ollama format
          {
            type: "function",
            function: {
              name: tool[:name],
              description: tool[:description],
              parameters: tool[:parameters]
            }
          }
        end
      end

      private_class_method :format_for_provider
    end
  end
end
