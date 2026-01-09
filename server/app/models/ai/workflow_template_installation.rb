# frozen_string_literal: true

module Ai
  class WorkflowTemplateInstallation < ApplicationRecord
    self.table_name = "ai_workflow_template_installations"

    # Associations
    belongs_to :template, class_name: "Ai::WorkflowTemplate", foreign_key: "ai_workflow_template_id"
    belongs_to :workflow, class_name: "Ai::Workflow", foreign_key: "ai_workflow_id"
    belongs_to :account
    belongs_to :installed_by_user, class_name: "User"

    # Validations
    validates :installation_id, presence: true, uniqueness: true
    validates :template_version, presence: true
    validates :ai_workflow_template_id, uniqueness: {
      scope: :account_id,
      message: "has already been installed for this account"
    }

    # JSON columns
    attribute :customizations, :json, default: -> { {} }
    attribute :variable_mappings, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :recent, -> { order(created_at: :desc) }
    scope :auto_updating, -> { where(auto_update: true) }
    scope :customized, -> { where.not(customizations: {}) }
    scope :for_template, ->(template_id) { where(ai_workflow_template_id: template_id) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }
    scope :by_version, ->(version) { where(template_version: version) }
    scope :outdated, -> {
      joins(:template)
        .where("ai_workflow_template_installations.template_version != ai_workflow_templates.version")
    }

    # Callbacks
    before_validation :generate_installation_id, on: :create
    before_validation :capture_template_version, on: :create
    after_create :log_installation

    def up_to_date?
      template_version == template.version
    end

    def outdated?
      !up_to_date?
    end

    def auto_updating?
      auto_update?
    end

    def customized?
      customizations.present? && customizations.any?
    end

    def template_name
      template.name
    end

    def workflow_name
      workflow.name
    end

    def current_template_version
      template.version
    end

    def can_update?
      outdated? && template.published?
    end

    def installation_summary
      {
        installation_id: installation_id,
        template_name: template_name,
        workflow_name: workflow_name,
        installed_version: template_version,
        current_version: current_template_version,
        up_to_date: up_to_date?,
        auto_updating: auto_updating?,
        customized: customized?,
        installed_at: created_at,
        last_updated: last_updated_at,
        installed_by: installed_by_user.full_name
      }
    end

    def has_variable_mappings?
      variable_mappings.present? && variable_mappings.any?
    end

    def add_customization(key, value)
      update!(
        customizations: customizations.merge(key.to_s => value),
        metadata: metadata.merge("last_customized_at" => Time.current.iso8601)
      )
    end

    def remove_customization(key)
      update!(customizations: customizations.except(key.to_s))
    end

    def map_variable(template_var, workflow_var)
      update!(variable_mappings: variable_mappings.merge(template_var.to_s => workflow_var))
    end

    def unmap_variable(var)
      update!(variable_mappings: variable_mappings.except(var.to_s))
    end

    def resolve_variable(var)
      variable_mappings[var.to_s] || var
    end

    def usage_statistics
      runs = workflow.workflow_runs
      completed_runs = runs.where(status: "completed")
      failed_runs = runs.where(status: "failed")

      {
        total_executions: runs.count,
        successful_executions: completed_runs.count,
        failed_executions: failed_runs.count,
        total_cost: runs.sum(:total_cost).to_f,
        average_execution_time: calculate_average_execution_time(completed_runs),
        success_rate: runs.count.positive? ? (completed_runs.count.to_f / runs.count * 100).round(1) : 0.0
      }
    end

    def installation_health_score
      stats = usage_statistics

      # Base score starts at 100
      score = 100.0

      # Penalize for failures (up to 50 points)
      if stats[:total_executions].positive?
        failure_rate = stats[:failed_executions].to_f / stats[:total_executions]
        score -= (failure_rate * 50)
      end

      # Penalize for being outdated (10 points)
      score -= 10 if outdated?

      # Reward for customization (5 points)
      score += 5 if customized?

      # Clamp between 0 and 100
      [[score, 0].max, 100].min.round(1)
    end

    private

    def calculate_average_execution_time(runs)
      completed_runs = runs.where.not(completed_at: nil).where.not(started_at: nil)
      return 0.0 if completed_runs.count.zero?

      total_time = completed_runs.sum { |run| (run.completed_at - run.started_at).to_f }
      (total_time / completed_runs.count).round(2)
    end

    def generate_installation_id
      self.installation_id = SecureRandom.uuid if installation_id.blank?
    end

    def capture_template_version
      self.template_version = template.version if template_version.blank?
    end

    def log_installation
      Rails.logger.info "Template installation created: #{template.name} -> #{workflow.name} (Account: #{account_id})"

      update_column(:metadata, metadata.merge({
        "installed_at" => created_at.iso8601,
        "installer_id" => installed_by_user_id,
        "original_template_version" => template_version
      }))
    end
  end
end
