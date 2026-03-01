# frozen_string_literal: true

module Ai
  module Git
    class BranchProtectionService
      class ProtectedBranchViolation < StandardError; end
      class WorktreeRequiredViolation < StandardError; end

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Raises ProtectedBranchViolation if committing to a protected branch
      def validate_commit_target!(branch_name)
        return unless protection_enabled?

        if branch_protected?(branch_name)
          raise ProtectedBranchViolation,
            "Direct commits to protected branch '#{branch_name}' are not allowed. Use a worktree or feature branch."
        end
      end

      # Returns hash indicating whether merge is allowed and if approval is needed
      def validate_merge_target(target_branch)
        return { allowed: true, requires_approval: false } unless protection_enabled?

        if branch_protected?(target_branch) && config.merge_approval_required
          {
            allowed: false,
            requires_approval: true,
            target_branch: target_branch,
            message: "Merge to protected branch '#{target_branch}' requires human approval"
          }
        else
          { allowed: true, requires_approval: false }
        end
      end

      # Raises WorktreeRequiredViolation if not working in a worktree
      def validate_worktree_usage!(repository_path:, working_dir:)
        return unless protection_enabled?
        return unless config.require_worktree_for_repos

        # A worktree working directory should differ from the main repository path
        return if working_dir != repository_path

        raise WorktreeRequiredViolation,
          "Operations must use git worktrees when branch protection is enabled. " \
          "Working directly in the main repository is not allowed."
      end

      # Returns current protection configuration summary
      def protection_summary
        {
          enabled: protection_enabled?,
          protected_branches: config&.protected_branches || [],
          require_worktree: config&.require_worktree_for_repos || false,
          merge_approval_required: config&.merge_approval_required || false,
          config: config&.branch_protection_config || {}
        }
      end

      # Check if a specific branch is protected
      def branch_protected?(branch_name)
        return false unless protection_enabled?

        protected_list = config.protected_branches || []
        protected_list.any? { |pattern| File.fnmatch(pattern, branch_name) }
      end

      private

      def protection_enabled?
        config&.branch_protection_enabled == true
      end

      def config
        @config ||= Ai::GuardrailConfig
          .where(account: account, ai_agent_id: nil)
          .active
          .first
      end
    end
  end
end
