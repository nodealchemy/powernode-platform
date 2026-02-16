# frozen_string_literal: true

require "open3"

module Ai
  module Git
    class WorktreeManager
      class WorktreeError < StandardError; end
      class BranchExistsError < WorktreeError; end
      class PathExistsError < WorktreeError; end

      WORKTREE_BASE_DIR = "tmp/worktrees"
      CONFIG_FILES_TO_COPY = %w[.env .env.local .tool-versions .ruby-version .node-version].freeze

      attr_reader :repository_path

      def initialize(repository_path:)
        @repository_path = repository_path
      end

      def create_worktree(session_id:, branch_suffix:, base_branch: "main", base_commit: nil)
        short_id = session_id.to_s[0..7]
        branch_name = "worktree/#{short_id}/#{branch_suffix}"
        worktree_path = File.join(repository_path, WORKTREE_BASE_DIR, short_id, branch_suffix)

        raise PathExistsError, "Worktree path already exists: #{worktree_path}" if File.exist?(worktree_path)

        # Create base directory
        FileUtils.mkdir_p(File.dirname(worktree_path))

        # Determine start point
        start_point = base_commit || base_branch

        # Create worktree with new branch
        stdout, stderr, status = run_git("worktree", "add", "-b", branch_name, worktree_path, start_point)

        unless status.success?
          if stderr.include?("already exists")
            raise BranchExistsError, "Branch already exists: #{branch_name}"
          end
          raise WorktreeError, "Failed to create worktree: #{stderr}"
        end

        # Get the base commit SHA
        base_sha = run_git_output("rev-parse", start_point).strip

        # Copy config files
        copied_files = copy_config_files(worktree_path)

        {
          branch_name: branch_name,
          worktree_path: worktree_path,
          base_commit_sha: base_sha,
          copied_config_files: copied_files
        }
      end

      def remove_worktree(worktree_path:, branch_name: nil, force: false)
        args = ["worktree", "remove"]
        args << "--force" if force
        args << worktree_path

        _stdout, stderr, status = run_git(*args)

        unless status.success?
          if force
            # Force removal of directory if git worktree remove fails
            FileUtils.rm_rf(worktree_path) if File.exist?(worktree_path)
            run_git("worktree", "prune")
          else
            raise WorktreeError, "Failed to remove worktree: #{stderr}"
          end
        end

        # Delete the branch if requested
        if branch_name
          run_git("branch", "-D", branch_name)
        end

        true
      end

      def lock_worktree(worktree_path:, reason: nil)
        args = ["worktree", "lock", worktree_path]
        args.push("--reason", reason) if reason

        _stdout, stderr, status = run_git(*args)
        raise WorktreeError, "Failed to lock worktree: #{stderr}" unless status.success?

        true
      end

      def unlock_worktree(worktree_path:)
        _stdout, stderr, status = run_git("worktree", "unlock", worktree_path)
        raise WorktreeError, "Failed to unlock worktree: #{stderr}" unless status.success?

        true
      end

      def health_check(worktree_path:)
        return { healthy: false, health_message: "Path does not exist" } unless File.exist?(worktree_path)

        head_sha = run_git_in("rev-parse", "HEAD", dir: worktree_path).strip
        dirty_output = run_git_in("status", "--porcelain", dir: worktree_path).strip
        dirty_files = dirty_output.lines.map(&:strip).reject(&:empty?)

        {
          healthy: true,
          head_sha: head_sha,
          dirty: dirty_files.any?,
          dirty_files: dirty_files
        }
      rescue StandardError => e
        { healthy: false, health_message: e.message }
      end

      def diff_stats(worktree_path:, base_branch:)
        output = run_git_in("diff", "--stat", "#{base_branch}...HEAD", dir: worktree_path)

        # Parse the summary line: " 5 files changed, 120 insertions(+), 30 deletions(-)"
        if output =~ /(\d+) files? changed(?:, (\d+) insertions?\(\+\))?(?:, (\d+) deletions?\(-\))?/
          {
            files_changed: $1.to_i,
            lines_added: ($2 || 0).to_i,
            lines_removed: ($3 || 0).to_i
          }
        else
          { files_changed: 0, lines_added: 0, lines_removed: 0 }
        end
      rescue StandardError
        { files_changed: 0, lines_added: 0, lines_removed: 0 }
      end

      def list_worktrees
        output = run_git_output("worktree", "list", "--porcelain")
        parse_worktree_list(output)
      end

      def prune
        run_git("worktree", "prune")
      end

      def push_branch(branch_name:, remote: "origin", force: false)
        validate_branch_name!(branch_name)

        args = ["push", remote, branch_name]
        args.insert(1, "--force-with-lease") if force

        log_info("Pushing branch #{branch_name} to #{remote}#{force ? ' (force)' : ''}")
        run_git_output(*args)

        { success: true, branch: branch_name, remote: remote }
      rescue StandardError => e
        log_error("Failed to push branch #{branch_name}: #{e.message}")
        { success: false, error: e.message }
      end

      def ensure_remote(remote_name:, remote_url:)
        existing = run_git_output("remote", "get-url", remote_name) rescue nil

        if existing.present?
          if existing.strip != remote_url
            run_git_output("remote", "set-url", remote_name, remote_url)
            log_info("Updated remote #{remote_name} URL to #{remote_url}")
          end
        else
          run_git_output("remote", "add", remote_name, remote_url)
          log_info("Added remote #{remote_name}: #{remote_url}")
        end

        { success: true, remote: remote_name, url: remote_url }
      rescue StandardError => e
        log_error("Failed to ensure remote #{remote_name}: #{e.message}")
        { success: false, error: e.message }
      end

      def fetch_branch(branch_name:, remote: "origin")
        log_info("Fetching branch #{branch_name} from #{remote}")
        run_git_output("fetch", remote, branch_name)

        { success: true, branch: branch_name, remote: remote }
      rescue StandardError => e
        log_error("Failed to fetch branch #{branch_name}: #{e.message}")
        { success: false, error: e.message }
      end

      private

      def run_git(*args)
        Open3.capture3("git", *args, chdir: repository_path)
      end

      def run_git_output(*args)
        stdout, stderr, status = run_git(*args)
        raise WorktreeError, "Git command failed: #{stderr}" unless status.success?

        stdout
      end

      def run_git_in(*args, dir:)
        stdout, stderr, status = Open3.capture3("git", *args, chdir: dir)
        raise WorktreeError, "Git command failed: #{stderr}" unless status.success?

        stdout
      end

      def copy_config_files(worktree_path)
        copied = []

        CONFIG_FILES_TO_COPY.each do |filename|
          source = File.join(repository_path, filename)
          next unless File.exist?(source)

          dest = File.join(worktree_path, filename)
          FileUtils.cp(source, dest)
          copied << filename
        end

        copied
      end

      def validate_branch_name!(name)
        raise ArgumentError, "Invalid branch name: #{name}" unless name.match?(/\A[a-zA-Z0-9\/_\-\.]+\z/)
      end

      def log_info(message)
        Rails.logger.info("[WorktreeManager] #{message}")
      end

      def log_error(message)
        Rails.logger.error("[WorktreeManager] #{message}")
      end

      def parse_worktree_list(output)
        worktrees = []
        current = {}

        output.each_line do |line|
          line = line.strip
          if line.empty?
            worktrees << current if current[:worktree]
            current = {}
          elsif line.start_with?("worktree ")
            current[:worktree] = line.sub("worktree ", "")
          elsif line.start_with?("HEAD ")
            current[:head] = line.sub("HEAD ", "")
          elsif line.start_with?("branch ")
            current[:branch] = line.sub("branch ", "")
          elsif line == "bare"
            current[:bare] = true
          elsif line == "detached"
            current[:detached] = true
          elsif line.start_with?("locked")
            current[:locked] = true
            current[:lock_reason] = line.sub("locked ", "").strip if line.length > 6
          end
        end

        worktrees << current if current[:worktree]
        worktrees
      end
    end
  end
end
