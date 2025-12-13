# frozen_string_literal: true

# PDF Report Service - Delegates to worker service
class PdfReportService
  REPORT_TYPES = %w[
    revenue_report
    growth_report
    churn_report
    customer_report
    subscription_report
    executive_summary
  ].freeze

  def initialize(report_type:, account: nil, start_date: nil, end_date: nil, user: nil)
    @report_type = report_type
    @account = account
    @start_date = start_date || 12.months.ago.to_date.beginning_of_month
    @end_date = end_date || Date.current.end_of_month
    @user = user
  end

  # Generate PDF report (delegated to worker service)
  def generate_pdf(format: "pdf")
    Rails.logger.info "Delegating PDF report generation to worker service"

    unless REPORT_TYPES.include?(@report_type)
      return { success: false, error: "Unsupported report type: #{@report_type}" }
    end

    job_data = {
      report_type: @report_type,
      account_id: @account&.id,
      start_date: @start_date.iso8601,
      end_date: @end_date.iso8601,
      user_id: @user&.id,
      format: format
    }

    begin
      # Enqueue report generation in worker service
      WorkerJobService.enqueue_report_job("generate_report", job_data)

      {
        success: true,
        message: "Report generation queued for processing",
        report_type: @report_type,
        format: format,
        job_data: job_data
      }
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to delegate report generation: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Synchronous method for simple report data (no PDF generation)
  def get_report_data
    case @report_type
    when "revenue_report"
      get_revenue_data
    when "growth_report"
      get_growth_data
    when "customer_report"
      get_customer_data
    else
      { success: false, error: "Report data not available for type: #{@report_type}" }
    end
  end

  private

  def get_revenue_data
    # Simple revenue data that doesn't require complex processing
    base_query = @account ? @account.payments : Payment.all
    payments = base_query.succeeded
                         .where(processed_at: @start_date..@end_date)

    {
      success: true,
      data: {
        total_revenue: payments.sum(:amount_cents),
        payment_count: payments.count,
        average_payment: payments.average(:amount_cents)&.to_f || 0,
        period: { start_date: @start_date, end_date: @end_date }
      }
    }
  end

  def get_growth_data
    # Simple growth metrics
    subscriptions = @account ? @account.subscriptions : Subscription.all
    active_subs = subscriptions.active.count
    new_subs = subscriptions.where(created_at: @start_date..@end_date).count

    {
      success: true,
      data: {
        active_subscriptions: active_subs,
        new_subscriptions: new_subs,
        period: { start_date: @start_date, end_date: @end_date }
      }
    }
  end

  def get_customer_data
    # Simple customer metrics
    base_query = @account ? @account.users : User.all
    users = base_query.active

    {
      success: true,
      data: {
        total_customers: users.count,
        new_customers: users.where(created_at: @start_date..@end_date).count,
        period: { start_date: @start_date, end_date: @end_date }
      }
    }
  end

  # Class method for bulk report generation
  class << self
    def generate_scheduled_reports
      Rails.logger.info "Delegating scheduled report generation to worker service"

      begin
        WorkerJobService.enqueue_report_job("generate_scheduled_reports", {})
        { success: true, message: "Scheduled report generation queued" }
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.error "Failed to delegate scheduled reports: #{e.message}"
        { success: false, error: e.message }
      end
    end

    def cleanup_old_reports(days_old: 30)
      Rails.logger.info "Delegating report cleanup to worker service"

      begin
        WorkerJobService.enqueue_report_job("cleanup_old_reports", { days_old: days_old })
        { success: true, message: "Report cleanup queued" }
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.error "Failed to delegate report cleanup: #{e.message}"
        { success: false, error: e.message }
      end
    end
  end
end
