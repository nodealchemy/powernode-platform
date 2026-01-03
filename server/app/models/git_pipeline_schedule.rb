# frozen_string_literal: true

class GitPipelineSchedule < ApplicationRecord
  # Associations
  belongs_to :git_repository
  belongs_to :account
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :last_pipeline, class_name: "GitPipeline", optional: true

  has_one :git_provider_credential, through: :git_repository
  has_one :git_provider, through: :git_repository

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :cron_expression, presence: true
  validates :timezone, presence: true
  validates :ref, presence: true
  validates :name, uniqueness: { scope: :git_repository_id }

  validate :valid_cron_expression
  validate :valid_timezone

  # Scopes
  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }
  scope :due, -> { active.where("next_run_at <= ?", Time.current) }
  scope :upcoming, -> { active.where("next_run_at > ?", Time.current).order(:next_run_at) }
  scope :for_repository, ->(repo_id) { where(git_repository_id: repo_id) }
  scope :by_status, ->(status) { where(last_run_status: status) }

  # Callbacks
  before_create :calculate_next_run
  after_update :recalculate_next_run, if: -> { saved_change_to_cron_expression? || saved_change_to_timezone? }

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
    update!(next_run_at: calculate_next_run_time)
  end

  def cron_schedule
    @cron_schedule ||= Fugit::Cron.parse(cron_expression)
  end

  def human_schedule
    return "Invalid schedule" unless cron_schedule
    cron_schedule.to_cron_s
  rescue
    cron_expression
  end

  def next_runs(count = 5)
    return [] unless cron_schedule

    runs = []
    time = Time.current.in_time_zone(timezone)
    count.times do
      time = cron_schedule.next_time(time).to_t
      runs << time
    end
    runs
  end

  private

  def calculate_next_run
    self.next_run_at = calculate_next_run_time
  end

  def recalculate_next_run
    calculate_next_run!
  end

  def calculate_next_run_time
    return nil unless active? && cron_schedule

    base_time = Time.current.in_time_zone(timezone)
    cron_schedule.next_time(base_time).to_t
  rescue
    nil
  end

  def valid_cron_expression
    return if cron_expression.blank?

    unless Fugit::Cron.parse(cron_expression)
      errors.add(:cron_expression, "is not a valid cron expression")
    end
  rescue
    errors.add(:cron_expression, "is not a valid cron expression")
  end

  def valid_timezone
    return if timezone.blank?

    unless ActiveSupport::TimeZone[timezone]
      errors.add(:timezone, "is not a valid timezone")
    end
  end
end
