# Analytics Engineer

**MCP Connection**: `analytics_engineer`
**Primary Role**: Business intelligence specialist implementing analytics, KPIs, and reporting features

## Role & Responsibilities

The Analytics Engineer specializes in implementing comprehensive analytics and business intelligence systems for the Powernode subscription platform. This includes KPI tracking, revenue analytics, user behavior analysis, custom reporting, and data visualization systems.

### Core Areas
- **Business Intelligence**: Revenue metrics, subscription analytics, and growth tracking
- **User Analytics**: Behavior analysis, engagement metrics, and conversion tracking
- **KPI Dashboard Development**: Real-time dashboards with key performance indicators
- **Custom Reporting**: Advanced reporting systems with filtering and exports
- **Data Pipeline Management**: ETL processes and data transformation workflows
- **Predictive Analytics**: Churn prediction, revenue forecasting, and growth modeling
- **A/B Testing Framework**: Experiment tracking and statistical analysis

### Integration Points
- **Platform Architect**: Analytics architecture design and data strategy planning
- **Dashboard Specialist**: Visualization components and interactive charts implementation
- **Backend Specialists**: Data collection, event tracking, and API analytics endpoints
- **Frontend Specialists**: Analytics dashboard interfaces and user interaction tracking
- **Billing Engine Developer**: Revenue analytics and subscription metrics coordination

## Business Intelligence Framework

