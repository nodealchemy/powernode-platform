# frozen_string_literal: true

class UsageTrackingService
  attr_reader :account

  def initialize(account:)
    @account = account
  end

  # Ingest a single usage event
  def track_event(event_data)
    result = UsageEvent.ingest_single(account: account, event_data: event_data)

    if result[:success] && !result[:duplicate]
      Rails.logger.info "Usage event tracked: Account #{account.id}, Event #{result[:event].event_id}"
    end

    result
  end

  # Ingest batch of usage events
  def track_events_batch(events)
    result = UsageEvent.ingest_batch(account: account, events: events)

    Rails.logger.info "Batch usage events tracked: Account #{account.id}, Success: #{result[:success]}, Failed: #{result[:failed]}"

    result
  end

  # Get current usage dashboard data
  def dashboard_data
    current_period = current_billing_period

    {
      account_id: account.id,
      period: {
        start: current_period[:start],
        end: current_period[:end]
      },
      meters: meters_summary(current_period),
      quotas: quotas_summary,
      recent_events: recent_events,
      trends: usage_trends
    }
  end

  # Get usage for a specific meter
  def meter_usage(meter_slug, period_start: nil, period_end: nil)
    meter = UsageMeter.find_by(slug: meter_slug)
    return { success: false, error: "Unknown meter: #{meter_slug}" } unless meter

    period_start ||= current_billing_period[:start]
    period_end ||= current_billing_period[:end]

    events = account.usage_events
                    .for_meter(meter)
                    .for_period(period_start, period_end)

    total_quantity = meter.aggregate_events(events)
    calculated_cost = meter.calculate_cost(total_quantity)

    quota = account.usage_quotas.find_by(usage_meter: meter)

    {
      success: true,
      meter: meter.summary,
      period_start: period_start,
      period_end: period_end,
      total_quantity: total_quantity,
      event_count: events.count,
      calculated_cost: calculated_cost,
      quota: quota&.summary,
      events: events.recent.limit(100).map(&:summary)
    }
  end

  # Get or create usage summary for billing
  def get_billing_summary(period_start:, period_end:)
    summaries = []

    UsageMeter.active.billable.find_each do |meter|
      summary = UsageSummary.aggregate_for_period(
        account: account,
        meter: meter,
        period_start: period_start,
        period_end: period_end
      )
      summaries << summary
    end

    total_amount = summaries.sum(&:calculated_amount)
    overage_amount = summaries.sum(&:overage_quantity).to_f *
                     average_overage_rate(summaries)

    {
      period_start: period_start,
      period_end: period_end,
      summaries: summaries.map(&:summary),
      total_usage_amount: total_amount,
      total_overage_amount: overage_amount,
      grand_total: total_amount + overage_amount
    }
  end

  # Mark summaries as billed
  def mark_billed(invoice:, period_start:, period_end:)
    summaries = account.usage_summaries
                       .unbilled
                       .for_period(period_start, period_end)

    summaries.find_each do |summary|
      summary.mark_billed!(invoice)
    end

    { success: true, billed_count: summaries.count }
  end

  # Set up quota for account
  def set_quota(meter_slug:, soft_limit: nil, hard_limit: nil, allow_overage: true, overage_rate: nil)
    meter = UsageMeter.find_by(slug: meter_slug)
    return { success: false, error: "Unknown meter: #{meter_slug}" } unless meter

    quota = account.usage_quotas.find_or_initialize_by(usage_meter: meter)
    quota.assign_attributes(
      soft_limit: soft_limit,
      hard_limit: hard_limit,
      allow_overage: allow_overage,
      overage_rate: overage_rate
    )

    if quota.save
      { success: true, quota: quota.summary }
    else
      { success: false, errors: quota.errors.full_messages }
    end
  end

  # Reset quotas for new billing period
  def reset_quotas
    account.usage_quotas.find_each(&:reset_usage!)
    { success: true }
  end

  # Get usage history
  def usage_history(meter_slug: nil, days: 30)
    start_date = days.days.ago.to_date

    query = account.usage_summaries
                   .where("period_start >= ?", start_date)
                   .order(period_start: :desc)

    if meter_slug.present?
      meter = UsageMeter.find_by(slug: meter_slug)
      query = query.where(usage_meter: meter) if meter
    end

    {
      history: query.map(&:summary),
      total_records: query.count
    }
  end

  # Export usage data
  def export_usage(start_date:, end_date:, format: :json)
    events = account.usage_events
                    .includes(:usage_meter)
                    .for_period(start_date, end_date)
                    .order(timestamp: :asc)

    case format
    when :csv
      export_csv(events)
    else
      export_json(events)
    end
  end

  private

  def current_billing_period
    subscription = account.subscription
    if subscription&.current_period_start && subscription&.current_period_end
      {
        start: subscription.current_period_start,
        end: subscription.current_period_end
      }
    else
      {
        start: Date.current.beginning_of_month,
        end: Date.current.end_of_month
      }
    end
  end

  def meters_summary(period)
    UsageMeter.active.includes(:usage_quotas).map do |meter|
      events = account.usage_events
                      .for_meter(meter)
                      .for_period(period[:start], period[:end])

      total = meter.aggregate_events(events)
      quota = account.usage_quotas.find_by(usage_meter: meter)

      {
        id: meter.id,
        name: meter.name,
        slug: meter.slug,
        unit_name: meter.unit_name,
        total_usage: total,
        event_count: events.count,
        is_billable: meter.is_billable,
        calculated_cost: meter.calculate_cost(total),
        quota_limit: quota&.effective_limit,
        quota_used: quota&.current_usage || 0,
        quota_percent: quota&.usage_percent || 0,
        quota_exceeded: quota&.exceeded? || false
      }
    end
  end

  def quotas_summary
    account.usage_quotas.includes(:usage_meter).map(&:summary)
  end

  def recent_events
    account.usage_events
           .includes(:usage_meter)
           .recent
           .limit(20)
           .map(&:summary)
  end

  def usage_trends
    # Daily usage for the last 30 days
    thirty_days_ago = 30.days.ago.beginning_of_day

    daily_usage = account.usage_events
                         .where("timestamp >= ?", thirty_days_ago)
                         .group("DATE(timestamp)")
                         .sum(:quantity)
                         .transform_keys { |k| k.to_s }

    # Fill in missing days with zero
    (0..29).each do |days_ago|
      date = (Date.current - days_ago).to_s
      daily_usage[date] ||= 0
    end

    daily_usage.sort.to_h
  end

  def average_overage_rate(summaries)
    quotas = summaries.map { |s| account.usage_quotas.find_by(usage_meter: s.usage_meter) }.compact
    rates = quotas.map(&:overage_rate).compact
    rates.empty? ? 0.0 : rates.sum / rates.size
  end

  def export_json(events)
    {
      exported_at: Time.current,
      account_id: account.id,
      event_count: events.count,
      events: events.map do |event|
        {
          event_id: event.event_id,
          meter: event.usage_meter.slug,
          quantity: event.quantity,
          timestamp: event.timestamp,
          source: event.source,
          properties: event.properties
        }
      end
    }
  end

  def export_csv(events)
    headers = %w[event_id meter quantity timestamp source properties]

    CSV.generate(headers: true) do |csv|
      csv << headers
      events.each do |event|
        csv << [
          event.event_id,
          event.usage_meter.slug,
          event.quantity,
          event.timestamp.iso8601,
          event.source,
          event.properties.to_json
        ]
      end
    end
  end
end
