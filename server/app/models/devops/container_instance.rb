# frozen_string_literal: true

module Devops
  class ContainerInstance < ApplicationRecord
    self.table_name = "devops_container_instances"

    # Concerns
    include Auditable

    # Constants
    STATUSES = %w[pending provisioning running completed failed cancelled timeout].freeze

    # Associations
    belongs_to :account
    belongs_to :template, class_name: "Devops::ContainerTemplate", optional: true
    belongs_to :triggered_by, class_name: "User", optional: true
    belongs_to :a2a_task, class_name: "Ai::A2aTask", optional: true

    # Validations
    validates :execution_id, presence: true, uniqueness: true
    validates :image_name, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :timeout_seconds, numericality: { greater_than: 0 }, allow_nil: true

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :provisioning, -> { where(status: "provisioning") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :timeout, -> { where(status: "timeout") }
    scope :active, -> { where(status: %w[pending provisioning running]) }
    scope :finished, -> { where(status: %w[completed failed cancelled timeout]) }
    scope :recent, -> { order(created_at: :desc) }
    scope :successful, -> { where(status: "completed", exit_code: "0") }

    # Callbacks
    before_validation :generate_execution_id, on: :create
    after_update :handle_completion, if: :saved_change_to_status?

    # Status checks
    def pending?
      status == "pending"
    end

    def running?
      status == "running"
    end

    def completed?
      status == "completed"
    end

    def failed?
      status == "failed"
    end

    def cancelled?
      status == "cancelled"
    end

    def timed_out?
      status == "timeout"
    end

    def active?
      %w[pending provisioning running].include?(status)
    end

    def finished?
      %w[completed failed cancelled timeout].include?(status)
    end

    def successful?
      completed? && exit_code == "0"
    end

    # Lifecycle
    def start_provisioning!
      update!(status: "provisioning", queued_at: Time.current)
    end

    def start_running!
      update!(status: "running", started_at: Time.current)
    end

    def complete!(output:, exit_code:, logs: nil, artifacts: nil)
      update!(
        status: exit_code == "0" ? "completed" : "failed",
        output_data: output,
        exit_code: exit_code,
        logs: logs&.truncate(100_000),
        artifacts: artifacts || [],
        completed_at: Time.current,
        duration_ms: calculate_duration
      )
    end

    def fail!(error_message, logs: nil)
      update!(
        status: "failed",
        error_message: error_message,
        logs: logs&.truncate(100_000),
        completed_at: Time.current,
        duration_ms: calculate_duration
      )
    end

    def cancel!(reason: nil)
      return unless active?

      update!(
        status: "cancelled",
        error_message: reason,
        completed_at: Time.current,
        duration_ms: calculate_duration
      )
    end

    def mark_timeout!
      update!(
        status: "timeout",
        error_message: "Execution timed out after #{timeout_seconds} seconds",
        completed_at: Time.current,
        duration_ms: calculate_duration
      )
    end

    # Resource tracking
    def record_resource_usage(memory_mb:, cpu_millicores:, storage_bytes: nil, network_in: nil, network_out: nil)
      update!(
        memory_used_mb: memory_mb,
        cpu_used_millicores: cpu_millicores,
        storage_used_bytes: storage_bytes,
        network_bytes_in: network_in,
        network_bytes_out: network_out
      )
    end

    # Security
    def record_security_violation!(violation)
      violations = security_violations.dup
      violations << violation.merge(detected_at: Time.current.iso8601)
      update!(security_violations: violations)
    end

    def has_security_violations?
      security_violations.any?
    end

    # Logs
    def append_logs(new_logs)
      current = logs || ""
      combined = current + new_logs
      update_column(:logs, combined.last(100_000))
    end

    # Vault cleanup
    def cleanup_vault_token!
      return unless vault_token_id.present?

      begin
        Security::VaultClient.revoke_token(accessor: vault_token_id)
        update_column(:vault_token_id, nil)
      rescue StandardError => e
        Rails.logger.warn "Failed to revoke Vault token: #{e.message}"
      end
    end

    # Summary
    def instance_summary
      {
        id: id,
        execution_id: execution_id,
        status: status,
        image_name: "#{image_name}:#{image_tag}",
        exit_code: exit_code,
        duration_ms: duration_ms,
        started_at: started_at,
        completed_at: completed_at,
        runner_name: runner_name
      }
    end

    def instance_details
      instance_summary.merge(
        template_id: template_id,
        a2a_task_id: a2a_task_id,
        input_parameters: input_parameters,
        output_data: output_data,
        artifacts: artifacts,
        logs: logs&.truncate(10_000),
        error_message: error_message,
        resource_usage: {
          memory_mb: memory_used_mb,
          cpu_millicores: cpu_used_millicores,
          storage_bytes: storage_used_bytes,
          network_in: network_bytes_in,
          network_out: network_bytes_out
        },
        gitea_workflow_run_id: gitea_workflow_run_id,
        security_violations: security_violations,
        sandbox_enabled: sandbox_enabled,
        triggered_by: triggered_by&.full_name,
        created_at: created_at
      )
    end

    private

    def generate_execution_id
      self.execution_id ||= "exec-#{UUID7.generate[0..7]}-#{Time.current.to_i}"
    end

    def calculate_duration
      return nil unless started_at

      ((completed_at || Time.current) - started_at) * 1000
    end

    def handle_completion
      return unless finished?

      # Update template statistics
      template&.record_execution!(success: successful?)

      # Clean up Vault token
      cleanup_vault_token! if vault_token_id.present?

      # Update A2A task if linked
      update_linked_task if a2a_task.present?
    end

    def update_linked_task
      if successful?
        a2a_task.complete!(result: output_data, artifacts: artifacts)
      else
        a2a_task.fail!(error_message: error_message || "Container execution failed")
      end
    end
  end
end