### Revenue Analytics System
```ruby
# Revenue analytics service
class RevenueAnalyticsService
  include ActiveModel::Model
  
  REVENUE_METRICS = {
    mrr: 'Monthly Recurring Revenue',
    arr: 'Annual Recurring Revenue',
    arpu: 'Average Revenue Per User',
    ltv: 'Customer Lifetime Value',
    churn_rate: 'Customer Churn Rate',
    expansion_revenue: 'Revenue from Upgrades/Expansion',
    contraction_revenue: 'Revenue Lost from Downgrades'
  }.freeze
  
  def self.calculate_revenue_metrics(start_date, end_date)
    metrics = {
      period: { start: start_date, end: end_date },
      mrr: calculate_monthly_recurring_revenue(end_date),
      arr: calculate_annual_recurring_revenue(end_date),
      arpu: calculate_average_revenue_per_user(start_date, end_date),
      ltv: calculate_customer_lifetime_value,
      churn_metrics: calculate_churn_metrics(start_date, end_date),
      growth_metrics: calculate_growth_metrics(start_date, end_date),
      cohort_analysis: generate_cohort_analysis(start_date, end_date)
    }
    
    # Store metrics snapshot
    RevenueMetricsSnapshot.create!(
      metrics_data: metrics,
      snapshot_date: end_date,
      created_at: Time.current
    )
    
    metrics
  end
  
  def self.calculate_monthly_recurring_revenue(as_of_date = Date.current)
    # Calculate MRR from active subscriptions
    active_subscriptions = Subscription.active.where('created_at <= ?', as_of_date.end_of_day)
    
    mrr_data = {
      total_mrr: 0,
      new_business_mrr: 0,
      expansion_mrr: 0,
      contraction_mrr: 0,
      churned_mrr: 0,
      reactivation_mrr: 0
    }
    
    active_subscriptions.includes(:plan).each do |subscription|
      monthly_value = calculate_monthly_value(subscription)
      mrr_data[:total_mrr] += monthly_value
      
      # Categorize MRR type based on subscription history
      mrr_type = determine_mrr_type(subscription, as_of_date)
      mrr_data[mrr_type] += monthly_value
    end
    
    # Add churned MRR from subscriptions that ended this month
    churned_subscriptions = Subscription.where(
      status: ['cancelled', 'expired'],
      cancelled_at: as_of_date.beginning_of_month..as_of_date.end_of_month
    )
    
    churned_subscriptions.each do |subscription|
      monthly_value = calculate_monthly_value(subscription)
      mrr_data[:churned_mrr] += monthly_value
    end
    
    mrr_data
  end
  
  def self.calculate_customer_lifetime_value
    # Calculate average customer lifespan
    cancelled_subscriptions = Subscription.where(status: ['cancelled', 'expired'])
      .where.not(cancelled_at: nil)
    
    avg_lifespan_months = cancelled_subscriptions.average(
      'EXTRACT(EPOCH FROM (cancelled_at - created_at)) / 2592000' # Convert to months
    ) || 12 # Default to 12 months if no data
    
    # Calculate average monthly revenue per customer
    current_arpu = calculate_average_revenue_per_user(1.month.ago, Date.current)
    
    {
      average_lifespan_months: avg_lifespan_months.round(2),
      average_monthly_revenue: current_arpu,
      lifetime_value: (avg_lifespan_months * current_arpu).round(2),
      calculation_date: Date.current
    }
  end
  
  def self.calculate_churn_metrics(start_date, end_date)
    beginning_customers = Subscription.active
      .where('created_at < ?', start_date.beginning_of_day)
      .count
    
    churned_customers = Subscription.where(
      cancelled_at: start_date..end_date,
      status: ['cancelled', 'expired']
    ).count
    
    new_customers = Subscription.where(
      created_at: start_date..end_date,
      status: 'active'
    ).count
    
    # Calculate churn rate
    churn_rate = beginning_customers > 0 ? 
      (churned_customers.to_f / beginning_customers * 100).round(2) : 0
    
    # Calculate net churn (accounting for expansion revenue)
    expansion_revenue = calculate_expansion_revenue(start_date, end_date)
    churned_revenue = calculate_churned_revenue(start_date, end_date)
    
    net_revenue_churn = churned_revenue > 0 ? 
      ((churned_revenue - expansion_revenue) / churned_revenue * 100).round(2) : 0
    
    {
      customer_churn_rate: churn_rate,
      net_revenue_churn_rate: net_revenue_churn,
      beginning_customers: beginning_customers,
      churned_customers: churned_customers,
      new_customers: new_customers,
      expansion_revenue: expansion_revenue,
      churned_revenue: churned_revenue
    }
  end
  
  private
  
  def self.calculate_monthly_value(subscription)
    case subscription.plan.billing_cycle
    when 'monthly'
      subscription.plan.price
    when 'yearly'
      subscription.plan.price / 12.0
    when 'quarterly'
      subscription.plan.price / 3.0
    else
      0
    end
  end
  
  def self.determine_mrr_type(subscription, as_of_date)
    # Check if subscription was created this month
    if subscription.created_at >= as_of_date.beginning_of_month
      return :new_business_mrr
    end
    
    # Check for plan changes this month
    plan_changes = subscription.subscription_changes
      .where(created_at: as_of_date.beginning_of_month..as_of_date.end_of_month)
    
    if plan_changes.exists?
      latest_change = plan_changes.order(:created_at).last
      
      if latest_change.new_plan_price > latest_change.old_plan_price
        return :expansion_mrr
      elsif latest_change.new_plan_price < latest_change.old_plan_price
        return :contraction_mrr
      end
    end
    
    # Check for reactivation
    if subscription.status == 'active' && 
       subscription.reactivated_at && 
       subscription.reactivated_at >= as_of_date.beginning_of_month
      return :reactivation_mrr
    end
    
    # Default to existing business
    :existing_business_mrr
  end
end

# Subscription analytics service
class SubscriptionAnalyticsService
  include ActiveModel::Model
  
  def self.generate_subscription_report(start_date, end_date)
    report_data = {
      period: { start: start_date, end: end_date },
      subscription_metrics: calculate_subscription_metrics(start_date, end_date),
      plan_performance: analyze_plan_performance(start_date, end_date),
      conversion_funnel: analyze_conversion_funnel(start_date, end_date),
      retention_analysis: calculate_retention_metrics(start_date, end_date),
      pricing_analysis: analyze_pricing_effectiveness(start_date, end_date)
    }
    
    # Store report
    SubscriptionAnalyticsReport.create!(
      report_data: report_data,
      report_period_start: start_date,
      report_period_end: end_date,
      generated_at: Time.current
    )
    
    report_data
  end
  
  def self.analyze_plan_performance(start_date, end_date)
    plan_metrics = {}
    
    Plan.active.each do |plan|
      subscriptions = plan.subscriptions.where(created_at: start_date..end_date)
      active_subscriptions = plan.subscriptions.active
      
      plan_metrics[plan.id] = {
        plan_name: plan.name,
        price: plan.price,
        billing_cycle: plan.billing_cycle,
        
        # Subscription metrics
        new_subscriptions: subscriptions.count,
        active_subscriptions: active_subscriptions.count,
        conversion_rate: calculate_plan_conversion_rate(plan, start_date, end_date),
        
        # Revenue metrics
        total_revenue: calculate_plan_revenue(plan, start_date, end_date),
        mrr_contribution: calculate_plan_mrr(plan),
        
        # Performance metrics
        churn_rate: calculate_plan_churn_rate(plan, start_date, end_date),
        upgrade_rate: calculate_plan_upgrade_rate(plan, start_date, end_date),
        average_tenure: calculate_plan_average_tenure(plan)
      }
    end
    
    # Rank plans by performance
    plan_metrics.values.sort_by { |metrics| -metrics[:total_revenue] }
  end
  
  def self.analyze_conversion_funnel(start_date, end_date)
    # Track user journey through subscription funnel
    funnel_data = {
      visitors: track_unique_visitors(start_date, end_date),
      signups: track_user_registrations(start_date, end_date),
      trial_starts: track_trial_starts(start_date, end_date),
      trial_conversions: track_trial_conversions(start_date, end_date),
      subscription_activations: track_subscription_activations(start_date, end_date)
    }
    
    # Calculate conversion rates between stages
    funnel_data[:conversion_rates] = {
      visitor_to_signup: calculate_conversion_rate(funnel_data[:visitors], funnel_data[:signups]),
      signup_to_trial: calculate_conversion_rate(funnel_data[:signups], funnel_data[:trial_starts]),
      trial_to_paid: calculate_conversion_rate(funnel_data[:trial_starts], funnel_data[:trial_conversions]),
      overall_conversion: calculate_conversion_rate(funnel_data[:visitors], funnel_data[:subscription_activations])
    }
    
    funnel_data
  end
  
  private
  
  def self.calculate_plan_conversion_rate(plan, start_date, end_date)
    # Calculate conversion from free trial to paid subscription for this plan
    trial_users = User.joins(:account)
      .where(accounts: { trial_started_at: start_date..end_date })
      .where(trial_plan_id: plan.id)
      .count
    
    converted_users = Subscription.where(
      plan: plan,
      created_at: start_date..end_date,
      status: 'active'
    ).joins(:account)
     .where(accounts: { trial_started_at: start_date..end_date })
     .count
    
    trial_users > 0 ? (converted_users.to_f / trial_users * 100).round(2) : 0
  end
  
  def self.calculate_plan_mrr(plan)
    active_subscriptions = plan.subscriptions.active.count
    monthly_value = case plan.billing_cycle
                   when 'monthly' then plan.price
                   when 'yearly' then plan.price / 12.0
                   when 'quarterly' then plan.price / 3.0
                   else 0
                   end
    
    (active_subscriptions * monthly_value).round(2)
  end
end
```

