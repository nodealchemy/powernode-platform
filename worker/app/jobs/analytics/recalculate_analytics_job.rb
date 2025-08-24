# frozen_string_literal: true

require_relative '../base_job'

# Converted from RecalculateAnalyticsJob to use API-only connectivity
# Handles analytics recalculation for revenue snapshots and metrics
class Analytics::RecalculateAnalyticsJob < BaseJob
  sidekiq_options queue: 'analytics',
                  retry: 2

  def execute(start_date, end_date, account_id: nil, period_type: "daily")
    logger.info "Starting analytics recalculation from #{start_date} to #{end_date}"

    start_time = Time.current
    
    begin
      start_date = Date.parse(start_date.to_s)
      end_date = Date.parse(end_date.to_s)

      # Validate date range
      raise "Start date must be before end date" if start_date > end_date
      raise "Date range too large" if (end_date - start_date) > 2.years

      recalc_params = {
        start_date: start_date.iso8601,
        end_date: end_date.iso8601,
        period_type: period_type
      }
      
      recalc_params[:account_id] = account_id if account_id

      # Request analytics recalculation via API
      result = with_api_retry do
        api_client.post('/api/v1/analytics/recalculate', recalc_params)
      end

      duration = Time.current - start_time
      
      logger.info "Analytics recalculation completed: #{result['snapshots_processed']} snapshots processed in #{duration.round(2)}s"

      if result['errors_count'] > 0
        logger.warn "Analytics recalculation had #{result['errors_count']} errors"
        result['errors']&.each { |error| logger.warn "  - #{error}" }
      end

      # Return summary
      {
        snapshots_processed: result['snapshots_processed'],
        errors_count: result['errors_count'],
        duration: duration.round(2),
        errors: result['errors'],
        date_range: "#{start_date} to #{end_date}",
        period_type: period_type
      }

    rescue StandardError => e
      logger.error "Analytics recalculation job failed: #{e.message}"
      raise e
    end
  end
end