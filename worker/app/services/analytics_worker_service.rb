# frozen_string_literal: true

require_relative 'base_worker_service'

class AnalyticsWorkerService < BaseWorkerService
  # Calculate and store revenue snapshot for an account
  def calculate_revenue_snapshot(account_id: nil, date: Date.current, period_type: "daily")
    log_info("Calculating revenue snapshot", account_id: account_id, date: date, period_type: period_type)

    begin
      # Get account details if specific account
      account = nil
      if account_id
        account_response = api_client.get("/api/v1/accounts/#{account_id}")
        unless account_response[:success]
          return { success: false, error: "Account not found" }
        end
        account = account_response[:data]
      end

      # Calculate all metrics for the given date and period
      metrics = calculate_all_metrics(account_id, date, period_type)

      # Store revenue snapshot via API
      snapshot_data = {
        account_id: account_id,
        snapshot_date: date.iso8601,
        mrr_cents: metrics[:mrr_cents],
        arr_cents: metrics[:arr_cents],
        total_revenue_cents: metrics[:total_revenue_cents],
        active_subscriptions: metrics[:active_subscriptions],
        new_subscriptions: metrics[:new_subscriptions],
        cancelled_subscriptions: metrics[:cancelled_subscriptions],
        churn_rate: metrics[:churn_rate],
        ltv_cents: metrics[:ltv_cents],
        arpu_cents: metrics[:arpu_cents],
        growth_rate: metrics[:growth_rate],
        trial_conversions: metrics[:trial_conversions],
        refunds_cents: metrics[:refunds_cents],
        net_revenue_cents: metrics[:net_revenue_cents],
        period_type: period_type
      }

      # Create or update revenue snapshot
      snapshot_response = api_client.post("/api/v1/analytics/revenue_snapshots", snapshot_data)

      if snapshot_response[:success]
        log_info("Revenue snapshot saved successfully", 
          account_id: account_id,
          mrr: (metrics[:mrr_cents] / 100.0),
          active_subscriptions: metrics[:active_subscriptions]
        )
        { success: true, snapshot: snapshot_response[:data], metrics: metrics }
      else
        log_error("Failed to save revenue snapshot", nil, error: snapshot_response[:error])
        { success: false, error: snapshot_response[:error] }
      end

    rescue => e
      log_error("Revenue snapshot calculation failed", e, account_id: account_id, date: date)
      { success: false, error: e.message }
    end
  end

  # Calculate growth metrics for a specific period
  def calculate_growth_metrics(account_id: nil, start_date: nil, end_date: nil)
    start_date ||= 12.months.ago.beginning_of_month.to_date
    end_date ||= Date.current.end_of_month

    log_info("Calculating growth metrics", account_id: account_id, start_date: start_date, end_date: end_date)

    begin
      # Get subscriptions data for the period
      subscriptions_params = {
        account_id: account_id,
        start_date: start_date.iso8601,
        end_date: end_date.iso8601,
        include_cancelled: true
      }

      subscriptions_response = api_client.get("/api/v1/subscriptions", subscriptions_params)
      unless subscriptions_response[:success]
        return { success: false, error: "Failed to fetch subscriptions data" }
      end

      subscriptions = subscriptions_response[:data]

      # Calculate growth metrics
      metrics = {
        customer_growth: calculate_customer_growth(subscriptions, start_date, end_date),
        revenue_growth: calculate_revenue_growth(account_id, start_date, end_date),
        churn_analysis: calculate_churn_analysis(subscriptions, start_date, end_date),
        cohort_data: calculate_cohort_metrics(subscriptions, start_date, end_date),
        ltv_analysis: calculate_ltv_analysis(subscriptions, account_id)
      }

      log_info("Growth metrics calculated successfully", account_id: account_id, metrics_count: metrics.keys.size)
      { success: true, metrics: metrics, period: { start_date: start_date, end_date: end_date } }

    rescue => e
      log_error("Growth metrics calculation failed", e, account_id: account_id)
      { success: false, error: e.message }
    end
  end

  # Update metrics for all accounts
  def update_all_metrics(force_recalculation: false)
    log_info("Updating metrics for all accounts", force_recalculation: force_recalculation)

    begin
      # Get all active accounts
      accounts_response = api_client.get("/api/v1/accounts", { status: 'active' })
      unless accounts_response[:success]
        return { success: false, error: "Failed to fetch accounts" }
      end

      accounts = accounts_response[:data]
      results = []

      # Process each account
      accounts.each do |account|
        account_result = calculate_revenue_snapshot(account_id: account['id'])
        results << {
          account_id: account['id'],
          account_name: account['name'],
          success: account_result[:success],
          error: account_result[:error]
        }

        # Add delay to prevent overwhelming the API
        sleep(0.1)
      end

      # Also calculate global metrics
      global_result = calculate_revenue_snapshot(account_id: nil)
      results << {
        account_id: nil,
        account_name: "Global",
        success: global_result[:success],
        error: global_result[:error]
      }

      successful_count = results.count { |r| r[:success] }
      failed_count = results.count { |r| !r[:success] }

      log_info("Metrics update completed", successful: successful_count, failed: failed_count)
      
      {
        success: true,
        results: results,
        summary: {
          total_accounts: accounts.size + 1, # +1 for global
          successful: successful_count,
          failed: failed_count
        }
      }

    rescue => e
      log_error("Metrics update failed", e)
      { success: false, error: e.message }
    end
  end

  private

  def calculate_all_metrics(account_id, date, period_type)
    # Get subscription data for metrics calculation
    subscription_params = { account_id: account_id, active_on: date.iso8601 }
    active_subs_response = api_client.get("/api/v1/subscriptions", subscription_params)
    active_subscriptions = active_subs_response[:success] ? active_subs_response[:data] : []

    # Get payment data for revenue calculation
    payment_params = { 
      account_id: account_id, 
      start_date: date.beginning_of_month.iso8601,
      end_date: date.end_of_month.iso8601,
      status: 'succeeded'
    }
    payments_response = api_client.get("/api/v1/payments", payment_params)
    payments = payments_response[:success] ? payments_response[:data] : []

    # Calculate Monthly Recurring Revenue (MRR)
    mrr_cents = active_subscriptions.sum do |sub|
      plan_price = sub.dig('plan', 'price_cents') || 0
      quantity = sub['quantity'] || 1
      
      # Normalize to monthly
      case sub.dig('plan', 'billing_interval')
      when 'year'
        plan_price * quantity / 12
      when 'week'
        plan_price * quantity * 4.33 # Average weeks per month
      else
        plan_price * quantity
      end
    end

    # Annual Recurring Revenue (ARR)
    arr_cents = mrr_cents * 12

    # Total revenue for the period
    total_revenue_cents = payments.sum { |p| p['amount_cents'] || 0 }

    # Subscription metrics
    active_subscriptions_count = active_subscriptions.size
    
    # Get new subscriptions for the period
    new_subs_params = { 
      account_id: account_id, 
      created_after: date.beginning_of_month.iso8601,
      created_before: date.end_of_month.iso8601
    }
    new_subs_response = api_client.get("/api/v1/subscriptions", new_subs_params)
    new_subscriptions = new_subs_response[:success] ? new_subs_response[:data].size : 0

    # Get cancelled subscriptions for the period
    cancelled_subs_params = { 
      account_id: account_id, 
      cancelled_after: date.beginning_of_month.iso8601,
      cancelled_before: date.end_of_month.iso8601
    }
    cancelled_subs_response = api_client.get("/api/v1/subscriptions", cancelled_subs_params)
    cancelled_subscriptions = cancelled_subs_response[:success] ? cancelled_subs_response[:data].size : 0

    # Calculate churn rate
    churn_rate = active_subscriptions_count > 0 ? 
      (cancelled_subscriptions.to_f / active_subscriptions_count * 100).round(2) : 0.0

    # Average Revenue Per User (ARPU)
    arpu_cents = active_subscriptions_count > 0 ? (mrr_cents / active_subscriptions_count) : 0

    # Calculate growth rate compared to previous period
    previous_date = date - 1.month
    previous_metrics = get_previous_snapshot(account_id, previous_date)
    previous_mrr = previous_metrics&.dig('mrr_cents') || 0
    
    growth_rate = previous_mrr > 0 ? 
      (((mrr_cents - previous_mrr).to_f / previous_mrr) * 100).round(2) : 0.0

    # Get refund data
    refunds_params = { 
      account_id: account_id, 
      start_date: date.beginning_of_month.iso8601,
      end_date: date.end_of_month.iso8601,
      status: 'refunded'
    }
    refunds_response = api_client.get("/api/v1/payments", refunds_params)
    refunds = refunds_response[:success] ? refunds_response[:data] : []
    refunds_cents = refunds.sum { |p| p['amount_cents'] || 0 }

    # Net revenue (total revenue minus refunds)
    net_revenue_cents = total_revenue_cents - refunds_cents

    # Estimated Customer Lifetime Value (simple calculation)
    ltv_cents = churn_rate > 0 ? (arpu_cents / (churn_rate / 100)) : arpu_cents * 12

    {
      mrr_cents: mrr_cents,
      arr_cents: arr_cents,
      total_revenue_cents: total_revenue_cents,
      active_subscriptions: active_subscriptions_count,
      new_subscriptions: new_subscriptions,
      cancelled_subscriptions: cancelled_subscriptions,
      churn_rate: churn_rate,
      ltv_cents: ltv_cents,
      arpu_cents: arpu_cents,
      growth_rate: growth_rate,
      trial_conversions: count_trial_conversions(account_id, date),
      refunds_cents: refunds_cents,
      net_revenue_cents: net_revenue_cents
    }
  end

  def count_trial_conversions(account_id, date)
    trial_params = {
      account_id: account_id,
      converted_after: date.beginning_of_month.iso8601,
      converted_before: date.end_of_month.iso8601,
      status: 'active',
      was_trial: true
    }
    trial_response = api_client.get("/api/v1/subscriptions", trial_params)
    trial_response[:success] ? trial_response[:data].size : 0
  rescue StandardError
    0
  end

  def get_previous_snapshot(account_id, date)
    params = { account_id: account_id, date: date.iso8601 }
    response = api_client.get("/api/v1/analytics/revenue_snapshots", params)
    response[:success] ? response[:data].first : nil
  end

  def calculate_customer_growth(subscriptions, start_date, end_date)
    new_customers = subscriptions.count { |s| Date.parse(s['created_at']) >= start_date }
    total = subscriptions.count
    active_at_start = subscriptions.count { |s| Date.parse(s['created_at']) < start_date }
    growth_rate = active_at_start > 0 ? ((new_customers.to_f / active_at_start) * 100).round(2) : 0.0

    {
      new_customers: new_customers,
      total_customers: total,
      growth_rate: growth_rate
    }
  end

  def calculate_revenue_growth(account_id, start_date, end_date)
    period_length = (end_date - start_date).to_i
    previous_start = start_date - period_length.days
    previous_end = start_date - 1.day

    current_response = api_client.get("/api/v1/payments", {
      account_id: account_id, start_date: start_date.iso8601,
      end_date: end_date.iso8601, status: 'succeeded'
    })
    current_payments = current_response[:success] ? current_response[:data] : []
    current_period_revenue = current_payments.sum { |p| p['amount_cents'] || 0 }

    previous_response = api_client.get("/api/v1/payments", {
      account_id: account_id, start_date: previous_start.iso8601,
      end_date: previous_end.iso8601, status: 'succeeded'
    })
    previous_payments = previous_response[:success] ? previous_response[:data] : []
    previous_period_revenue = previous_payments.sum { |p| p['amount_cents'] || 0 }

    growth_rate = previous_period_revenue > 0 ?
      (((current_period_revenue - previous_period_revenue).to_f / previous_period_revenue) * 100).round(2) : 0.0

    {
      current_period: current_period_revenue,
      previous_period: previous_period_revenue,
      growth_rate: growth_rate,
      growth_amount: current_period_revenue - previous_period_revenue
    }
  end

  def calculate_churn_analysis(subscriptions, start_date, end_date)
    cancelled = subscriptions.select { |s| s['cancelled_at'] && Date.parse(s['cancelled_at']) >= start_date }
    active_at_start = subscriptions.count { |s| Date.parse(s['created_at']) < start_date }
    churn_rate = active_at_start > 0 ? ((cancelled.size.to_f / active_at_start) * 100).round(2) : 0.0

    {
      total_churned: cancelled.size,
      churn_rate: churn_rate,
      reasons: cancelled.group_by { |s| s['cancellation_reason'] || 'unspecified' }.transform_values(&:size)
    }
  end

  def calculate_cohort_metrics(subscriptions, start_date, end_date)
    # Group subscriptions by creation month (cohorts)
    cohorts = subscriptions.group_by { |s| Date.parse(s['created_at']).beginning_of_month.to_s }
    retention_rates = {}

    cohorts.each do |month, subs|
      total = subs.size
      still_active = subs.count { |s| s['cancelled_at'].nil? || Date.parse(s['cancelled_at']) > end_date }
      retention_rates[month] = total > 0 ? ((still_active.to_f / total) * 100).round(2) : 0.0
    end

    {
      cohorts: cohorts.map { |month, subs| { month: month, size: subs.size } },
      retention_rates: retention_rates
    }
  end

  def calculate_ltv_analysis(subscriptions, account_id)
    active_subs = subscriptions.select { |s| s['status'] == 'active' }
    return { average_ltv: 0, ltv_by_plan: {}, ltv_trend: [] } if active_subs.empty?

    # Group by plan and compute average monthly revenue per plan
    by_plan = active_subs.group_by { |s| s.dig('plan', 'name') || 'unknown' }
    ltv_by_plan = {}

    by_plan.each do |plan_name, subs|
      avg_monthly = subs.sum { |s| (s.dig('plan', 'price_cents') || 0) * (s['quantity'] || 1) } / subs.size
      ltv_by_plan[plan_name] = avg_monthly * 12 # Annualized estimate
    end

    total_monthly = active_subs.sum { |s| (s.dig('plan', 'price_cents') || 0) * (s['quantity'] || 1) }
    average_ltv = (total_monthly / active_subs.size) * 12

    {
      average_ltv: average_ltv,
      ltv_by_plan: ltv_by_plan,
      ltv_trend: []
    }
  end
end