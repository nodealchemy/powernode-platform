# frozen_string_literal: true

module Devops
  class ContainerOrchestrationService
    class OrchestrationError < StandardError; end
    class QuotaExceededError < OrchestrationError; end
    class TemplateNotFoundError < OrchestrationError; end
    class ExecutionError < OrchestrationError; end

    attr_reader :account, :user

    def initialize(account:, user:)
      @account = account
      @user = user
      @gitea_client = build_gitea_client
    end

    # Execute a container from template
    def execute(template:, input_parameters: {}, timeout_seconds: nil, a2a_task: nil)
      # Verify access
      unless template.accessible_by?(account)
        raise TemplateNotFoundError, "Template not accessible"
      end

      # Check quotas
      quota_service = QuotaService.new(account)
      quota_service.check_execution_allowed!

      # Create container instance
      instance = create_instance(template, input_parameters, timeout_seconds, a2a_task)

      begin
        # Generate short-lived Vault token
        vault_token_data = generate_vault_token(instance)
        instance.update!(vault_token_id: vault_token_data[:token_accessor])

        # Trigger Gitea workflow
        workflow_run = trigger_gitea_workflow(instance, vault_token_data[:token])

        instance.update!(
          gitea_workflow_run_id: workflow_run[:id],
          status: "provisioning"
        )

        # Update quota
        quota_service.increment_usage!

        instance
      rescue StandardError => e
        instance.fail!(e.message)
        raise ExecutionError, "Failed to start container: #{e.message}"
      end
    end

    # Get execution status
    def get_status(execution_id)
      instance = account.devops_container_instances.find_by!(execution_id: execution_id)

      # Sync status from Gitea if still running
      if instance.active? && instance.gitea_workflow_run_id.present?
        sync_status_from_gitea(instance)
      end

      instance
    end

    # Cancel execution
    def cancel(execution_id, reason: nil)
      instance = account.devops_container_instances.find_by!(execution_id: execution_id)

      return false unless instance.active?

      # Cancel Gitea workflow if running
      if instance.gitea_workflow_run_id.present?
        cancel_gitea_workflow(instance)
      end

      instance.cancel!(reason: reason)

      # Update quota
      QuotaService.new(account).decrement_running!

      true
    end

    # Handle callback from Gitea workflow
    def handle_completion(execution_id, result)
      instance = account.devops_container_instances.find_by!(execution_id: execution_id)

      return if instance.finished?

      if result[:status] == "success"
        output = decode_output(result[:output])
        instance.complete!(
          output: output,
          exit_code: result[:exit_code] || "0",
          logs: result[:logs],
          artifacts: result[:artifacts]
        )
      else
        instance.fail!(result[:error] || "Execution failed", logs: result[:logs])
      end

      # Update quota
      QuotaService.new(account).decrement_running!

      # Trigger callback if configured
      trigger_completion_callback(instance)

      instance
    end

    # List running containers
    def list_active
      account.devops_container_instances.active.order(created_at: :desc)
    end

    # Get execution history
    def list_history(limit: 50, status: nil)
      instances = account.devops_container_instances.order(created_at: :desc).limit(limit)
      instances = instances.where(status: status) if status.present?
      instances
    end

    private

    def create_instance(template, input_parameters, timeout_seconds, a2a_task)
      Devops::ContainerInstance.create!(
        account: account,
        template: template,
        triggered_by: user,
        a2a_task: a2a_task,
        image_name: template.image_name,
        image_tag: template.image_tag,
        status: "pending",
        input_parameters: input_parameters,
        timeout_seconds: timeout_seconds || template.timeout_seconds,
        sandbox_enabled: template.sandbox_mode.nil? ? true : template.sandbox_mode,
        environment_variables: build_environment_variables(template, input_parameters),
        runner_labels: template.labels["runner_labels"] || [ "powernode-ai-agent" ]
      )
    end

    def build_environment_variables(template, input_parameters)
      env = template.environment_variables.dup

      # Add input parameters as JSON
      env["INPUT_PARAMETERS"] = input_parameters.to_json

      # Add execution metadata
      env["POWERNODE_ACCOUNT_ID"] = account.id
      env["POWERNODE_EXECUTION_TIME"] = Time.current.iso8601

      env
    end

    def generate_vault_token(instance)
      Security::VaultClient.generate_container_token(
        account_id: account.id,
        execution_id: instance.execution_id,
        ttl: "#{instance.timeout_seconds + 300}s"  # TTL = timeout + 5 min buffer
      )
    end

    def trigger_gitea_workflow(instance, vault_token)
      workflow_inputs = {
        execution_id: instance.execution_id,
        container_image: instance.template&.full_image_name || "#{instance.image_name}:#{instance.image_tag}",
        account_id: account.id,
        vault_token: vault_token,
        input_parameters: instance.input_parameters.to_json,
        timeout_minutes: (instance.timeout_seconds / 60.0).ceil,
        callback_url: build_callback_url(instance)
      }

      @gitea_client.trigger_workflow(
        owner: gitea_org,
        repo: gitea_repo,
        workflow: "ai-agent-execution.yml",
        ref: "main",
        inputs: workflow_inputs
      )
    end

    def sync_status_from_gitea(instance)
      run = @gitea_client.get_workflow_run(
        owner: gitea_org,
        repo: gitea_repo,
        run_id: instance.gitea_workflow_run_id
      )

      case run[:status]
      when "completed"
        if run[:conclusion] == "success"
          # Wait for callback, or fetch results
        else
          instance.fail!("Workflow failed: #{run[:conclusion]}")
          QuotaService.new(account).decrement_running!
        end
      when "cancelled"
        instance.cancel!(reason: "Workflow cancelled")
        QuotaService.new(account).decrement_running!
      end
    rescue StandardError => e
      Rails.logger.warn "Failed to sync Gitea status: #{e.message}"
    end

    def cancel_gitea_workflow(instance)
      @gitea_client.cancel_workflow_run(
        owner: gitea_org,
        repo: gitea_repo,
        run_id: instance.gitea_workflow_run_id
      )
    rescue StandardError => e
      Rails.logger.warn "Failed to cancel Gitea workflow: #{e.message}"
    end

    def decode_output(encoded_output)
      return {} if encoded_output.blank?

      JSON.parse(Base64.decode64(encoded_output))
    rescue StandardError
      { raw: encoded_output }
    end

    def build_callback_url(instance)
      Rails.application.routes.url_helpers.api_v1_internal_container_execution_complete_url(
        execution_id: instance.execution_id,
        host: ENV.fetch("API_HOST", "localhost:3000")
      )
    end

    def trigger_completion_callback(instance)
      nil unless instance.a2a_task.present?

      # A2A task completion is handled by instance#handle_completion callback
    end

    def build_gitea_client
      provider = Devops::GitProvider.where(provider_type: "gitea", is_active: true)
                                     .joins(:credentials)
                                     .first
      raise OrchestrationError, "No active Gitea provider configured" unless provider

      Devops::Git::GiteaApiClient.new(provider.credentials.first)
    end

    def gitea_org
      ENV.fetch("POWERNODE_GITEA_ORG", "powernode")
    end

    def gitea_repo
      ENV.fetch("POWERNODE_RUNNER_REPO", "agent-runners")
    end
  end
end