### User Behavior Analytics
```ruby
# User behavior tracking service
class UserBehaviorAnalyticsService
  include ActiveModel::Model
  
  EVENT_CATEGORIES = {
    authentication: %w[login logout password_reset signup],
    subscription: %w[trial_start subscription_create subscription_cancel subscription_change],
    billing: %w[payment_method_add payment_success payment_failure invoice_view],
    feature_usage: %w[dashboard_view report_generate export_data api_call],
    engagement: %w[help_article_view support_ticket_create feedback_submit]
  }.freeze
  
  def self.track_user_event(user, event_name, properties = {})
    # Validate event
    unless valid_event?(event_name)
      Rails.logger.warn "Invalid analytics event: #{event_name}"
      return
    end
    
    # Create event record
    event_record = UserAnalyticsEvent.create!(
      user_id: user&.id,
      account_id: user&.account_id,
      event_name: event_name,
      event_category: determine_event_category(event_name),
      properties: sanitize_properties(properties),
      session_id: properties[:session_id],
      ip_address: properties[:ip_address],
      user_agent: properties[:user_agent],
      created_at: Time.current
    )
    
    # Update user metrics
    update_user_engagement_metrics(user, event_name)
    
    # Trigger real-time analytics processing
    process_real_time_analytics(event_record)
    
    event_record
  end
  
  def self.analyze_user_engagement(start_date, end_date)
    engagement_data = {
      period: { start: start_date, end: end_date },
      active_users: calculate_active_users(start_date, end_date),
      feature_adoption: analyze_feature_adoption(start_date, end_date),
      user_journey: analyze_user_journeys(start_date, end_date),
      engagement_cohorts: generate_engagement_cohorts(start_date, end_date),
      drop_off_analysis: analyze_drop_off_points(start_date, end_date)
    }
    
    # Store engagement report
    UserEngagementReport.create!(
      report_data: engagement_data,
      report_period_start: start_date,
      report_period_end: end_date,
      generated_at: Time.current
    )
    
    engagement_data
  end
  
  def self.calculate_active_users(start_date, end_date)
    # Daily Active Users (DAU)
    dau_data = (start_date.to_date..end_date.to_date).map do |date|
      active_users = UserAnalyticsEvent.where(
        created_at: date.beginning_of_day..date.end_of_day
      ).distinct.count(:user_id)
      
      { date: date, active_users: active_users }
    end
    
    # Weekly Active Users (WAU)
    wau = UserAnalyticsEvent.where(
      created_at: start_date..end_date
    ).where(
      'created_at >= ?', 7.days.ago
    ).distinct.count(:user_id)
    
    # Monthly Active Users (MAU)
    mau = UserAnalyticsEvent.where(
      created_at: start_date..end_date
    ).where(
      'created_at >= ?', 30.days.ago
    ).distinct.count(:user_id)
    
    {
      daily_active_users: dau_data,
      weekly_active_users: wau,
      monthly_active_users: mau,
      dau_average: dau_data.sum { |d| d[:active_users] } / dau_data.length.to_f,
      stickiness_ratio: wau > 0 ? (dau_data.last[:active_users].to_f / wau * 100).round(2) : 0
    }
  end
  
  def self.analyze_feature_adoption(start_date, end_date)
    feature_events = UserAnalyticsEvent.where(
      created_at: start_date..end_date,
      event_category: 'feature_usage'
    )
    
    feature_metrics = {}
    
    EVENT_CATEGORIES[:feature_usage].each do |feature_event|
      users_using_feature = feature_events.where(event_name: feature_event)
        .distinct.count(:user_id)
      
      total_active_users = calculate_total_active_users(start_date, end_date)
      
      feature_metrics[feature_event] = {
        users_count: users_using_feature,
        adoption_rate: total_active_users > 0 ? 
          (users_using_feature.to_f / total_active_users * 100).round(2) : 0,
        usage_frequency: calculate_feature_usage_frequency(feature_event, start_date, end_date)
      }
    end
    
    # Sort by adoption rate
    feature_metrics.sort_by { |_, metrics| -metrics[:adoption_rate] }.to_h
  end
  
  def self.generate_engagement_cohorts(start_date, end_date)
    cohorts = {}
    
    # Group users by signup month
    (start_date.beginning_of_month.to_date..end_date.beginning_of_month.to_date).each do |month|
      next_month_end = month.end_of_month
      
      # Users who signed up in this month
      cohort_users = User.where(created_at: month.beginning_of_month..next_month_end)
      
      next if cohort_users.empty?
      
      cohort_data = {
        month: month.strftime('%Y-%m'),
        cohort_size: cohort_users.count,
        retention: {}
      }
      
      # Calculate retention for each subsequent month
      12.times do |month_offset|
        retention_month = month + month_offset.months
        break if retention_month > Date.current
        
        active_users = cohort_users.joins(:analytics_events)
          .where(
            user_analytics_events: {
              created_at: retention_month.beginning_of_month..retention_month.end_of_month
            }
          ).distinct.count
        
        retention_rate = (active_users.to_f / cohort_users.count * 100).round(2)
        cohort_data[:retention]["month_#{month_offset}"] = retention_rate
      end
      
      cohorts[month.strftime('%Y-%m')] = cohort_data
    end
    
    cohorts
  end
  
  private
  
  def self.valid_event?(event_name)
    EVENT_CATEGORIES.values.flatten.include?(event_name.to_s)
  end
  
  def self.determine_event_category(event_name)
    EVENT_CATEGORIES.each do |category, events|
      return category.to_s if events.include?(event_name.to_s)
    end
    'other'
  end
  
  def self.sanitize_properties(properties)
    # Remove sensitive data from analytics properties
    sanitized = properties.dup
    
    # Remove sensitive keys
    sensitive_keys = %w[password credit_card ssn api_key token]
    sensitive_keys.each { |key| sanitized.delete(key) }
    
    # Truncate long strings
    sanitized.each do |key, value|
      if value.is_a?(String) && value.length > 500
        sanitized[key] = value[0..499] + '...'
      end
    end
    
    sanitized
  end
  
  def self.update_user_engagement_metrics(user, event_name)
    return unless user
    
    user_metrics = user.user_metrics || {}
    user_metrics['last_activity_at'] = Time.current.iso8601
    user_metrics['total_events'] = (user_metrics['total_events'] || 0) + 1
    user_metrics["#{event_name}_count"] = (user_metrics["#{event_name}_count"] || 0) + 1
    
    user.update_column(:user_metrics, user_metrics)
  end
end

# Predictive analytics service
class PredictiveAnalyticsService
  include ActiveModel::Model
  
  def self.predict_churn_risk
    # Calculate churn risk score for active users
    active_users = User.joins(:account)
      .where(accounts: { status: 'active' })
      .includes(:analytics_events, :subscriptions)
    
    churn_predictions = active_users.map do |user|
      risk_score = calculate_churn_risk_score(user)
      
      {
        user_id: user.id,
        user_email: user.email,
        account_name: user.account.name,
        churn_risk_score: risk_score,
        risk_level: categorize_risk_level(risk_score),
        contributing_factors: identify_churn_factors(user),
        recommended_actions: generate_retention_recommendations(user, risk_score)
      }
    end
    
    # Sort by risk score (highest risk first)
    churn_predictions.sort_by { |prediction| -prediction[:churn_risk_score] }
  end
  
  def self.forecast_revenue(months_ahead = 12)
    # Get historical revenue data
    historical_data = gather_historical_revenue_data(24) # 24 months of history
    
    # Simple linear regression for revenue forecasting
    forecast_data = []
    
    months_ahead.times do |month_offset|
      forecast_month = (Date.current + month_offset.months).beginning_of_month
      
      # Calculate trend-based forecast
      trend_forecast = calculate_trend_forecast(historical_data, month_offset + 1)
      
      # Apply seasonal adjustments
      seasonal_adjustment = calculate_seasonal_adjustment(forecast_month)
      adjusted_forecast = trend_forecast * seasonal_adjustment
      
      # Calculate confidence interval
      confidence_interval = calculate_forecast_confidence(historical_data, month_offset + 1)
      
      forecast_data << {
        month: forecast_month.strftime('%Y-%m'),
        forecasted_revenue: adjusted_forecast.round(2),
        confidence_lower: (adjusted_forecast - confidence_interval).round(2),
        confidence_upper: (adjusted_forecast + confidence_interval).round(2),
        confidence_level: 95
      }
    end
    
    {
      forecast_generated_at: Time.current,
      historical_data_points: historical_data.length,
      forecast_periods: months_ahead,
      forecasts: forecast_data
    }
  end
  
  private
  
  def self.calculate_churn_risk_score(user)
    risk_factors = {
      activity_decline: calculate_activity_decline_factor(user),
      payment_issues: calculate_payment_issues_factor(user),
      support_tickets: calculate_support_ticket_factor(user),
      feature_adoption: calculate_feature_adoption_factor(user),
      tenure: calculate_tenure_factor(user)
    }
    
    # Weighted risk score calculation
    weights = {
      activity_decline: 0.3,
      payment_issues: 0.25,
      support_tickets: 0.15,
      feature_adoption: 0.2,
      tenure: 0.1
    }
    
    risk_score = risk_factors.sum { |factor, value| weights[factor] * value }
    
    # Normalize to 0-100 scale
    (risk_score * 100).round(2)
  end
  
  def self.calculate_activity_decline_factor(user)
    # Compare recent activity to historical average
    recent_activity = user.analytics_events
      .where(created_at: 30.days.ago..Time.current)
      .count
    
    historical_activity = user.analytics_events
      .where(created_at: 90.days.ago..30.days.ago)
      .count / 2.0 # Average over 2 months
    
    return 0.0 if historical_activity == 0
    
    decline_ratio = 1 - (recent_activity / historical_activity)
    [decline_ratio, 1.0].min.clamp(0.0, 1.0)
  end
  
  def self.calculate_payment_issues_factor(user)
    # Check for recent payment failures
    recent_payment_failures = user.account.payments
      .where(created_at: 90.days.ago..Time.current)
      .where(status: 'failed')
      .count
    
    # Risk increases with payment failures
    case recent_payment_failures
    when 0 then 0.0
    when 1 then 0.3
    when 2 then 0.6
    else 1.0
    end
  end
  
  def self.categorize_risk_level(risk_score)
    case risk_score
    when 0..25 then 'low'
    when 26..50 then 'medium'
    when 51..75 then 'high'
    else 'critical'
    end
  end
end
```

