class Analytics::MetricsAggregationJob < BaseJob
  sidekiq_options queue: 'analytics'
  
  # Run every 5 minutes to keep live metrics fresh
  def self.schedule_recurring
    # Schedule to run every 5 minutes
    cron_expression = "*/5 * * * *"
    
    # This would be handled by a cron scheduler like sidekiq-scheduler
    puts "Scheduling recurring metrics aggregation job with cron: #{cron_expression}"
  end

  def execute(time_period: 'current', account_ids: nil)
    logger.info "Starting metrics aggregation for period: #{time_period}"
    
    start_time = Time.current
    processed_accounts = 0
    
    begin
      account_list = determine_accounts_to_process(account_ids)
      
      account_list.each do |account_id|
        process_account_metrics(account_id, time_period)
        processed_accounts += 1
      end
      
      # Process global metrics if no specific accounts
      if account_ids.nil?
        process_global_metrics(time_period)
      end
      
      # Update cache timestamps
      update_cache_timestamps
      
      execution_time = Time.current - start_time
      logger.info "Metrics aggregation completed. Processed #{processed_accounts} accounts in #{execution_time.round(2)}s"
      
      # Schedule live metrics updates
      schedule_live_metrics_updates(account_list)
      
    rescue => e
      logger.error "Metrics aggregation job failed: #{e.message}"
      logger.error e.backtrace.join("\n")
      
      # Notify error handling service
      ErrorNotificationService.notify(
        error: e,
        context: { 
          job: 'MetricsAggregationJob', 
          time_period: time_period, 
          processed_accounts: processed_accounts 
        }
      )
      
      raise e
    end
  end

  private

  def determine_accounts_to_process(account_ids)
    if account_ids.present?
      Array(account_ids)
    else
      # Get all active accounts from the backend API
      api_client = BackendApiClient.new
      response = api_client.get("/api/v1/accounts", { active: true })
      
      if response.success? && response.data.is_a?(Array)
        response.data.map { |account| account['id'] }
      else
        logger.warn "Failed to fetch active accounts, processing global metrics only"
        []
      end
    end
  end

  def process_account_metrics(account_id, time_period)
    logger.debug "Processing metrics for account: #{account_id}"
    
    begin
      # Trigger live metrics calculation for this account
      Analytics::LiveMetricsJob.perform_async(
        account_id: account_id,
        broadcast: true
      )
      
      # Update revenue snapshots if needed
      if should_update_snapshots?(time_period)
        update_revenue_snapshots(account_id)
      end
      
    rescue => e
      logger.error "Failed to process metrics for account #{account_id}: #{e.message}"
      # Continue processing other accounts
    end
  end

  def process_global_metrics(time_period)
    logger.debug "Processing global metrics"
    
    begin
      # Trigger global live metrics calculation
      Analytics::LiveMetricsJob.perform_async(
        account_id: nil,
        broadcast: true
      )
      
      # Update global revenue snapshots if needed
      if should_update_snapshots?(time_period)
        update_revenue_snapshots(nil)
      end
      
    rescue => e
      logger.error "Failed to process global metrics: #{e.message}"
    end
  end

  def should_update_snapshots?(time_period)
    # Update snapshots for 'current' period or specific time periods
    %w[current daily monthly].include?(time_period.to_s)
  end

  def update_revenue_snapshots(account_id)
    begin
      api_client = BackendApiClient.new
      response = api_client.post("/api/v1/analytics/update_revenue_snapshots", {
        account_id: account_id,
        period: 'current'
      })
      
      unless response.success?
        logger.warn "Failed to update revenue snapshots for account #{account_id}: #{response.error}"
      end
    rescue => e
      logger.error "Error updating revenue snapshots for account #{account_id}: #{e.message}"
    end
  end

  def update_cache_timestamps
    timestamp = Time.current.to_i
    
    begin
      # Update Redis timestamp for cache invalidation
      Redis.current.setex('analytics:last_update', 3600, timestamp)
      
      # Update cache timestamp via Redis (Rails.cache not available in worker service)
      Redis.current.setex('analytics:last_aggregation', 3600, timestamp)
      
    rescue Redis::BaseError => e
      logger.warn "Failed to update cache timestamps: #{e.message}"
    end
  end

  def schedule_live_metrics_updates(account_list)
    # Schedule individual live metrics updates with slight delays to spread load
    delay = 0
    
    account_list.each do |account_id|
      Analytics::LiveMetricsJob.perform_in(delay.seconds,
        account_id: account_id,
        broadcast: true
      )
      delay += 2 # 2 second delay between each job
    end
    
    # Schedule global metrics update
    Analytics::LiveMetricsJob.perform_in(delay.seconds,
      account_id: nil,
      broadcast: true
    )
  end
end