require 'ostruct'

class RevenueAnalyticsService
  include ActiveModel::Model

  attr_accessor :account, :start_date, :end_date

  def initialize(account: nil, start_date: nil, end_date: nil)
    @account = account
    @start_date = start_date || 12.months.ago.beginning_of_month
    @end_date = end_date || Date.current.end_of_month
  end

  # Main method to calculate and store revenue snapshot
  def calculate_revenue_snapshot(date = Date.current, period_type = "daily")
    Rails.logger.info "Calculating revenue snapshot for #{account&.name || 'global'} on #{date} (#{period_type})"

    # Calculate all metrics for the given date and period
    metrics = calculate_all_metrics(date, period_type)

    # Create or update revenue snapshot
    snapshot = RevenueSnapshot.find_or_initialize_by(
      account: account,
      snapshot_date: date
    )

    snapshot.assign_attributes(metrics)
    snapshot.save!

    Rails.logger.info "Revenue snapshot saved: MRR $#{snapshot.mrr.to_f}, Active Subscriptions: #{snapshot.active_subscriptions}"
    snapshot
  end

  # Calculate current MRR for account or globally
  def current_mrr
    subscriptions = base_subscription_query.active
    calculate_mrr_from_subscriptions(subscriptions)
  end

  # Calculate historical MRR trend
  def mrr_trend(months: 12)
    end_date_local = @end_date
    start_date_local = end_date_local.beginning_of_month - (months - 1).months

    snapshots = revenue_snapshots_query
                 .in_date_range(start_date_local, end_date_local)
                 .order(:snapshot_date)

    # Fill in missing months with zero values
    fill_missing_snapshots(snapshots, start_date_local, end_date_local, "monthly")
  end

  # Calculate churn rate for a given period
  def calculate_churn_rate(date = Date.current, period_type = "monthly")
    case period_type
    when "monthly"
      period_start = date.beginning_of_month
      period_end = date.end_of_month
      previous_period_start = (date - 1.month).beginning_of_month
      previous_period_end = (date - 1.month).end_of_month
    when "daily"
      period_start = date.beginning_of_day
      period_end = date.end_of_day
      previous_period_start = (date - 1.day).beginning_of_day
      previous_period_end = (date - 1.day).end_of_day
    end

    # Customers at start of period
    customers_start = base_subscription_query
                       .joins(:account)
                       .where(subscriptions: { created_at: ..previous_period_end })
                       .where.not(subscriptions: { ended_at: ..previous_period_start })
                       .distinct
                       .count("accounts.id")

    # Customers who churned during period
    churned_customers = base_subscription_query
                         .joins(:account)
                         .where(subscriptions: { ended_at: period_start..period_end })
                         .distinct
                         .count("accounts.id")

    return 0.0 if customers_start == 0
    churned_customers.to_f / customers_start
  end

  # Calculate growth rate between periods
  def calculate_growth_rate(current_mrr, previous_mrr)
    return 0.0 if previous_mrr == 0
    ((current_mrr - previous_mrr) / previous_mrr.to_f)
  end

  # Cohort analysis - retention by month
  def cohort_analysis(cohort_months: 12)
    results = []

    (0..cohort_months).each do |month|
      cohort_date = Date.current.beginning_of_month - month.months

      # Get customers who started in this cohort month
      cohort_customers = base_subscription_query
                          .joins(:account)
                          .where(subscriptions: { created_at: cohort_date..cohort_date.end_of_month })
                          .distinct
                          .pluck("accounts.id")

      next if cohort_customers.empty?

      retention_data = []

      # Calculate retention for each subsequent month
      (0..12).each do |retention_month|
        check_date = cohort_date + retention_month.months

        # Count how many of the cohort customers are still active
        active_customers = base_subscription_query
                            .joins(:account)
                            .where(accounts: { id: cohort_customers })
                            .where(subscriptions: { created_at: ..check_date.end_of_month })
                            .where.not(subscriptions: { ended_at: ..check_date.beginning_of_month })
                            .distinct
                            .count("accounts.id")

        retention_rate = active_customers.to_f / cohort_customers.count
        retention_data << {
          month: retention_month,
          retained_customers: active_customers,
          retention_rate: retention_rate
        }
      end

      results << {
        cohort_date: cohort_date,
        cohort_size: cohort_customers.count,
        retention_by_month: retention_data
      }
    end

    results
  end

  # Customer lifetime value calculation
  def calculate_ltv
    churn_rate = calculate_churn_rate
    return 0.0 if churn_rate == 0

    arpu = calculate_arpu
    average_customer_lifetime = 1.0 / churn_rate

    (arpu * average_customer_lifetime).round(2)
  end

  # Average revenue per user
  def calculate_arpu
    current_mrr_value = current_mrr
    active_customers = count_active_customers

    return 0.0 if active_customers == 0
    current_mrr_value / active_customers
  end

  # Export data to CSV format
  def export_revenue_data_csv(period_type = "monthly")
    snapshots = revenue_snapshots_query.for_period(period_type).recent(24).reverse

    CSV.generate(headers: true) do |csv|
      csv << %w[Date Period MRR ARR ActiveSubscriptions NewSubscriptions ChurnedSubscriptions CustomerChurnRate RevenueChurnRate GrowthRate ARPU LTV]

      snapshots.each do |snapshot|
        csv << [
          snapshot.date.strftime("%Y-%m-%d"),
          "monthly",
          snapshot.mrr.to_f,
          snapshot.arr.to_f,
          snapshot.active_subscriptions,
          snapshot.new_subscriptions,
          snapshot.churned_subscriptions,
          snapshot.customer_churn_rate_percentage,
          snapshot.revenue_churn_rate_percentage,
          snapshot.growth_rate_percentage,
          snapshot.arpu.to_f,
          snapshot.ltv.to_f
        ]
      end
    end
  end

  # Batch update revenue snapshots for a date range
  def batch_update_snapshots(start_date, end_date, period_type = "daily")
    current_date = start_date

    while current_date <= end_date
      calculate_revenue_snapshot(current_date, period_type)
      current_date += 1.day
    end
  end

  def count_active_customers(date = Date.current)
    base_subscription_query
      .joins(:account)
      .where(created_at: ..date.end_of_day)
      .where.not(ended_at: ..date.beginning_of_day)
      .distinct
      .count("accounts.id")
  end

  private

  # Calculate all metrics for a given date and period
  def calculate_all_metrics(date, period_type)
    # Determine period boundaries
    case period_type
    when "daily"
      period_start = date.beginning_of_day
      period_end = date.end_of_day
      previous_period_start = (date - 1.day).beginning_of_day
      previous_period_end = (date - 1.day).end_of_day
    when "monthly"
      period_start = date.beginning_of_month
      period_end = date.end_of_month
      previous_period_start = (date - 1.month).beginning_of_month
      previous_period_end = (date - 1.month).end_of_month
    when "yearly"
      period_start = date.beginning_of_year
      period_end = date.end_of_year
      previous_period_start = (date - 1.year).beginning_of_year
      previous_period_end = (date - 1.year).end_of_year
    else
      period_start = date.beginning_of_day
      period_end = date.end_of_day
      previous_period_start = (date - 1.day).beginning_of_day
      previous_period_end = (date - 1.day).end_of_day
    end

    # Active subscriptions at end of period
    active_subs = base_subscription_query
                   .where(created_at: ..period_end)
                   .where.not(ended_at: ..period_start)

    active_subscriptions_count = active_subs.count
    mrr_cents = calculate_mrr_from_subscriptions(active_subs, cents: true)

    # New subscriptions in period
    new_subscriptions_count = base_subscription_query
                               .where(created_at: period_start..period_end)
                               .count

    # Churned subscriptions in period
    churned_subscriptions_count = base_subscription_query
                                   .where(ended_at: period_start..period_end)
                                   .count

    # Customer counts
    total_customers_count = count_active_customers(period_end)
    new_customers_count = count_new_customers(period_start, period_end)
    churned_customers_count = count_churned_customers(period_start, period_end)

    # Churn rates
    customer_churn_rate = calculate_churn_rate(date, period_type)
    revenue_churn_rate = calculate_revenue_churn_rate(date, period_type)

    # Growth rate (compare to previous period)
    previous_mrr = calculate_historical_mrr(previous_period_end)
    growth_rate = calculate_growth_rate(mrr_cents, previous_mrr)

    {
      mrr_cents: mrr_cents,
      arr_cents: mrr_cents * 12,
      active_subscriptions: active_subscriptions_count,
      new_subscriptions: new_subscriptions_count,
      churned_subscriptions: churned_subscriptions_count,
      currency: "USD",
      metadata: {
        total_customers_count: total_customers_count,
        new_customers_count: new_customers_count,
        churned_customers_count: churned_customers_count,
        customer_churn_rate: customer_churn_rate,
        revenue_churn_rate: revenue_churn_rate,
        growth_rate: growth_rate
      }
    }
  end

  # Calculate MRR from a collection of subscriptions
  def calculate_mrr_from_subscriptions(subscriptions, cents: false)
    total_mrr = 0

    subscriptions.includes(:plan).find_each do |subscription|
      monthly_amount = case subscription.plan.billing_cycle
      when "monthly"
                        subscription.plan.price_cents * subscription.quantity
      when "quarterly"
                        (subscription.plan.price_cents * subscription.quantity) / 3.0
      when "yearly"
                        (subscription.plan.price_cents * subscription.quantity) / 12.0
      else
                        subscription.plan.price_cents * subscription.quantity
      end

      total_mrr += monthly_amount
    end

    cents ? total_mrr.to_i : (total_mrr / 100.0)
  end

  # Calculate historical MRR for a specific date
  def calculate_historical_mrr(date)
    subscriptions = base_subscription_query
                     .where(created_at: ..date.end_of_day)
                     .where.not(ended_at: ..date.beginning_of_day)

    calculate_mrr_from_subscriptions(subscriptions, cents: true)
  end

  # Calculate revenue churn rate
  def calculate_revenue_churn_rate(date, period_type)
    case period_type
    when "monthly"
      period_start = date.beginning_of_month
      period_end = date.end_of_month
      previous_period_end = (date - 1.month).end_of_month
    when "daily"
      period_start = date.beginning_of_day
      period_end = date.end_of_day
      previous_period_end = (date - 1.day).end_of_day
    end

    # MRR at start of period
    start_mrr = calculate_historical_mrr(previous_period_end)

    # MRR lost from churned subscriptions
    churned_subscriptions = base_subscription_query
                             .where(ended_at: period_start..period_end)

    churned_mrr = calculate_mrr_from_subscriptions(churned_subscriptions, cents: true)

    return 0.0 if start_mrr == 0
    churned_mrr.to_f / start_mrr
  end


  # Count new customers in period
  def count_new_customers(start_date, end_date)
    base_subscription_query
      .joins(:account)
      .where(created_at: start_date..end_date)
      .distinct
      .count("accounts.id")
  end

  # Count churned customers in period
  def count_churned_customers(start_date, end_date)
    base_subscription_query
      .joins(:account)
      .where(ended_at: start_date..end_date)
      .distinct
      .count("accounts.id")
  end

  # Base query for subscriptions (scoped by account if provided)
  def base_subscription_query
    if account
      account.subscriptions
    else
      Subscription.all
    end
  end

  # Base query for revenue snapshots (scoped by account if provided)
  def revenue_snapshots_query
    if account
      RevenueSnapshot.for_account(account)
    else
      RevenueSnapshot.global
    end
  end

  # Fill missing snapshots with zero values
  def fill_missing_snapshots(snapshots, start_date, end_date, period_type)
    snapshot_hash = snapshots.index_by(&:snapshot_date)
    results = []

    current_date = start_date
    while current_date <= end_date
      if snapshot_hash[current_date]
        results << snapshot_hash[current_date]
      else
        # Create zero-value snapshot for missing date
        results << OpenStruct.new(
          date: current_date,
          period_type: period_type,
          mrr_cents: 0,
          arr_cents: 0,
          active_subscriptions: 0,
          new_subscriptions: 0,
          churned_subscriptions: 0,
          total_customers_count: 0,
          customer_churn_rate: 0.0,
          revenue_churn_rate: 0.0,
          growth_rate: 0.0,
          arpu_cents: 0,
          ltv_cents: 0
        )
      end

      current_date = case period_type
      when "monthly"
                      current_date + 1.month
      when "yearly"
                      current_date + 1.year
      else
                      current_date + 1.day
      end
    end

    results
  end
end