## KPI Dashboard System

### Real-time KPI Tracking
```ruby
# KPI dashboard service
class KpiDashboardService
  include ActiveModel::Model
  
  CORE_KPIS = {
    financial: {
      mrr: { name: 'Monthly Recurring Revenue', format: 'currency' },
      arr: { name: 'Annual Recurring Revenue', format: 'currency' },
      revenue_growth: { name: 'Revenue Growth Rate', format: 'percentage' },
      arpu: { name: 'Average Revenue Per User', format: 'currency' }
    },
    growth: {
      new_customers: { name: 'New Customers', format: 'number' },
      customer_growth_rate: { name: 'Customer Growth Rate', format: 'percentage' },
      trial_conversion: { name: 'Trial Conversion Rate', format: 'percentage' },
      viral_coefficient: { name: 'Viral Coefficient', format: 'number' }
    },
    retention: {
      churn_rate: { name: 'Customer Churn Rate', format: 'percentage' },
      retention_rate: { name: 'Customer Retention Rate', format: 'percentage' },
      net_retention: { name: 'Net Revenue Retention', format: 'percentage' },
      customer_lifespan: { name: 'Average Customer Lifespan', format: 'months' }
    },
    engagement: {
      dau: { name: 'Daily Active Users', format: 'number' },
      mau: { name: 'Monthly Active Users', format: 'number' },
      session_duration: { name: 'Average Session Duration', format: 'minutes' },
      feature_adoption: { name: 'Feature Adoption Rate', format: 'percentage' }
    }
  }.freeze
  
  def self.generate_real_time_dashboard
    dashboard_data = {
      last_updated: Time.current,
      kpis: calculate_all_kpis,
      trends: calculate_kpi_trends,
      alerts: check_kpi_alerts,
      goals: track_goal_progress
    }
    
    # Cache dashboard data for performance
    Rails.cache.write('kpi_dashboard_data', dashboard_data, expires_in: 5.minutes)
    
    # Broadcast updates to connected clients
    broadcast_dashboard_update(dashboard_data)
    
    dashboard_data
  end
  
  def self.calculate_all_kpis
    kpi_data = {}
    
    CORE_KPIS.each do |category, kpis|
      kpi_data[category] = {}
      
      kpis.each do |kpi_key, kpi_config|
        begin
          current_value = calculate_kpi_value(kpi_key)
          previous_value = calculate_kpi_value(kpi_key, 1.month.ago)
          
          kpi_data[category][kpi_key] = {
            name: kpi_config[:name],
            current_value: current_value,
            previous_value: previous_value,
            change: calculate_percentage_change(current_value, previous_value),
            trend: determine_trend(current_value, previous_value),
            format: kpi_config[:format],
            status: evaluate_kpi_status(kpi_key, current_value)
          }
        rescue => e
          Rails.logger.error "Failed to calculate KPI #{kpi_key}: #{e.message}"
          
          kpi_data[category][kpi_key] = {
            name: kpi_config[:name],
            error: e.message,
            status: 'error'
          }
        end
      end
    end
    
    kpi_data
  end
  
  def self.calculate_kpi_trends(time_period = 30.days)
    trend_data = {}
    
    # Get daily data points for the specified period
    (time_period.ago.to_date..Date.current).each do |date|
      date_key = date.strftime('%Y-%m-%d')
      trend_data[date_key] = {}
      
      # Calculate key KPIs for each day
      %i[mrr new_customers churn_rate dau].each do |kpi|
        trend_data[date_key][kpi] = calculate_kpi_value(kpi, date.end_of_day)
      end
    end
    
    trend_data
  end
  
  def self.track_goal_progress
    active_goals = KpiGoal.active.where(target_date: Date.current..1.year.from_now)
    
    goal_progress = active_goals.map do |goal|
      current_value = calculate_kpi_value(goal.kpi_name.to_sym)
      progress_percentage = calculate_goal_progress(goal, current_value)
      
      {
        goal_id: goal.id,
        kpi_name: goal.kpi_name,
        target_value: goal.target_value,
        current_value: current_value,
        progress_percentage: progress_percentage,
        target_date: goal.target_date,
        days_remaining: (goal.target_date - Date.current).to_i,
        status: determine_goal_status(goal, progress_percentage),
        projected_completion: project_goal_completion(goal, current_value)
      }
    end
    
    goal_progress.sort_by { |goal| goal[:progress_percentage] }.reverse
  end
  
  private
  
  def self.calculate_kpi_value(kpi_key, as_of_date = Time.current)
    case kpi_key
    when :mrr
      RevenueAnalyticsService.calculate_monthly_recurring_revenue(as_of_date)[:total_mrr]
    when :arr
      RevenueAnalyticsService.calculate_monthly_recurring_revenue(as_of_date)[:total_mrr] * 12
    when :new_customers
      Subscription.where(
        created_at: as_of_date.beginning_of_month..as_of_date.end_of_month,
        status: 'active'
      ).count
    when :churn_rate
      RevenueAnalyticsService.calculate_churn_metrics(
        as_of_date.beginning_of_month, 
        as_of_date.end_of_month
      )[:customer_churn_rate]
    when :dau
      UserAnalyticsEvent.where(
        created_at: as_of_date.beginning_of_day..as_of_date.end_of_day
      ).distinct.count(:user_id)
    when :trial_conversion
      calculate_trial_conversion_rate(as_of_date.beginning_of_month, as_of_date.end_of_month)
    else
      0
    end
  end
  
  def self.calculate_trial_conversion_rate(start_date, end_date)
    trials_started = Account.where(trial_started_at: start_date..end_date).count
    trials_converted = Account.joins(:subscriptions)
      .where(trial_started_at: start_date..end_date)
      .where(subscriptions: { status: 'active' })
      .count
    
    trials_started > 0 ? (trials_converted.to_f / trials_started * 100).round(2) : 0
  end
  
  def self.evaluate_kpi_status(kpi_key, current_value)
    # Get KPI thresholds from configuration
    thresholds = KpiThreshold.find_by(kpi_name: kpi_key.to_s)
    return 'unknown' unless thresholds
    
    case current_value
    when thresholds.critical_min..thresholds.warning_min
      'critical'
    when thresholds.warning_min..thresholds.good_min
      'warning'
    when thresholds.good_min..Float::INFINITY
      'good'
    else
      'critical'
    end
  end
  
  def self.broadcast_dashboard_update(dashboard_data)
    # Broadcast to real-time dashboard subscribers
    ActionCable.server.broadcast('kpi_dashboard', {
      type: 'dashboard_update',
      data: dashboard_data,
      timestamp: Time.current.iso8601
    })
  end
end

# Custom report generator
class CustomReportGenerator
  include ActiveModel::Model
  
  REPORT_TYPES = {
    revenue_analysis: {
      name: 'Revenue Analysis Report',
      description: 'Comprehensive revenue metrics and trends',
      data_sources: %w[subscriptions payments plans]
    },
    customer_analytics: {
      name: 'Customer Analytics Report',
      description: 'Customer behavior and lifecycle analysis',
      data_sources: %w[users analytics_events subscriptions]
    },
    churn_analysis: {
      name: 'Churn Analysis Report',
      description: 'Customer churn patterns and predictions',
      data_sources: %w[subscriptions users analytics_events]
    },
    feature_adoption: {
      name: 'Feature Adoption Report',
      description: 'Feature usage and adoption metrics',
      data_sources: %w[analytics_events users]
    }
  }.freeze
  
  def self.generate_custom_report(report_type, filters = {})
    raise ArgumentError, "Unknown report type: #{report_type}" unless REPORT_TYPES.key?(report_type.to_sym)
    
    report_config = REPORT_TYPES[report_type.to_sym]
    
    report_data = {
      report_type: report_type,
      report_name: report_config[:name],
      description: report_config[:description],
      filters: filters,
      generated_at: Time.current,
      data: generate_report_data(report_type, filters)
    }
    
    # Store report for future reference
    report_record = CustomReport.create!(
      report_type: report_type,
      filters: filters,
      report_data: report_data,
      generated_at: Time.current
    )
    
    # Generate export files if requested
    if filters[:export_format]
      generate_report_export(report_record, filters[:export_format])
    end
    
    report_data
  end
  
  def self.schedule_recurring_report(report_type, schedule, recipients, filters = {})
    RecurringReport.create!(
      report_type: report_type,
      schedule: schedule, # 'daily', 'weekly', 'monthly'
      recipients: recipients,
      filters: filters,
      active: true,
      next_run_at: calculate_next_run_time(schedule),
      created_at: Time.current
    )
  end
  
  private
  
  def self.generate_report_data(report_type, filters)
    start_date = filters[:start_date]&.to_date || 30.days.ago.to_date
    end_date = filters[:end_date]&.to_date || Date.current
    
    case report_type.to_sym
    when :revenue_analysis
      generate_revenue_analysis_data(start_date, end_date, filters)
    when :customer_analytics
      generate_customer_analytics_data(start_date, end_date, filters)
    when :churn_analysis
      generate_churn_analysis_data(start_date, end_date, filters)
    when :feature_adoption
      generate_feature_adoption_data(start_date, end_date, filters)
    else
      {}
    end
  end
  
  def self.generate_revenue_analysis_data(start_date, end_date, filters)
    {
      summary: RevenueAnalyticsService.calculate_revenue_metrics(start_date, end_date),
      trends: calculate_revenue_trends(start_date, end_date),
      plan_performance: SubscriptionAnalyticsService.analyze_plan_performance(start_date, end_date),
      cohort_analysis: RevenueAnalyticsService.generate_cohort_analysis(start_date, end_date),
      forecasting: PredictiveAnalyticsService.forecast_revenue(12)
    }
  end
  
  def self.generate_customer_analytics_data(start_date, end_date, filters)
    {
      customer_metrics: calculate_customer_metrics(start_date, end_date),
      behavioral_analysis: UserBehaviorAnalyticsService.analyze_user_engagement(start_date, end_date),
      segmentation: generate_customer_segmentation(filters),
      lifecycle_analysis: analyze_customer_lifecycle(start_date, end_date),
      satisfaction_metrics: analyze_customer_satisfaction(start_date, end_date)
    }
  end
  
  def self.generate_report_export(report_record, format)
    case format.to_sym
    when :csv
      generate_csv_export(report_record)
    when :excel
      generate_excel_export(report_record)
    when :pdf
      generate_pdf_export(report_record)
    end
  end
end
```

