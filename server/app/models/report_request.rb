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
  belongs_to :user

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :report_type, presence: true, inclusion: { 
    in: %w[revenue_analytics customer_analytics churn_analysis growth_analytics cohort_analysis comprehensive_report],
    message: "is not a valid report type"
  }
  validates :format, presence: true, inclusion: { 
    in: %w[pdf csv xlsx json],
    message: "is not a valid format"
  }
  validates :status, presence: true, inclusion: { 
    in: %w[pending processing completed failed cancelled],
    message: "is not a valid status"
  }

  # Scopes
  scope :for_account, ->(account) { where(account: account) }
  scope :by_status, ->(status) { where(status: status) }
  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :pending, -> { where(status: 'pending') }
  scope :processing, -> { where(status: 'processing') }

  # Callbacks
  before_save :set_content_type
  after_update :log_status_change, if: :saved_change_to_status?

  # State machine for status transitions
  def can_cancel?
    %w[pending processing].include?(status)
  end

  def can_retry?
    status == 'failed'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def processing?
    status == 'processing'
  end

  def pending?
    status == 'pending'
  end

  # Mark as processing
  def mark_processing!
    update!(status: 'processing', error_message: nil)
  end

  # Mark as completed
  def mark_completed!(file_path: nil, file_url: nil, file_size: nil)
    update!(
      status: 'completed',
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
      status: 'failed',
      error_message: error_message,
      completed_at: Time.current
    )
  end

  # Cancel the request
  def cancel!
    return false unless can_cancel?
    update!(status: 'cancelled')
  end

  # Get estimated completion time based on report type and queue
  def estimated_completion_time
    base_time = case report_type
    when 'comprehensive_report'
      5.minutes
    when 'revenue_analytics', 'customer_analytics'
      3.minutes
    when 'churn_analysis', 'growth_analytics', 'cohort_analysis'
      2.minutes
    else
      1.minute
    end

    # Add queue delay estimation
    queue_size = ReportRequest.where(status: ['pending', 'processing']).count
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
      [(elapsed.to_f / estimated.to_f * 100).round, 95].min
    else
      0
    end
  end

  # Generate filename
  def generate_filename
    timestamp = created_at.strftime('%Y%m%d_%H%M%S')
    sanitized_name = name.parameterize(separator: '_')
    "#{sanitized_name}_#{timestamp}.#{format}"
  end

  # Get human readable status
  def status_display
    case status
    when 'pending'
      'Pending'
    when 'processing'
      'Processing'
    when 'completed'
      'Completed'
    when 'failed'
      'Failed'
    when 'cancelled'
      'Cancelled'
    else
      status.humanize
    end
  end

  # Get report type display name
  def report_type_display
    case report_type
    when 'revenue_analytics'
      'Revenue Analytics'
    when 'customer_analytics'
      'Customer Analytics'
    when 'churn_analysis'
      'Churn Analysis'
    when 'growth_analytics'
      'Growth Analytics'
    when 'cohort_analysis'
      'Cohort Analysis'
    when 'comprehensive_report'
      'Executive Summary'
    else
      report_type.humanize
    end
  end

  # Cleanup old completed/failed requests
  def self.cleanup_old_requests(older_than: 30.days)
    where('created_at < ? AND status IN (?)', older_than.ago, %w[completed failed cancelled])
      .find_each do |request|
        # Delete associated file if it exists
        if request.file_path && File.exist?(request.file_path)
          File.delete(request.file_path)
        end
        request.destroy
      end
  end

  private

  def set_content_type
    self.content_type = case format
    when 'pdf'
      'application/pdf'
    when 'csv'
      'text/csv'
    when 'xlsx'
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    when 'json'
      'application/json'
    else
      'application/octet-stream'
    end
  end

  def log_status_change
    Rails.logger.info "Report request #{id} status changed to #{status}"
    
    # Create audit log entry
    AuditLog.create!(
      user: user,
      account: account,
      action: "report_request_#{status}",
      auditable: self,
      changes: { 
        status: saved_changes['status'],
        completed_at: completed_at,
        error_message: error_message
      }.compact,
      ip_address: nil, # Would be set by controller if available
      user_agent: nil
    )
  end
end