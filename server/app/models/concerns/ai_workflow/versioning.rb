# frozen_string_literal: true

module AiWorkflow::Versioning
  extend ActiveSupport::Concern

  # Versioning methods
  def version_manager
    @version_manager ||= Mcp::WorkflowVersionManager.new(
      workflow: self,
      account: account,
      user: creator
    )
  end

  def create_new_version(changes:, change_summary: nil)
    version_manager.create_version(changes: changes, change_summary: change_summary)
  end

  def version_history
    version_manager.version_history
  end

  def has_active_runs?
    ai_workflow_runs.where(status: [ "running", "paused" ]).exists?
  end

  def all_versions
    self.class.version_family(name, account_id)
  end

  def latest_active_version
    all_versions.active_versions.first
  end

  def is_latest_version?
    self == latest_active_version
  end

  def version_number
    Gem::Version.new(version)
  end

  def newer_than?(other_workflow)
    version_number > Gem::Version.new(other_workflow.version)
  end
end
