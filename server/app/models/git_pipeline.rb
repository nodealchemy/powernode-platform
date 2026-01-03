# frozen_string_literal: true

class GitPipeline < ApplicationRecord
  # Authentication
  # Belongs to account - access controlled through account ownership

  # Concerns
  include Auditable

  # Constants
  STATUSES = %w[queued pending in_progress completed failed cancelled skipped].freeze
  CONCLUSIONS = %w[success failure cancelled skipped timed_out action_required neutral stale].freeze
  TRIGGER_EVENTS = %w[push pull_request schedule workflow_dispatch api manual].freeze

  # Associations
  belongs_to :git_repository
  belongs_to :account
  has_one :git_provider_credential, through: :git_repository
  has_one :git_provider, through: :git_repository
  has_many :git_pipeline_jobs, dependent: :destroy
  has_many :git_pipeline_approvals, dependent: :destroy

  # Delegations
  delegate :provider_type, :full_name, to: :git_repository, prefix: :repository, allow_nil: true

  # Validations
  validates :external_id, presence: true
  validates :name, presence: true, length: { maximum: 255 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :conclusion, inclusion: { in: CONCLUSIONS }, allow_nil: true
  validates :trigger_event, inclusion: { in: TRIGGER_EVENTS }, allow_nil: true
  validates :external_id, uniqueness: { scope: :git_repository_id }

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
  scope :unsuccessful, -> { where(conclusion: %w[failure cancelled timed_out]) }
  scope :by_trigger, ->(event) { where(trigger_event: event) }
  scope :by_ref, ->(ref) { where(ref: ref) }
  scope :by_sha, ->(sha) { where(sha: sha) }
  scope :recent, ->(limit = 20) { order(created_at: :desc).limit(limit) }
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }
  scope :this_week, -> { where("created_at >= ?", Time.current.beginning_of_week) }

  # Callbacks
  before_save :calculate_job_counts
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

  def branch_name
    return nil unless ref.present?

    ref.sub(%r{^refs/heads/}, "")
  end

  def short_sha
    sha&.first(7)
  end

  def duration_formatted
    return nil unless duration_seconds

    hours = duration_seconds / 3600
    minutes = (duration_seconds % 3600) / 60
    seconds = duration_seconds % 60

    if hours.positive?
      "#{hours}h #{minutes}m #{seconds}s"
    elsif minutes.positive?
      "#{minutes}m #{seconds}s"
    else
      "#{seconds}s"
    end
  end

  def progress_percentage
    return 0 if total_jobs.zero?
    return 100 if finished?

    ((completed_jobs.to_f / total_jobs) * 100).round
  end

  # State transition methods
  def start!
    update!(
      status: "in_progress",
      started_at: Time.current
    )
  end

  def complete!(conclusion_value)
    update!(
      status: "completed",
      conclusion: conclusion_value,
      completed_at: Time.current
    )
  end

  def cancel!
    update!(
      status: "cancelled",
      conclusion: "cancelled",
      completed_at: Time.current
    )
  end

  def update_from_provider_data(data)
    update!(
      status: normalize_status(data["status"]),
      conclusion: data["conclusion"],
      started_at: data["started_at"],
      completed_at: data["completed_at"],
      run_attempt: data["run_attempt"] || run_attempt
    )
  end

  def sync_jobs!
    credential = git_provider_credential
    return unless credential&.can_be_used?

    client = Git::ApiClient.for(credential)
    jobs_data = client.get_workflow_run_jobs(
      git_repository.owner,
      git_repository.name,
      external_id
    )

    jobs_data.each do |job_data|
      sync_job(job_data)
    end

    calculate_job_counts
    save!
  end

  def update_job_counts!
    calculate_job_counts
    save!
  end

  private

  def calculate_job_counts
    jobs = git_pipeline_jobs
    self.total_jobs = jobs.count
    self.completed_jobs = jobs.where(status: %w[completed success]).count
    self.failed_jobs = jobs.where(conclusion: "failure").count
  end

  def calculate_duration
    return unless started_at.present? && completed_at.present?

    self.duration_seconds = (completed_at - started_at).to_i
  end

  def normalize_status(provider_status)
    case provider_status&.downcase
    when "queued", "waiting"
      "queued"
    when "pending", "requested"
      "pending"
    when "in_progress", "running"
      "in_progress"
    when "completed", "success"
      "completed"
    when "failure", "failed"
      "failed"
    when "cancelled", "canceled"
      "cancelled"
    when "skipped"
      "skipped"
    else
      provider_status || "pending"
    end
  end

  def sync_job(job_data)
    job = git_pipeline_jobs.find_or_initialize_by(external_id: job_data["id"].to_s)
    job.assign_attributes(
      account: account,
      name: job_data["name"],
      status: normalize_status(job_data["status"]),
      conclusion: job_data["conclusion"],
      step_number: job_data["step_number"],
      runner_name: job_data.dig("runner", "name") || job_data["runner_name"],
      runner_id: job_data.dig("runner", "id")&.to_s || job_data["runner_id"],
      runner_os: job_data.dig("runner", "os") || job_data["runner_os"],
      logs_url: job_data["logs_url"],
      started_at: job_data["started_at"],
      completed_at: job_data["completed_at"],
      steps: job_data["steps"] || []
    )
    job.save!
  end
end
