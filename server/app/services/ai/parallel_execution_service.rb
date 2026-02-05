# frozen_string_literal: true

module Ai
  class ParallelExecutionService
    attr_reader :account, :user

    def initialize(account:, user: nil)
      @account = account
      @user = user
    end

    # Start a parallel execution session
    #
    # @param source [ActiveRecord::Base] Originating model (RalphLoop, AgentTeam, etc.)
    # @param tasks [Array<Hash>] Tasks to execute: [{ task:, agent:, branch_suffix:, metadata: }]
    # @param repository_path [String] Local filesystem path to the repository
    # @param options [Hash] Configuration options
    # @return [Hash] Result with session details
    def start_session(source:, tasks:, repository_path:, options: {})
      return error_result("No tasks provided") if tasks.blank?
      return error_result("Repository path is required") if repository_path.blank?
      return error_result("Repository path does not exist") unless File.directory?(repository_path)
      return error_result("Repository path is outside allowed directories") unless valid_repository_path?(repository_path)

      session = nil

      ActiveRecord::Base.transaction do
        session = create_session(source, repository_path, tasks, options)
        create_worktree_records(session, tasks)
      end

      # Enqueue provisioning job
      ::Ai::WorktreeProvisioningJob.perform_later(session.id)

      success_result(
        session: session.session_summary,
        message: "Parallel session started with #{tasks.size} worktrees"
      )
    rescue StandardError => e
      Rails.logger.error "[ParallelExecution] Failed to start session: #{e.message}"
      error_result("Failed to start parallel session: #{e.message}")
    end

    # Cancel a running session
    def cancel_session(session_id:, reason: nil)
      session = account.ai_worktree_sessions.find(session_id)
      return error_result("Session is already terminal") if session.terminal?

      session.cancel!

      # Cancel active worktrees
      session.worktrees.active.find_each do |wt|
        wt.fail!(error_message: "Session cancelled: #{reason}")
      end

      # Enqueue cleanup
      ::Ai::WorktreeCleanupJob.perform_later(session.id) if session.auto_cleanup

      success_result(session: session.reload.session_summary, message: "Session cancelled")
    rescue ActiveRecord::RecordNotFound
      error_result("Session not found")
    end

    # Handle worktree completion
    def worktree_completed(worktree_id:, result: {})
      worktree = Ai::Worktree.find(worktree_id)
      session = worktree.worktree_session

      worktree.complete!(
        head_sha: result[:head_sha],
        stats: {
          files_changed: result[:files_changed],
          lines_added: result[:lines_added],
          lines_removed: result[:lines_removed]
        }
      )

      # Test gate: if session requires tests and they haven't passed, enter testing
      if session.require_tests? && result[:test_status] != "passed"
        worktree.update!(status: "testing", test_status: "pending")
        return success_result(worktree: worktree.reload.worktree_summary, testing: true)
      end

      # Use with_lock to prevent race conditions when checking session completion
      session.with_lock do
        session.reload
        if session.all_worktrees_completed? && session.status == "active"
          session.begin_merge!
          ::Ai::MergeExecutionJob.perform_later(session.id)
        end
      end

      success_result(worktree: worktree.worktree_summary)
    rescue StandardError => e
      Rails.logger.error "[ParallelExecution] worktree_completed failed: #{e.message}"
      error_result(e.message)
    end

    # Handle worktree failure
    def worktree_failed(worktree_id:, error:)
      worktree = Ai::Worktree.find(worktree_id)
      session = worktree.worktree_session

      worktree.fail!(error_message: error)

      if session.failure_policy == "abort"
        # Cancel remaining worktrees
        session.worktrees.active.where.not(id: worktree.id).find_each do |wt|
          wt.fail!(error_message: "Aborted due to failure in #{worktree.branch_name}")
        end
        session.fail!(error_message: "Aborted: #{error}")
      else
        # Use with_lock to prevent race conditions when checking session completion
        session.with_lock do
          session.reload
          if session.all_worktrees_completed?
            # All done (some failed), still try to merge completed ones
            completed_count = session.worktrees.where(status: %w[completed merged]).count
            if completed_count.positive? && session.status == "active"
              session.begin_merge!
              ::Ai::MergeExecutionJob.perform_later(session.id)
            elsif completed_count.zero? && session.status == "active"
              session.fail!(error_message: "All worktrees failed")
            end
          end
        end
      end

      success_result(worktree: worktree.reload.worktree_summary)
    rescue StandardError => e
      Rails.logger.error "[ParallelExecution] worktree_failed failed: #{e.message}"
      error_result(e.message)
    end

    # Get full session status
    def session_status(session_id:)
      session = account.ai_worktree_sessions
        .includes(worktrees: :ai_agent, merge_operations: [])
        .find(session_id)

      {
        session: session.session_summary,
        worktrees: session.worktrees.map(&:worktree_summary),
        merge_operations: session.merge_operations.by_order.map(&:operation_summary)
      }
    rescue ActiveRecord::RecordNotFound
      error_result("Session not found")
    end

    private

    def create_session(source, repository_path, tasks, options)
      account.ai_worktree_sessions.create!(
        initiated_by: user,
        source: source,
        repository_path: repository_path,
        base_branch: options[:base_branch] || "main",
        integration_branch: options[:integration_branch],
        merge_strategy: options[:merge_strategy] || "sequential",
        merge_config: options[:merge_config] || {},
        max_parallel: [ options[:max_parallel] || 4, 20 ].min,
        total_worktrees: tasks.size,
        auto_cleanup: options.fetch(:auto_cleanup, true),
        execution_mode: options[:execution_mode] || "complementary",
        max_duration_seconds: options[:max_duration_seconds],
        configuration: options[:configuration] || {},
        metadata: options[:metadata] || {}
      )
    end

    def create_worktree_records(session, tasks)
      manager = Ai::Git::WorktreeManager.new(repository_path: session.repository_path)
      base_sha = nil

      begin
        stdout, _stderr, status = Open3.capture3("git", "rev-parse", session.base_branch, chdir: session.repository_path)
        base_sha = stdout.strip if status.success?
      rescue StandardError
        # Will be resolved during provisioning
      end

      tasks.each do |task_config|
        short_id = session.id.to_s[0..7]
        suffix = task_config[:branch_suffix] || SecureRandom.hex(4)
        branch_name = "worktree/#{short_id}/#{suffix}"
        worktree_path = File.join(session.repository_path, Ai::Git::WorktreeManager::WORKTREE_BASE_DIR, short_id, suffix)

        worktree_metadata = task_config[:metadata] || {}
        worktree_metadata["container_template_id"] = task_config[:container_template_id] if task_config[:container_template_id]

        session.worktrees.create!(
          account: account,
          ai_agent_id: task_config[:agent]&.respond_to?(:id) ? task_config[:agent].id : task_config[:agent_id],
          assignee: task_config[:task],
          branch_name: branch_name,
          worktree_path: worktree_path,
          base_commit_sha: base_sha,
          timeout_at: session.max_duration_seconds ? Time.current + session.max_duration_seconds.seconds : nil,
          metadata: worktree_metadata
        )
      end
    end

    def success_result(data = {})
      { success: true }.merge(data)
    end

    def error_result(message)
      { success: false, error: message }
    end

    def valid_repository_path?(path)
      allowed = Rails.application.config.respond_to?(:allowed_repository_paths) ?
        Rails.application.config.allowed_repository_paths : nil
      return true unless allowed.present?

      expanded = File.expand_path(path)
      allowed.any? { |allowed_path| expanded.start_with?(File.expand_path(allowed_path)) }
    end

    def update_worktree_cost(worktree_id:, tokens:, cost_cents:)
      worktree = Ai::Worktree.find(worktree_id)
      worktree.update_cost!(tokens: tokens, cost_cents: cost_cents)
      success_result(worktree: worktree.reload.worktree_summary)
    rescue StandardError => e
      error_result(e.message)
    end
  end
end
