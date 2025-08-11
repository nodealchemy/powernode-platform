class ScheduledReport < ApplicationRecord

  belongs_to :account, optional: true
  belongs_to :user

  validates :report_type, presence: true, inclusion: { in: PdfReportService::REPORT_TYPES }
  validates :frequency, presence: true, inclusion: { in: %w[daily weekly monthly] }
  validates :format, presence: true, inclusion: { in: %w[pdf csv] }

  scope :active, -> { where(active: true) }
  scope :for_account, ->(account) { where(account: account) }
  scope :due_for_execution, -> { active.where('next_run_at <= ?', Time.current) }

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

  def execute_report!
    return unless active?
    
    # Generate the report
    pdf_data = PdfReportService.new(
      report_type: report_type,
      account: account,
      start_date: 1.month.ago.beginning_of_month,
      end_date: Date.current.end_of_month,
      user: user
    ).generate_pdf

    # Update last run time and calculate next run time
    self.last_run_at = Time.current
    calculate_next_run_time
    save!

    # TODO: Send email with report attachment
    # This would be handled by a mailer/notification service
    Rails.logger.info "Scheduled report #{id} executed for #{recipients_list.join(', ')}"
    
    pdf_data
  end

  private

  def calculate_next_run_time
    base_time = last_run_at || created_at || Time.current
    
    self.next_run_at = case frequency
                      when 'daily'
                        base_time.beginning_of_day + 1.day + 8.hours
                      when 'weekly'
                        base_time.beginning_of_week + 1.week + 8.hours
                      when 'monthly'
                        base_time.beginning_of_month + 1.month + 8.hours
                      end
  end
end
