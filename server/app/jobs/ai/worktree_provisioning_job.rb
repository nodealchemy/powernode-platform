# frozen_string_literal: true

module Ai
  class WorktreeProvisioningJob < ApplicationJob
    queue_as :ai_execution

    def perform(session_id)
      session = Ai::WorktreeSession.find(session_id)
      return if session.terminal?

      session.start!

      manager = Ai::Git::WorktreeManager.new(repository_path: session.repository_path)
      pending_worktrees = session.worktrees.where(status: "pending")

      # Enforce max_parallel limit
      max_concurrent = session.max_parallel

      success_count = 0
      fail_count = 0

      pending_worktrees.find_each do |worktree|
        provision_worktree(manager, session, worktree)
        success_count += 1
      rescue StandardError => e
        Rails.logger.error "[WorktreeProvisioning] Failed to provision #{worktree.branch_name}: #{e.message}"
        worktree.fail!(error_message: e.message, error_code: "PROVISIONING_FAILED")
        fail_count += 1
      end

      if success_count.zero?
        session.fail!(error_message: "All worktrees failed to provision", error_code: "ALL_PROVISIONING_FAILED")
      else
        session.activate!
        ::Ai::ConflictDetectionJob.perform_later(session.id)
      end
    rescue StandardError => e
      Rails.logger.error "[WorktreeProvisioning] Job failed: #{e.message}"
      session&.fail!(error_message: e.message, error_code: "PROVISIONING_JOB_FAILED")
    end

    private

    def provision_worktree(manager, session, worktree)
      worktree.mark_creating!
      worktree.lock!(reason: "provisioning")

      result = manager.create_worktree(
        session_id: session.id,
        branch_suffix: worktree.branch_name.split("/").last,
        base_branch: session.base_branch,
        base_commit: worktree.base_commit_sha
      )

      worktree.update!(
        worktree_path: result[:worktree_path],
        branch_name: result[:branch_name],
        base_commit_sha: result[:base_commit_sha],
        head_commit_sha: result[:base_commit_sha],
        copied_config_files: result[:copied_config_files]
      )

      worktree.unlock!
      worktree.mark_ready!

      health = manager.health_check(worktree_path: result[:worktree_path])
      worktree.update!(healthy: health[:healthy], health_message: health[:health_message]) unless health[:healthy]

      # Launch container execution if a template is configured
      launch_container_if_configured(worktree, session)
    end

    def launch_container_if_configured(worktree, session)
      template_id = worktree.container_template_id
      return unless template_id

      template = ::Devops::ContainerTemplate.find_by(id: template_id)
      return unless template

      orchestration = ::Devops::ContainerOrchestrationService.new(
        account: session.account,
        user: session.initiated_by || session.account.users.first
      )

      instance = orchestration.execute(
        template: template,
        input_parameters: {
          worktree_session_id: session.id,
          worktree_id: worktree.id,
          working_directory: worktree.worktree_path,
          branch_name: worktree.branch_name,
          metadata: worktree.metadata
        },
        timeout_seconds: template.timeout_seconds
      )

      worktree.track_container_instance!(instance.id)
      worktree.mark_in_use!
    rescue StandardError => e
      Rails.logger.error "[WorktreeProvisioning] Container launch failed for #{worktree.branch_name}: #{e.message}"
      # Don't fail the worktree — container execution is optional
    end
  end
end
