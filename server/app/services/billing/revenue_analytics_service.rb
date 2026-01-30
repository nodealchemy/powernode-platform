# frozen_string_literal: true

module Billing
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
        WorkerJobService.enqueue_analytics_job("calculate_revenue_snapshot", job_data)

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
        WorkerJobService.enqueue_analytics_job("calculate_growth_metrics", job_data)

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
      subscriptions = account_subscriptions_active

      mrr_cents = subscriptions.sum do |subscription|
        plan_price = subscription.plan.price_cents
        quantity = subscription.quantity || 1

        # Normalize to monthly
        case subscription.plan.billing_cycle
        when "yearly"
          plan_price * quantity / 12
        when "weekly"
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
      if @account
        @account.subscription&.active? ? 1 : 0
      else
        Subscription.active.count
      end
    end

    def churn_rate(period_days = 30)
      end_date = Date.current
      start_date = end_date - period_days.days

      if @account
        # Account has_one :subscription - handle singular relationship
        sub = @account.subscription
        if sub && sub.created_at <= start_date && sub.active?
          active_start = 1
        else
          active_start = 0
        end
        cancelled_period = (sub && sub.canceled_at.present? && sub.canceled_at.between?(start_date, end_date)) ? 1 : 0
      else
        active_start = Subscription.where("created_at <= ?", start_date).active.count
        cancelled_period = Subscription.where(canceled_at: start_date..end_date).count
      end

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
      if @account
        @account.subscription&.active? ? 1 : 0
      else
        Subscription.active.count
      end
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

    # MRR trend data using RevenueSnapshot model
    def mrr_trend(months: 12)
      end_date = Date.current
      start_date = end_date - months.months

      # First try to get from snapshots
      snapshots = if @account
                    RevenueSnapshot.for_account(@account).in_date_range(start_date, end_date).order(:snapshot_date)
      else
                    RevenueSnapshot.global.in_date_range(start_date, end_date).order(:snapshot_date)
      end

      if snapshots.any?
        snapshots.map do |snapshot|
          {
            date: snapshot.snapshot_date.iso8601,
            mrr: snapshot.mrr_cents / 100.0,
            arr: snapshot.arr_cents / 100.0,
            subscriber_count: snapshot.active_subscriptions || 0,
            growth_rate: snapshot.growth_rate_percentage || 0.0,
            new_mrr: (snapshot.get_metadata("new_mrr_cents") || 0) / 100.0,
            churned_mrr: (snapshot.get_metadata("churned_mrr_cents") || 0) / 100.0
          }
        end
      else
        # Generate trend from subscription data when no snapshots exist
        generate_mrr_trend_from_subscriptions(start_date, end_date)
      end
    end

    # Cohort analysis - groups customers by signup month
    def cohort_analysis(cohort_months: 12)
      end_date = Date.current
      start_date = end_date - cohort_months.months

      all_subs = if @account
                   sub = @account.subscription
                   sub ? [sub] : []
                 else
                   Subscription.all.to_a
                 end

      # Group subscriptions by signup month
      cohorts = all_subs
                .select { |s| s.created_at >= start_date }
                .group_by { |s| s.created_at.beginning_of_month }

      cohort_data = []

      cohorts.each do |cohort_start, cohort_subscriptions|
        cohort_name = cohort_start.strftime("%b %Y")
        cohort_size = cohort_subscriptions.count

        # Calculate retention for each month after signup
        retention_data = []
        (0..12).each do |month_offset|
          check_date = cohort_start + month_offset.months

          # Skip future months
          break if check_date > Date.current

          # Count how many from this cohort are still active
          active_count = cohort_subscriptions.count do |subscription|
            subscription.active? ||
              (subscription.canceled_at.present? && subscription.canceled_at > check_date.end_of_month)
          end

          retention_rate = cohort_size > 0 ? (active_count.to_f / cohort_size * 100).round(1) : 0
          retention_data << retention_rate
        end

        # Calculate cohort revenue
        cohort_mrr = cohort_subscriptions.select(&:active?).sum do |sub|
          (sub.plan.price_cents * (sub.quantity || 1)) / 100.0
        end

        cohort_data << {
          cohort: cohort_name,
          cohort_date: cohort_start.iso8601,
          size: cohort_size,
          retention: retention_data,
          current_mrr: cohort_mrr.round(2),
          churned: cohort_subscriptions.count { |s| s.status == "canceled" },
          active: cohort_subscriptions.count(&:active?)
        }
      end

      # Sort by cohort date descending
      cohort_data.sort_by { |c| c[:cohort_date] }.reverse
    end

    # Export revenue data as CSV with proper formatting
    def export_revenue_data_csv(period = "monthly")
      require "csv"

      end_date = Date.current
      start_date = case period
      when "daily" then end_date - 30.days
      when "weekly" then end_date - 12.weeks
      when "yearly" then end_date - 5.years
      else end_date - 12.months
      end

      # Get snapshot data or generate from subscriptions
      trend_data = mrr_trend(months: ((end_date - start_date) / 30).to_i.clamp(1, 60))

      CSV.generate do |csv|
        # Headers
        csv << ["Date", "MRR ($)", "ARR ($)", "Active Subscriptions", "Growth Rate (%)", "New MRR ($)", "Churned MRR ($)", "Net New MRR ($)"]

        # Data rows
        trend_data.each do |row|
          net_new = (row[:new_mrr] || 0) - (row[:churned_mrr] || 0)
          csv << [
            row[:date],
            format("%.2f", row[:mrr] || 0),
            format("%.2f", row[:arr] || 0),
            row[:subscriber_count] || 0,
            format("%.2f", row[:growth_rate] || 0),
            format("%.2f", row[:new_mrr] || 0),
            format("%.2f", row[:churned_mrr] || 0),
            format("%.2f", net_new)
          ]
        end

        # Summary row
        if trend_data.any?
          csv << []
          csv << ["Summary"]
          csv << ["Current MRR", format("%.2f", current_mrr)]
          csv << ["Current ARR", format("%.2f", current_arr)]
          csv << ["Active Subscriptions", active_subscriptions_count]
          csv << ["Churn Rate", format("%.4f", churn_rate)]
          csv << ["ARPU", format("%.2f", calculate_arpu)]
        end
      end
    end

    private

    # Helper to get active subscriptions for account or globally
    # Account has has_one :subscription, so we wrap it in an array
    def account_subscriptions_active
      if @account
        sub = @account.subscription
        sub&.active? ? [sub] : []
      else
        Subscription.active.to_a
      end
    end

    # Helper to get all subscriptions for account or globally
    def account_subscriptions_all
      if @account
        sub = @account.subscription
        sub ? [sub] : []
      else
        Subscription.all.to_a
      end
    end

    def generate_mrr_trend_from_subscriptions(start_date, end_date)
      all_subscriptions = if @account
                            sub = @account.subscription
                            (sub && sub.created_at <= end_date) ? [sub] : []
                          else
                            Subscription.where("created_at <= ?", end_date).to_a
                          end

      trend_data = []
      current_date = start_date

      previous_mrr = 0

      while current_date <= end_date
        # Calculate MRR as of this date
        active_subs = all_subscriptions.select do |sub|
          sub.created_at <= current_date.end_of_month &&
            (sub.active? || (sub.canceled_at.present? && sub.canceled_at > current_date.end_of_month))
        end

        mrr_cents = active_subs.sum do |sub|
          price = sub.plan.price_cents * (sub.quantity || 1)
          case sub.plan.billing_cycle
          when "yearly" then price / 12
          when "weekly" then price * 4.33
          else price
          end
        end

        mrr = mrr_cents / 100.0
        growth_rate = previous_mrr > 0 ? ((mrr - previous_mrr) / previous_mrr * 100).round(2) : 0

        # Calculate new and churned for this month
        new_subs = all_subscriptions.count do |sub|
          sub.created_at.between?(current_date.beginning_of_month, current_date.end_of_month)
        end

        churned_subs = all_subscriptions.count do |sub|
          sub.canceled_at.present? &&
            sub.canceled_at.between?(current_date.beginning_of_month, current_date.end_of_month)
        end

        trend_data << {
          date: current_date.end_of_month.iso8601,
          mrr: mrr.round(2),
          arr: (mrr * 12).round(2),
          subscriber_count: active_subs.count,
          growth_rate: growth_rate,
          new_mrr: 0, # Would require more complex calculation
          churned_mrr: 0,
          new_subscriptions: new_subs,
          churned_subscriptions: churned_subs
        }

        previous_mrr = mrr
        current_date += 1.month
      end

      trend_data
    end

    # Class methods for bulk operations
    class << self
      def update_all_metrics(force_recalculation: false)
        Rails.logger.info "Delegating bulk metrics update to worker service"

        job_data = { force_recalculation: force_recalculation }

        begin
          WorkerJobService.enqueue_analytics_job("update_all_metrics", job_data)
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
          WorkerJobService.enqueue_analytics_job("cleanup_old_snapshots", job_data)
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
          WorkerJobService.enqueue_analytics_job("recalculate_historical_data", job_data)
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
end

# Backwards compatibility alias
