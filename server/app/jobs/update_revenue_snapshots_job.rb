class UpdateRevenueSnapshotsJob < ApplicationJob
  queue_as :analytics

  def perform(date = Date.current, period_type = "daily")
    Rails.logger.info "Starting revenue snapshot update for #{date} (#{period_type})"

    start_time = Time.current
    snapshots_created = 0
    errors = []

    begin
      # Update global snapshot first
      global_service = RevenueAnalyticsService.new(account: nil)
      global_snapshot = global_service.calculate_revenue_snapshot(date, period_type)
      snapshots_created += 1

      Rails.logger.info "Global snapshot created: MRR $#{global_snapshot.mrr.to_f}"

      # Update snapshots for each account
      Account.active.find_each do |account|
        begin
          account_service = RevenueAnalyticsService.new(account: account)
          account_snapshot = account_service.calculate_revenue_snapshot(date, period_type)
          snapshots_created += 1

          Rails.logger.debug "Account #{account.name} snapshot: MRR $#{account_snapshot.mrr.to_f}"
        rescue => e
          error_msg = "Failed to update snapshot for account #{account.id}: #{e.message}"
          Rails.logger.error error_msg
          errors << error_msg
        end
      end

      # Schedule next period calculation for monthly/yearly snapshots
      if period_type == "monthly" && date == Date.current.beginning_of_month
        # Also create monthly snapshot on first day of month
        UpdateRevenueSnapshotsJob.perform_later(date, "monthly")
      elsif period_type == "yearly" && date == Date.current.beginning_of_year
        # Also create yearly snapshot on first day of year
        UpdateRevenueSnapshotsJob.perform_later(date, "yearly")
      end

    rescue => e
      Rails.logger.error "Revenue snapshot job failed: #{e.message}"
      raise e
    end

    duration = Time.current - start_time
    Rails.logger.info "Revenue snapshot update completed: #{snapshots_created} snapshots created in #{duration.round(2)}s"

    if errors.any?
      Rails.logger.warn "Revenue snapshot update had #{errors.count} errors: #{errors.join(', ')}"
    end

    # Return summary
    {
      snapshots_created: snapshots_created,
      errors_count: errors.count,
      duration: duration.round(2),
      errors: errors
    }
  end
end
