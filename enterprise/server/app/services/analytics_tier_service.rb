# frozen_string_literal: true

class AnalyticsTierService
  attr_reader :account

  def initialize(account:)
    @account = account
  end

  # Get current tier for account
  def current_tier
    tier_slug = account.analytics_tier || "free"
    AnalyticsTier.find_by(slug: tier_slug) || AnalyticsTier.free
  end

  # Check if account has access to a feature
  def has_feature?(feature_name)
    current_tier.has_feature?(feature_name)
  end

  # Check if account can access data within retention period
  def can_access_date?(date)
    tier = current_tier
    return true if tier.unlimited_retention?

    days_ago = (Date.current - date.to_date).to_i
    days_ago <= tier.retention_days
  end

  # Check if account can access cohort data for a given number of months
  def can_access_cohort_months?(months)
    tier = current_tier
    return true if tier.unlimited_cohorts?
    return false if tier.cohort_months == 0

    months <= tier.cohort_months
  end

  # Check if account has API calls remaining for today
  def can_make_api_call?
    tier = current_tier
    return false unless tier.api_access
    return true if tier.unlimited_api_calls?

    daily_calls_used < tier.api_calls_per_day
  end

  # Record an API call
  def record_api_call!
    # Use Redis or DB counter for tracking
    key = api_calls_key
    Rails.cache.increment(key, 1, expires_in: 1.day)
  end

  # Get remaining API calls
  def remaining_api_calls
    tier = current_tier
    return 0 unless tier.api_access
    return Float::INFINITY if tier.unlimited_api_calls?

    [ tier.api_calls_per_day - daily_calls_used, 0 ].max
  end

  # Upgrade account tier
  def upgrade_tier(new_tier_slug)
    new_tier = AnalyticsTier.find_by(slug: new_tier_slug)
    return { success: false, error: "Invalid tier: #{new_tier_slug}" } unless new_tier
    return { success: false, error: "Already on this tier" } if current_tier.slug == new_tier_slug

    account.update!(analytics_tier: new_tier_slug)
    Rails.logger.info "Analytics tier upgraded: Account #{account.id} to #{new_tier_slug}"

    { success: true, tier: new_tier.summary }
  end

  # Get tier comparison for upgrade page
  def tier_comparison
    {
      current_tier: current_tier.summary,
      available_tiers: AnalyticsTier.for_comparison,
      can_upgrade: can_upgrade?,
      upgrade_options: upgrade_options
    }
  end

  # Get feature gates for current tier (for frontend)
  def feature_gates
    tier = current_tier
    {
      tier_slug: tier.slug,
      tier_name: tier.name,
      features: {
        csv_export: tier.csv_export,
        api_access: tier.api_access,
        forecasting: tier.forecasting,
        custom_reports: tier.custom_reports
      },
      limits: {
        retention_days: tier.unlimited_retention? ? nil : tier.retention_days,
        cohort_months: tier.unlimited_cohorts? ? nil : tier.cohort_months,
        api_calls_per_day: tier.unlimited_api_calls? ? nil : tier.api_calls_per_day,
        api_calls_remaining: remaining_api_calls == Float::INFINITY ? nil : remaining_api_calls
      }
    }
  end

  # Apply date filter based on tier retention
  def apply_retention_filter(query, date_column: :created_at)
    tier = current_tier
    return query if tier.unlimited_retention?

    cutoff_date = tier.retention_days.days.ago
    query.where("#{date_column} >= ?", cutoff_date)
  end

  # Get maximum allowed date range for tier
  def max_date_range
    tier = current_tier
    return nil if tier.unlimited_retention?

    {
      earliest: tier.retention_days.days.ago.to_date,
      latest: Date.current
    }
  end

  private

  def daily_calls_used
    key = api_calls_key
    Rails.cache.read(key)&.to_i || 0
  end

  def api_calls_key
    "analytics_api_calls:#{account.id}:#{Date.current}"
  end

  def can_upgrade?
    current_tier.slug != "enterprise"
  end

  def upgrade_options
    current_order = current_tier.sort_order
    AnalyticsTier.active
                 .where("sort_order > ?", current_order)
                 .ordered
                 .map do |tier|
      {
        slug: tier.slug,
        name: tier.name,
        monthly_price: tier.monthly_price,
        price_increase: tier.monthly_price - current_tier.monthly_price,
        new_features: new_features_for_tier(tier)
      }
    end
  end

  def new_features_for_tier(tier)
    current = current_tier
    features = []

    features << "Extended data retention (#{tier.retention_display})" if tier.retention_days > current.retention_days || (tier.unlimited_retention? && !current.unlimited_retention?)
    features << "Cohort analysis (#{tier.cohort_display})" if tier.cohort_months > current.cohort_months
    features << "CSV Export" if tier.csv_export && !current.csv_export
    features << "API Access" if tier.api_access && !current.api_access
    features << "Revenue Forecasting" if tier.forecasting && !current.forecasting
    features << "Custom Reports" if tier.custom_reports && !current.custom_reports

    features
  end
end
