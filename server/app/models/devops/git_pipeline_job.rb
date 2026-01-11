# frozen_string_literal: true

module Devops
  class GitPipelineJob < ApplicationRecord
    # Table name (using git_ prefix, not devops_)
    self.table_name = "git_pipeline_jobs"

    # Authentication
    # Belongs to account - access controlled through account ownership

    # Concerns
    include Auditable

    # Constants
    STATUSES = %w[queued pending in_progress completed failed cancelled skipped].freeze
    CONCLUSIONS = %w[success failure cancelled skipped].freeze

    # Associations
    belongs_to :pipeline, class_name: "Devops::GitPipeline", foreign_key: "git_pipeline_id"
    belongs_to :account
    has_one :repository, through: :pipeline, source: :repository
    has_one :credential, through: :repository, source: :credential
    has_one :provider, through: :repository, source: :provider

    # Delegations
    delegate :provider_type, to: :provider, allow_nil: true

    # Validations
    validates :external_id, presence: true
    validates :name, presence: true, length: { maximum: 255 }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :conclusion, inclusion: { in: CONCLUSIONS }, allow_nil: true
    validates :external_id, uniqueness: { scope: :git_pipeline_id }

    # Scopes
    scope :queued, -> { where(status: "queued") }
    scope :pending, -> { where(status: "pending") }
    scope :in_progress, -> { where(status: "in_progress") }
    scope :running, -> { in_progress } # Alias for backwards compatibility
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :active, -> { where(status: %w[queued pending in_progress]) }
    scope :finished, -> { where(status: %w[completed failed cancelled skipped]) }
    scope :successful, -> { where(conclusion: "success") }
    scope :unsuccessful, -> { where(conclusion: %w[failure cancelled]) }
    scope :by_runner, ->(runner_name) { where(runner_name: runner_name) }
    scope :ordered, -> { order(:step_number, :created_at) }

    # Callbacks
    before_save :calculate_duration

    # Instance Methods

    def queued?
      status == "queued"
    end

    def pending?
      status == "pending"
    end

    def in_progress?
      status == "in_progress"
    end

    def completed?
      status == "completed"
    end

    def active?
      %w[queued pending in_progress].include?(status)
    end

    def finished?
      %w[completed failed cancelled skipped].include?(status)
    end

    def successful?
      conclusion == "success"
    end

    def failed?
      conclusion == "failure"
    end

    def logs_available?
      logs_url.present? || logs_content.present?
    end

    alias has_logs? logs_available?

    # State transition methods
    def start!(runner_name_val = nil, runner_id_val = nil, runner_os_val = nil)
      update!(
        status: "in_progress",
        started_at: Time.current,
        runner_name: runner_name_val,
        runner_id: runner_id_val,
        runner_os: runner_os_val
      )
    end

    def complete!(conclusion_value)
      update!(
        status: "completed",
        conclusion: conclusion_value,
        completed_at: Time.current
      )
    end

    def duration_formatted
      return nil unless duration_seconds

      minutes = duration_seconds / 60
      seconds = duration_seconds % 60

      if minutes.positive?
        "#{minutes}m #{seconds}s"
      else
        "#{seconds}s"
      end
    end

    def fetch_logs!
      return logs_content if logs_content.present?

      return nil unless credential&.can_be_used?

      client = Devops::Git::ApiClient.for(credential)

      begin
        content = client.get_job_logs(
          repository.owner,
          repository.name,
          external_id
        )

        # Cache logs (truncated to avoid huge storage)
        update!(logs_content: content.truncate(500_000))
        content
      rescue StandardError => e
        Rails.logger.error "Failed to fetch job logs: #{e.message}"
        nil
      end
    end

    def step_summary
      return [] unless steps.present?

      steps.map do |step|
        {
          name: step["name"],
          status: step["status"],
          conclusion: step["conclusion"],
          number: step["number"],
          started_at: step["started_at"],
          completed_at: step["completed_at"]
        }
      end
    end

    def completed_steps_count
      return 0 unless steps.present?

      steps.count { |s| s["status"] == "completed" }
    end

    alias completed_steps completed_steps_count

    def total_steps_count
      steps&.count || 0
    end

    alias step_count total_steps_count

    def runner_info
      {
        name: runner_name,
        id: runner_id,
        os: runner_os
      }
    end

    def act_runner?
      provider&.gitea? && runner_name.present?
    end

    # Backwards compatibility aliases
    def git_pipeline
      pipeline
    end

    def git_repository
      repository
    end

    def git_provider_credential
      credential
    end

    def git_provider
      provider
    end

    private

    def calculate_duration
      return unless started_at.present? && completed_at.present?

      self.duration_seconds = (completed_at - started_at).to_i
    end
  end
end