## A/B Testing Framework

### A/B Testing System
```ruby
# A/B testing framework
class AbTestingService
  include ActiveModel::Model
  
  def self.create_experiment(experiment_config)
    experiment = Experiment.create!(
      name: experiment_config[:name],
      description: experiment_config[:description],
      hypothesis: experiment_config[:hypothesis],
      success_metric: experiment_config[:success_metric],
      variants: experiment_config[:variants],
      traffic_allocation: experiment_config[:traffic_allocation] || 50, # 50/50 split
      start_date: experiment_config[:start_date] || Date.current,
      end_date: experiment_config[:end_date],
      status: 'draft',
      confidence_level: experiment_config[:confidence_level] || 95,
      minimum_sample_size: calculate_minimum_sample_size(experiment_config)
    )
    
    # Create variant groups
    experiment_config[:variants].each_with_index do |variant, index|
      ExperimentVariant.create!(
        experiment: experiment,
        name: variant[:name],
        description: variant[:description],
        configuration: variant[:configuration],
        traffic_percentage: variant[:traffic_percentage] || 50,
        is_control: index == 0
      )
    end
    
    experiment
  end
  
  def self.assign_user_to_experiment(user, experiment_name)
    experiment = Experiment.active.find_by(name: experiment_name)
    return nil unless experiment
    
    # Check if user is already assigned
    existing_assignment = ExperimentAssignment.find_by(
      user: user,
      experiment: experiment
    )
    
    return existing_assignment if existing_assignment
    
    # Assign user to variant based on traffic allocation
    assigned_variant = determine_user_variant(user, experiment)
    
    assignment = ExperimentAssignment.create!(
      user: user,
      experiment: experiment,
      experiment_variant: assigned_variant,
      assigned_at: Time.current
    )
    
    # Track assignment event
    UserBehaviorAnalyticsService.track_user_event(user, 'experiment_assigned', {
      experiment_name: experiment.name,
      variant_name: assigned_variant.name,
      assignment_id: assignment.id
    })
    
    assignment
  end
  
  def self.track_conversion(user, experiment_name, conversion_value = nil)
    assignment = ExperimentAssignment.joins(:experiment)
      .where(
        user: user,
        experiments: { name: experiment_name }
      ).first
    
    return unless assignment
    
    # Create conversion record
    ExperimentConversion.create!(
      experiment_assignment: assignment,
      conversion_value: conversion_value,
      converted_at: Time.current
    )
    
    # Track conversion event
    UserBehaviorAnalyticsService.track_user_event(user, 'experiment_conversion', {
      experiment_name: experiment_name,
      variant_name: assignment.experiment_variant.name,
      conversion_value: conversion_value
    })
  end
  
  def self.analyze_experiment_results(experiment_id)
    experiment = Experiment.find(experiment_id)
    
    analysis_results = {
      experiment: experiment.as_json,
      statistical_analysis: perform_statistical_analysis(experiment),
      variant_performance: analyze_variant_performance(experiment),
      confidence_intervals: calculate_confidence_intervals(experiment),
      recommendation: generate_experiment_recommendation(experiment)
    }
    
    # Store analysis results
    ExperimentAnalysis.create!(
      experiment: experiment,
      analysis_results: analysis_results,
      analyzed_at: Time.current
    )
    
    analysis_results
  end
  
  private
  
  def self.determine_user_variant(user, experiment)
    # Use consistent hashing to ensure same user always gets same variant
    hash_value = Digest::MD5.hexdigest("#{user.id}_#{experiment.id}").to_i(16)
    percentage = hash_value % 100
    
    cumulative_percentage = 0
    experiment.experiment_variants.order(:id).each do |variant|
      cumulative_percentage += variant.traffic_percentage
      
      if percentage < cumulative_percentage
        return variant
      end
    end
    
    # Fallback to control variant
    experiment.experiment_variants.find_by(is_control: true)
  end
  
  def self.perform_statistical_analysis(experiment)
    variants = experiment.experiment_variants.includes(:experiment_assignments, :experiment_conversions)
    
    variant_stats = variants.map do |variant|
      assignments = variant.experiment_assignments.count
      conversions = variant.experiment_conversions.count
      conversion_rate = assignments > 0 ? (conversions.to_f / assignments * 100).round(4) : 0
      
      {
        variant_name: variant.name,
        assignments: assignments,
        conversions: conversions,
        conversion_rate: conversion_rate,
        is_control: variant.is_control
      }
    end
    
    # Calculate statistical significance
    control_variant = variant_stats.find { |v| v[:is_control] }
    test_variants = variant_stats.reject { |v| v[:is_control] }
    
    significance_tests = test_variants.map do |test_variant|
      p_value = calculate_p_value(control_variant, test_variant)
      significant = p_value < (1 - experiment.confidence_level / 100.0)
      
      {
        variant_name: test_variant[:variant_name],
        p_value: p_value.round(6),
        is_significant: significant,
        improvement: calculate_improvement(control_variant, test_variant)
      }
    end
    
    {
      variant_statistics: variant_stats,
      significance_tests: significance_tests,
      sample_size_adequate: check_sample_size_adequacy(experiment)
    }
  end
  
  def self.calculate_p_value(control, test)
    # Simplified chi-square test implementation
    # In production, use a proper statistical library
    
    control_successes = control[:conversions]
    control_failures = control[:assignments] - control[:conversions]
    test_successes = test[:conversions]
    test_failures = test[:assignments] - test[:conversions]
    
    return 1.0 if control[:assignments] == 0 || test[:assignments] == 0
    
    # Chi-square calculation
    total = control[:assignments] + test[:assignments]
    expected_control_success = (control_successes + test_successes) * control[:assignments] / total.to_f
    expected_test_success = (control_successes + test_successes) * test[:assignments] / total.to_f
    
    chi_square = ((control_successes - expected_control_success) ** 2 / expected_control_success) +
                 ((test_successes - expected_test_success) ** 2 / expected_test_success)
    
    # Convert chi-square to p-value (simplified)
    # In production, use proper statistical distribution functions
    case chi_square
    when 0..3.84 then 0.05
    when 3.84..6.63 then 0.01
    when 6.63..Float::INFINITY then 0.001
    else 1.0
    end
  end
end
```

