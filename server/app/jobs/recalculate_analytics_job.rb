class RecalculateAnalyticsJob < ApplicationJob
  queue_as :analytics_recalc

  def perform(start_date, end_date, account_id: nil, period_type: "daily")
    Rails.logger.info "Starting analytics recalculation from #{start_date} to #{end_date}"

    start_time = Time.current
    total_snapshots = 0
    errors = []

    begin
      start_date = start_date.to_date if start_date.is_a?(String)
      end_date = end_date.to_date if end_date.is_a?(String)

      # Validate date range
      raise "Start date must be before end date" if start_date > end_date
      raise "Date range too large" if (end_date - start_date) > 2.years

      if account_id.present?
        # Recalculate for specific account
        account = Account.find(account_id)
        total_snapshots += recalculate_account_snapshots(account, start_date, end_date, period_type)
      else
        # Recalculate global and all account snapshots

        # Global snapshots first
        total_snapshots += recalculate_global_snapshots(start_date, end_date, period_type)

        # Then each account
        Account.active.find_each do |account|
          begin
            snapshots_count = recalculate_account_snapshots(account, start_date, end_date, period_type)
            total_snapshots += snapshots_count
            Rails.logger.debug "Recalculated #{snapshots_count} snapshots for account #{account.name}"
          rescue => e
            error_msg = "Failed to recalculate analytics for account #{account.id}: #{e.message}"
            Rails.logger.error error_msg
            errors << error_msg
          end
        end
      end

    rescue => e
      Rails.logger.error "Analytics recalculation job failed: #{e.message}"
      raise e
    end

    duration = Time.current - start_time
    Rails.logger.info "Analytics recalculation completed: #{total_snapshots} snapshots processed in #{duration.round(2)}s"

    if errors.any?
      Rails.logger.warn "Analytics recalculation had #{errors.count} errors: #{errors.join(', ')}"
    end

    # Return summary
    {
      snapshots_processed: total_snapshots,
      errors_count: errors.count,
      duration: duration.round(2),
      errors: errors,
      date_range: "#{start_date} to #{end_date}",
      period_type: period_type
    }
  end

  private

  def recalculate_global_snapshots(start_date, end_date, period_type)
    service = RevenueAnalyticsService.new(account: nil)
    snapshots_count = 0

    current_date = start_date
    while current_date <= end_date
      # Delete existing snapshot if it exists
      existing_snapshot = RevenueSnapshot.find_by(
        account: nil,
        date: current_date,
        period_type: period_type
      )
      existing_snapshot&.destroy

      # Recalculate
      service.calculate_revenue_snapshot(current_date, period_type)
      snapshots_count += 1

      # Move to next period
      current_date = next_date(current_date, period_type)
    end

    snapshots_count
  end

  def recalculate_account_snapshots(account, start_date, end_date, period_type)
    service = RevenueAnalyticsService.new(account: account)
    snapshots_count = 0

    current_date = start_date
    while current_date <= end_date
      # Delete existing snapshot if it exists
      existing_snapshot = RevenueSnapshot.find_by(
        account: account,
        date: current_date,
        period_type: period_type
      )
      existing_snapshot&.destroy

      # Recalculate
      service.calculate_revenue_snapshot(current_date, period_type)
      snapshots_count += 1

      # Move to next period
      current_date = next_date(current_date, period_type)
    end

    snapshots_count
  end

  def next_date(current_date, period_type)
    case period_type
    when "daily"
      current_date + 1.day
    when "weekly"
      current_date + 1.week
    when "monthly"
      current_date + 1.month
    when "quarterly"
      current_date + 3.months
    when "yearly"
      current_date + 1.year
    else
      current_date + 1.day
    end
  end
end
