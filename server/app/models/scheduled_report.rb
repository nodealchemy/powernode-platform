# frozen_string_literal: true

class ScheduledReport < ApplicationRecord
  belongs_to :account, optional: true
  belongs_to :user, foreign_key: "created_by_id"

  validates :report_type, presence: true, inclusion: { in: PdfReportService::REPORT_TYPES }
  validates :frequency, presence: true, inclusion: { in: %w[daily weekly monthly] }
  validates :format, presence: true, inclusion: { in: PdfReportService::SUPPORTED_FORMATS }

  scope :active, -> { where(is_active: true) }
  scope :for_account, ->(account) { where(account: account) }
  scope :due_for_execution, -> { active.where("next_run_at <= ?", Time.current) }

  before_save :calculate_next_run_time, if: -> { frequency_changed? || new_record? }

  def recipients_list
    return [] if recipients.blank?

    recipients.is_a?(Array) ? recipients : JSON.parse(recipients)
  rescue JSON::ParserError
    []
  end

  def recipients_list=(emails)
    self.recipients = emails.is_a?(Array) ? emails.to_json : emails
  end

  # Enqueue a worker job to generate and (if recipients are configured) email
  # the report. Updates run timestamps and returns the persisted ReportRequest.
  def execute_report!
    return nil unless is_active?

    request_parameters = (parameters.is_a?(Hash) ? parameters.deep_dup : {})
    if recipients_list.any?
      request_parameters["delivery_method"] = "email"
      request_parameters["recipients"] = recipients_list
    end

    report_request = PdfReportService.enqueue!(
      report_type: report_type,
      account: account,
      user: user,
      format: format,
      name: scheduled_report_name,
      start_date: 1.month.ago.beginning_of_month,
      end_date: Date.current.end_of_month,
      parameters: request_parameters
    )

    self.last_run_at = Time.current
    calculate_next_run_time
    save!

    Rails.logger.info "Scheduled report #{id} dispatched as request #{report_request.id}"
    report_request
  end

  # Advance the schedule WITHOUT dispatching. Used by the sweep when
  # execute_report! raised: next_run_at would otherwise stay in the past, so
  # every subsequent sweep would re-dispatch the same failing report and pile
  # up ReportRequest rows. A failed report waits for its next window instead.
  def reschedule_after_failure!
    self.last_run_at = Time.current
    calculate_next_run_time

    # update_columns, not save!(validate: false): this is reached AFTER a failed
    # dispatch, so the record may be dirty with — or invalid because of — the
    # very attributes that made it fail. Writing only these three columns keeps
    # the failure from being force-persisted along with the schedule bump.
    update_columns(
      last_run_at: last_run_at,
      next_run_at: next_run_at,
      last_status: "failed"
    )
  end

  private

  def scheduled_report_name
    base = name.presence || report_type.humanize
    period = case frequency
             when "daily"   then Date.current.strftime("%B %d, %Y")
             when "weekly"  then "Week of #{Date.current.beginning_of_week.strftime('%B %d, %Y')}"
             when "monthly" then Date.current.strftime("%B %Y")
             else Date.current.iso8601
             end
    "#{base} — #{period}"
  end

  def calculate_next_run_time
    base_time = last_run_at || created_at || Time.current

    self.next_run_at = case frequency
                       when "daily"
                         base_time.beginning_of_day + 1.day + 8.hours
                       when "weekly"
                         base_time.beginning_of_week + 1.week + 8.hours
                       when "monthly"
                         base_time.beginning_of_month + 1.month + 8.hours
                       end
  end
end