## Development Commands

### Analytics Data Management
```bash
# Revenue analytics
cd server && rails runner "RevenueAnalyticsService.calculate_revenue_metrics(30.days.ago, Time.current)"
cd server && rails runner "SubscriptionAnalyticsService.generate_subscription_report(30.days.ago, Time.current)"

# User behavior analytics
cd server && rails runner "UserBehaviorAnalyticsService.analyze_user_engagement(30.days.ago, Time.current)"
cd server && rails runner "PredictiveAnalyticsService.predict_churn_risk"

# KPI dashboard
cd server && rails runner "KpiDashboardService.generate_real_time_dashboard"
cd server && rails runner "CustomReportGenerator.generate_custom_report('revenue_analysis')"

# A/B testing
cd server && rails runner "AbTestingService.analyze_experiment_results(1)"
```

### Data Pipeline Management
```bash
# ETL processes
cd server && rails runner "AnalyticsDataPipeline.run_daily_etl"          # Daily data processing
cd server && rails runner "AnalyticsDataPipeline.rebuild_data_warehouse" # Rebuild data warehouse

# Data validation
cd server && rails runner "DataQualityService.validate_analytics_data"   # Validate data quality
cd server && rails runner "DataQualityService.fix_data_inconsistencies"  # Fix data issues
```

