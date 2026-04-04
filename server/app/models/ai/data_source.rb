# frozen_string_literal: true

module Ai
  class DataSource < ApplicationRecord
    self.table_name = "ai_data_sources"

    # Concerns
    include Auditable

    # Associations
    belongs_to :account
    has_many :credentials, class_name: "Ai::DataSourceCredential",
             foreign_key: "ai_data_source_id", dependent: :destroy

    # Constants
    SOURCE_TYPES = %w[noaa_ncei noaa_gfs noaa_observations open_meteo custom].freeze
    HEALTH_STATUSES = %w[healthy degraded critical unknown].freeze

    # Validations
    validates :name, presence: true, length: { maximum: 255 },
              uniqueness: { scope: :account_id, case_sensitive: false }
    validates :slug, presence: true, length: { maximum: 100 },
              uniqueness: { scope: :account_id },
              format: { with: /\A[a-z0-9_-]+\z/, message: "must be lowercase alphanumeric with hyphens/underscores" }
    validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }
    validates :priority_order, numericality: { greater_than: 0 }
    validates :health_status, inclusion: { in: HEALTH_STATUSES }, allow_nil: true

    # JSON column defaults (lambda required for mutable defaults)
    attribute :capabilities, :json, default: -> { [] }
    attribute :configuration, :json, default: -> { {} }
    attribute :rate_limits, :json, default: -> { {} }
    attribute :default_parameters, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Callbacks
    before_validation :generate_slug, on: :create

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :by_type, ->(type) { where(source_type: type) }
    scope :for_account, ->(account) { where(account: account) }
    scope :ordered_by_priority, -> { order(:priority_order, :name) }
    scope :requiring_auth, -> { where(requires_auth: true) }

    def to_param
      slug
    end

    # Returns the best available credential for making API requests.
    def active_credential
      credentials.where(is_active: true, is_default: true).first ||
        credentials.where(is_active: true).order(created_at: :desc).first
    end

    # Convenience accessor for the active credential's API key.
    def api_key
      active_credential&.decrypted_api_key
    end

    def healthy?
      is_active? && %w[healthy unknown].include?(health_status)
    end

    # Check if a request is within configured rate limits.
    # Returns { allowed: true } or { allowed: false, retry_after: seconds, limit: "limit_name" }.
    def check_quota!
      limits = rate_limits
      return { allowed: true } if limits.blank?

      now = Time.current
      usage = current_quota_usage

      if limits["requests_per_minute"] && usage[:minute] >= limits["requests_per_minute"]
        return { allowed: false, retry_after: 60 - now.sec, limit: "requests_per_minute" }
      end
      if limits["requests_per_hour"] && usage[:hour] >= limits["requests_per_hour"]
        return { allowed: false, retry_after: 3600 - (now.min * 60 + now.sec), limit: "requests_per_hour" }
      end
      if limits["requests_per_day"] && usage[:day] >= limits["requests_per_day"]
        return { allowed: false, retry_after: 86_400 - (now.hour * 3600 + now.min * 60 + now.sec), limit: "requests_per_day" }
      end

      { allowed: true }
    end

    # Record a completed request for quota tracking. Uses Redis atomic counters.
    def record_request!(bytes: 0)
      prefix = "data_source:#{id}:quota"
      begin
        redis = Redis.current
      rescue StandardError
        return
      end

      now = Time.current
      minute_key = "#{prefix}:min:#{now.strftime('%Y%m%d%H%M')}"
      hour_key = "#{prefix}:hr:#{now.strftime('%Y%m%d%H')}"
      day_key = "#{prefix}:day:#{now.strftime('%Y%m%d')}"

      redis.multi do |tx|
        tx.incr(minute_key)
        tx.expire(minute_key, 120)
        tx.incr(hour_key)
        tx.expire(hour_key, 7200)
        tx.incr(day_key)
        tx.expire(day_key, 172_800)
      end

      if bytes > 0
        bw_key = "#{prefix}:bw:#{now.strftime('%Y%m%d')}"
        redis.incrby(bw_key, bytes)
        redis.expire(bw_key, 172_800)
      end
    end

    # Current quota usage from Redis counters.
    def current_quota_usage
      prefix = "data_source:#{id}:quota"
      begin
        redis = Redis.current
      rescue StandardError
        return { minute: 0, hour: 0, day: 0, bandwidth_today: 0 }
      end

      now = Time.current
      minute_key = "#{prefix}:min:#{now.strftime('%Y%m%d%H%M')}"
      hour_key = "#{prefix}:hr:#{now.strftime('%Y%m%d%H')}"
      day_key = "#{prefix}:day:#{now.strftime('%Y%m%d')}"
      bw_key = "#{prefix}:bw:#{now.strftime('%Y%m%d')}"

      values = redis.mget(minute_key, hour_key, day_key, bw_key)
      {
        minute: values[0].to_i,
        hour: values[1].to_i,
        day: values[2].to_i,
        bandwidth_today: values[3].to_i
      }
    end

    # Returns a summary of current usage vs configured limits with utilization percentages.
    def quota_summary
      usage = current_quota_usage
      limits = rate_limits
      {
        usage: usage,
        limits: limits,
        utilization: {
          minute_pct: limits["requests_per_minute"] ? (usage[:minute].to_f / limits["requests_per_minute"] * 100).round(1) : nil,
          hour_pct: limits["requests_per_hour"] ? (usage[:hour].to_f / limits["requests_per_hour"] * 100).round(1) : nil,
          day_pct: limits["requests_per_day"] ? (usage[:day].to_f / limits["requests_per_day"] * 100).round(1) : nil
        }
      }
    end

    # Recalculates health status based on active credential state.
    def update_health_status!
      cred = active_credential
      status = if !is_active?
                 "unknown"
               elsif cred.nil?
                 "unknown"
               elsif cred.consecutive_failures >= 5
                 "critical"
               elsif cred.consecutive_failures >= 2
                 "degraded"
               else
                 "healthy"
               end
      update_columns(health_status: status, last_health_check_at: Time.current)
    end

    private

    def generate_slug
      return if slug.present?

      base = name.to_s.parameterize.underscore.first(90)
      self.slug = base
      counter = 1
      while self.class.where(account_id: account_id, slug: slug).where.not(id: id).exists?
        self.slug = "#{base}_#{counter}"
        counter += 1
      end
    end
  end
end
