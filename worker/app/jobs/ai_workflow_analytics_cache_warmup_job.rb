# frozen_string_literal: true

# Background job to pre-compute and cache analytics data for dashboards
# Runs every 15 minutes to ensure dashboard data is always fresh
class AiWorkflowAnalyticsCacheWarmupJob < BaseJob
  sidekiq_options queue: :analytics

  # Cache keys and their computation strategies
  CACHE_CONFIGURATIONS = {
    'dashboard_summary' => {
      ttl: 900,       # 15 minutes
      priority: :high
    },
    'execution_stats_1h' => {
      ttl: 300,       # 5 minutes
      priority: :high
    },
    'execution_stats_24h' => {
      ttl: 900,       # 15 minutes
      priority: :high
    },
    'execution_stats_7d' => {
      ttl: 1800,      # 30 minutes
      priority: :medium
    },
    'cost_summary_24h' => {
      ttl: 900,       # 15 minutes
      priority: :high
    },
    'cost_summary_30d' => {
      ttl: 3600,      # 1 hour
      priority: :medium
    },
    'provider_health_summary' => {
      ttl: 300,       # 5 minutes
      priority: :high
    },
    'top_workflows_7d' => {
      ttl: 1800,      # 30 minutes
      priority: :medium
    },
    'error_distribution_24h' => {
      ttl: 900,       # 15 minutes
      priority: :medium
    },
    'performance_percentiles' => {
      ttl: 900,       # 15 minutes
      priority: :medium
    }
  }.freeze

  def execute
    log_info("Starting AI Workflow Analytics Cache Warmup")

    warmup_report = {
      started_at: Time.current.iso8601,
      status: 'running',
      caches_warmed: [],
      caches_failed: [],
      caches_skipped: []
    }

    begin
      # Sort by priority (high first)
      sorted_caches = CACHE_CONFIGURATIONS.sort_by { |_, config| config[:priority] == :high ? 0 : 1 }

      sorted_caches.each do |cache_key, config|
        warm_cache(cache_key, config, warmup_report)
      end

      # Calculate overall status
      warmup_report[:status] = if warmup_report[:caches_failed].any?
                                 'completed_with_errors'
                               else
                                 'completed'
                               end

      warmup_report[:completed_at] = Time.current.iso8601
      warmup_report[:duration_seconds] = calculate_duration(warmup_report)

      # Store metrics
      store_warmup_metrics(warmup_report)

      log_info("AI Workflow Analytics Cache Warmup completed: " \
               "warmed=#{warmup_report[:caches_warmed].size}, " \
               "failed=#{warmup_report[:caches_failed].size}, " \
               "skipped=#{warmup_report[:caches_skipped].size}")
    rescue StandardError => e
      log_error("AI Workflow Analytics Cache Warmup failed", e)
      warmup_report[:status] = 'failed'
      warmup_report[:error] = e.message
    end

    warmup_report
  end

  private

  def warm_cache(cache_key, config, warmup_report)
    log_info("Warming cache: #{cache_key}")

    start_time = Time.current

    # Check if cache needs refresh
    unless cache_needs_refresh?(cache_key, config[:ttl])
      warmup_report[:caches_skipped] << cache_key
      log_info("Cache #{cache_key} still valid, skipping")
      return
    end

    # Compute and cache the data
    result = compute_and_cache(cache_key, config[:ttl])

    if result[:success]
      warmup_report[:caches_warmed] << {
        key: cache_key,
        duration_ms: ((Time.current - start_time) * 1000).round,
        record_count: result[:record_count]
      }
    else
      warmup_report[:caches_failed] << {
        key: cache_key,
        error: result[:error]
      }
    end
  rescue StandardError => e
    log_error("Failed to warm cache: #{cache_key}", e)
    warmup_report[:caches_failed] << {
      key: cache_key,
      error: e.message
    }
  end

  def cache_needs_refresh?(cache_key, ttl)
    # Check with backend if cache is stale
    response = api_client.get('admin/analytics_cache/status', { key: cache_key })

    return true unless response['exists']
    return true if response['stale']

    # Check if cache will expire before next run (15 minutes)
    expires_in = response['expires_in'] || 0
    expires_in < 900 # Refresh if less than 15 minutes remaining
  rescue StandardError
    true # Refresh on error
  end

  def compute_and_cache(cache_key, ttl)
    case cache_key
    when 'dashboard_summary'
      compute_dashboard_summary(ttl)
    when 'execution_stats_1h'
      compute_execution_stats('1h', ttl)
    when 'execution_stats_24h'
      compute_execution_stats('24h', ttl)
    when 'execution_stats_7d'
      compute_execution_stats('7d', ttl)
    when 'cost_summary_24h'
      compute_cost_summary('24h', ttl)
    when 'cost_summary_30d'
      compute_cost_summary('30d', ttl)
    when 'provider_health_summary'
      compute_provider_health_summary(ttl)
    when 'top_workflows_7d'
      compute_top_workflows(ttl)
    when 'error_distribution_24h'
      compute_error_distribution(ttl)
    when 'performance_percentiles'
      compute_performance_percentiles(ttl)
    else
      { success: false, error: "Unknown cache key: #{cache_key}" }
    end
  end

  def compute_dashboard_summary(ttl)
    response = with_api_retry do
      api_client.post('admin/analytics_cache/compute', {
        cache_key: 'dashboard_summary',
        ttl: ttl,
        computation: {
          type: 'dashboard_summary',
          include: [
            'total_workflows',
            'active_executions',
            'success_rate_24h',
            'total_cost_mtd',
            'provider_status'
          ]
        }
      })
    end

    {
      success: response['success'],
      record_count: response['record_count'] || 0,
      error: response['error']
    }
  end

  def compute_execution_stats(period, ttl)
    response = with_api_retry do
      api_client.post('admin/analytics_cache/compute', {
        cache_key: "execution_stats_#{period}",
        ttl: ttl,
        computation: {
          type: 'execution_stats',
          period: period,
          include: [
            'total_executions',
            'successful_executions',
            'failed_executions',
            'average_duration',
            'executions_by_status'
          ]
        }
      })
    end

    {
      success: response['success'],
      record_count: response['record_count'] || 0,
      error: response['error']
    }
  end

  def compute_cost_summary(period, ttl)
    response = with_api_retry do
      api_client.post('admin/analytics_cache/compute', {
        cache_key: "cost_summary_#{period}",
        ttl: ttl,
        computation: {
          type: 'cost_summary',
          period: period,
          include: [
            'total_cost',
            'cost_by_provider',
            'cost_by_workflow',
            'cost_trend'
          ]
        }
      })
    end

    {
      success: response['success'],
      record_count: response['record_count'] || 0,
      error: response['error']
    }
  end

  def compute_provider_health_summary(ttl)
    response = with_api_retry do
      api_client.post('admin/analytics_cache/compute', {
        cache_key: 'provider_health_summary',
        ttl: ttl,
        computation: {
          type: 'provider_health_summary',
          include: [
            'provider_status',
            'response_times',
            'error_rates',
            'availability'
          ]
        }
      })
    end

    {
      success: response['success'],
      record_count: response['record_count'] || 0,
      error: response['error']
    }
  end

  def compute_top_workflows(ttl)
    response = with_api_retry do
      api_client.post('admin/analytics_cache/compute', {
        cache_key: 'top_workflows_7d',
        ttl: ttl,
        computation: {
          type: 'top_workflows',
          period: '7d',
          limit: 20,
          sort_by: ['execution_count', 'total_cost', 'success_rate']
        }
      })
    end

    {
      success: response['success'],
      record_count: response['record_count'] || 0,
      error: response['error']
    }
  end

  def compute_error_distribution(ttl)
    response = with_api_retry do
      api_client.post('admin/analytics_cache/compute', {
        cache_key: 'error_distribution_24h',
        ttl: ttl,
        computation: {
          type: 'error_distribution',
          period: '24h',
          include: [
            'errors_by_type',
            'errors_by_node_type',
            'errors_by_provider',
            'error_timeline'
          ]
        }
      })
    end

    {
      success: response['success'],
      record_count: response['record_count'] || 0,
      error: response['error']
    }
  end

  def compute_performance_percentiles(ttl)
    response = with_api_retry do
      api_client.post('admin/analytics_cache/compute', {
        cache_key: 'performance_percentiles',
        ttl: ttl,
        computation: {
          type: 'performance_percentiles',
          period: '24h',
          percentiles: [50, 75, 90, 95, 99],
          include: [
            'execution_duration',
            'node_processing_time',
            'api_response_time'
          ]
        }
      })
    end

    {
      success: response['success'],
      record_count: response['record_count'] || 0,
      error: response['error']
    }
  end

  def calculate_duration(warmup_report)
    return 0 unless warmup_report[:started_at] && warmup_report[:completed_at]

    started = Time.parse(warmup_report[:started_at])
    completed = Time.parse(warmup_report[:completed_at])
    (completed - started).round(2)
  end

  def store_warmup_metrics(warmup_report)
    with_api_retry do
      api_client.post('admin/ai_workflow_cache_warmup_metrics', {
        timestamp: warmup_report[:started_at],
        duration_seconds: warmup_report[:duration_seconds],
        caches_warmed: warmup_report[:caches_warmed].size,
        caches_failed: warmup_report[:caches_failed].size,
        caches_skipped: warmup_report[:caches_skipped].size,
        details: {
          warmed: warmup_report[:caches_warmed],
          failed: warmup_report[:caches_failed],
          skipped: warmup_report[:caches_skipped]
        }
      })
    end
  rescue StandardError => e
    log_error("Failed to store warmup metrics", e)
  end
end
