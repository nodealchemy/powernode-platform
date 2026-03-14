# frozen_string_literal: true

class Analytics::LiveMetricsJob < BaseJob
  sidekiq_options queue: 'analytics'

  def execute(account_id: nil, broadcast: true)
    log_info("Processing live metrics for account: #{account_id || 'global'}")

    begin
      # Calculate live metrics
      metrics_data = calculate_live_metrics(account_id)
      
      # Cache the results for faster API responses
      cache_live_metrics(metrics_data, account_id)
      
      # Broadcast to real-time channels if requested
      if broadcast
        broadcast_live_metrics(metrics_data, account_id)
      end
      
      log_info("Live metrics processed successfully for account: #{account_id || 'global'}")
      metrics_data
    rescue => e
      log_error("Live metrics job failed for account #{account_id}: #{e.message}")
      log_error(e.backtrace.join("\n"))
      
      # Send error notification
      ErrorNotificationService.notify(
        error: e,
        context: { job: 'LiveMetricsJob', account_id: account_id }
      )
      
      raise e
    end
  end

  private

  def calculate_live_metrics(account_id)
    # Use the backend API to get analytics data
    api_client = BackendApiClient.new
    
    # Get current real-time metrics
    current_metrics_response = api_client.get("/api/v1/analytics/live", {
      account_id: account_id
    })
    
    if current_metrics_response.success?
      current_metrics_response.data
    else
      # Fallback calculation if API is unavailable
      calculate_fallback_metrics(account_id)
    end
  end

  def calculate_fallback_metrics(account_id)
    # Basic fallback metrics calculation
    {
      current_metrics: {
        mrr: 0,
        arr: 0,
        active_customers: 0,
        churn_rate: 0,
        arpu: 0,
        growth_rate: 0
      },
      today_activity: {
        new_subscriptions: 0,
        cancelled_subscriptions: 0,
        payments_processed: 0,
        failed_payments: 0,
        revenue_today: 0
      },
      weekly_trend: [],
      last_updated: Time.current.iso8601,
      account_id: account_id
    }
  end

  def cache_live_metrics(metrics_data, account_id)
    cache_key = account_id ? "live_metrics:account:#{account_id}" : "live_metrics:global"
    
    # Cache for 5 minutes (these are live metrics, should be fresh)
    # Rails.cache is not available in worker service, using Redis directly
    
    # Also store in Redis for WebSocket broadcasting
    redis_key = account_id ? "analytics:live:account:#{account_id}" : "analytics:live:global"
    
    begin
      Sidekiq.redis { |conn| conn.set(redis_key, metrics_data.to_json, ex: 300) } # 5 minutes expiry
    rescue Redis::BaseError => e
      log_warn("Failed to cache live metrics in Redis: #{e.message}")
    end
  end

  def broadcast_live_metrics(metrics_data, account_id)
    begin
      # Broadcast via ActionCable
      channel_name = account_id ? "analytics_account_#{account_id}" : "analytics_global"
      
      # Use the backend API to trigger broadcast
      api_client = BackendApiClient.new
      api_client.post("/api/v1/analytics/live", {
        account_id: account_id,
        broadcast: true
      })
      
      log_info("Live metrics broadcasted to channel: #{channel_name}")
    rescue => e
      log_error("Failed to broadcast live metrics: #{e.message}")
      # Don't re-raise - broadcasting failure shouldn't fail the entire job
    end
  end
end