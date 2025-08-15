require_relative '../base_job'

# Converted from UpdateRevenueSnapshotsJob to use API-only connectivity
# Handles daily revenue snapshot updates for analytics
class Analytics::UpdateRevenueSnapshotsJob < BaseJob
  sidekiq_options queue: 'analytics',
                  retry: 2

  def execute(date = Date.current, period_type = "daily")
    date = Date.parse(date.to_s) if date.is_a?(String)
    logger.info "Starting revenue snapshot update for #{date} (#{period_type})"

    start_time = Time.current
    
    begin
      update_params = {
        date: date.iso8601,
        period_type: period_type
      }

      # Request revenue snapshot update via API
      result = with_api_retry do
        api_client.post('/api/v1/analytics/update_revenue_snapshots', update_params)
      end

      duration = Time.current - start_time
      
      logger.info "Revenue snapshot update completed: #{result['snapshots_created']} snapshots created in #{duration.round(2)}s"

      if result['errors_count'] > 0
        logger.warn "Revenue snapshot update had #{result['errors_count']} errors"
        result['errors']&.each { |error| logger.warn "  - #{error}" }
      end

      # Schedule additional period calculations if needed
      schedule_period_snapshots(date, period_type)

      # Return summary
      {
        snapshots_created: result['snapshots_created'],
        errors_count: result['errors_count'],
        duration: duration.round(2),
        errors: result['errors']
      }

    rescue StandardError => e
      logger.error "Revenue snapshot job failed: #{e.message}"
      raise e
    end
  end

  private

  def schedule_period_snapshots(date, period_type)
    # Schedule monthly snapshot on first day of month
    if period_type == "daily" && date == Date.current.beginning_of_month
      Analytics::UpdateRevenueSnapshotsJob.perform_async(date.iso8601, "monthly")
      logger.info "Scheduled monthly snapshot for #{date}"
    end

    # Schedule yearly snapshot on first day of year
    if period_type == "daily" && date == Date.current.beginning_of_year
      Analytics::UpdateRevenueSnapshotsJob.perform_async(date.iso8601, "yearly")
      logger.info "Scheduled yearly snapshot for #{date}"
    end
  end
end