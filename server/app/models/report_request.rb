# frozen_string_literal: true

# == Schema Information
#
# Table name: report_requests
#
#  id                 :uuid             not null, primary key
#  account_id         :uuid             not null
#  user_id            :uuid             not null
#  name               :string           not null
#  report_type        :string           not null
#  format             :string           not null
#  status             :string           default("pending"), not null
#  parameters         :jsonb
#  file_url           :string
#  file_path          :string
#  file_size          :integer
#  content_type       :string
#  error_message      :text
#  completed_at       :timestamp
#  created_at         :timestamp        not null
#  updated_at         :timestamp        not null
#
# Indexes
#
#  index_report_requests_on_account_id    (account_id)
#  index_report_requests_on_user_id       (user_id)
#  index_report_requests_on_status        (status)
#  index_report_requests_on_created_at    (created_at)
#

class ReportRequest < ApplicationRecord
  # Associations
  belongs_to :account
  belongs_to :user, foreign_key: "requested_by_id"

  # Validations
  validates :report_type, presence: true, inclusion: {
    in: %w[revenue_analytics customer_analytics churn_analysis growth_analytics cohort_analysis comprehensive_report],
    message: "is not a valid report type"
  }
  validates :status, presence: true, inclusion: {
    in: %w[pending processing completed failed cancelled],
    message: "is not a valid status"
  }

  # Scopes
  scope :for_account, ->(account) { where(account: account) }
  scope :by_status, ->(status) { where(status: status) }
  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }

  # Callbacks
  after_update_commit :log_status_change, if: :saved_change_to_status?

  # State machine for status transitions
  def can_cancel?
    %w[pending processing].include?(status)
  end

  def can_retry?
    status == "failed"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def processing?
    status == "processing"
  end

  def pending?
    status == "pending"
  end

  # Mark as processing
  def mark_processing!
    update!(status: "processing", error_message: nil)
  end

  # Mark as completed
  def mark_completed!(file_path: nil, file_url: nil, file_size: nil)
    update!(
      status: "completed",
      completed_at: Time.current,
      file_path: file_path,
      file_url: file_url,
      file_size: file_size,
      error_message: nil
    )
  end

  # Mark as failed
  def mark_failed!(error_message)
    update!(
      status: "failed",
      error_message: error_message,
      completed_at: Time.current
    )
  end

  # Cancel the request
  def cancel!
    return false unless can_cancel?
    update!(status: "cancelled")
  end

  # Get estimated completion time based on report type and queue
  def estimated_completion_time
    base_time = case report_type
    when "comprehensive_report"
      5.minutes
    when "revenue_analytics", "customer_analytics"
      3.minutes
    when "churn_analysis", "growth_analytics", "cohort_analysis"
      2.minutes
    else
      1.minute
    end

    # Add queue delay estimation
    queue_size = ReportRequest.where(status: [ "pending", "processing" ]).count
    queue_delay = queue_size * 30.seconds

    base_time + queue_delay
  end

  # Get progress percentage (estimated)
  def progress_percentage
    return 100 if completed?
    return 0 if pending?

    if processing?
      # Estimate progress based on time elapsed
      elapsed = Time.current - updated_at
      estimated = estimated_completion_time
      [ (elapsed.to_f / estimated.to_f * 100).round, 95 ].min
    else
      0
    end
  end

  # Generate filename
  def generate_filename
    timestamp = created_at.strftime("%Y%m%d_%H%M%S")
    sanitized_type = report_type.parameterize(separator: "_")
    # Infer format from file_path extension, default to pdf
    extension = file_path ? File.extname(file_path).delete(".") : "pdf"
    "#{sanitized_type}_#{timestamp}.#{extension}"
  end

  # Get human readable status
  def status_display
    case status
    when "pending"
      "Pending"
    when "processing"
      "Processing"
    when "completed"
      "Completed"
    when "failed"
      "Failed"
    when "cancelled"
      "Cancelled"
    else
      status.humanize
    end
  end

  # Get report type display name
  def report_type_display
    case report_type
    when "revenue_analytics"
      "Revenue Analytics"
    when "customer_analytics"
      "Customer Analytics"
    when "churn_analysis"
      "Churn Analysis"
    when "growth_analytics"
      "Growth Analytics"
    when "cohort_analysis"
      "Cohort Analysis"
    when "comprehensive_report"
      "Executive Summary"
    else
      report_type.humanize
    end
  end

  # Statuses whose requests are finished and therefore eligible for retention
  # sweeps. "pending"/"processing" are excluded — a request still in flight
  # must never be swept out from under the worker rendering it.
  CLEANUP_STATUSES = %w[completed failed cancelled].freeze

  # Hard cap on rows removed by a single cleanup_old_requests call. The sweep
  # has never run in this deployment, so the first pass faces an unswept
  # backlog of unknown size; bounding every call means no single invocation can
  # delete an unbounded set of stored artifacts, and the remainder is reported
  # so the next invocation picks it up.
  DEFAULT_CLEANUP_LIMIT = 100

  # Directories a report artifact is allowed to live in. cleanup_old_requests
  # unlinks files, and file_path is written by the worker over HTTP, so a
  # poisoned path must not be able to steer File.delete at an arbitrary file.
  #
  # Same two roots as the read path in
  # Api::V1::ReportsController#download_request, but the check here is STRICTER:
  # that one compares `start_with?(root)` without a separator, so a sibling
  # directory whose name merely begins with "reports" satisfies it. Do not
  # weaken this one to match it.
  def self.artifact_roots
    [
      Rails.root.join("tmp", "reports").to_s,
      Rails.root.parent.join("worker", "storage", "reports").to_s
    ]
  end

  # Finished requests older than the retention boundary. Exposed separately so
  # a caller can COUNT the backlog without deleting anything.
  def self.cleanup_candidates(older_than: 30.days)
    where(status: CLEANUP_STATUSES).where(created_at: ...older_than.ago)
  end

  # DESTRUCTIVE retention sweep: unlinks the stored artifact and destroys the
  # row, for finished requests past the retention boundary.
  #
  # Always bounded by `limit` (see DEFAULT_CLEANUP_LIMIT). Pass `dry_run: true`
  # to get the candidate count with nothing deleted.
  #
  # Returns a summary hash: candidate_count / deleted_count / files_deleted /
  # remaining_count / dry_run, plus `deleted_records` — [{ id:, account_id: }]
  # for each row removed, so the caller can audit what it destroyed. That array
  # is bounded by `limit` like everything else here.
  def self.cleanup_old_requests(older_than: 30.days, limit: DEFAULT_CLEANUP_LIMIT, dry_run: false)
    limit = [ limit.to_i, 1 ].max
    scope = cleanup_candidates(older_than: older_than)
    candidate_count = scope.count

    if dry_run
      return {
        candidate_count: candidate_count,
        deleted_count: 0,
        files_deleted: 0,
        remaining_count: candidate_count,
        dry_run: true,
        deleted_records: []
      }
    end

    deleted_records = []
    files_deleted = 0

    scope.order(:created_at).limit(limit).to_a.each do |request|
      identity = { id: request.id, account_id: request.account_id }
      # Row first, then the file. If destroy raises, the artifact is still there
      # and the surviving row still points at it truthfully; the reverse order
      # would leave a "completed" row advertising a file that is gone.
      request.destroy
      files_deleted += 1 if request.delete_artifact_file
      deleted_records << identity
    end

    {
      candidate_count: candidate_count,
      deleted_count: deleted_records.size,
      files_deleted: files_deleted,
      remaining_count: [ candidate_count - deleted_records.size, 0 ].max,
      dry_run: false,
      deleted_records: deleted_records
    }
  end

  # Unlink this request's artifact if it exists and sits inside an allowed
  # reports directory. Returns true only when a file was actually removed.
  #
  # File.expand_path is load-bearing, not cosmetic: without it a file_path
  # containing ".." segments would satisfy the prefix check and then resolve
  # outside the allowed roots when File.delete follows it.
  def delete_artifact_file
    return false if file_path.blank?

    expanded = File.expand_path(file_path)
    unless self.class.artifact_roots.any? { |root| expanded.start_with?(root + File::SEPARATOR) }
      Rails.logger.error "Refusing to delete report artifact outside reports directories: #{file_path}"
      return false
    end
    return false unless File.file?(expanded)

    File.delete(expanded)
    true
  rescue SystemCallError => e
    Rails.logger.error "Failed to delete report artifact #{file_path}: #{e.message}"
    false
  end

  private

  def log_status_change
    Rails.logger.info "Report request #{id} status changed to #{status}"

    # Create audit log entry with error handling
    # Use after_update_commit to prevent audit failures from rolling back the main transaction
    begin
      AuditLog.create!(
        user: user,
        account: account,
        action: "report_request_#{status}",
        resource_type: self.class.name,
        resource_id: id,
        old_values: {
          status: previous_changes["status"]&.first
        }.compact.presence || {},
        new_values: {
          status: status,
          completed_at: completed_at,
          error_message: error_message
        }.compact,
        metadata: {},
        source: "system",
        severity: "low",
        risk_level: "low",
        ip_address: nil,
        user_agent: nil
      )
    rescue StandardError => e
      Rails.logger.error "Failed to create audit log for report request #{id}: #{e.message}"
    end
  end
end
