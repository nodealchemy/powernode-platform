# frozen_string_literal: true

require "csv"

class Api::V1::AnalyticsController < ApplicationController
  before_action :check_analytics_permission
  before_action :set_date_range, only: [ :revenue, :growth, :churn, :cohorts, :customers ]
  before_action :set_account_scope, only: [ :revenue, :growth, :churn, :cohorts, :customers ]

  # GET /api/v1/analytics/live
  # Returns real-time analytics data for live dashboard updates
  def live
    # Check cache first for performance
    cache_key = generate_live_cache_key(@account_scope&.id)
    cached_data = Rails.cache.read(cache_key)

    if cached_data && params[:force_refresh] != "true"
      Rails.logger.debug "Returning cached live analytics for account: #{@account_scope&.id}"
      render_success(cached_data)
      return
    end

    analytics_service = RevenueAnalyticsService.new(
      account: @account_scope
    )

    # Get current real-time metrics
    current_metrics = {
      mrr: analytics_service.current_mrr,
      arr: analytics_service.current_mrr * 12,
      active_customers: analytics_service.count_active_customers,
      churn_rate: (analytics_service.calculate_churn_rate * 100).round(2),
      arpu: analytics_service.calculate_arpu,
      growth_rate: calculate_current_growth_rate(analytics_service)
    }

    # Get today's activity metrics
    today_activity = {
      new_subscriptions: count_todays_subscriptions(:active),
      cancelled_subscriptions: count_todays_subscriptions(:cancelled),
      payments_processed: count_todays_payments(:successful),
      failed_payments: count_todays_payments(:failed),
      revenue_today: calculate_todays_revenue
    }

    # Get recent trends (last 7 days)
    weekly_trend = calculate_weekly_trend

    data = {
      current_metrics: current_metrics,
      today_activity: today_activity,
      weekly_trend: weekly_trend,
      last_updated: Time.current.iso8601,
      account_id: @account_scope&.id
    }

    # Cache the results for 2 minutes for live data
    Rails.cache.write(cache_key, data, expires_in: 2.minutes)

    render_success(data)

    # Broadcast update to WebSocket channel if requested
    if params[:broadcast] == "true"
      broadcast_analytics_update(data)
    end

    # Trigger analytics notifications check in background
    schedule_analytics_notification_check(data)
  rescue => e
    render_internal_error("Live analytics error", exception: e)
  end

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
        # Handle both hash format (from service) and object format (from model)
        if snapshot.is_a?(Hash)
          {
            date: snapshot[:date],
            mrr: snapshot[:mrr] || 0,
            arr: snapshot[:arr] || 0,
            active_subscriptions: snapshot[:subscriber_count] || snapshot[:active_subscriptions] || 0,
            new_subscriptions: snapshot[:new_subscriptions] || 0,
            churned_subscriptions: snapshot[:churned_subscriptions] || 0
          }
        else
          {
            date: snapshot.date,
            mrr: snapshot.respond_to?(:mrr_cents) ? snapshot.mrr_cents / 100.0 : 0,
            arr: snapshot.respond_to?(:arr_cents) ? snapshot.arr_cents / 100.0 : 0,
            active_subscriptions: snapshot.respond_to?(:active_subscriptions) ? snapshot.active_subscriptions : 0,
            new_subscriptions: snapshot.respond_to?(:new_subscriptions) ? snapshot.new_subscriptions : 0,
            churned_subscriptions: snapshot.respond_to?(:churned_subscriptions) ? snapshot.churned_subscriptions : 0
          }
        end
      end,
      period: {
        start_date: @start_date,
        end_date: @end_date
      }
    }

    render_success(data)
  rescue => e
    render_error(e.message, status: :internal_server_error)
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

    render_success(data)
  rescue => e
    render_error(e.message, status: :internal_server_error)
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

    render_success(data)
  rescue => e
    render_error(e.message, status: :internal_server_error)
  end

  # GET /api/v1/analytics/cohorts
  # Returns cohort retention analysis
  def cohorts
    analytics_service = RevenueAnalyticsService.new(
      account: @account_scope
    )

    cohort_data = analytics_service.cohort_analysis(cohort_months: 12)

    # Transform cohort data for frontend consumption
    # Service returns: { cohort, cohort_date, size, retention (array of rates), current_mrr, churned, active }
    formatted_cohorts = cohort_data.map do |cohort|
      # Get cohort date - handle both string and Date formats
      cohort_date_str = if cohort[:cohort_date].is_a?(String)
                          cohort[:cohort_date][0..6] # Already ISO format, take YYYY-MM
      else
                          cohort[:cohort_date].strftime("%Y-%m")
      end

      # Get cohort size - service uses :size, might also have :cohort_size
      cohort_size = cohort[:size] || cohort[:cohort_size] || 0

      # Get retention data - service returns array of rates, transform to expected format
      retention_array = cohort[:retention] || cohort[:retention_by_month] || []
      retention_rates = if retention_array.is_a?(Array) && retention_array.first.is_a?(Numeric)
                          # Simple array of rates from service
                          retention_array.map.with_index do |rate, index|
                            {
                              month: index,
                              retention_rate: rate.round(2),
                              retained_customers: (cohort_size * rate / 100.0).round
                            }
                          end
      elsif retention_array.is_a?(Array) && retention_array.first.is_a?(Hash)
                          # Already in expected format
                          retention_array.map do |r|
                            {
                              month: r[:month],
                              retention_rate: (r[:retention_rate].is_a?(Numeric) && r[:retention_rate] <= 1 ? r[:retention_rate] * 100 : r[:retention_rate]).round(2),
                              retained_customers: r[:retained_customers] || 0
                            }
                          end
      else
                          []
      end

      {
        cohort_date: cohort_date_str,
        cohort_size: cohort_size,
        retention_rates: retention_rates,
        current_mrr: cohort[:current_mrr] || 0,
        churned: cohort[:churned] || 0,
        active: cohort[:active] || 0
      }
    end

    # Calculate summary safely
    first_month_sum = 0
    six_month_sum = 0
    cohorts_with_first_month = 0
    cohorts_with_six_month = 0

    formatted_cohorts.each do |c|
      if c[:retention_rates].any?
        first_month_sum += c[:retention_rates][0][:retention_rate]
        cohorts_with_first_month += 1
      end
      if c[:retention_rates].length > 5 && c[:retention_rates][5]
        six_month_sum += c[:retention_rates][5][:retention_rate]
        cohorts_with_six_month += 1
      end
    end

    data = {
      cohorts: formatted_cohorts,
      summary: {
        total_cohorts: formatted_cohorts.length,
        average_first_month_retention: cohorts_with_first_month > 0 ? (first_month_sum / cohorts_with_first_month).round(2) : 0,
        average_six_month_retention: cohorts_with_six_month > 0 ? (six_month_sum / cohorts_with_six_month).round(2) : 0
      }
    }

    render_success(data)
  rescue => e
    render_error(e.message, status: :internal_server_error)
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

    render_success(data)
  rescue => e
    render_error(e.message, status: :internal_server_error)
  end

  # GET/POST /api/v1/analytics/export
  # Export analytics data in various formats
  def export
    format = params[:format] || "csv"
    report_type = params[:report_type] || "revenue"

    unless can_export_analytics?
      render_error("Export permission required", status: :forbidden)
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
          render_success(
            data: {
              csv_data: csv_data,
              filename: "#{report_type}_analytics_#{Date.current.strftime('%Y%m%d')}.csv"
            }
          )
        }
      end
    when "pdf"
      pdf_data = PdfReportService.new(
        report_type: "#{report_type}_report",
        account: @account_scope,
        start_date: @start_date,
        end_date: @end_date,
        user: current_user
      ).generate_pdf

      respond_to do |format|
        format.pdf {
          send_data pdf_data,
          filename: "#{report_type}_report_#{Date.current.strftime('%Y%m%d')}.pdf",
          type: "application/pdf"
        }
        format.json {
          render_success(
            data: {
              pdf_data: Base64.encode64(pdf_data),
              filename: "#{report_type}_report_#{Date.current.strftime('%Y%m%d')}.pdf",
              content_type: "application/pdf"
            }
          )
        }
      end
    else
      render_error("Unsupported export format", status: :bad_request)
    end
  rescue => e
    render_error(e.message, status: :internal_server_error)
  end

  private

  def check_analytics_permission
    unless current_user.has_permission?("ai.analytics.read") || current_user.has_permission?("admin.access")
      render_error("Analytics permission required", status: :forbidden)
    end
  end

  def can_export_analytics?
    current_user.has_permission?("ai.analytics.export") || current_user.has_permission?("admin.access")
  end

  def set_date_range
    @start_date = params[:start_date]&.to_date || 12.months.ago.to_date.beginning_of_month
    @end_date = params[:end_date]&.to_date || Date.current.end_of_month

    # Validate date range
    if @start_date > @end_date
      render_error("Start date must be before end date", status: :bad_request)
      return
    end

    # Limit to reasonable range (2 years max)
    if @end_date - @start_date > 2.years
      render_error("Date range too large (max 2 years)", status: :bad_request)
      nil
    end
  end

  def set_account_scope
    # If user has admin access, allow querying all accounts or specific accounts
    if current_user.has_permission?("admin.access") && params[:account_id].blank?
      @account_scope = nil # Global analytics
    elsif params[:account_id].present? && current_user.has_permission?("admin.access")
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

  # Live analytics helper methods
  def calculate_current_growth_rate(analytics_service)
    # Get current month and previous month MRR for growth calculation
    current_month = Date.current.beginning_of_month
    previous_month = 1.month.ago.beginning_of_month

    current_snapshot = if @account_scope
                        RevenueSnapshot.latest_for_account(@account_scope, "monthly")
    else
                        RevenueSnapshot.latest_global("monthly")
    end

    previous_snapshot = if @account_scope
                         RevenueSnapshot.for_account(@account_scope).monthly
                           .where(date: previous_month).first
    else
                         RevenueSnapshot.global.monthly
                           .where(date: previous_month).first
    end

    if current_snapshot && previous_snapshot && previous_snapshot.mrr_cents > 0
      growth_rate = ((current_snapshot.mrr_cents.to_f - previous_snapshot.mrr_cents.to_f) / previous_snapshot.mrr_cents.to_f) * 100
      growth_rate.round(2)
    else
      0.0
    end
  end

  def count_todays_subscriptions(status)
    base_query = @account_scope ? @account_scope.subscriptions : Subscription.all
    base_query.where(status: status)
              .where(created_at: Date.current.beginning_of_day..Date.current.end_of_day)
              .count
  end

  def count_todays_payments(status)
    base_query = if @account_scope
                  Payment.joins(subscription: :account).where(subscriptions: { accounts: { id: @account_scope.id } })
    else
                  Payment.all
    end
    base_query.where(status: status)
              .where(created_at: Date.current.beginning_of_day..Date.current.end_of_day)
              .count
  end

  def calculate_todays_revenue
    base_query = if @account_scope
                  Payment.joins(subscription: :account).where(subscriptions: { accounts: { id: @account_scope.id } })
    else
                  Payment.all
    end
    successful_payments = base_query.where(status: :successful)
                                   .where(created_at: Date.current.beginning_of_day..Date.current.end_of_day)

    total_cents = successful_payments.sum(:amount_cents)
    (total_cents / 100.0).round(2)
  end

  def calculate_weekly_trend
    # Get last 7 days of key metrics
    trend_data = []

    (0..6).each do |days_ago|
      date = days_ago.days.ago.to_date

      # Count subscriptions for this day
      base_subscriptions = @account_scope ? @account_scope.subscriptions : Subscription.all
      new_subs = base_subscriptions.where(created_at: date.beginning_of_day..date.end_of_day).count

      # Count payments for this day
      base_payments = if @account_scope
                       Payment.joins(subscription: :account).where(subscriptions: { accounts: { id: @account_scope.id } })
      else
                       Payment.all
      end
      payments = base_payments.where(status: :successful)
                             .where(created_at: date.beginning_of_day..date.end_of_day)

      revenue = (payments.sum(:amount_cents) / 100.0).round(2)

      trend_data.unshift({
        date: date.iso8601,
        new_subscriptions: new_subs,
        revenue: revenue,
        payments_count: payments.count
      })
    end

    trend_data
  end

  def broadcast_analytics_update(data)
    # Broadcast to appropriate channel
    if @account_scope
      ActionCable.server.broadcast "analytics_account_#{@account_scope.id}", {
        type: "analytics_update",
        data: data
      }
    else
      ActionCable.server.broadcast "analytics_global", {
        type: "analytics_update",
        data: data
      }
    end
  rescue => e
    Rails.logger.error "Failed to broadcast analytics update: #{e.message}"
  end

  def generate_live_cache_key(account_id)
    timestamp = Time.current.strftime("%Y%m%d%H%M") # Changes every minute
    if account_id
      "analytics:live:account:#{account_id}:#{timestamp}"
    else
      "analytics:live:global:#{timestamp}"
    end
  end

  def schedule_analytics_notification_check(data)
    # Schedule background job to check notifications
    # This uses the worker service pattern
    Rails.logger.debug "Scheduling analytics notification check for account: #{@account_scope&.id}"

    # Queue the notification check job
    begin
      # This would be handled by the worker service
      WorkerJobService.enqueue_job(
        "analytics_notification_check",
        account_id: @account_scope&.id,
        metrics_data: data
      )
    rescue => e
      Rails.logger.warn "Failed to schedule analytics notification check: #{e.message}"
      # Don't fail the main request if background job scheduling fails
    end
  end
end
