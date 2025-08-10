require 'prawn'
require 'prawn/table'

# Suppress Prawn international text warning
Prawn::Fonts::AFM.hide_m17n_warning = true

class PdfReportService
  include ActionView::Helpers::NumberHelper
  
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
    @analytics_service = RevenueAnalyticsService.new(
      account: @account,
      start_date: @start_date,
      end_date: @end_date
    )
  end

  def generate_pdf
    unless REPORT_TYPES.include?(@report_type)
      raise ArgumentError, "Invalid report type: #{@report_type}"
    end

    pdf = Prawn::Document.new(page_size: 'LETTER', margin: 40)
    
    # Add company branding
    add_header(pdf)
    
    # Generate report content based on type
    case @report_type
    when 'revenue_report'
      generate_revenue_report(pdf)
    when 'growth_report'
      generate_growth_report(pdf)
    when 'churn_report'
      generate_churn_report(pdf)
    when 'customer_report'
      generate_customer_report(pdf)
    when 'subscription_report'
      generate_subscription_report(pdf)
    when 'executive_summary'
      generate_executive_summary(pdf)
    end

    # Add footer
    add_footer(pdf)
    
    pdf.render
  end

  private

  def add_header(pdf)
    pdf.font "Helvetica", size: 24, style: :bold
    pdf.text "Powernode Analytics Report", align: :center
    pdf.move_down 10
    
    pdf.font "Helvetica", size: 14, style: :normal
    pdf.text report_title, align: :center
    pdf.move_down 5
    
    pdf.font "Helvetica", size: 10, style: :italic
    pdf.text "Generated on #{Date.current.strftime('%B %d, %Y')} | Period: #{@start_date.strftime('%b %Y')} - #{@end_date.strftime('%b %Y')}", align: :center
    
    if @account
      pdf.text "Account: #{@account.name}", align: :center
    else
      pdf.text "Global Analytics", align: :center
    end
    
    pdf.move_down 20
    pdf.stroke_horizontal_rule
    pdf.move_down 20
  end

  def add_footer(pdf)
    pdf.repeat :all do
      pdf.bounding_box [pdf.bounds.left, pdf.bounds.bottom + 25], width: pdf.bounds.width do
        pdf.font "Helvetica", size: 8
        pdf.stroke_horizontal_rule
        pdf.move_down 5
        pdf.text "Powernode Platform | Confidential", align: :left
        pdf.draw_text "Page #{pdf.page_number} of #{pdf.page_count}", at: [pdf.bounds.right - 100, pdf.cursor]
      end
    end
  end

  def generate_revenue_report(pdf)
    pdf.font "Helvetica", size: 16, style: :bold
    pdf.text "Revenue Analysis"
    pdf.move_down 15

    # Get revenue data
    current_mrr = @analytics_service.current_mrr
    mrr_trend = @analytics_service.mrr_trend(months: 12)

    # Current metrics table
    pdf.font "Helvetica", size: 12, style: :bold
    pdf.text "Current Metrics"
    pdf.move_down 10

    latest_snapshot = get_latest_snapshot
    
    metrics_data = [
      ["Metric", "Value"],
      ["Monthly Recurring Revenue (MRR)", number_to_currency(current_mrr)],
      ["Annual Recurring Revenue (ARR)", number_to_currency(current_mrr * 12)],
      ["Active Subscriptions", latest_snapshot&.active_subscriptions || 0],
      ["Total Customers", latest_snapshot&.total_customers_count || 0],
      ["Average Revenue Per User (ARPU)", number_to_currency(latest_snapshot&.arpu&.to_f || 0)],
      ["Growth Rate", "#{(latest_snapshot&.growth_rate_percentage || 0).round(2)}%"]
    ]

    pdf.table(metrics_data, header: true, width: pdf.bounds.width) do
      row(0).font_style = :bold
      row(0).background_color = "E8E8E8"
      columns(0).width = 300
      self.cell_style = { size: 10, padding: 8 }
    end

    pdf.move_down 20

    # Historical trend
    if mrr_trend.any?
      pdf.font "Helvetica", size: 12, style: :bold
      pdf.text "12-Month Revenue Trend"
      pdf.move_down 10

      trend_data = [["Month", "MRR", "ARR", "Active Subs", "New Subs", "Churned"]]
      
      mrr_trend.last(12).each do |snapshot|
        trend_data << [
          snapshot.date.strftime('%b %Y'),
          number_to_currency(snapshot.respond_to?(:mrr_cents) ? snapshot.mrr_cents / 100.0 : 0),
          number_to_currency(snapshot.respond_to?(:arr_cents) ? snapshot.arr_cents / 100.0 : 0),
          snapshot.respond_to?(:active_subscriptions) ? snapshot.active_subscriptions : 0,
          snapshot.respond_to?(:new_subscriptions) ? snapshot.new_subscriptions : 0,
          snapshot.respond_to?(:churned_subscriptions) ? snapshot.churned_subscriptions : 0
        ]
      end

      pdf.table(trend_data, header: true, width: pdf.bounds.width) do
        row(0).font_style = :bold
        row(0).background_color = "E8E8E8"
        self.cell_style = { size: 8, padding: 4 }
      end
    end

    add_insights_section(pdf, generate_revenue_insights(current_mrr, mrr_trend))
  end

  def generate_growth_report(pdf)
    pdf.font "Helvetica", size: 16, style: :bold
    pdf.text "Growth Analysis"
    pdf.move_down 15

    # Get growth data
    monthly_snapshots = get_monthly_snapshots
    growth_data = calculate_growth_data(monthly_snapshots)
    
    if growth_data.any?
      # Growth metrics
      pdf.font "Helvetica", size: 12, style: :bold
      pdf.text "Growth Metrics"
      pdf.move_down 10

      first_mrr = growth_data.first[:mrr]
      last_mrr = growth_data.last[:mrr]
      months = growth_data.length - 1
      
      cmgr = if first_mrr > 0 && months > 0
               ((last_mrr / first_mrr) ** (1.0 / months) - 1) * 100
             else
               0.0
             end

      avg_growth = growth_data.sum { |d| d[:growth_rate] } / growth_data.length

      growth_metrics = [
        ["Metric", "Value"],
        ["Compound Monthly Growth Rate (CMGR)", "#{cmgr.round(2)}%"],
        ["Average Monthly Growth Rate", "#{avg_growth.round(2)}%"],
        ["Period Growth", "#{((last_mrr - first_mrr) / first_mrr * 100).round(2)}%"],
        ["Total Revenue Growth", number_to_currency(last_mrr - first_mrr)]
      ]

      pdf.table(growth_metrics, header: true, width: pdf.bounds.width) do
        row(0).font_style = :bold
        row(0).background_color = "E8E8E8"
        columns(0).width = 300
        self.cell_style = { size: 10, padding: 8 }
      end

      pdf.move_down 20

      # Monthly growth trend
      pdf.font "Helvetica", size: 12, style: :bold
      pdf.text "Monthly Growth Trend"
      pdf.move_down 10

      trend_headers = ["Month", "MRR", "Growth %", "New Revenue", "Churned Revenue"]
      trend_data = [trend_headers]
      
      growth_data.each do |data|
        trend_data << [
          Date.parse(data[:date].to_s).strftime('%b %Y'),
          number_to_currency(data[:mrr]),
          "#{data[:growth_rate]}%",
          number_to_currency(data[:new_revenue]),
          number_to_currency(data[:churned_revenue])
        ]
      end

      pdf.table(trend_data, header: true, width: pdf.bounds.width) do
        row(0).font_style = :bold
        row(0).background_color = "E8E8E8"
        self.cell_style = { size: 9, padding: 5 }
      end
    end

    add_insights_section(pdf, generate_growth_insights(growth_data))
  end

  def generate_churn_report(pdf)
    pdf.font "Helvetica", size: 16, style: :bold
    pdf.text "Churn Analysis"
    pdf.move_down 15

    # Current churn metrics
    current_churn_rate = @analytics_service.calculate_churn_rate(Date.current, "monthly")
    churn_snapshots = get_churn_snapshots

    pdf.font "Helvetica", size: 12, style: :bold
    pdf.text "Current Churn Metrics"
    pdf.move_down 10

    churn_metrics = [
      ["Metric", "Value"],
      ["Current Customer Churn Rate", "#{(current_churn_rate * 100).round(2)}%"],
      ["Customer Retention Rate", "#{((1 - current_churn_rate) * 100).round(2)}%"],
      ["Risk Level", current_churn_rate > 0.05 ? "High" : (current_churn_rate > 0.02 ? "Medium" : "Low")]
    ]

    pdf.table(churn_metrics, header: true, width: pdf.bounds.width) do
      row(0).font_style = :bold
      row(0).background_color = "E8E8E8"
      columns(0).width = 300
      self.cell_style = { size: 10, padding: 8 }
    end

    pdf.move_down 20

    # Churn trend
    if churn_snapshots.any?
      pdf.font "Helvetica", size: 12, style: :bold
      pdf.text "Churn Trend"
      pdf.move_down 10

      churn_data = [["Month", "Customer Churn %", "Revenue Churn %", "Churned Customers", "Churned Subs"]]
      
      churn_snapshots.each do |snapshot|
        churn_data << [
          snapshot.date.strftime('%b %Y'),
          "#{snapshot.customer_churn_rate_percentage.round(2)}%",
          "#{snapshot.revenue_churn_rate_percentage.round(2)}%",
          snapshot.churned_customers_count,
          snapshot.churned_subscriptions
        ]
      end

      pdf.table(churn_data, header: true, width: pdf.bounds.width) do
        row(0).font_style = :bold
        row(0).background_color = "E8E8E8"
        self.cell_style = { size: 9, padding: 5 }
      end
    end

    add_insights_section(pdf, generate_churn_recommendations(current_churn_rate))
  end

  def generate_customer_report(pdf)
    pdf.font "Helvetica", size: 16, style: :bold
    pdf.text "Customer Analysis"
    pdf.move_down 15

    # Current customer metrics
    current_customers = @analytics_service.count_active_customers
    arpu = @analytics_service.calculate_arpu
    ltv = @analytics_service.calculate_ltv

    pdf.font "Helvetica", size: 12, style: :bold
    pdf.text "Customer Metrics"
    pdf.move_down 10

    customer_metrics = [
      ["Metric", "Value"],
      ["Total Active Customers", current_customers],
      ["Average Revenue Per User (ARPU)", number_to_currency(arpu)],
      ["Customer Lifetime Value (LTV)", number_to_currency(ltv)],
      ["LTV:CAC Ratio", "3.0:1"] # Placeholder
    ]

    pdf.table(customer_metrics, header: true, width: pdf.bounds.width) do
      row(0).font_style = :bold
      row(0).background_color = "E8E8E8"
      columns(0).width = 300
      self.cell_style = { size: 10, padding: 8 }
    end

    pdf.move_down 20

    # Customer segmentation by plan
    pdf.font "Helvetica", size: 12, style: :bold
    pdf.text "Customer Segmentation by Plan"
    pdf.move_down 10

    plan_segmentation = generate_customer_segmentation_by_plan
    if plan_segmentation.any?
      plan_data = [["Plan", "Customers", "Percentage"]]
      total_customers = plan_segmentation.sum { |seg| seg[:customers] }
      
      plan_segmentation.each do |segment|
        percentage = total_customers > 0 ? (segment[:customers].to_f / total_customers * 100).round(1) : 0
        plan_data << [segment[:plan], segment[:customers], "#{percentage}%"]
      end

      pdf.table(plan_data, header: true, width: pdf.bounds.width) do
        row(0).font_style = :bold
        row(0).background_color = "E8E8E8"
        self.cell_style = { size: 10, padding: 8 }
      end
    end

    pdf.move_down 15

    # Customer segmentation by tenure
    pdf.font "Helvetica", size: 12, style: :bold
    pdf.text "Customer Segmentation by Tenure"
    pdf.move_down 10

    tenure_segmentation = generate_customer_segmentation_by_tenure
    tenure_data = [["Segment", "Customers", "Percentage"]]
    total_customers = tenure_segmentation.sum { |seg| seg[:customers] }
    
    tenure_segmentation.each do |segment|
      percentage = total_customers > 0 ? (segment[:customers].to_f / total_customers * 100).round(1) : 0
      tenure_data << [segment[:segment], segment[:customers], "#{percentage}%"]
    end

    pdf.table(tenure_data, header: true, width: pdf.bounds.width) do
      row(0).font_style = :bold
      row(0).background_color = "E8E8E8"
      self.cell_style = { size: 10, padding: 8 }
    end
  end

  def generate_subscription_report(pdf)
    pdf.font "Helvetica", size: 16, style: :bold
    pdf.text "Subscription Analysis"
    pdf.move_down 15

    # Subscription metrics
    subscriptions = get_subscription_data
    
    pdf.font "Helvetica", size: 12, style: :bold
    pdf.text "Subscription Overview"
    pdf.move_down 10

    sub_metrics = [
      ["Metric", "Value"],
      ["Total Active Subscriptions", subscriptions[:active_count]],
      ["Trial Subscriptions", subscriptions[:trial_count]],
      ["Canceled Subscriptions", subscriptions[:canceled_count]],
      ["Past Due Subscriptions", subscriptions[:past_due_count]]
    ]

    pdf.table(sub_metrics, header: true, width: pdf.bounds.width) do
      row(0).font_style = :bold
      row(0).background_color = "E8E8E8"
      columns(0).width = 300
      self.cell_style = { size: 10, padding: 8 }
    end

    pdf.move_down 20

    # Subscription by plan
    if subscriptions[:by_plan].any?
      pdf.font "Helvetica", size: 12, style: :bold
      pdf.text "Subscriptions by Plan"
      pdf.move_down 10

      plan_data = [["Plan", "Active", "Trial", "Canceled", "Total"]]
      subscriptions[:by_plan].each do |plan, data|
        plan_data << [plan, data[:active], data[:trial], data[:canceled], data[:total]]
      end

      pdf.table(plan_data, header: true, width: pdf.bounds.width) do
        row(0).font_style = :bold
        row(0).background_color = "E8E8E8"
        self.cell_style = { size: 9, padding: 5 }
      end
    end
  end

  def generate_executive_summary(pdf)
    pdf.font "Helvetica", size: 16, style: :bold
    pdf.text "Executive Summary"
    pdf.move_down 15

    # Key metrics
    current_mrr = @analytics_service.current_mrr
    current_customers = @analytics_service.count_active_customers
    arpu = @analytics_service.calculate_arpu
    current_churn_rate = @analytics_service.calculate_churn_rate(Date.current, "monthly")

    pdf.font "Helvetica", size: 12, style: :bold
    pdf.text "Key Business Metrics"
    pdf.move_down 10

    key_metrics = [
      ["Metric", "Current Value", "Status"],
      ["Monthly Recurring Revenue", number_to_currency(current_mrr), get_trend_indicator(current_mrr, "revenue")],
      ["Total Active Customers", current_customers, get_trend_indicator(current_customers, "customers")],
      ["Average Revenue Per User", number_to_currency(arpu), get_trend_indicator(arpu, "arpu")],
      ["Customer Churn Rate", "#{(current_churn_rate * 100).round(2)}%", get_churn_status(current_churn_rate)]
    ]

    pdf.table(key_metrics, header: true, width: pdf.bounds.width) do
      row(0).font_style = :bold
      row(0).background_color = "E8E8E8"
      self.cell_style = { size: 10, padding: 8 }
    end

    pdf.move_down 20

    # Key insights
    pdf.font "Helvetica", size: 12, style: :bold
    pdf.text "Key Insights & Recommendations"
    pdf.move_down 10

    insights = generate_executive_insights(current_mrr, current_customers, arpu, current_churn_rate)
    insights.each_with_index do |insight, index|
      pdf.font "Helvetica", size: 10, style: :normal
      pdf.text "#{index + 1}. #{insight}", leading: 5
      pdf.move_down 8
    end
  end

  def add_insights_section(pdf, insights)
    pdf.move_down 20
    pdf.font "Helvetica", size: 12, style: :bold
    pdf.text "Insights & Recommendations"
    pdf.move_down 10

    insights.each_with_index do |insight, index|
      pdf.font "Helvetica", size: 10, style: :normal
      pdf.text "• #{insight}", leading: 5
      pdf.move_down 5
    end
  end

  # Helper methods for data retrieval and calculations

  def report_title
    case @report_type
    when 'revenue_report'
      "Revenue Analytics Report"
    when 'growth_report'
      "Growth Analysis Report"
    when 'churn_report'
      "Customer Churn Report"
    when 'customer_report'
      "Customer Analytics Report"
    when 'subscription_report'
      "Subscription Overview Report"
    when 'executive_summary'
      "Executive Summary Report"
    else
      "Analytics Report"
    end
  end

  def get_latest_snapshot
    if @account
      RevenueSnapshot.latest_for_account(@account, "monthly")
    else
      RevenueSnapshot.latest_global("monthly")
    end
  end

  def get_monthly_snapshots
    if @account
      RevenueSnapshot.for_account(@account)
    else
      RevenueSnapshot.global
    end.monthly
       .in_date_range(@start_date, @end_date)
       .order(:date)
  end

  def get_churn_snapshots
    get_monthly_snapshots
  end

  def calculate_growth_data(snapshots)
    growth_data = []
    previous_snapshot = nil

    snapshots.each do |snapshot|
      if previous_snapshot
        month_growth = @analytics_service.calculate_growth_rate(
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

    growth_data
  end

  def get_subscription_data
    base_query = @account ? Subscription.where(account: @account) : Subscription.all
    
    {
      active_count: base_query.active.count,
      trial_count: base_query.trialing.count,
      canceled_count: base_query.where(status: 'canceled').count,
      past_due_count: base_query.past_due.count,
      by_plan: calculate_subscriptions_by_plan(base_query)
    }
  end

  def calculate_subscriptions_by_plan(base_query)
    plans_data = {}
    
    base_query.joins(:plan).group("plans.name").group(:status).count.each do |key, count|
      plan_name, status = key
      plans_data[plan_name] ||= { active: 0, trial: 0, canceled: 0, total: 0 }
      
      case status
      when 'active'
        plans_data[plan_name][:active] = count
      when 'trialing'
        plans_data[plan_name][:trial] = count
      when 'canceled'
        plans_data[plan_name][:canceled] = count
      end
      
      plans_data[plan_name][:total] += count
    end

    plans_data
  end

  def generate_customer_segmentation_by_plan
    base_query = @account ? Subscription.where(account: @account).active : Subscription.active
    
    base_query.joins(:plan)
              .group("plans.name")
              .count
              .map { |plan_name, count| { plan: plan_name, customers: count } }
  end

  def generate_customer_segmentation_by_tenure
    base_query = @account ? Subscription.where(account: @account).active : Subscription.active
    
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

  def generate_revenue_insights(current_mrr, mrr_trend)
    insights = []
    
    if mrr_trend.length >= 2
      recent_growth = ((mrr_trend.last.mrr_cents - mrr_trend[-2].mrr_cents) / mrr_trend[-2].mrr_cents * 100) rescue 0
      if recent_growth > 10
        insights << "Strong revenue growth of #{recent_growth.round(1)}% in the most recent month"
      elsif recent_growth < -5
        insights << "Revenue declined by #{recent_growth.abs.round(1)}% in the most recent month - investigation needed"
      end
    end
    
    insights << "Current MRR of #{number_to_currency(current_mrr)} indicates #{current_mrr > 50000 ? "strong" : "developing"} revenue base"
    insights << "Focus on customer retention and expansion to maintain growth trajectory"
    
    insights
  end

  def generate_growth_insights(growth_data)
    return ["No growth data available for analysis"] if growth_data.empty?
    
    insights = []
    avg_growth = growth_data.sum { |d| d[:growth_rate] } / growth_data.length
    
    if avg_growth > 10
      insights << "Excellent average monthly growth rate of #{avg_growth.round(1)}%"
    elsif avg_growth > 5
      insights << "Good average monthly growth rate of #{avg_growth.round(1)}%"
    elsif avg_growth > 0
      insights << "Modest growth rate of #{avg_growth.round(1)}% - consider growth acceleration strategies"
    else
      insights << "Negative growth trend requires immediate attention - review product-market fit"
    end
    
    insights
  end

  def generate_churn_recommendations(churn_rate)
    case churn_rate
    when 0..0.02
      ["Monitor customer satisfaction regularly", "Continue current retention strategies", "Focus on expansion revenue"]
    when 0.02..0.05
      ["Implement proactive customer success outreach", "Analyze churned customer feedback", "Consider loyalty programs", "Review onboarding process"]
    else
      ["Urgent: Review product-market fit", "Implement immediate retention campaigns", "Conduct exit interviews with churned customers", "Review pricing strategy and value proposition"]
    end
  end

  def generate_executive_insights(mrr, customers, arpu, churn_rate)
    insights = []
    
    # Revenue insights
    if mrr > 100000
      insights << "Strong revenue foundation with MRR exceeding $100k - focus on scaling operations"
    elsif mrr > 50000
      insights << "Growing revenue base - opportunity to accelerate customer acquisition"
    else
      insights << "Early-stage revenue - prioritize product-market fit and customer validation"
    end
    
    # Customer insights  
    if customers > 500
      insights << "Substantial customer base - invest in customer success and retention programs"
    else
      insights << "Building customer base - focus on acquisition channels and customer satisfaction"
    end
    
    # ARPU insights
    if arpu > 200
      insights << "High ARPU indicates strong value delivery - explore expansion opportunities"
    elsif arpu < 50
      insights << "Low ARPU suggests potential for pricing optimization or value-added services"
    end
    
    # Churn insights
    if churn_rate < 0.02
      insights << "Excellent customer retention - leverage satisfied customers for referrals"
    elsif churn_rate > 0.05
      insights << "High churn rate requires immediate attention to retention strategies"
    end
    
    insights
  end

  def get_trend_indicator(current_value, metric_type)
    # This would compare to previous period - simplified for now
    "Stable" # Could be "↗ Growing", "↘ Declining", etc.
  end

  def get_churn_status(churn_rate)
    if churn_rate < 0.02
      "✓ Healthy"
    elsif churn_rate < 0.05
      "⚠ Monitor"
    else
      "⚠ Critical"
    end
  end
end