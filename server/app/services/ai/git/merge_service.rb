# frozen_string_literal: true

require "open3"

module Ai
  module Git
    class MergeService
      attr_reader :session, :manager

      def initialize(session:)
        @session = session
        @manager = Ai::Git::WorktreeManager.new(repository_path: session.repository_path)
      end

      # Execute the merge strategy for the session
      def execute
        return execute_competitive if session.competitive?

        case session.merge_strategy
        when "sequential"
          execute_sequential
        when "integration_branch"
          execute_integration_branch
        when "manual"
          execute_manual
        else
          { success: false, error: "Unknown merge strategy: #{session.merge_strategy}" }
        end
      rescue StandardError => e
        Rails.logger.error "[MergeService] Merge failed: #{e.message}"
        { success: false, error: e.message }
      end

      # Rollback a specific merge operation
      def rollback(merge_operation_id:)
        operation = session.merge_operations.find(merge_operation_id)

        unless operation.can_rollback?
          return { success: false, error: "Cannot rollback this merge operation" }
        end

        # Revert the merge commit
        stdout, stderr, status = run_git("revert", "-m", "1", "--no-edit", operation.merge_commit_sha)

        if status.success?
          revert_sha = run_git_output("rev-parse", "HEAD").strip
          operation.rollback!(rollback_sha: revert_sha)
          { success: true, rollback_sha: revert_sha }
        else
          { success: false, error: "Rollback failed: #{stderr}" }
        end
      end

      private

      # Sequential: merge worktrees one at a time into base branch
      def execute_sequential
        target = session.base_branch
        completed_worktrees = session.worktrees.where(status: %w[completed]).order(:completed_at)
        results = []

        completed_worktrees.each_with_index do |worktree, index|
          operation = create_merge_operation(worktree, target, index)
          result = perform_merge(operation, worktree.branch_name, target)
          results << result

          # Stop on first conflict or failure in sequential mode
          if result[:status].in?(%w[conflict failed])
            Rails.logger.warn "[MergeService] #{result[:status].capitalize} in sequential merge at #{worktree.branch_name}"
            break
          end

          # Mark worktree as merged on success
          worktree.mark_merged! if result[:status] == "completed"
        end

        all_ok = results.all? { |r| r[:status] == "completed" }
        { success: all_ok, results: results }
      end

      # Integration branch: merge all into a dedicated branch
      def execute_integration_branch
        integration = session.integration_branch || "integration/#{session.id.to_s[0..7]}"

        # Create integration branch from base
        run_git("checkout", "-b", integration, session.base_branch)

        completed_worktrees = session.worktrees.where(status: "completed").order(:completed_at)
        results = []

        completed_worktrees.each_with_index do |worktree, index|
          operation = create_merge_operation(worktree, integration, index)
          result = perform_merge(operation, worktree.branch_name, integration)
          results << result

          # Continue past conflicts in integration mode (record them)
          if result[:status] == "conflict"
            # Abort this merge and continue to next
            begin
              run_git("merge", "--abort")
            rescue StandardError => e
              Rails.logger.error "[MergeService] merge --abort failed: #{e.message}"
            end
          else
            worktree.mark_merged! if result[:status] == "completed"
          end
        end

        # Switch back to base branch
        run_git("checkout", session.base_branch)

        # Update session with integration branch name
        session.update!(integration_branch: integration)

        all_ok = results.all? { |r| r[:status] == "completed" }
        { success: all_ok, results: results, integration_branch: integration }
      end

      # Manual: create merge operation records, leave branches for manual PR creation
      def execute_manual
        completed_worktrees = session.worktrees.where(status: "completed").order(:completed_at)
        results = []

        completed_worktrees.each_with_index do |worktree, index|
          operation = create_merge_operation(worktree, session.base_branch, index)
          # Leave as pending for manual handling
          results << {
            status: "pending",
            merge_operation_id: operation.id,
            source_branch: worktree.branch_name,
            target_branch: session.base_branch
          }
        end

        { success: true, results: results, manual: true }
      end

      def create_merge_operation(worktree, target_branch, order)
        strategy = session.merge_config&.dig("squash") ? "squash" : "merge"

        session.merge_operations.create!(
          worktree: worktree,
          account: session.account,
          source_branch: worktree.branch_name,
          target_branch: target_branch,
          strategy: strategy,
          merge_order: order
        )
      end

      def perform_merge(operation, source_branch, target_branch)
        operation.start!

        merge_args = case operation.strategy
        when "squash"
                       ["merge", "--squash", source_branch]
        when "rebase"
                       ["rebase", source_branch]
        else
                       ["merge", "--no-ff", source_branch]
        end

        _stdout, stderr, status = run_git(*merge_args)

        if status.success?
          # For squash merges, we need to commit
          if operation.strategy == "squash"
            run_git("commit", "-m", "Merge #{source_branch} into #{target_branch} (squash)")
          end

          sha = run_git_output("rev-parse", "HEAD").strip
          operation.complete!(merge_commit_sha: sha)

          { status: "completed", merge_commit_sha: sha, merge_operation_id: operation.id }
        elsif stderr.include?("CONFLICT") || stderr.include?("Merge conflict")
          conflict_files = parse_conflict_files
          operation.mark_conflict!(
            conflict_files: conflict_files,
            conflict_details: stderr
          )
          { status: "conflict", conflict_files: conflict_files, merge_operation_id: operation.id }
        else
          operation.fail!(error_message: stderr)
          { status: "failed", error: stderr, merge_operation_id: operation.id }
        end
      rescue StandardError => e
        operation.fail!(error_message: e.message)
        { status: "failed", error: e.message, merge_operation_id: operation.id }
      end

      def parse_conflict_files
        output = run_git_output("diff", "--name-only", "--diff-filter=U")
        output.lines.map(&:strip).reject(&:empty?)
      rescue StandardError
        []
      end

      # Competitive mode: evaluate all completed worktrees and merge only the best one
      def execute_competitive
        completed_worktrees = session.worktrees.where(status: "completed").order(:completed_at)
        return { success: false, error: "No completed worktrees" } if completed_worktrees.empty?

        # In competitive mode, evaluate all results and pick the best
        evaluations = completed_worktrees.map do |wt|
          stats = @manager.diff_stats(worktree_path: wt.worktree_path, base_branch: session.base_branch)
          health = @manager.health_check(worktree_path: wt.worktree_path)

          {
            worktree_id: wt.id,
            branch_name: wt.branch_name,
            files_changed: stats[:files_changed],
            lines_added: stats[:lines_added],
            lines_removed: stats[:lines_removed],
            commit_count: wt.commit_count,
            duration_ms: wt.duration_ms,
            tokens_used: wt.tokens_used,
            healthy: health[:healthy],
            dirty: health[:dirty] || false,
            test_status: wt.test_status
          }
        end

        # Score: prefer passed tests, fewer tokens, cleaner diffs, faster completion
        winner = evaluations.max_by do |e|
          score = 0
          score += 100 if e[:test_status] == "passed"
          score += 50 if e[:healthy] && !e[:dirty]
          score -= (e[:tokens_used] || 0) / 1000  # Penalize token usage
          score -= (e[:duration_ms] || 0) / 60_000  # Penalize slower runs
          score
        end

        # Only merge the winner
        winner_wt = completed_worktrees.find { |wt| wt.id == winner[:worktree_id] }
        operation = create_merge_operation(winner_wt, session.base_branch, 0)
        result = perform_merge(operation, winner_wt.branch_name, session.base_branch)

        winner_wt.mark_merged! if result[:status] == "completed"

        # Store evaluation metadata
        session.update!(metadata: (session.metadata || {}).merge(
          "competition_evaluations" => evaluations,
          "winner_worktree_id" => winner[:worktree_id]
        ))

        {
          success: result[:status] == "completed",
          results: [result],
          evaluations: evaluations,
          winner: winner,
          competitive: true
        }
      end

      def run_git(*args)
        Open3.capture3("git", *args, chdir: session.repository_path)
      end

      def run_git_output(*args)
        stdout, stderr, status = run_git(*args)
        raise Ai::Git::WorktreeManager::WorktreeError, "Git command failed: #{stderr}" unless status.success?

        stdout
      end
    end
  end
end