### Report Generation
```bash
# Generate reports
cd server && rails runner "CustomReportGenerator.generate_custom_report('customer_analytics', { start_date: '2024-01-01', end_date: '2024-12-31' })"

# Export reports
cd server && rails runner "ReportExportService.export_report_to_csv(report_id)"
cd server && rails runner "ReportExportService.export_dashboard_to_pdf"

# Schedule recurring reports
cd server && rails runner "CustomReportGenerator.schedule_recurring_report('revenue_analysis', 'weekly', ['team@powernode.com'])"
```

## Integration Points

### Platform Architect Coordination
- **Analytics Architecture**: Design scalable analytics and data processing systems
- **Data Strategy**: Define data collection, storage, and processing strategies
- **Performance Planning**: Ensure analytics systems can handle platform scale
- **Integration Planning**: Coordinate analytics integration across all platform components

### Dashboard Specialist Integration
- **Visualization Components**: Provide data for interactive charts and dashboards
- **Real-time Updates**: Coordinate real-time data updates for dashboard components
- **User Interface**: Design analytics dashboard interfaces and user experiences
- **Performance Optimization**: Optimize data loading and visualization performance

### Backend Specialist Integration
- **Data Collection**: Implement analytics event tracking and data collection APIs
- **API Endpoints**: Create analytics API endpoints for dashboard and reporting systems
- **Data Processing**: Coordinate background processing of analytics data
- **Database Optimization**: Optimize database queries for analytics workloads

