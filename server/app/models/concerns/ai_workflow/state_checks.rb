# frozen_string_literal: true

module AiWorkflow::StateChecks
  extend ActiveSupport::Concern

  # Status check methods
  def active?
    status == "active"
  end

  def draft?
    status == "draft"
  end

  def inactive?
    status == "inactive"
  end

  def archived?
    status == "archived"
  end

  def paused?
    status == "paused"
  end

  def can_execute?
    (active? || paused?) && has_valid_structure? && ai_workflow_nodes.any?
  end

  def can_edit?
    %w[draft paused].include?(status)
  end

  def can_delete?
    # Don't allow deletion if there are running or pending executions
    return false if ai_workflow_runs.where(status: %w[pending running initializing]).exists?

    # Don't allow deletion if there are recent executions (within last 5 minutes)
    return false if ai_workflow_runs.where("created_at > ?", 5.minutes.ago).exists?

    true
  end

  # Timeout functionality for workflow execution
  def timeout_minutes
    configuration.dig("max_execution_time").to_f / 60.0 if configuration.dig("max_execution_time")
  end

  def timeout_minutes=(minutes)
    self.configuration = (configuration || {}).merge("max_execution_time" => (minutes.to_f * 60).to_i)
  end

  def timeout_seconds
    configuration.dig("max_execution_time") || 3600 # Default 1 hour
  end
end
