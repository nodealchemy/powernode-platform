# frozen_string_literal: true

module Ai
  class DevopsTemplateInstallation < ApplicationRecord
    self.table_name = "ai_devops_template_installations"

    # Associations
    belongs_to :account
    belongs_to :devops_template, class_name: "Ai::DevopsTemplate"
    belongs_to :installed_by, class_name: "User", optional: true
    belongs_to :created_workflow, class_name: "Ai::Workflow", optional: true

    has_many :pipeline_executions, class_name: "Ai::PipelineExecution", foreign_key: :devops_installation_id, dependent: :nullify

    # Validations
    validates :status, presence: true, inclusion: { in: %w[active paused disabled pending_update] }
    validates :account_id, uniqueness: { scope: :devops_template_id, message: "already has this template installed" }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :paused, -> { where(status: "paused") }

    # Methods
    def active?
      status == "active"
    end

    def pause!
      update!(status: "paused") if active?
    end

    def resume!
      update!(status: "active") if status == "paused"
    end

    def disable!
      update!(status: "disabled")
    end

    def record_execution(success:)
      increment!(:execution_count)
      if success
        increment!(:success_count)
      else
        increment!(:failure_count)
      end
      update!(last_executed_at: Time.current)
    end

    def success_rate
      return 0 if execution_count.zero?

      (success_count.to_f / execution_count * 100).round(2)
    end

    def needs_update?
      installed_version != devops_template.version
    end

    def update_to_latest!
      return unless needs_update?

      update!(
        installed_version: devops_template.version,
        status: "active"
      )
    end
  end
end
