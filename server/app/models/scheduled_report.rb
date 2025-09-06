# frozen_string_literal: true

class ScheduledReport < ApplicationRecord

  belongs_to :account, optional: true
  belongs_to :user, foreign_key: 'created_by_id'

  validates :report_type, presence: true, inclusion: { in: PdfReportService::REPORT_TYPES }
  validates :frequency, presence: true, inclusion: { in: %w[daily weekly monthly] }
  validates :format, presence: true, inclusion: { in: %w[pdf csv] }

  scope :active, -> { where(is_active: true) }
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
    return unless is_active?
    
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

    # Send email with report attachment via worker service
    send_report_email(pdf_data)
    
    Rails.logger.info "Scheduled report #{id} executed and emailed to #{recipients_list.join(', ')}"
    
    pdf_data
  end

  def send_report_email(pdf_data)
    return if recipients_list.empty?
    
    # Generate report filename with timestamp
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    filename = "#{report_type}_report_#{timestamp}.pdf"
    
    # Create temporary file for the PDF
    temp_file = Tempfile.new([filename, '.pdf'])
    temp_file.binmode
    temp_file.write(pdf_data)
    temp_file.close
    
    begin
      # Send email to each recipient using worker service
      recipients_list.each do |recipient_email|
        # Use WorkerJobService to queue the email delivery
        WorkerJobService.enqueue_email_job('report_email', {
          recipient: recipient_email,
          subject: generate_report_subject,
          template: 'scheduled_report',
          template_data: {
            report_type: report_type,
            frequency: frequency,
            account_name: account&.name || 'System',
            user_name: user.full_name,
            generated_at: Time.current.strftime('%B %d, %Y at %I:%M %p'),
            period: format_report_period
          },
          attachments: [
            {
              filename: filename,
              content: Base64.encode64(pdf_data),
              content_type: 'application/pdf'
            }
          ],
          account_id: account&.id,
          user_id: user.id
        })
      end
    ensure
      # Clean up temporary file
      temp_file.unlink if temp_file
    end
    
    # Record email delivery attempt
    EmailDelivery.create!(
      recipient_email: recipients_list.join(', '),
      subject: generate_report_subject,
      email_type: 'report_generated',
      account: account,
      user: user,
      template: 'scheduled_report',
      template_data: {
        report_id: id,
        recipients_count: recipients_list.size
      }.to_json
    )
  end
  
  def generate_report_subject
    period_text = case frequency
                  when 'daily' then 'Daily'
                  when 'weekly' then 'Weekly'
                  when 'monthly' then 'Monthly'
                  end
    
    "#{period_text} #{report_type.humanize} Report - #{format_report_period}"
  end
  
  def format_report_period
    case frequency
    when 'daily'
      (last_run_at || Time.current).strftime('%B %d, %Y')
    when 'weekly'
      start_of_week = (last_run_at || Time.current).beginning_of_week
      end_of_week = start_of_week.end_of_week
      "Week of #{start_of_week.strftime('%B %d')} - #{end_of_week.strftime('%B %d, %Y')}"
    when 'monthly'
      (last_run_at || Time.current).strftime('%B %Y')
    end
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