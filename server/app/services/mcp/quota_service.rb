# frozen_string_literal: true

module Mcp
  class QuotaService
    class QuotaExceededError < StandardError
      attr_reader :quota_type, :current, :limit

      def initialize(quota_type:, current:, limit:)
        @quota_type = quota_type
        @current = current
        @limit = limit
        super("#{quota_type} quota exceeded: #{current}/#{limit}")
      end
    end

    attr_reader :account, :quota

    def initialize(account)
      @account = account
      @quota = Mcp::ResourceQuota.for_account(account)
    end

    # Check if execution is allowed
    def check_execution_allowed!
      quota.reset_usage_if_needed!

      unless quota.concurrent_ok?
        raise QuotaExceededError.new(
          quota_type: "concurrent",
          current: quota.current_running_containers,
          limit: quota.max_concurrent_containers
        )
      end

      unless quota.hourly_ok?
        raise QuotaExceededError.new(
          quota_type: "hourly",
          current: quota.containers_used_this_hour,
          limit: quota.max_containers_per_hour
        )
      end

      unless quota.daily_ok?
        if quota.allow_overage
          Rails.logger.info "Account #{account.id} using overage quota"
        else
          raise QuotaExceededError.new(
            quota_type: "daily",
            current: quota.containers_used_today,
            limit: quota.max_containers_per_day
          )
        end
      end

      true
    end

    # Check if execution would be allowed (without raising)
    def can_execute?
      check_execution_allowed!
      true
    rescue QuotaExceededError
      false
    end

    # Increment usage counters
    def increment_usage!
      quota.increment_usage!
    end

    # Decrement running counter
    def decrement_running!
      quota.decrement_running!
    end

    # Validate resource request
    def validate_resources!(memory_mb:, cpu_millicores:, timeout_seconds:)
      if memory_mb > quota.max_memory_mb
        raise QuotaExceededError.new(
          quota_type: "memory",
          current: memory_mb,
          limit: quota.max_memory_mb
        )
      end

      if cpu_millicores > quota.max_cpu_millicores
        raise QuotaExceededError.new(
          quota_type: "cpu",
          current: cpu_millicores,
          limit: quota.max_cpu_millicores
        )
      end

      if timeout_seconds > quota.max_execution_time_seconds
        raise QuotaExceededError.new(
          quota_type: "execution_time",
          current: timeout_seconds,
          limit: quota.max_execution_time_seconds
        )
      end

      true
    end

    # Get current quota status
    def status
      quota.quota_status
    end

    # Get resource limits
    def resource_limits
      quota.resource_limits
    end

    # Check network access
    def network_allowed?
      quota.allow_network_access
    end

    def domain_allowed?(domain)
      quota.domain_allowed?(domain)
    end

    # Calculate overage cost
    def overage_cost
      return 0 unless quota.allow_overage

      quota.calculate_overage_cost(quota.containers_used_today)
    end

    # Update quota limits (admin only)
    def update_limits!(params)
      quota.update!(params.slice(
        :max_concurrent_containers,
        :max_containers_per_hour,
        :max_containers_per_day,
        :max_memory_mb,
        :max_cpu_millicores,
        :max_storage_bytes,
        :max_execution_time_seconds,
        :allow_network_access,
        :allowed_egress_domains,
        :allow_overage,
        :overage_rate_per_container
      ))
    end

    # Reset usage counters (for testing/admin)
    def reset_usage!
      quota.update!(
        current_running_containers: 0,
        containers_used_today: 0,
        containers_used_this_hour: 0,
        usage_reset_at: Time.current
      )
    end
  end
end
