# frozen_string_literal: true

# Revenue Analytics Service - Delegates to worker service
class RevenueAnalyticsService
  include ActiveModel::Model

  attr_accessor :account, :start_date, :end_date

  def initialize(account: nil, start_date: nil, end_date: nil)
    @account = account
    @start_date = start_date || 12.months.ago.beginning_of_month
    @end_date = end_date || Date.current.end_of_month
  end

  # Calculate and store revenue snapshot (delegated to worker service)
  def calculate_revenue_snapshot(date = Date.current, period_type = "daily")
    Rails.logger.info "Delegating revenue snapshot calculation to worker service"

    job_data = {
      account_id: @account&.id,
      date: date.iso8601,
      period_type: period_type
    }

    begin
      # Enqueue analytics job in worker service
      WorkerJobService.enqueue_analytics_job('calculate_revenue_snapshot', job_data)
      
      {
        success: true,
        message: "Revenue snapshot calculation queued",
        account: @account&.name || "Global",
        date: date,
        period_type: period_type
      }
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to delegate revenue snapshot calculation: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Calculate growth metrics (delegated to worker service)
  def calculate_growth_metrics
    Rails.logger.info "Delegating growth metrics calculation to worker service"

    job_data = {
      account_id: @account&.id,
      start_date: @start_date.iso8601,
      end_date: @end_date.iso8601
    }

    begin
      # Enqueue analytics job in worker service
      WorkerJobService.enqueue_analytics_job('calculate_growth_metrics', job_data)
      
      {
        success: true,
        message: "Growth metrics calculation queued",
        account: @account&.name || "Global",
        period: { start_date: @start_date, end_date: @end_date }
      }
    rescue WorkerJobService::WorkerServiceError => e
      Rails.logger.error "Failed to delegate growth metrics calculation: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Simple synchronous methods for immediate data needs
  def current_mrr
    subscriptions = @account ? @account.subscriptions.active : Subscription.active
    
    mrr_cents = subscriptions.sum do |subscription|
      plan_price = subscription.plan.price_cents
      quantity = subscription.quantity || 1
      
      # Normalize to monthly
      case subscription.plan.billing_cycle
      when 'yearly'
        plan_price * quantity / 12
      when 'weekly'
        plan_price * quantity * 4.33 # Average weeks per month
      else
        plan_price * quantity
      end
    end

    mrr_cents / 100.0 # Return as float for controller compatibility
  end

  def current_arr
    current_mrr * 12
  end

  def active_subscriptions_count
    subscriptions = @account ? @account.subscriptions : Subscription.all
    subscriptions.active.count
  end

  def churn_rate(period_days = 30)
    end_date = Date.current
    start_date = end_date - period_days.days
    
    subscriptions = @account ? @account.subscriptions : Subscription.all
    
    active_start = subscriptions.where('created_at <= ?', start_date).active.count
    cancelled_period = subscriptions.where(canceled_at: start_date..end_date).count
    
    return 0.0 if active_start == 0
    
    (cancelled_period.to_f / active_start).round(4) # Return as decimal for controller
  end

  # Alias for controller compatibility
  def calculate_churn_rate(date = Date.current, period_type = "monthly")
    case period_type
    when "monthly"
      churn_rate(30)
    when "weekly"
      churn_rate(7)
    else
      churn_rate(30)
    end
  end

  # Count active customers
  def count_active_customers
    active_subscriptions_count
  end

  # Calculate ARPU (Average Revenue Per User)
  def calculate_arpu
    active_customers = count_active_customers
    return 0.0 if active_customers == 0
    
    (current_mrr / active_customers).round(2)
  end

  # Calculate LTV (Customer Lifetime Value)
  def calculate_ltv
    arpu = calculate_arpu
    monthly_churn = calculate_churn_rate
    
    return 0.0 if monthly_churn <= 0
    
    # Simple LTV calculation: ARPU / Monthly Churn Rate
    (arpu / monthly_churn).round(2)
  end

  # Calculate growth rate between two values
  def calculate_growth_rate(current_value, previous_value)
    return 0.0 if previous_value <= 0 || current_value <= 0
    
    ((current_value.to_f - previous_value.to_f) / previous_value.to_f).round(4)
  end

  # MRR trend data (simplified for immediate needs)
  def mrr_trend(months: 12)
    # Return empty array for now - would need RevenueSnapshot data
    []
  end

  # Cohort analysis (simplified for immediate needs)
  def cohort_analysis(cohort_months: 12)
    # Return empty array for now - would need proper cohort calculation
    []
  end

  # Export revenue data as CSV (simplified)
  def export_revenue_data_csv(period = "monthly")
    # Return empty CSV for now
    "Date,MRR,ARR,Active Subscriptions\n"
  end

  # Class methods for bulk operations
  class << self
    def update_all_metrics(force_recalculation: false)
      Rails.logger.info "Delegating bulk metrics update to worker service"
      
      job_data = { force_recalculation: force_recalculation }

      begin
        WorkerJobService.enqueue_analytics_job('update_all_metrics', job_data)
        { success: true, message: "Bulk metrics update queued" }
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.error "Failed to delegate bulk metrics update: #{e.message}"
        { success: false, error: e.message }
      end
    end

    def cleanup_old_snapshots(days_old: 90)
      Rails.logger.info "Delegating analytics cleanup to worker service"
      
      job_data = { days_old: days_old }

      begin
        WorkerJobService.enqueue_analytics_job('cleanup_old_snapshots', job_data)
        { success: true, message: "Analytics cleanup queued" }
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.error "Failed to delegate analytics cleanup: #{e.message}"
        { success: false, error: e.message }
      end
    end

    def recalculate_historical_data(start_date:, end_date: Date.current)
      Rails.logger.info "Delegating historical data recalculation to worker service"
      
      job_data = {
        start_date: start_date.iso8601,
        end_date: end_date.iso8601
      }

      begin
        WorkerJobService.enqueue_analytics_job('recalculate_historical_data', job_data)
        { success: true, message: "Historical data recalculation queued" }
      rescue WorkerJobService::WorkerServiceError => e
        Rails.logger.error "Failed to delegate historical recalculation: #{e.message}"
        { success: false, error: e.message }
      end
    end

    # Get current snapshot data (synchronous for dashboard needs)
    def current_global_metrics
      {
        mrr: new(account: nil).current_mrr,
        arr: new(account: nil).current_arr,
        active_subscriptions: new(account: nil).active_subscriptions_count,
        churn_rate: new(account: nil).churn_rate,
        calculated_at: Time.current
      }
    end
  end
end