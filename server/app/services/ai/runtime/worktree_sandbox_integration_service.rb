# frozen_string_literal: true

module Ai
  module Runtime
    class WorktreeSandboxIntegrationService
      class IntegrationError < StandardError; end

      LOG_TAG = "[WorktreeSandboxIntegration]"

      attr_reader :account, :user

      def initialize(account:, user: nil)
        @account = account
        @user = user
        @sandbox_manager = Ai::Runtime::SandboxManagerService.new(account: account)
      end

      # Provision a sandbox with a worktree mounted as workspace.
      # Called by WorktreeProvisioningJob after the worktree is created on disk.
      #
      # @param worktree [Ai::Worktree] the worktree record (must have worktree_path set)
      # @param agent [Ai::Agent] the agent that will work inside the sandbox
      # @param config [Hash] additional sandbox configuration overrides
      # @return [Hash] { success:, sandbox:, worktree_path: } or { success: false, error: }
      def provision_sandbox_for_worktree(worktree:, agent:, config: {})
        Rails.logger.info("#{LOG_TAG} Provisioning sandbox for worktree #{worktree.id} (agent: #{agent.id})")

        validate_worktree_for_provisioning!(worktree)

        sandbox_config = build_sandbox_config(worktree, config)
        instance = @sandbox_manager.create_sandbox(agent: agent, config: sandbox_config)

        worktree.track_container_instance!(instance.id)

        Rails.logger.info(
          "#{LOG_TAG} Sandbox #{instance.execution_id} provisioned for worktree #{worktree.id}"
        )

        success_result(
          sandbox: instance.instance_summary,
          worktree_path: worktree.worktree_path,
          execution_id: instance.execution_id
        )
      rescue IntegrationError => e
        Rails.logger.error("#{LOG_TAG} Provisioning failed for worktree #{worktree.id}: #{e.message}")
        error_result(e.message)
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} Unexpected error provisioning sandbox for worktree #{worktree.id}: #{e.message}")
        error_result("Failed to provision sandbox: #{e.message}")
      end

      # Teardown the sandbox associated with a worktree.
      #
      # @param worktree [Ai::Worktree] the worktree whose sandbox should be destroyed
      # @param reason [String] reason for teardown
      # @return [Hash] { success: } or { success: false, error: }
      def teardown_sandbox_for_worktree(worktree:, reason: "work_completed")
        instance_id = worktree.container_instance_id
        unless instance_id
          Rails.logger.info("#{LOG_TAG} No sandbox to teardown for worktree #{worktree.id}")
          return success_result(message: "No sandbox associated with worktree")
        end

        instance = find_container_instance(instance_id)
        return error_result("Container instance #{instance_id} not found") unless instance

        unless instance.active?
          Rails.logger.info("#{LOG_TAG} Sandbox #{instance.execution_id} already inactive (#{instance.status})")
          return success_result(message: "Sandbox already inactive", status: instance.status)
        end

        destroyed = @sandbox_manager.destroy_sandbox(instance: instance, reason: reason)

        if destroyed
          Rails.logger.info("#{LOG_TAG} Sandbox #{instance.execution_id} destroyed for worktree #{worktree.id}")
          success_result(execution_id: instance.execution_id, message: "Sandbox destroyed")
        else
          error_result("Failed to destroy sandbox #{instance.execution_id}")
        end
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} Teardown failed for worktree #{worktree.id}: #{e.message}")
        error_result("Failed to teardown sandbox: #{e.message}")
      end

      # Provision sandboxes for all worktrees in a session.
      #
      # @param session [Ai::WorktreeSession] the worktree session
      # @param agents_map [Hash] maps worktree_id => Ai::Agent
      # @return [Hash] { success:, results: [{ worktree_id:, success:, ... }] }
      def provision_session_sandboxes(session:, agents_map: {})
        Rails.logger.info("#{LOG_TAG} Provisioning sandboxes for session #{session.id}")

        worktrees = session.worktrees.where(status: %w[pending creating ready])
        if worktrees.empty?
          Rails.logger.info("#{LOG_TAG} No provisionable worktrees in session #{session.id}")
          return success_result(results: [], message: "No worktrees to provision")
        end

        results = worktrees.map do |worktree|
          agent = agents_map[worktree.id] || worktree.ai_agent
          unless agent
            Rails.logger.warn("#{LOG_TAG} No agent found for worktree #{worktree.id}, skipping sandbox")
            next { worktree_id: worktree.id, success: false, error: "No agent assigned" }
          end

          result = provision_sandbox_for_worktree(worktree: worktree, agent: agent)
          result.merge(worktree_id: worktree.id)
        end

        succeeded = results.count { |r| r[:success] }
        failed = results.count { |r| !r[:success] }

        Rails.logger.info(
          "#{LOG_TAG} Session #{session.id} sandbox provisioning: #{succeeded} succeeded, #{failed} failed"
        )

        success_result(
          results: results,
          succeeded: succeeded,
          failed: failed,
          message: "Provisioned #{succeeded}/#{results.size} sandboxes"
        )
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} Session sandbox provisioning failed for #{session.id}: #{e.message}")
        error_result("Failed to provision session sandboxes: #{e.message}")
      end

      # Teardown all sandboxes in a session.
      #
      # @param session [Ai::WorktreeSession] the worktree session
      # @param reason [String] reason for teardown
      # @return [Hash] { success:, results: [...] }
      def teardown_session_sandboxes(session:, reason: "session_completed")
        Rails.logger.info("#{LOG_TAG} Tearing down sandboxes for session #{session.id}")

        worktrees = session.worktrees.where.not(metadata: nil)
        results = []

        worktrees.find_each do |worktree|
          next unless worktree.container_instance_id

          result = teardown_sandbox_for_worktree(worktree: worktree, reason: reason)
          results << result.merge(worktree_id: worktree.id)
        end

        succeeded = results.count { |r| r[:success] }

        Rails.logger.info(
          "#{LOG_TAG} Session #{session.id} teardown: #{succeeded}/#{results.size} sandboxes destroyed"
        )

        success_result(
          results: results,
          succeeded: succeeded,
          total: results.size,
          message: "Destroyed #{succeeded}/#{results.size} sandboxes"
        )
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} Session teardown failed for #{session.id}: #{e.message}")
        error_result("Failed to teardown session sandboxes: #{e.message}")
      end

      # Execute a command inside the sandbox associated with a worktree.
      #
      # @param worktree [Ai::Worktree] the worktree
      # @param command [String] the command to execute
      # @return [Hash] { success:, execution_id:, command: } or { success: false, error: }
      def exec_in_worktree_sandbox(worktree:, command:)
        instance = resolve_container_instance(worktree)
        return instance if instance.is_a?(Hash) && !instance[:success]

        result = @sandbox_manager.exec_in_sandbox(instance: instance, command: command)

        if result[:success]
          Rails.logger.info("#{LOG_TAG} Executed command in sandbox #{instance.execution_id} for worktree #{worktree.id}")
        else
          Rails.logger.warn("#{LOG_TAG} Command execution failed in sandbox #{instance.execution_id}: #{result[:error]}")
        end

        result
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} Exec failed for worktree #{worktree.id}: #{e.message}")
        error_result("Failed to execute command: #{e.message}")
      end

      # Get combined health status of both the git worktree and its sandbox.
      #
      # @param worktree [Ai::Worktree] the worktree to check
      # @return [Hash] combined health report
      def health_check(worktree:)
        git_health = check_git_health(worktree)
        sandbox_health = check_sandbox_health(worktree)

        overall_healthy = git_health[:healthy] && sandbox_health[:healthy]

        {
          success: true,
          healthy: overall_healthy,
          worktree_id: worktree.id,
          git: git_health,
          sandbox: sandbox_health,
          checked_at: Time.current.iso8601
        }
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} Health check failed for worktree #{worktree.id}: #{e.message}")
        {
          success: false,
          healthy: false,
          worktree_id: worktree.id,
          error: "Health check failed: #{e.message}",
          checked_at: Time.current.iso8601
        }
      end

      # Pause the sandbox associated with a worktree (e.g., when idle).
      #
      # @param worktree [Ai::Worktree] the worktree
      # @return [Hash] { success: } or { success: false, error: }
      def pause_worktree_sandbox(worktree:)
        instance = resolve_container_instance(worktree)
        return instance if instance.is_a?(Hash) && !instance[:success]

        result = @sandbox_manager.pause_sandbox(instance: instance)

        if result[:success]
          Rails.logger.info("#{LOG_TAG} Paused sandbox #{instance.execution_id} for worktree #{worktree.id}")
        else
          Rails.logger.warn("#{LOG_TAG} Failed to pause sandbox #{instance.execution_id}: #{result[:error]}")
        end

        result
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} Pause failed for worktree #{worktree.id}: #{e.message}")
        error_result("Failed to pause sandbox: #{e.message}")
      end

      # Resume a paused sandbox associated with a worktree.
      #
      # @param worktree [Ai::Worktree] the worktree
      # @return [Hash] { success: } or { success: false, error: }
      def resume_worktree_sandbox(worktree:)
        instance = resolve_container_instance(worktree)
        return instance if instance.is_a?(Hash) && !instance[:success]

        result = @sandbox_manager.resume_sandbox(instance: instance)

        if result[:success]
          Rails.logger.info("#{LOG_TAG} Resumed sandbox #{instance.execution_id} for worktree #{worktree.id}")
        else
          Rails.logger.warn("#{LOG_TAG} Failed to resume sandbox #{instance.execution_id}: #{result[:error]}")
        end

        result
      rescue StandardError => e
        Rails.logger.error("#{LOG_TAG} Resume failed for worktree #{worktree.id}: #{e.message}")
        error_result("Failed to resume sandbox: #{e.message}")
      end

      private

      # Build sandbox configuration that mounts the worktree as a workspace volume.
      def build_sandbox_config(worktree, config)
        workspace_volume = "#{worktree.worktree_path}:/workspace"

        volumes = Array(config[:volumes])
        volumes << workspace_volume unless volumes.include?(workspace_volume)

        environment = (config[:environment] || {}).merge(
          "WORKSPACE_PATH" => "/workspace",
          "WORKTREE_ID" => worktree.id,
          "WORKTREE_BRANCH" => worktree.branch_name,
          "SESSION_ID" => worktree.worktree_session_id
        )

        labels = (config[:labels] || {}).merge(
          "powernode.worktree_id" => worktree.id,
          "powernode.session_id" => worktree.worktree_session_id,
          "powernode.branch" => worktree.branch_name
        )

        template_id = worktree.container_template_id
        base_config = config.except(:volumes, :environment, :labels)
        base_config[:container_template_id] = template_id if template_id

        base_config.merge(
          volumes: volumes,
          environment: environment,
          labels: labels
        )
      end

      # Validate that a worktree is in a valid state for sandbox provisioning.
      def validate_worktree_for_provisioning!(worktree)
        if worktree.worktree_path.blank?
          raise IntegrationError, "Worktree #{worktree.id} has no worktree_path"
        end

        if worktree.container_instance_id.present?
          existing = find_container_instance(worktree.container_instance_id)
          if existing&.active?
            raise IntegrationError,
                  "Worktree #{worktree.id} already has an active sandbox (#{existing.execution_id})"
          end
        end

        if worktree.status.in?(%w[completed merged cleaned_up failed])
          raise IntegrationError, "Worktree #{worktree.id} is in terminal status: #{worktree.status}"
        end
      end

      # Resolve the container instance for a worktree, returning an error hash if not found.
      def resolve_container_instance(worktree)
        instance_id = worktree.container_instance_id
        unless instance_id
          return error_result("No sandbox associated with worktree #{worktree.id}")
        end

        instance = find_container_instance(instance_id)
        unless instance
          return error_result("Container instance #{instance_id} not found for worktree #{worktree.id}")
        end

        instance
      end

      # Look up a container instance by ID, scoped to the account.
      def find_container_instance(instance_id)
        Devops::ContainerInstance.find_by(id: instance_id, account_id: account.id)
      end

      # Check git worktree health via WorktreeManager.
      def check_git_health(worktree)
        session = worktree.worktree_session
        unless session&.repository_path.present?
          return { healthy: false, error: "No repository path on session" }
        end

        manager = Ai::Git::WorktreeManager.new(repository_path: session.repository_path)
        manager.health_check(worktree_path: worktree.worktree_path)
      rescue StandardError => e
        { healthy: false, error: "Git health check failed: #{e.message}" }
      end

      # Check sandbox container health via SandboxManagerService metrics.
      def check_sandbox_health(worktree)
        instance_id = worktree.container_instance_id
        unless instance_id
          return { healthy: false, error: "No sandbox associated", status: "none" }
        end

        instance = find_container_instance(instance_id)
        unless instance
          return { healthy: false, error: "Container instance not found", status: "missing" }
        end

        metrics = @sandbox_manager.get_metrics(instance: instance)

        {
          healthy: instance.running?,
          status: instance.status,
          execution_id: instance.execution_id,
          metrics: metrics
        }
      rescue StandardError => e
        { healthy: false, error: "Sandbox health check failed: #{e.message}" }
      end

      def success_result(data = {})
        { success: true }.merge(data)
      end

      def error_result(message)
        { success: false, error: message }
      end
    end
  end
end
