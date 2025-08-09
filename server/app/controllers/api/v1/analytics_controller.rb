require "csv"

class Api::V1::AnalyticsController < ApplicationController
  before_action :check_analytics_permission
  before_action :set_date_range, only: [ :revenue, :growth, :churn, :cohorts, :customers ]
  before_action :set_account_scope, only: [ :revenue, :growth, :churn, :cohorts, :customers ]

  # GET /api/v1/analytics/revenue
  # Returns MRR/ARR overview with historical data
  def revenue
    analytics_service = RevenueAnalyticsService.new(
      account: @account_scope,
      start_date: @start_date,
      end_date: @end_date
    )

    current_mrr = analytics_service.current_mrr
    mrr_trend = analytics_service.mrr_trend(months: params[:months]&.to_i || 12)

    latest_snapshot = if @account_scope
                       RevenueSnapshot.latest_for_account(@account_scope, "monthly")
    else
                       RevenueSnapshot.latest_global("monthly")
    end

    data = {
      current_metrics: {
        mrr: current_mrr,
        arr: current_mrr * 12,
        active_subscriptions: latest_snapshot&.active_subscriptions || 0,
        total_customers: latest_snapshot&.total_customers_count || 0,
        arpu: latest_snapshot&.arpu&.to_f || 0,
        growth_rate: latest_snapshot&.growth_rate_percentage || 0
      },
      historical_data: mrr_trend.map do |snapshot|
        {
          date: snapshot.date,
          mrr: snapshot.respond_to?(:mrr_cents) ? snapshot.mrr_cents / 100.0 : 0,
          arr: snapshot.respond_to?(:arr_cents) ? snapshot.arr_cents / 100.0 : 0,
          active_subscriptions: snapshot.respond_to?(:active_subscriptions) ? snapshot.active_subscriptions : 0,
          new_subscriptions: snapshot.respond_to?(:new_subscriptions) ? snapshot.new_subscriptions : 0,
          churned_subscriptions: snapshot.respond_to?(:churned_subscriptions) ? snapshot.churned_subscriptions : 0
        }
      end,
      period: {
        start_date: @start_date,
        end_date: @end_date
      }
    }

    render json: { success: true, data: data }
  rescue => e
    render json: { success: false, error: e.message }, status: 500
  end

  # GET /api/v1/analytics/growth
  # Returns growth metrics and forecasting
  def growth
    analytics_service = RevenueAnalyticsService.new(
      account: @account_scope,
      start_date: @start_date,
      end_date: @end_date
    )

    # Get monthly snapshots for growth analysis
    monthly_snapshots = if @account_scope
                         RevenueSnapshot.for_account(@account_scope)
    else
                         RevenueSnapshot.global
    end.monthly
                          .in_date_range(@start_date, @end_date)
                          .order(:date)

    growth_data = []
    previous_snapshot = nil

    monthly_snapshots.each do |snapshot|
      if previous_snapshot
        month_growth = analytics_service.calculate_growth_rate(
          snapshot.mrr_cents,
          previous_snapshot.mrr_cents
        )
      else
        month_growth = 0.0
      end

      growth_data << {
        date: snapshot.date,
        mrr: snapshot.mrr_cents / 100.0,
        growth_rate: (month_growth * 100).round(2),
        new_revenue: (snapshot.new_subscriptions * (snapshot.arpu_cents / 100.0)).round(2),
        churned_revenue: (snapshot.churned_subscriptions * (snapshot.arpu_cents / 100.0)).round(2)
      }

      previous_snapshot = snapshot
    end

    # Calculate compound monthly growth rate
    if growth_data.length > 1
      first_mrr = growth_data.first[:mrr]
      last_mrr = growth_data.last[:mrr]
      months = growth_data.length - 1

      if first_mrr > 0 && months > 0
        cmgr = ((last_mrr / first_mrr) ** (1.0 / months) - 1) * 100
      else
        cmgr = 0.0
      end
    else
      cmgr = 0.0
    end

    data = {
      compound_monthly_growth_rate: cmgr.round(2),
      monthly_growth_data: growth_data,
      forecasting: {
        next_month_projection: growth_data.any? ? (growth_data.last[:mrr] * 1.1).round(2) : 0,
        confidence_interval: "±15%"
      },
      period: {
        start_date: @start_date,
        end_date: @end_date
      }
    }

    render json: { success: true, data: data }
  rescue => e
    render json: { success: false, error: e.message }, status: 500
  end

  # GET /api/v1/analytics/churn
  # Returns comprehensive churn analysis
  def churn
    analytics_service = RevenueAnalyticsService.new(
      account: @account_scope,
      start_date: @start_date,
      end_date: @end_date
    )

    # Get churn data from snapshots
    churn_snapshots = if @account_scope
                       RevenueSnapshot.for_account(@account_scope)
    else
                       RevenueSnapshot.global
    end.monthly
                        .in_date_range(@start_date, @end_date)
                        .order(:date)

    churn_trend = churn_snapshots.map do |snapshot|
      {
        date: snapshot.date,
        customer_churn_rate: snapshot.customer_churn_rate_percentage,
        revenue_churn_rate: snapshot.revenue_churn_rate_percentage,
        churned_customers: snapshot.churned_customers_count,
        churned_subscriptions: snapshot.churned_subscriptions
      }
    end

    # Calculate average churn rates
    if churn_trend.any?
      avg_customer_churn = churn_trend.sum { |data| data[:customer_churn_rate] } / churn_trend.length
      avg_revenue_churn = churn_trend.sum { |data| data[:revenue_churn_rate] } / churn_trend.length
    else
      avg_customer_churn = 0.0
      avg_revenue_churn = 0.0
    end

    # Current month churn rate
    current_churn_rate = analytics_service.calculate_churn_rate(Date.current, "monthly")

    data = {
      current_metrics: {
        customer_churn_rate: (current_churn_rate * 100).round(2),
        average_customer_churn_rate: avg_customer_churn.round(2),
        average_revenue_churn_rate: avg_revenue_churn.round(2),
        customer_retention_rate: ((1 - current_churn_rate) * 100).round(2)
      },
      churn_trend: churn_trend,
      insights: {
        churn_risk_level: current_churn_rate > 0.05 ? "high" : (current_churn_rate > 0.02 ? "medium" : "low"),
        recommended_actions: generate_churn_recommendations(current_churn_rate)
      },
      period: {
        start_date: @start_date,
        end_date: @end_date
      }
    }

    render json: { success: true, data: data }
  rescue => e
    render json: { success: false, error: e.message }, status: 500
  end

  # GET /api/v1/analytics/cohorts
  # Returns cohort retention analysis
  def cohorts
    analytics_service = RevenueAnalyticsService.new(
      account: @account_scope
    )

    cohort_data = analytics_service.cohort_analysis(cohort_months: 12)

    # Transform cohort data for frontend consumption
    formatted_cohorts = cohort_data.map do |cohort|
      {
        cohort_date: cohort[:cohort_date].strftime("%Y-%m"),
        cohort_size: cohort[:cohort_size],
        retention_rates: cohort[:retention_by_month].map do |retention|
          {
            month: retention[:month],
            retention_rate: (retention[:retention_rate] * 100).round(2),
            retained_customers: retention[:retained_customers]
          }
        end
      }
    end

    data = {
      cohorts: formatted_cohorts,
      summary: {
        total_cohorts: formatted_cohorts.length,
        average_first_month_retention: formatted_cohorts.any? ?
          (formatted_cohorts.sum { |c| c[:retention_rates][0][:retention_rate] } / formatted_cohorts.length).round(2) : 0,
        average_six_month_retention: formatted_cohorts.any? ?
          (formatted_cohorts.sum { |c| c[:retention_rates][5] ? c[:retention_rates][5][:retention_rate] : 0 } / formatted_cohorts.length).round(2) : 0
      }
    }

    render json: { success: true, data: data }
  rescue => e
    render json: { success: false, error: e.message }, status: 500
  end

  # GET /api/v1/analytics/customers
  # Returns customer metrics and segmentation
  def customers
    analytics_service = RevenueAnalyticsService.new(
      account: @account_scope,
      start_date: @start_date,
      end_date: @end_date
    )

    # Current customer metrics
    current_customers = analytics_service.count_active_customers
    arpu = analytics_service.calculate_arpu
    ltv = analytics_service.calculate_ltv

    # Customer growth trend
    customer_snapshots = if @account_scope
                          RevenueSnapshot.for_account(@account_scope)
    else
                          RevenueSnapshot.global
    end.monthly
                           .in_date_range(@start_date, @end_date)
                           .order(:date)

    customer_trend = customer_snapshots.map do |snapshot|
      {
        date: snapshot.date,
        total_customers: snapshot.total_customers_count,
        new_customers: snapshot.new_customers_count,
        churned_customers: snapshot.churned_customers_count,
        net_growth: snapshot.new_customers_count - snapshot.churned_customers_count,
        arpu: snapshot.arpu_cents / 100.0,
        ltv: snapshot.ltv_cents / 100.0
      }
    end

    data = {
      current_metrics: {
        total_customers: current_customers,
        arpu: arpu.round(2),
        ltv: ltv.round(2),
        ltv_to_cac_ratio: 3.0 # Placeholder - would need CAC data
      },
      customer_growth_trend: customer_trend,
      segmentation: {
        by_plan: generate_customer_segmentation_by_plan,
        by_tenure: generate_customer_segmentation_by_tenure
      },
      period: {
        start_date: @start_date,
        end_date: @end_date
      }
    }

    render json: { success: true, data: data }
  rescue => e
    render json: { success: false, error: e.message }, status: 500
  end

  # GET/POST /api/v1/analytics/export
  # Export analytics data in various formats
  def export
    format = params[:format] || "csv"
    report_type = params[:report_type] || "revenue"

    unless can_export_analytics?
      render json: { success: false, error: "Export permission required" }, status: 403
      return
    end

    analytics_service = RevenueAnalyticsService.new(
      account: @account_scope,
      start_date: @start_date,
      end_date: @end_date
    )

    case format.downcase
    when "csv"
      csv_data = analytics_service.export_revenue_data_csv("monthly")

      respond_to do |format|
        format.csv {
          send_data csv_data,
          filename: "#{report_type}_analytics_#{Date.current.strftime('%Y%m%d')}.csv",
          type: "text/csv"
        }
        format.json {
          render json: {
            success: true,
            data: csv_data,
            filename: "#{report_type}_analytics_#{Date.current.strftime('%Y%m%d')}.csv"
          }
        }
      end
    when "pdf"
      # PDF generation would be implemented here
      render json: { success: false, error: "PDF export not yet implemented" }, status: 501
    else
      render json: { success: false, error: "Unsupported export format" }, status: 400
    end
  rescue => e
    render json: { success: false, error: e.message }, status: 500
  end

  private

  def check_analytics_permission
    unless current_user.has_permission?("analytics.read") || current_user.has_permission?("analytics.global")
      render json: { success: false, error: "Analytics permission required" }, status: 403
    end
  end

  def can_export_analytics?
    current_user.has_permission?("analytics.export") || current_user.has_permission?("analytics.global")
  end

  def set_date_range
    @start_date = params[:start_date]&.to_date || 12.months.ago.to_date.beginning_of_month
    @end_date = params[:end_date]&.to_date || Date.current.end_of_month

    # Validate date range
    if @start_date > @end_date
      render json: { success: false, error: "Start date must be before end date" }, status: 400
      return
    end

    # Limit to reasonable range (2 years max)
    if @end_date - @start_date > 2.years
      render json: { success: false, error: "Date range too large (max 2 years)" }, status: 400
      nil
    end
  end

  def set_account_scope
    # If user has global analytics permission, allow querying all accounts
    if current_user.has_permission?("analytics.global") && params[:account_id].blank?
      @account_scope = nil # Global analytics
    elsif params[:account_id].present? && current_user.has_permission?("analytics.global")
      @account_scope = Account.find(params[:account_id])
    else
      # Regular users can only see their own account's analytics
      @account_scope = current_user.account
    end
  end

  def generate_churn_recommendations(churn_rate)
    case churn_rate
    when 0..0.02
      [ "Monitor customer satisfaction regularly", "Continue current retention strategies" ]
    when 0.02..0.05
      [ "Implement proactive customer success outreach", "Analyze churned customer feedback", "Consider loyalty programs" ]
    else
      [ "Urgent: Review product-market fit", "Implement immediate retention campaigns", "Conduct exit interviews", "Review pricing strategy" ]
    end
  end

  def generate_customer_segmentation_by_plan
    # This would analyze subscription data by plan
    base_query = @account_scope ? @account_scope.subscriptions.active : Subscription.active

    base_query.joins(:plan)
              .group("plans.name")
              .count
              .map { |plan_name, count| { plan: plan_name, customers: count } }
  end

  def generate_customer_segmentation_by_tenure
    # Segment customers by how long they've been subscribed
    base_query = @account_scope ? @account_scope.subscriptions.active : Subscription.active

    segments = {
      "New (0-3 months)" => 0,
      "Growing (3-12 months)" => 0,
      "Mature (12+ months)" => 0
    }

    base_query.each do |subscription|
      tenure_months = ((Date.current - subscription.created_at.to_date) / 30.days).to_i

      case tenure_months
      when 0..3
        segments["New (0-3 months)"] += 1
      when 3..12
        segments["Growing (3-12 months)"] += 1
      else
        segments["Mature (12+ months)"] += 1
      end
    end

    segments.map { |segment, count| { segment: segment, customers: count } }
  end
end
