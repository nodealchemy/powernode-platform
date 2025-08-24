# frozen_string_literal: true

class AnalyticsNotificationService < BaseWorkerService
  # Notification thresholds and configurations
  NOTIFICATION_THRESHOLDS = {
    high_churn_rate: 0.10,        # 10% monthly churn
    critical_churn_rate: 0.20,    # 20% monthly churn
    negative_growth: -0.05,       # -5% growth
    high_payment_failures: 0.15,  # 15% payment failure rate
    revenue_decline: -0.10,       # 10% revenue decline
    low_conversion: 0.02          # 2% conversion rate
  }.freeze

  def initialize
    super
    @notification_cache = {}
  end

  # Main method to check analytics and send notifications
  def check_and_notify(account_id: nil)
    begin
      metrics = fetch_live_metrics(account_id)
      return unless metrics

      # Check various thresholds and send notifications
      check_churn_thresholds(metrics, account_id)
      check_growth_thresholds(metrics, account_id)
      check_payment_failure_thresholds(metrics, account_id)
      check_revenue_decline_thresholds(metrics, account_id)
      
      # Send daily/weekly summaries if applicable
      send_periodic_summaries(metrics, account_id)
      
      logger.info "Analytics notifications checked for account: #{account_id || 'global'}"
      
    rescue => e
      logger.error "Analytics notification check failed for account #{account_id}: #{e.message}"
      handle_service_error(e, account_id: account_id)
    end
  end

  # Send real-time alert notifications
  def send_real_time_alert(alert_type:, message:, severity: 'medium', account_id: nil, data: {})
    begin
      # Prevent spam notifications with rate limiting
      return if notification_recently_sent?(alert_type, account_id)
      
      notification_data = {
        type: 'analytics_alert',
        alert_type: alert_type,
        message: message,
        severity: severity, # low, medium, high, critical
        account_id: account_id,
        data: data,
        timestamp: Time.now.iso8601
      }
      
      # Send via multiple channels based on severity
      send_notification_channels(notification_data, severity)
      
      # Cache to prevent duplicate notifications
      cache_notification_sent(alert_type, account_id)
      
      logger.info "Real-time analytics alert sent: #{alert_type} for account #{account_id}"
      
    rescue => e
      logger.error "Failed to send real-time analytics alert: #{e.message}"
    end
  end

  # Send analytics insights and recommendations
  def send_insights_notification(insights:, account_id: nil)
    begin
      notification_data = {
        type: 'analytics_insights',
        insights: insights,
        account_id: account_id,
        timestamp: Time.now.iso8601
      }
      
      # Send insights via email and in-app notifications
      send_insights_email(notification_data)
      send_in_app_notification(notification_data)
      
      logger.info "Analytics insights sent for account: #{account_id || 'global'}"
      
    rescue => e
      logger.error "Failed to send analytics insights: #{e.message}"
    end
  end

  private

  def fetch_live_metrics(account_id)
    response = api_client.get("/api/v1/analytics/live", { account_id: account_id })
    
    if response.success?
      response.data
    else
      logger.warn "Failed to fetch live metrics for notifications: #{response.error}"
      nil
    end
  end

  def check_churn_thresholds(metrics, account_id)
    churn_rate = metrics.dig('current_metrics', 'churn_rate') || 0
    churn_rate_decimal = churn_rate / 100.0
    
    if churn_rate_decimal >= NOTIFICATION_THRESHOLDS[:critical_churn_rate]
      send_real_time_alert(
        alert_type: 'critical_churn_rate',
        message: "Critical churn rate detected: #{churn_rate.round(1)}%. Immediate action required.",
        severity: 'critical',
        account_id: account_id,
        data: { churn_rate: churn_rate }
      )
    elsif churn_rate_decimal >= NOTIFICATION_THRESHOLDS[:high_churn_rate]
      send_real_time_alert(
        alert_type: 'high_churn_rate',
        message: "High churn rate detected: #{churn_rate.round(1)}%. Consider retention strategies.",
        severity: 'high',
        account_id: account_id,
        data: { churn_rate: churn_rate }
      )
    end
  end

  def check_growth_thresholds(metrics, account_id)
    growth_rate = metrics.dig('current_metrics', 'growth_rate') || 0
    growth_rate_decimal = growth_rate / 100.0
    
    if growth_rate_decimal <= NOTIFICATION_THRESHOLDS[:negative_growth]
      send_real_time_alert(
        alert_type: 'negative_growth',
        message: "Negative growth detected: #{growth_rate.round(1)}%. Review growth strategies.",
        severity: 'high',
        account_id: account_id,
        data: { growth_rate: growth_rate }
      )
    end
  end

  def check_payment_failure_thresholds(metrics, account_id)
    today_activity = metrics['today_activity'] || {}
    failed_payments = today_activity['failed_payments'] || 0
    total_payments = (today_activity['payments_processed'] || 0) + failed_payments
    
    if total_payments > 0
      failure_rate = failed_payments.to_f / total_payments
      
      if failure_rate >= NOTIFICATION_THRESHOLDS[:high_payment_failures]
        send_real_time_alert(
          alert_type: 'high_payment_failures',
          message: "High payment failure rate today: #{(failure_rate * 100).round(1)}%. Check payment systems.",
          severity: 'high',
          account_id: account_id,
          data: { 
            failure_rate: (failure_rate * 100).round(2),
            failed_payments: failed_payments,
            total_payments: total_payments
          }
        )
      end
    end
  end

  def check_revenue_decline_thresholds(metrics, account_id)
    weekly_trend = metrics['weekly_trend'] || []
    return if weekly_trend.length < 7
    
    # Compare last 3 days average with previous 3 days
    recent_revenue = weekly_trend.last(3).sum { |day| day['revenue'] || 0 } / 3.0
    previous_revenue = weekly_trend[-6..-4].sum { |day| day['revenue'] || 0 } / 3.0
    
    if previous_revenue > 0
      decline_rate = (recent_revenue - previous_revenue) / previous_revenue
      
      if decline_rate <= NOTIFICATION_THRESHOLDS[:revenue_decline]
        send_real_time_alert(
          alert_type: 'revenue_decline',
          message: "Revenue decline detected: #{(decline_rate * 100).round(1)}% over last 3 days.",
          severity: 'medium',
          account_id: account_id,
          data: {
            decline_rate: (decline_rate * 100).round(2),
            recent_revenue: recent_revenue.round(2),
            previous_revenue: previous_revenue.round(2)
          }
        )
      end
    end
  end

  def send_periodic_summaries(metrics, account_id)
    # Send daily summary at end of day
    if end_of_day? && !daily_summary_sent?(account_id)
      send_daily_summary(metrics, account_id)
    end
    
    # Send weekly summary on Monday mornings
    if monday_morning? && !weekly_summary_sent?(account_id)
      send_weekly_summary(metrics, account_id)
    end
  end

  def send_notification_channels(notification_data, severity)
    case severity
    when 'critical'
      # Send via all channels for critical alerts
      send_email_notification(notification_data)
      send_slack_notification(notification_data)
      send_in_app_notification(notification_data)
      send_push_notification(notification_data)
    when 'high'
      # Send via email and in-app for high severity
      send_email_notification(notification_data)
      send_in_app_notification(notification_data)
      send_slack_notification(notification_data)
    when 'medium'
      # Send via in-app and slack for medium severity
      send_in_app_notification(notification_data)
      send_slack_notification(notification_data)
    else
      # Send via in-app only for low severity
      send_in_app_notification(notification_data)
    end
  end

  def send_email_notification(notification_data)
    # Send email via backend API
    api_client.post("/api/v1/notifications", {
      type: 'email',
      notification_data: notification_data
    })
  end

  def send_slack_notification(notification_data)
    # Send Slack notification if configured
    # This would integrate with Slack webhook or API
    logger.info "Slack notification: #{notification_data[:message]}"
  end

  def send_in_app_notification(notification_data)
    # Send in-app notification via backend API
    api_client.post("/api/v1/notifications", {
      type: 'in_app',
      notification_data: notification_data
    })
  end

  def send_push_notification(notification_data)
    # Send push notification via backend API
    api_client.post("/api/v1/notifications", {
      type: 'push',
      notification_data: notification_data
    })
  end

  def send_insights_email(notification_data)
    # Send analytical insights via email
    api_client.post("/api/v1/notifications", {
      type: 'insights_email',
      notification_data: notification_data
    })
  end

  def send_daily_summary(metrics, account_id)
    summary_data = {
      type: 'daily_analytics_summary',
      metrics: metrics,
      account_id: account_id,
      date: Date.today.iso8601
    }
    
    send_email_notification(summary_data)
    cache_daily_summary_sent(account_id)
  end

  def send_weekly_summary(metrics, account_id)
    summary_data = {
      type: 'weekly_analytics_summary',
      metrics: metrics,
      account_id: account_id,
      week_ending: Date.today.iso8601
    }
    
    send_email_notification(summary_data)
    cache_weekly_summary_sent(account_id)
  end

  # Rate limiting and caching methods
  def notification_recently_sent?(alert_type, account_id)
    cache_key = "notification:#{alert_type}:#{account_id || 'global'}"
    @notification_cache[cache_key] = redis_get(cache_key) if @notification_cache[cache_key].nil?
    
    @notification_cache[cache_key] == true
  end

  def cache_notification_sent(alert_type, account_id)
    cache_key = "notification:#{alert_type}:#{account_id || 'global'}"
    expiry = case alert_type
             when /critical/
               15.minutes # Critical alerts can repeat more frequently
             when /high/
               1.hour     # High severity alerts repeat hourly
             else
               4.hours    # Medium/low alerts repeat every 4 hours
             end
    
    redis_set(cache_key, true, expires_in: expiry)
    @notification_cache[cache_key] = true
  end

  def end_of_day?
    Time.now.hour >= 23
  end

  def monday_morning?
    Time.now.monday? && Time.now.hour.between?(8, 10)
  end

  def daily_summary_sent?(account_id)
    cache_key = "daily_summary:#{Date.today}:#{account_id || 'global'}"
    redis_get(cache_key) == true
  end

  def weekly_summary_sent?(account_id)
    cache_key = "weekly_summary:#{Date.today.cweek}:#{account_id || 'global'}"
    redis_get(cache_key) == true
  end

  def cache_daily_summary_sent(account_id)
    cache_key = "daily_summary:#{Date.today}:#{account_id || 'global'}"
    redis_set(cache_key, true, expires_in: 25.hours)
  end

  def cache_weekly_summary_sent(account_id)
    cache_key = "weekly_summary:#{Date.today.cweek}:#{account_id || 'global'}"
    redis_set(cache_key, true, expires_in: 8.days)
  end

  # Redis cache helpers since Rails.cache is not available
  def redis_get(key)
    Redis.current.get(key)
  rescue Redis::BaseError => e
    logger.error "Redis get error for key #{key}: #{e.message}"
    nil
  end

  def redis_set(key, value, expires_in: nil)
    if expires_in
      # Convert Rails-style expires_in to seconds
      expiry = case expires_in.to_s
               when /(\d+)/ then $1.to_i * 86400  # Assume days for simple integer
               else expires_in.to_i
               end
      Redis.current.setex(key, expiry, value.to_s)
    else
      Redis.current.set(key, value.to_s)
    end
  rescue Redis::BaseError => e
    logger.error "Redis set error for key #{key}: #{e.message}"
    false
  end
end