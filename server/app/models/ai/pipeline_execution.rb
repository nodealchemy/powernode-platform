# frozen_string_literal: true

module Ai
  class PipelineExecution < ApplicationRecord
    self.table_name = "ai_pipeline_executions"

    # Associations
    belongs_to :account
    belongs_to :devops_installation, class_name: "Ai::DevopsTemplateInstallation", foreign_key: "devops_installation_id", optional: true
    belongs_to :workflow_run, class_name: "Ai::WorkflowRun", foreign_key: "workflow_run_id", optional: true
    belongs_to :triggered_by, class_name: "User", foreign_key: "triggered_by_id", optional: true

    has_many :deployment_risks, class_name: "Ai::DeploymentRisk", foreign_key: "pipeline_execution_id", dependent: :nullify
    has_many :code_reviews, class_name: "Ai::CodeReview", foreign_key: "pipeline_execution_id", dependent: :nullify

    # Validations
    validates :execution_id, presence: true, uniqueness: true
    validates :pipeline_type, presence: true, inclusion: {
      in: %w[pr_review commit_analysis deployment release scheduled manual]
    }
    validates :status, presence: true, inclusion: {
      in: %w[pending running completed failed cancelled timeout]
    }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :by_type, ->(type) { where(pipeline_type: type) }
    scope :for_repository, ->(repo_id) { where(repository_id: repo_id) }
    scope :for_branch, ->(branch) { where(branch: branch) }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_validation :set_execution_id, on: :create

    # Methods
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

    def start!
      update!(status: "running", started_at: Time.current)
    end

    def complete!(output_data: {}, ai_analysis: {}, metrics: {})
      duration = started_at.present? ? ((Time.current - started_at) * 1000).to_i : nil

      update!(
        status: "completed",
        completed_at: Time.current,
        duration_ms: duration,
        output_data: output_data,
        ai_analysis: ai_analysis,
        metrics: metrics
      )

      devops_installation&.record_execution(success: true)
    end

    def fail!(error_data = {})
      duration = started_at.present? ? ((Time.current - started_at) * 1000).to_i : nil

      update!(
        status: "failed",
        completed_at: Time.current,
        duration_ms: duration,
        output_data: output_data.merge(error: error_data)
      )

      devops_installation&.record_execution(success: false)
    end

    def cancel!
      update!(status: "cancelled", completed_at: Time.current)
    end

    def timeout!
      update!(status: "timeout", completed_at: Time.current)
      devops_installation&.record_execution(success: false)
    end

    def for_pull_request?
      pull_request_number.present?
    end

    private

    def set_execution_id
      self.execution_id ||= SecureRandom.uuid
    end
  end
end
