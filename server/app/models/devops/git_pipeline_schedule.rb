# frozen_string_literal: true

module Devops
  class GitPipelineSchedule < ApplicationRecord
    include Schedulable

    # Table name (using git_ prefix, not devops_)
    self.table_name = "git_pipeline_schedules"

    # Associations
    belongs_to :repository, class_name: "Devops::GitRepository", foreign_key: "git_repository_id"
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :last_pipeline, class_name: "Devops::GitPipeline", optional: true

    has_one :credential, through: :repository, source: :credential
    has_one :provider, through: :repository, source: :provider

    # Validations
    validates :name, presence: true, length: { maximum: 100 }
    validates :ref, presence: true
    validates :name, uniqueness: { scope: :git_repository_id }

    validate :valid_timezone

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :due, -> { active.where("next_run_at <= ?", Time.current) }
    scope :upcoming, -> { active.where("next_run_at > ?", Time.current).order(:next_run_at) }
    scope :for_repository, ->(repo_id) { where(git_repository_id: repo_id) }
    scope :by_status, ->(status) { where(last_run_status: status) }

    # Class Methods
    class << self
      def due_for_execution
        active.where("next_run_at <= ?", Time.current)
      end

      def with_failures
        where("consecutive_failures > 0")
      end
    end

    # Instance Methods
    def active?
      is_active
    end

    def inactive?
      !is_active
    end

    def activate!
      update!(is_active: true, consecutive_failures: 0)
      calculate_next_run!
    end

    def deactivate!
      update!(is_active: false)
    end

    def success_rate
      return 0.0 if run_count.zero?
      (success_count.to_f / run_count * 100).round(2)
    end

    def failure_rate
      return 0.0 if run_count.zero?
      (failure_count.to_f / run_count * 100).round(2)
    end

    def overdue?
      active? && next_run_at.present? && next_run_at < Time.current
    end

    def record_run!(status, pipeline = nil)
      attrs = {
        last_run_at: Time.current,
        last_run_status: status,
        run_count: run_count + 1
      }

      case status
      when "success"
        attrs[:success_count] = success_count + 1
        attrs[:consecutive_failures] = 0
      when "failure"
        attrs[:failure_count] = failure_count + 1
        attrs[:consecutive_failures] = consecutive_failures + 1
      end

      attrs[:last_pipeline_id] = pipeline.id if pipeline.present?

      update!(attrs)
      calculate_next_run!
    end

    def calculate_next_run!
      update!(next_run_at: next_execution_time)
    end

    def human_schedule
      cron_description
    end

    def next_runs(count = 5)
      execution_times_in_range(Time.current, 1.year.from_now, max_count: count)
    end

    # Backwards compatibility aliases
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

    def valid_timezone
      return if timezone.blank?

      unless ActiveSupport::TimeZone[timezone]
        errors.add(:timezone, "is not a valid timezone")
      end
    end
  end
end
