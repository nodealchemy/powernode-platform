# frozen_string_literal: true

require "open3"

module Ai
  module Git
    class ConflictDetectionService
      attr_reader :session

      def initialize(session:)
        @session = session
      end

      # Run conflict detection between all active worktree pairs using git merge-tree
      def detect
        worktrees = session.worktrees.where(status: %w[in_use completed testing]).to_a
        return { conflicts: [], matrix: {} } if worktrees.size < 2

        # Get the merge base for all comparisons
        base_sha = resolve_base_sha
        return { conflicts: [], matrix: {}, error: "Could not resolve base SHA" } unless base_sha

        matrix = {}
        conflicts = []

        worktrees.combination(2).each do |wt_a, wt_b|
          result = check_pair(base_sha, wt_a, wt_b)
          key = "#{wt_a.id}:#{wt_b.id}"
          matrix[key] = result

          if result[:has_conflicts]
            conflicts << {
              worktree_a_id: wt_a.id,
              worktree_a_branch: wt_a.branch_name,
              worktree_b_id: wt_b.id,
              worktree_b_branch: wt_b.branch_name,
              conflict_files: result[:conflict_files]
            }
          end
        end

        # Store the matrix on the session
        session.update_conflict_matrix!(matrix)

        # Broadcast the result
        broadcast_conflicts(conflicts)

        { conflicts: conflicts, matrix: matrix }
      rescue StandardError => e
        Rails.logger.error "[ConflictDetection] Failed: #{e.message}"
        { conflicts: [], matrix: {}, error: e.message }
      end

      private

      def resolve_base_sha
        stdout, _stderr, status = Open3.capture3(
          "git", "rev-parse", session.base_branch,
          chdir: session.repository_path
        )
        status.success? ? stdout.strip : nil
      end

      def check_pair(base_sha, wt_a, wt_b)
        sha_a = wt_a.head_commit_sha
        sha_b = wt_b.head_commit_sha

        return { has_conflicts: false, conflict_files: [] } unless sha_a && sha_b

        # git merge-tree performs a three-way merge without modifying the repository
        stdout, _stderr, status = Open3.capture3(
          "git", "merge-tree", base_sha, sha_a, sha_b,
          chdir: session.repository_path
        )

        # merge-tree outputs conflict markers if there are conflicts
        conflict_files = []
        if stdout.present?
          # Parse merge-tree output for conflict indicators
          stdout.each_line do |line|
            if line =~ /^  our\s+\d+\s+\w+\s+(.+)$/ || line =~ /^  their\s+\d+\s+\w+\s+(.+)$/
              conflict_files << $1.strip
            end
          end
          conflict_files = conflict_files.uniq
        end

        # Non-zero exit = conflicts exist
        has_conflicts = !status.success? || conflict_files.any?

        { has_conflicts: has_conflicts, conflict_files: conflict_files }
      rescue StandardError => e
        Rails.logger.warn "[ConflictDetection] Pair check failed: #{e.message}"
        { has_conflicts: false, conflict_files: [], error: e.message }
      end

      def broadcast_conflicts(conflicts)
        return if conflicts.empty?

        AiOrchestrationChannel.broadcast_worktree_session_event(
          session,
          "conflicts_detected",
          { conflicts: conflicts, detected_at: Time.current.iso8601 }
        )
      rescue StandardError => e
        Rails.logger.warn "[ConflictDetection] Broadcast failed: #{e.message}"
      end
    end
  end
end
