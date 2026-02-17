# frozen_string_literal: true

module Ai
  module Ralph
    class GitToolExecutor
      MAX_FILE_SIZE = 50 * 1024 # 50KB truncation limit for read_file

      attr_reader :file_changes, :last_commit_sha

      def initialize(ralph_loop:)
        @ralph_loop = ralph_loop
        @repository = ralph_loop.mission&.repository
        raise ArgumentError, "Ralph loop has no associated repository" unless @repository

        @credential = @repository.credential
        @git_client = Devops::Git::ApiClient.for(@credential)
        @owner = @repository.owner
        @repo = @repository.name
        @branch = ralph_loop.branch || @repository.default_branch || "main"
        @file_changes = []
        @last_commit_sha = nil
      end

      # Check if git tools are available for this ralph loop
      def self.available?(ralph_loop)
        ralph_loop.mission&.repository.present?
      end

      # Execute a named git tool with arguments
      # @param tool_name [String]
      # @param arguments [Hash]
      # @return [Hash] { success:, ... }
      def execute(tool_name, arguments)
        arguments = (arguments || {}).deep_symbolize_keys

        case tool_name
        when "read_file"      then handle_read_file(arguments)
        when "write_file"     then handle_write_file(arguments)
        when "delete_file"    then handle_delete_file(arguments)
        when "list_files"     then handle_list_files(arguments)
        when "search_code"    then handle_search_code(arguments)
        when "get_file_info"  then handle_get_file_info(arguments)
        when "get_repo_info"  then handle_get_repo_info
        when "list_branches"  then handle_list_branches
        when "get_branch_diff" then handle_get_branch_diff(arguments)
        when "list_commits"   then handle_list_commits(arguments)
        else
          { success: false, error: "Unknown git tool: #{tool_name}" }
        end
      rescue StandardError => e
        Rails.logger.error("GitToolExecutor #{tool_name} failed: #{e.message}")
        { success: false, error: "#{tool_name} failed: #{e.message}" }
      end

      private

      def handle_read_file(arguments)
        path = arguments[:path]
        return { success: false, error: "path is required" } if path.blank?

        result = @git_client.get_file_content(@owner, @repo, path, @branch)
        return { success: false, error: "File not found: #{path}" } unless result

        content = result[:content]
        truncated = false

        if content && content.bytesize > MAX_FILE_SIZE
          content = content.byteslice(0, MAX_FILE_SIZE)
          truncated = true
        end

        {
          success: true,
          path: result[:path] || path,
          content: content,
          size: result[:size],
          truncated: truncated
        }
      end

      def handle_write_file(arguments)
        path = arguments[:path]
        content = arguments[:content]
        message = arguments[:message] || "Update #{path}"

        return { success: false, error: "path and content are required" } if path.blank? || content.nil?

        # Check if file exists to determine create vs update
        existing = @git_client.get_file_content(@owner, @repo, path, @branch)

        result = if existing && existing[:sha]
          @git_client.update_file(@owner, @repo, path, content, existing[:sha],
            message: message, branch: @branch)
        else
          @git_client.create_file(@owner, @repo, path, content,
            message: message, branch: @branch)
        end

        unless result[:success]
          return { success: false, error: result[:error] || "Failed to write file" }
        end

        operation = existing ? :updated : :created
        commit_sha = extract_commit_sha(result)
        @last_commit_sha = commit_sha if commit_sha

        @file_changes << { path: path, operation: operation, commit_sha: commit_sha }

        {
          success: true,
          path: path,
          operation: operation,
          commit_sha: commit_sha,
          message: message
        }
      end

      def handle_delete_file(arguments)
        path = arguments[:path]
        message = arguments[:message] || "Delete #{path}"

        return { success: false, error: "path is required" } if path.blank?

        # Get current SHA for deletion
        existing = @git_client.get_file_content(@owner, @repo, path, @branch)
        return { success: false, error: "File not found: #{path}" } unless existing && existing[:sha]

        result = @git_client.delete_file(@owner, @repo, path, existing[:sha],
          message: message, branch: @branch)

        unless result[:success]
          return { success: false, error: result[:error] || "Failed to delete file" }
        end

        commit_sha = extract_commit_sha(result)
        @last_commit_sha = commit_sha if commit_sha

        @file_changes << { path: path, operation: :deleted, commit_sha: commit_sha }

        { success: true, path: path, operation: :deleted, commit_sha: commit_sha }
      end

      def handle_list_files(arguments)
        path_filter = arguments[:path] || ""
        recursive = arguments[:recursive] == true

        # Get branch HEAD SHA for tree lookup
        branch_info = @git_client.get_branch(@owner, @repo, @branch)
        tree_sha = branch_info&.dig("commit", "id") || branch_info&.dig("commit", "sha")
        return { success: false, error: "Could not resolve branch HEAD" } unless tree_sha

        tree = @git_client.get_tree(@owner, @repo, tree_sha, recursive: recursive)
        return { success: false, error: "Could not retrieve tree" } unless tree

        entries = tree[:entries] || []

        # Filter by path prefix if specified
        if path_filter.present?
          prefix = path_filter.chomp("/")
          entries = entries.select { |e| e[:path]&.start_with?(prefix) }
        end

        {
          success: true,
          path: path_filter.presence || "/",
          entries: entries.map { |e| { path: e[:path], type: e[:type], size: e[:size] } },
          count: entries.size,
          truncated: tree[:truncated] || false
        }
      end

      def handle_search_code(arguments)
        query = arguments[:query]
        return { success: false, error: "query is required" } if query.blank?

        path_filter = arguments[:path_filter]

        # Attempt Gitea code search API
        result = @git_client.search_code(@owner, @repo, query, ref: @branch, limit: 20)

        if result[:success] && result[:results].is_a?(Array) && result[:results].any?
          matches = result[:results].map do |r|
            entry = { path: r["path"] || r[:path], name: r["name"] || r[:name] }
            entry[:path] = entry[:name] if entry[:path].blank?
            entry
          end

          if path_filter.present?
            matches = matches.select { |m| m[:path]&.start_with?(path_filter) }
          end

          return { success: true, query: query, matches: matches, count: matches.size }
        end

        # Fallback: list all files and filter by name containing query
        fallback_tree_search(query, path_filter)
      end

      def fallback_tree_search(query, path_filter)
        branch_info = @git_client.get_branch(@owner, @repo, @branch)
        tree_sha = branch_info&.dig("commit", "id") || branch_info&.dig("commit", "sha")
        return { success: false, error: "Could not resolve branch HEAD for search" } unless tree_sha

        tree = @git_client.get_tree(@owner, @repo, tree_sha, recursive: true)
        return { success: false, error: "Could not retrieve tree for search" } unless tree

        entries = (tree[:entries] || []).select { |e| e[:type] == "blob" }

        if path_filter.present?
          entries = entries.select { |e| e[:path]&.start_with?(path_filter) }
        end

        matches = entries.select { |e| e[:path]&.downcase&.include?(query.downcase) }
                        .first(20)
                        .map { |e| { path: e[:path], size: e[:size] } }

        {
          success: true,
          query: query,
          matches: matches,
          count: matches.size,
          note: "Filename-based search (content search not available)"
        }
      end

      def handle_get_file_info(arguments)
        path = arguments[:path]
        return { success: false, error: "path is required" } if path.blank?

        result = @git_client.get_file_content(@owner, @repo, path, @branch)
        return { success: false, error: "File not found: #{path}" } unless result

        {
          success: true,
          path: result[:path] || path,
          size: result[:size],
          sha: result[:sha],
          type: result[:type]
        }
      end

      def handle_get_repo_info
        result = @git_client.get_repository(@owner, @repo)

        {
          success: true,
          name: result["name"],
          full_name: result["full_name"],
          description: result["description"],
          default_branch: result["default_branch"],
          language: result["language"],
          size: result["size"] || result["repo_size"],
          updated_at: result["updated_at"],
          private: result["private"],
          topics: result["topics"]
        }
      end

      def handle_list_branches
        branches = @git_client.list_branches(@owner, @repo)
        branch_list = (branches || []).map do |b|
          {
            name: b["name"],
            commit_sha: b.dig("commit", "id") || b.dig("commit", "sha")
          }
        end

        { success: true, branches: branch_list, count: branch_list.size }
      end

      def handle_get_branch_diff(arguments)
        base_branch = arguments[:base_branch]
        return { success: false, error: "base_branch is required" } if base_branch.blank?

        result = @git_client.compare_commits(@owner, @repo, base_branch, @branch)
        return { success: false, error: "Could not compare branches" } unless result

        commits = (result[:commits] || []).map do |c|
          { sha: c[:sha] || c[:short_sha], message: c[:message] || c[:title] }
        end

        {
          success: true,
          base: base_branch,
          head: @branch,
          ahead_by: result[:ahead_by] || commits.size,
          commits: commits,
          files: (result[:files] || []).map { |f| { path: f[:filename], status: f[:status] } }
        }
      end

      def handle_list_commits(arguments)
        limit = (arguments[:limit] || 10).to_i.clamp(1, 50)

        commits = @git_client.list_commits(@owner, @repo, sha: @branch, per_page: limit)
        commit_list = (commits || []).map do |c|
          commit_data = c["commit"] || c
          {
            sha: c["sha"],
            message: commit_data.dig("message") || commit_data["message"],
            date: commit_data.dig("author", "date") || commit_data.dig("committer", "date")
          }
        end

        { success: true, commits: commit_list, count: commit_list.size }
      end

      def extract_commit_sha(result)
        # Gitea returns commit info in the content response
        result.dig(:content, "commit", "sha") ||
          result.dig(:content, "commit", "id") ||
          result.dig(:content, "sha")
      end
    end
  end
end
