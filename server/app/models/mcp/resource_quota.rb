# frozen_string_literal: true

module Mcp
  class ResourceQuota < ApplicationRecord
    # Concerns
    include Auditable

    # Associations
    belongs_to :account

    # Validations
    validates :account_id, uniqueness: true
    validates :max_concurrent_containers, numericality: { greater_than: 0 }
    validates :max_containers_per_hour, numericality: { greater_than: 0 }
    validates :max_containers_per_day, numericality: { greater_than: 0 }
    validates :max_memory_mb, numericality: { greater_than: 0 }
    validates :max_cpu_millicores, numericality: { greater_than: 0 }
    validates :max_storage_bytes, numericality: { greater_than: 0 }
    validates :max_execution_time_seconds, numericality: { greater_than: 0 }

    # Scopes
    scope :with_overage, -> { where(allow_overage: true) }

    # Class method to get or create quota for account
    def self.for_account(account)
      find_or_create_by(account: account) do |quota|
        quota.set_defaults
      end
    end

    # Set default values
    def set_defaults
      self.max_concurrent_containers ||= 5
      self.max_containers_per_hour ||= 50
      self.max_containers_per_day ||= 500
      self.max_memory_mb ||= 512
      self.max_cpu_millicores ||= 500
      self.max_storage_bytes ||= 1.gigabyte
      self.max_execution_time_seconds ||= 3600
      self.allowed_egress_domains ||= []
    end

    # Usage tracking
    def increment_usage!
      reset_usage_if_needed!

      increment!(:containers_used_this_hour)
      increment!(:containers_used_today)
      increment!(:current_running_containers)
    end

    def decrement_running!
      decrement!(:current_running_containers) if current_running_containers.positive?
    end

    def reset_usage_if_needed!
      now = Time.current

      # Reset hourly counter
      if usage_reset_at.nil? || usage_reset_at < 1.hour.ago
        update!(
          containers_used_this_hour: 0,
          usage_reset_at: now.beginning_of_hour
        )
      end

      # Reset daily counter
      if usage_reset_at.nil? || usage_reset_at < now.beginning_of_day
        update!(containers_used_today: 0)
      end
    end

    # Quota checks
    def can_execute?
      reset_usage_if_needed!

      concurrent_ok? && hourly_ok? && daily_ok?
    end

    def concurrent_ok?
      current_running_containers < max_concurrent_containers
    end

    def hourly_ok?
      containers_used_this_hour < max_containers_per_hour
    end

    def daily_ok?
      containers_used_today < max_containers_per_day
    end

    def quota_status
      reset_usage_if_needed!

      {
        concurrent: {
          used: current_running_containers,
          limit: max_concurrent_containers,
          available: max_concurrent_containers - current_running_containers,
          ok: concurrent_ok?
        },
        hourly: {
          used: containers_used_this_hour,
          limit: max_containers_per_hour,
          available: max_containers_per_hour - containers_used_this_hour,
          ok: hourly_ok?
        },
        daily: {
          used: containers_used_today,
          limit: max_containers_per_day,
          available: max_containers_per_day - containers_used_today,
          ok: daily_ok?
        },
        can_execute: can_execute?,
        allow_overage: allow_overage
      }
    end

    # Resource limits
    def resource_limits
      {
        memory_mb: max_memory_mb,
        cpu_millicores: max_cpu_millicores,
        storage_bytes: max_storage_bytes,
        execution_time_seconds: max_execution_time_seconds
      }
    end

    # Network policy
    def network_policy
      {
        allow_network: allow_network_access,
        allowed_domains: allowed_egress_domains
      }
    end

    def domain_allowed?(domain)
      return true unless allow_network_access
      return true if allowed_egress_domains.empty?

      allowed_egress_domains.any? do |pattern|
        if pattern.start_with?("*.")
          domain.end_with?(pattern[1..])
        else
          domain == pattern
        end
      end
    end

    # Overage calculation
    def calculate_overage_cost(container_count)
      return 0 unless allow_overage
      return 0 if overage_rate_per_container.nil?

      overage_count = [ container_count - max_containers_per_day, 0 ].max
      (overage_count * overage_rate_per_container).round(2)
    end

    # Summary
    def quota_summary
      status = quota_status

      {
        id: id,
        account_id: account_id,
        concurrent: status[:concurrent],
        hourly: status[:hourly],
        daily: status[:daily],
        resource_limits: resource_limits,
        network_policy: network_policy,
        allow_overage: allow_overage,
        overage_rate: overage_rate_per_container
      }
    end
  end
end