### Billing Engine Developer Coordination
- **Revenue Analytics**: Integrate billing data with revenue analytics and reporting
- **Subscription Metrics**: Track subscription lifecycle events and metrics
- **Payment Analytics**: Analyze payment success rates and failure patterns
- **Financial Reporting**: Coordinate financial reporting and revenue recognition

## Quick Reference

### Key Analytics Metrics
```ruby
# Revenue Metrics
MRR (Monthly Recurring Revenue)
ARR (Annual Recurring Revenue)  
ARPU (Average Revenue Per User)
LTV (Customer Lifetime Value)
Churn Rate
Net Revenue Retention

# Growth Metrics
New Customer Acquisition
Trial Conversion Rate
Customer Growth Rate
Viral Coefficient

# Engagement Metrics
DAU/MAU (Daily/Monthly Active Users)
Session Duration
Feature Adoption Rate
User Retention Cohorts
```

### Essential Commands
```bash
# Quick analytics
rails runner "KpiDashboardService.calculate_all_kpis"                    # Get current KPIs
rails runner "RevenueAnalyticsService.calculate_monthly_recurring_revenue" # Calculate MRR
rails runner "UserBehaviorAnalyticsService.calculate_active_users(30.days.ago, Time.current)" # Get active users

# Reporting
rails runner "CustomReportGenerator.generate_custom_report('revenue_analysis')" # Generate revenue report
rails runner "ExperimentAnalysis.analyze_all_active_experiments"          # Analyze A/B tests
```

### Critical Analytics Tasks
- **Daily**: KPI dashboard updates, active user calculations, revenue tracking
- **Weekly**: Cohort analysis, churn prediction, experiment analysis
- **Monthly**: Comprehensive reporting, forecasting, goal tracking
- **Quarterly**: Strategic analytics review, model accuracy assessment

## Quick Reference

### Essential Analytics Commands
```bash
# Data export and analysis - run from $POWERNODE_ROOT/server
cd $POWERNODE_ROOT/server && rails runner "AnalyticsExporter.export_daily_metrics"
cd $POWERNODE_ROOT/server && rails runner "RevenueAnalyzer.generate_monthly_report"
cd $POWERNODE_ROOT/server && rails runner "UserCohortAnalyzer.analyze_retention"

# Dashboard updates
cd $POWERNODE_ROOT/server && rails runner "DashboardMetrics.refresh_all"
cd $POWERNODE_ROOT/server && rails runner "KPICalculator.update_real_time_metrics"

# Data verification
cd $POWERNODE_ROOT/server && rails runner "DataIntegrity.verify_analytics_data"
cd $POWERNODE_ROOT/server && rails runner "MetricsValidator.check_calculation_accuracy"
```

### Key Metrics Categories
- **Revenue Metrics**: MRR, ARR, ARPU, churn rate, expansion revenue
- **User Metrics**: DAU, MAU, retention rate, activation rate, session duration
- **Subscription Metrics**: Conversion rate, upgrade rate, cancellation rate
- **Product Metrics**: Feature adoption, usage frequency, support tickets
- **Business Metrics**: Customer acquisition cost, lifetime value, payback period

### Analytics Tools Integration
```bash
# Mixpanel event tracking
curl -X POST "https://api.mixpanel.com/track" -d 'data={"event":"subscription_created","properties":{"plan":"pro","revenue":99}}'

# Google Analytics reporting
cd $POWERNODE_ROOT/server && rails runner "GoogleAnalyticsReporter.sync_conversion_data"

# Data warehouse sync
cd $POWERNODE_ROOT/server && rails runner "DataWarehouse.sync_daily_metrics"
```

### Emergency Procedures
- **Data Discrepancy**: Verify calculation logic, check data sources, rerun analysis
- **Missing Metrics**: Check data pipeline, verify integrations, run backfill jobs
- **Dashboard Issues**: Clear cache, refresh data connections, verify API keys
- **Report Delays**: Check scheduled jobs, verify data availability, run manual updates

**ALWAYS REFERENCE TODO.md FOR CURRENT TASKS AND PRIORITIES**