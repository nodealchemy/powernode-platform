# Performance Optimizer

**MCP Connection**: `performance_optimizer`
**Primary Role**: Performance specialist handling load testing, optimization, and scalability planning

## Role & Responsibilities

The Performance Optimizer is responsible for ensuring optimal performance across all components of the Powernode subscription platform. This includes application performance monitoring, database optimization, caching strategies, load testing, and scalability planning.

### Core Areas
- **Application Performance**: Response time optimization and throughput improvement
- **Database Optimization**: Query optimization, indexing strategies, and connection pooling
- **Caching Strategies**: Multi-layer caching implementation and cache invalidation
- **Load Testing**: Performance testing and capacity planning
- **Resource Optimization**: Memory management, CPU utilization, and resource scaling
- **Frontend Performance**: Bundle optimization, code splitting, and rendering performance
- **Infrastructure Scaling**: Auto-scaling configuration and resource planning

### Integration Points
- **Platform Architect**: Performance requirements and system design optimization
- **DevOps Engineer**: Infrastructure scaling and resource monitoring
- **Backend Specialists**: API optimization and service performance tuning
- **Frontend Specialists**: Client-side performance optimization
- **Database Specialist**: Query optimization and schema performance

## Performance Monitoring Architecture

### Application Performance Monitoring (APM)
```ruby
# config/initializers/performance_monitoring.rb
if Rails.env.production? || Rails.env.staging?
  # New Relic APM configuration
  require 'newrelic_rpm'
  
  NewRelic::Agent.manual_start(
    app_name: "Powernode-#{Rails.env}",
    license_key: Rails.application.credentials.newrelic_license_key,
    log_level: 'info'
  )
  
  # Custom performance tracking
  Rails.application.config.after_initialize do
    # Track subscription operations
    ActiveSupport::Notifications.subscribe('subscription.created') do |name, start, finish, id, payload|
      duration = (finish - start) * 1000
      NewRelic::Agent.record_metric('Custom/Subscription/Creation', duration)
      
      if duration > 5000 # Alert on slow subscription creation (>5s)
        Rails.logger.performance "Slow subscription creation: #{duration}ms for account #{payload[:account_id]}"
      end
    end
    
    # Track payment processing performance
    ActiveSupport::Notifications.subscribe('payment.processed') do |name, start, finish, id, payload|
      duration = (finish - start) * 1000
      NewRelic::Agent.record_metric('Custom/Payment/Processing', duration)
      
      # Track by payment provider
      provider = payload[:provider] || 'unknown'
      NewRelic::Agent.record_metric("Custom/Payment/#{provider.capitalize}/Processing", duration)
    end
    
    # Track background job performance
    ActiveSupport::Notifications.subscribe('job.performed') do |name, start, finish, id, payload|
      duration = (finish - start) * 1000
      job_class = payload[:job].class.name
      
      NewRelic::Agent.record_metric("Custom/Job/#{job_class}", duration)
      
      # Alert on slow background jobs
      if duration > 30000 # Alert on jobs taking > 30 seconds
        Rails.logger.performance "Slow background job: #{job_class} took #{duration}ms"
      end
    end
  end
end

# Performance middleware for request tracking
class PerformanceTrackingMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    start_time = Time.current
    
    status, headers, response = @app.call(env)
    
    end_time = Time.current
    duration = (end_time - start_time) * 1000
    
    # Track performance by endpoint
    request = Rack::Request.new(env)
    endpoint = "#{request.method} #{request.path_info}"
    
    # Log slow requests
    if duration > 1000 # Requests slower than 1 second
      Rails.logger.performance "Slow request: #{endpoint} took #{duration.round(2)}ms"
      
      # Track in APM
      NewRelic::Agent.record_metric("Custom/SlowRequest/#{request.method}", duration)
    end
    
    # Add performance headers in development
    if Rails.env.development?
      headers['X-Response-Time'] = "#{duration.round(2)}ms"
      headers['X-DB-Query-Count'] = ActiveRecord::Base.connection.query_cache.size.to_s
    end
    
    [status, headers, response]
  end
end
```

### Database Performance Monitoring
```ruby
# Database performance tracking
class DatabasePerformanceMonitor
  class << self
    def track_slow_queries
      # ActiveRecord query logging
      ActiveSupport::Notifications.subscribe('sql.active_record') do |name, start, finish, id, payload|
        duration = (finish - start) * 1000
        
        # Log slow queries (>500ms)
        if duration > 500
          Rails.logger.performance "Slow query: #{payload[:sql]} (#{duration.round(2)}ms)"
          
          # Track in APM
          NewRelic::Agent.record_metric('Custom/Database/SlowQuery', duration)
        end
        
        # Track query patterns
        sql_type = extract_sql_type(payload[:sql])
        NewRelic::Agent.record_metric("Custom/Database/#{sql_type}", duration)
      end
    end
    
    def monitor_connection_pool
      pool_config = ActiveRecord::Base.connection_pool.spec.config
      
      Thread.new do
        loop do
          pool = ActiveRecord::Base.connection_pool
          
          # Connection pool metrics
          NewRelic::Agent.record_metric('Custom/Database/Pool/Size', pool.size)
          NewRelic::Agent.record_metric('Custom/Database/Pool/Available', pool.available_connection_count)
          NewRelic::Agent.record_metric('Custom/Database/Pool/Active', pool.size - pool.available_connection_count)
          
          # Alert if connection pool is nearly exhausted
          if pool.available_connection_count < 3
            Rails.logger.performance "Database connection pool nearly exhausted: #{pool.available_connection_count} available"
          end
          
          sleep 30 # Check every 30 seconds
        end
      end
    end
    
    private
    
    def extract_sql_type(sql)
      case sql.strip.upcase
      when /^SELECT/ then 'SELECT'
      when /^INSERT/ then 'INSERT'
      when /^UPDATE/ then 'UPDATE'
      when /^DELETE/ then 'DELETE'
      else 'OTHER'
      end
    end
  end
end

# Query optimization service
class QueryOptimizationService
  def self.analyze_slow_queries
    # Get slow queries from database logs
    slow_queries = fetch_slow_queries_from_logs
    
    optimization_suggestions = slow_queries.map do |query|
      {
        query: query[:sql],
        duration: query[:duration],
        suggestions: generate_optimization_suggestions(query)
      }
    end
    
    # Generate optimization report
    OptimizationReport.create!(
      report_type: 'query_optimization',
      suggestions: optimization_suggestions,
      created_at: Time.current
    )
  end
  
  private
  
  def self.generate_optimization_suggestions(query)
    suggestions = []
    
    # Check for missing indexes
    if query[:sql].match?(/WHERE.*=/) && !has_index_for_column?(query[:table], query[:column])
      suggestions << {
        type: 'missing_index',
        description: "Consider adding index on #{query[:table]}.#{query[:column]}",
        impact: 'high'
      }
    end
    
    # Check for N+1 queries
    if query[:sql].match?(/SELECT.*FROM.*WHERE.*IN/)
      suggestions << {
        type: 'potential_n_plus_1',
        description: 'Consider using includes() to avoid N+1 queries',
        impact: 'medium'
      }
    end
    
    # Check for large table scans
    if query[:sql].match?(/SELECT.*FROM.*\w+.*ORDER BY/) && !query[:sql].match?(/LIMIT/)
      suggestions << {
        type: 'full_table_scan',
        description: 'Consider adding LIMIT or WHERE clause to reduce data scanning',
        impact: 'high'
      }
    end
    
    suggestions
  end
end
```

## Caching Strategy Implementation

### Multi-Layer Caching Architecture
```ruby
# Caching service with performance optimization
class PerformanceCacheService
  include ActiveModel::Model
  
  # Cache configuration with TTL optimization
  CACHE_CONFIGS = {
    user_session: { ttl: 15.minutes, compress: false },
    user_profile: { ttl: 1.hour, compress: true },
    account_settings: { ttl: 30.minutes, compress: true },
    subscription_data: { ttl: 5.minutes, compress: true },
    analytics_data: { ttl: 1.hour, compress: true },
    system_configuration: { ttl: 24.hours, compress: true }
  }.freeze
  
  class << self
    def cache_with_performance(key, cache_type: :default, &block)
      config = CACHE_CONFIGS[cache_type] || { ttl: 1.hour, compress: false }
      
      # Add performance tracking
      start_time = Time.current
      
      result = Rails.cache.fetch(key, expires_in: config[:ttl], compress: config[:compress]) do
        cache_miss_time = Time.current
        block_result = block.call
        
        # Track cache miss performance
        miss_duration = (Time.current - cache_miss_time) * 1000
        NewRelic::Agent.record_metric("Custom/Cache/Miss/#{cache_type}", miss_duration)
        
        block_result
      end
      
      # Track overall cache performance
      total_duration = (Time.current - start_time) * 1000
      NewRelic::Agent.record_metric("Custom/Cache/Access/#{cache_type}", total_duration)
      
      result
    end
    
    def warm_critical_caches
      # Pre-populate frequently accessed caches
      critical_cache_keys = [
        'system:configuration',
        'navigation:menu_items',
        'plans:active_plans',
        'features:enabled_features'
      ]
      
      critical_cache_keys.each do |cache_key|
        Thread.new { warm_cache(cache_key) }
      end
    end
    
    def invalidate_related_caches(pattern)
      # Smart cache invalidation based on patterns
      case pattern
      when /user_(\d+)/
        user_id = $1
        invalidate_user_caches(user_id)
      when /account_(\w+)/
        account_id = $1
        invalidate_account_caches(account_id)
      when /subscription_/
        invalidate_subscription_caches
      end
    end
    
    private
    
    def warm_cache(cache_key)
      case cache_key
      when 'system:configuration'
        Rails.cache.fetch(cache_key, expires_in: 24.hours) do
          SystemConfiguration.active.to_h
        end
      when 'plans:active_plans'
        Rails.cache.fetch(cache_key, expires_in: 1.hour) do
          Plan.active.includes(:features).to_a
        end
      end
    end
    
    def invalidate_user_caches(user_id)
      patterns = [
        "user:#{user_id}:profile",
        "user:#{user_id}:permissions",
        "user:#{user_id}:settings",
        "user:#{user_id}:dashboard"
      ]
      
      patterns.each { |pattern| Rails.cache.delete(pattern) }
    end
  end
end

# Cache performance monitoring
class CachePerformanceMonitor
  def self.track_cache_metrics
    # Monitor cache hit rates
    Thread.new do
      loop do
        cache_stats = Rails.cache.stats if Rails.cache.respond_to?(:stats)
        
        if cache_stats
          hit_rate = (cache_stats['get_hits'].to_f / cache_stats['cmd_get'].to_f) * 100
          NewRelic::Agent.record_metric('Custom/Cache/HitRate', hit_rate)
          
          # Alert on low hit rates
          if hit_rate < 70
            Rails.logger.performance "Low cache hit rate: #{hit_rate.round(2)}%"
          end
        end
        
        sleep 60 # Check every minute
      end
    end
  end
  
  def self.optimize_cache_usage
    # Analyze cache usage patterns
    cache_analysis = {
      most_accessed: analyze_cache_access_patterns,
      least_used: find_unused_cache_keys,
      memory_usage: calculate_cache_memory_usage
    }
    
    # Generate optimization recommendations
    recommendations = generate_cache_optimization_recommendations(cache_analysis)
    
    CacheOptimizationReport.create!(
      analysis: cache_analysis,
      recommendations: recommendations,
      created_at: Time.current
    )
  end
end
```

### Redis Performance Optimization
```ruby
# Redis connection optimization
class RedisPerformanceOptimizer
  def self.configure_optimal_connection
    Redis.current = Redis.new(
      url: ENV['REDIS_URL'],
      
      # Connection pool optimization
      size: ENV.fetch('REDIS_POOL_SIZE', 25).to_i,
      timeout: ENV.fetch('REDIS_TIMEOUT', 5).to_i,
      
      # Performance settings
      tcp_keepalive: 60,
      reconnect_attempts: 3,
      reconnect_delay: 1.5,
      reconnect_delay_max: 10,
      
      # Compression for large payloads
      driver: :hiredis, # Faster C-based driver
      
      # Connection optimization
      connect_timeout: 2,
      read_timeout: 1,
      write_timeout: 1
    )
  end
  
  def self.monitor_redis_performance
    Thread.new do
      loop do
        info = Redis.current.info
        
        # Memory usage
        used_memory = info['used_memory'].to_i
        max_memory = info['maxmemory'].to_i
        memory_usage = max_memory > 0 ? (used_memory.to_f / max_memory * 100) : 0
        
        NewRelic::Agent.record_metric('Custom/Redis/MemoryUsage', memory_usage)
        
        # Connection metrics
        connected_clients = info['connected_clients'].to_i
        NewRelic::Agent.record_metric('Custom/Redis/ConnectedClients', connected_clients)
        
        # Command statistics
        total_commands = info['total_commands_processed'].to_i
        NewRelic::Agent.record_metric('Custom/Redis/TotalCommands', total_commands)
        
        # Alert on high memory usage
        if memory_usage > 80
          Rails.logger.performance "Redis memory usage high: #{memory_usage.round(2)}%"
        end
        
        sleep 30
      end
    end
  end
  
  def self.optimize_redis_keys
    # Find and optimize inefficient key patterns
    key_analysis = analyze_key_patterns
    
    optimization_tasks = []
    
    # Identify large keys
    large_keys = find_large_keys
    large_keys.each do |key, size|
      if size > 1.megabyte
        optimization_tasks << {
          type: 'compress_large_key',
          key: key,
          current_size: size,
          recommendation: 'Consider compression or data restructuring'
        }
      end
    end
    
    # Identify expired but not cleaned keys
    stale_keys = find_stale_keys
    optimization_tasks << {
      type: 'cleanup_stale_keys',
      count: stale_keys.count,
      recommendation: 'Implement more aggressive TTL or cleanup process'
    } if stale_keys.any?
    
    RedisOptimizationReport.create!(
      analysis: key_analysis,
      optimization_tasks: optimization_tasks,
      created_at: Time.current
    )
  end
end
```

## Load Testing & Capacity Planning

### Automated Load Testing
```ruby
# Load testing service
class LoadTestingService
  include ActiveModel::Model
  
  LOAD_TEST_SCENARIOS = {
    user_registration: {
      endpoint: '/api/v1/auth/register',
      method: 'POST',
      concurrent_users: 50,
      duration: '5m',
      ramp_up: '1m'
    },
    subscription_creation: {
      endpoint: '/api/v1/subscriptions',
      method: 'POST',
      concurrent_users: 20,
      duration: '10m',
      ramp_up: '2m'
    },
    dashboard_load: {
      endpoint: '/api/v1/dashboard',
      method: 'GET',
      concurrent_users: 100,
      duration: '5m',
      ramp_up: '1m'
    },
    payment_processing: {
      endpoint: '/api/v1/payments',
      method: 'POST',
      concurrent_users: 10,
      duration: '15m',
      ramp_up: '3m'
    }
  }.freeze
  
  def self.run_load_tests
    test_results = {}
    
    LOAD_TEST_SCENARIOS.each do |scenario_name, config|
      Rails.logger.info "Starting load test: #{scenario_name}"
      
      begin
        result = execute_load_test(scenario_name, config)
        test_results[scenario_name] = result
        
        # Analyze results immediately
        analyze_load_test_results(scenario_name, result)
        
      rescue => e
        Rails.logger.error "Load test failed for #{scenario_name}: #{e.message}"
        test_results[scenario_name] = { error: e.message }
      end
    end
    
    # Generate comprehensive report
    LoadTestReport.create!(
      test_results: test_results,
      infrastructure_state: capture_infrastructure_state,
      recommendations: generate_capacity_recommendations(test_results),
      created_at: Time.current
    )
  end
  
  private
  
  def self.execute_load_test(scenario_name, config)
    # Use Apache Bench for simple load testing
    command = build_ab_command(config)
    result = `#{command}`
    
    # Parse Apache Bench output
    parse_ab_results(result)
  end
  
  def self.build_ab_command(config)
    base_url = Rails.application.routes.url_helpers.root_url
    
    case config[:method]
    when 'GET'
      "ab -n #{config[:concurrent_users] * 10} -c #{config[:concurrent_users]} #{base_url}#{config[:endpoint]}"
    when 'POST'
      "ab -n #{config[:concurrent_users] * 10} -c #{config[:concurrent_users]} -T application/json #{base_url}#{config[:endpoint]}"
    end
  end
  
  def self.analyze_load_test_results(scenario_name, result)
    # Performance thresholds
    thresholds = {
      response_time_p95: 2000, # 2 seconds
      response_time_p99: 5000, # 5 seconds
      error_rate: 1.0,         # 1% error rate
      throughput_min: 10       # 10 requests/second minimum
    }
    
    issues = []
    
    # Check response time thresholds
    if result[:response_time_p95] > thresholds[:response_time_p95]
      issues << "95th percentile response time exceeded: #{result[:response_time_p95]}ms"
    end
    
    if result[:error_rate] > thresholds[:error_rate]
      issues << "Error rate exceeded threshold: #{result[:error_rate]}%"
    end
    
    if result[:throughput] < thresholds[:throughput_min]
      issues << "Throughput below minimum: #{result[:throughput]} req/sec"
    end
    
    # Log performance issues
    if issues.any?
      Rails.logger.performance "Load test issues for #{scenario_name}: #{issues.join(', ')}"
      
      # Create performance alerts
      PerformanceAlert.create!(
        alert_type: 'load_test_failure',
        scenario: scenario_name,
        issues: issues,
        test_results: result,
        created_at: Time.current
      )
    end
  end
end

# Capacity planning service
class CapacityPlanningService
  def self.analyze_current_capacity
    current_metrics = {
      api_servers: analyze_api_server_capacity,
      database: analyze_database_capacity,
      background_jobs: analyze_worker_capacity,
      cache_layer: analyze_cache_capacity
    }
    
    # Predict future capacity needs
    growth_projections = calculate_growth_projections
    capacity_recommendations = generate_capacity_recommendations(current_metrics, growth_projections)
    
    CapacityReport.create!(
      current_metrics: current_metrics,
      growth_projections: growth_projections,
      recommendations: capacity_recommendations,
      created_at: Time.current
    )
  end
  
  private
  
  def self.analyze_api_server_capacity
    {
      current_throughput: calculate_current_throughput,
      max_throughput: estimate_max_throughput,
      cpu_utilization: get_cpu_utilization,
      memory_utilization: get_memory_utilization,
      response_time_trends: analyze_response_time_trends
    }
  end
  
  def self.calculate_growth_projections
    # Analyze historical data to project future growth
    user_growth = analyze_user_growth_rate
    transaction_growth = analyze_transaction_growth_rate
    
    {
      user_growth_monthly: user_growth,
      transaction_growth_monthly: transaction_growth,
      projected_peak_load: calculate_projected_peak_load(user_growth, transaction_growth),
      capacity_timeline: generate_capacity_timeline
    }
  end
end
```

### Performance Testing Pipeline
```yaml
# .github/workflows/performance-testing.yml
name: Performance Testing

on:
  schedule:
    - cron: '0 2 * * 0' # Weekly performance tests
  workflow_dispatch:
    inputs:
      test_duration:
        description: 'Test duration in minutes'
        required: false
        default: '10'

jobs:
  performance-test:
    runs-on: ubuntu-latest
    environment: staging
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Test Environment
      run: |
        # Install performance testing tools
        sudo apt-get update
        sudo apt-get install -y apache2-utils wrk
    
    - name: Warm Up Application
      run: |
        # Warm up the staging environment
        curl -f $STAGING_URL/health
        curl -f $STAGING_URL/api/v1/status
    
    - name: Run Load Tests
      run: |
        # API endpoint load test
        ab -n 1000 -c 50 $STAGING_URL/api/v1/dashboard > ab-dashboard.txt
        
        # High concurrency test
        wrk -t12 -c400 -d30s $STAGING_URL/api/v1/health > wrk-results.txt
        
        # Subscription flow test
        ab -n 500 -c 25 -T application/json -p subscription-payload.json $STAGING_URL/api/v1/subscriptions > ab-subscription.txt
    
    - name: Analyze Results
      run: |
        # Extract key metrics
        echo "=== Dashboard Load Test Results ===" >> performance-report.txt
        grep -E "(Requests per second|Time per request|Transfer rate)" ab-dashboard.txt >> performance-report.txt
        
        echo "=== High Concurrency Test Results ===" >> performance-report.txt
        grep -E "(Requests/sec|Latency|Transfer/sec)" wrk-results.txt >> performance-report.txt
        
        # Check for performance degradation
        python3 scripts/analyze-performance.py ab-dashboard.txt wrk-results.txt
    
    - name: Upload Results
      uses: actions/upload-artifact@v3
      with:
        name: performance-test-results
        path: |
          ab-*.txt
          wrk-results.txt
          performance-report.txt
    
    - name: Performance Regression Check
      run: |
        # Compare with baseline performance metrics
        python3 scripts/performance-regression-check.py \
          --current-results performance-report.txt \
          --baseline-results baseline/performance-baseline.txt \
          --threshold 20  # 20% performance degradation threshold
```

## Frontend Performance Optimization

### Bundle Optimization
```typescript
// webpack.config.js performance optimization
const path = require('path');
const { BundleAnalyzerPlugin } = require('webpack-bundle-analyzer');
const CompressionPlugin = require('compression-webpack-plugin');

module.exports = {
  // Code splitting optimization
  optimization: {
    splitChunks: {
      chunks: 'all',
      cacheGroups: {
        // Vendor dependencies
        vendor: {
          test: /[\\/]node_modules[\\/]/,
          name: 'vendors',
          chunks: 'all',
          priority: 10
        },
        // Common components
        common: {
          name: 'common',
          minChunks: 2,
          chunks: 'all',
          priority: 5,
          enforce: true
        },
        // React/React-DOM in separate chunk
        react: {
          test: /[\\/]node_modules[\\/](react|react-dom)[\\/]/,
          name: 'react',
          chunks: 'all',
          priority: 20
        },
        // Chart.js and visualization libraries
        charts: {
          test: /[\\/]node_modules[\\/](chart\.js|chartjs-.*|d3|recharts)[\\/]/,
          name: 'charts',
          chunks: 'all',
          priority: 15
        }
      }
    },
    // Runtime chunk optimization
    runtimeChunk: 'single'
  },
  
  // Performance budgets
  performance: {
    hints: 'warning',
    maxEntrypointSize: 500000, // 500KB
    maxAssetSize: 250000,      // 250KB
    assetFilter: function(assetFilename) {
      return assetFilename.endsWith('.js') || assetFilename.endsWith('.css');
    }
  },
  
  plugins: [
    // Gzip compression
    new CompressionPlugin({
      filename: '[path][base].gz',
      algorithm: 'gzip',
      test: /\.(js|css|html|svg)$/,
      threshold: 8192,
      minRatio: 0.8
    }),
    
    // Bundle analysis in development
    process.env.NODE_ENV === 'development' && new BundleAnalyzerPlugin({
      analyzerMode: 'server',
      openAnalyzer: false
    })
  ].filter(Boolean)
};
```

### React Performance Optimization
```typescript
// Performance-optimized React components
import React, { memo, useMemo, useCallback, lazy, Suspense } from 'react';
import { debounce } from 'lodash';

// Lazy loading for heavy components
const DashboardCharts = lazy(() => import('./DashboardCharts'));
const ReportsTable = lazy(() => import('./ReportsTable'));

// Memoized components for expensive renders
export const OptimizedUserList = memo<UserListProps>(({ users, onUserSelect }) => {
  // Memoize expensive calculations
  const sortedUsers = useMemo(() => {
    return users.sort((a, b) => a.name.localeCompare(b.name));
  }, [users]);
  
  // Memoize callback functions
  const handleUserClick = useCallback((userId: string) => {
    onUserSelect(userId);
  }, [onUserSelect]);
  
  // Virtualization for large lists
  const renderUserItem = useCallback(({ index, style }) => (
    <div style={style} key={sortedUsers[index].id}>
      <UserItem 
        user={sortedUsers[index]} 
        onClick={handleUserClick}
      />
    </div>
  ), [sortedUsers, handleUserClick]);
  
  return (
    <div className="user-list">
      {/* Virtual scrolling for large datasets */}
      <FixedSizeList
        height={400}
        itemCount={sortedUsers.length}
        itemSize={60}
        itemData={sortedUsers}
      >
        {renderUserItem}
      </FixedSizeList>
    </div>
  );
});

// Performance monitoring hook
export const usePerformanceMonitor = (componentName: string) => {
  useEffect(() => {
    const startTime = performance.now();
    
    return () => {
      const endTime = performance.now();
      const renderTime = endTime - startTime;
      
      // Track render performance
      if (renderTime > 100) { // Alert on slow renders (>100ms)
        console.warn(`Slow render detected: ${componentName} took ${renderTime.toFixed(2)}ms`);
        
        // Send to analytics in production
        if (process.env.NODE_ENV === 'production') {
          analytics.track('slow_component_render', {
            component: componentName,
            render_time: renderTime
          });
        }
      }
    };
  }, [componentName]);
};

// Debounced search optimization
export const useOptimizedSearch = (searchFn: (query: string) => void, delay = 300) => {
  const debouncedSearch = useMemo(
    () => debounce(searchFn, delay),
    [searchFn, delay]
  );
  
  // Cleanup on unmount
  useEffect(() => {
    return () => {
      debouncedSearch.cancel();
    };
  }, [debouncedSearch]);
  
  return debouncedSearch;
};
```

### Image and Asset Optimization
```typescript
// Image optimization service
export class ImageOptimizationService {
  private static readonly SUPPORTED_FORMATS = ['webp', 'avif', 'jpeg', 'png'];
  private static readonly SIZE_BREAKPOINTS = [320, 640, 768, 1024, 1280, 1536];
  
  static generateResponsiveImageSrcSet(baseUrl: string, sizes: number[] = this.SIZE_BREAKPOINTS): string {
    return sizes
      .map(size => `${baseUrl}?w=${size}&q=80&fm=webp ${size}w`)
      .join(', ');
  }
  
  static generateOptimizedImageUrl(
    baseUrl: string, 
    options: {
      width?: number;
      height?: number;
      quality?: number;
      format?: string;
    } = {}
  ): string {
    const params = new URLSearchParams();
    
    if (options.width) params.append('w', options.width.toString());
    if (options.height) params.append('h', options.height.toString());
    if (options.quality) params.append('q', options.quality.toString());
    if (options.format) params.append('fm', options.format);
    
    return `${baseUrl}?${params.toString()}`;
  }
  
  // Lazy loading with intersection observer
  static setupLazyLoading(): void {
    if ('IntersectionObserver' in window) {
      const imageObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            const img = entry.target as HTMLImageElement;
            if (img.dataset.src) {
              img.src = img.dataset.src;
              img.classList.remove('lazy');
              observer.unobserve(img);
            }
          }
        });
      }, {
        rootMargin: '50px 0px', // Start loading 50px before image enters viewport
        threshold: 0.1
      });
      
      document.querySelectorAll('img[data-src]').forEach(img => {
        imageObserver.observe(img);
      });
    }
  }
}

// Optimized image component
export const OptimizedImage: React.FC<{
  src: string;
  alt: string;
  width?: number;
  height?: number;
  className?: string;
  lazy?: boolean;
}> = ({ src, alt, width, height, className, lazy = true }) => {
  const [isLoaded, setIsLoaded] = useState(false);
  const [error, setError] = useState(false);
  
  const optimizedSrc = useMemo(() => 
    ImageOptimizationService.generateOptimizedImageUrl(src, {
      width,
      height,
      quality: 80,
      format: 'webp'
    }),
    [src, width, height]
  );
  
  const srcSet = useMemo(() => 
    ImageOptimizationService.generateResponsiveImageSrcSet(src),
    [src]
  );
  
  return (
    <div className={`image-container ${className}`}>
      {!isLoaded && !error && (
        <div className="image-placeholder animate-pulse bg-theme-surface" />
      )}
      
      <img
        src={optimizedSrc}
        srcSet={srcSet}
        sizes="(max-width: 640px) 100vw, (max-width: 1024px) 50vw, 33vw"
        alt={alt}
        loading={lazy ? 'lazy' : 'eager'}
        onLoad={() => setIsLoaded(true)}
        onError={() => setError(true)}
        className={`transition-opacity duration-300 ${
          isLoaded ? 'opacity-100' : 'opacity-0'
        }`}
      />
      
      {error && (
        <div className="image-error bg-theme-error-background text-theme-error p-4">
          Failed to load image
        </div>
      )}
    </div>
  );
};
```

## Database Performance Optimization

### Query Optimization Strategies
```ruby
# Database optimization service
class DatabaseOptimizationService
  include ActiveModel::Model
  
  def self.optimize_common_queries
    optimization_reports = []
    
    # Optimize user lookup queries
    optimize_user_queries.each { |report| optimization_reports << report }
    
    # Optimize subscription queries
    optimize_subscription_queries.each { |report| optimization_reports << report }
    
    # Optimize payment queries
    optimize_payment_queries.each { |report| optimization_reports << report }
    
    # Optimize analytics queries
    optimize_analytics_queries.each { |report| optimization_reports << report }
    
    DatabaseOptimizationReport.create!(
      optimizations: optimization_reports,
      performed_at: Time.current
    )
  end
  
  private
  
  def self.optimize_user_queries
    reports = []
    
    # Add composite index for user lookups by email and status
    unless index_exists?(:users, [:email, :status])
      ActiveRecord::Migration.add_index :users, [:email, :status], 
        name: 'index_users_on_email_and_status'
      
      reports << {
        type: 'composite_index',
        table: 'users',
        columns: [:email, :status],
        impact: 'high',
        description: 'Optimizes user authentication and active user queries'
      }
    end
    
    # Add partial index for active users
    unless index_exists?(:users, :created_at, where: "status = 'active'")
      execute <<-SQL
        CREATE INDEX CONCURRENTLY index_active_users_on_created_at
        ON users (created_at)
        WHERE status = 'active';
      SQL
      
      reports << {
        type: 'partial_index',
        table: 'users',
        columns: [:created_at],
        condition: "status = 'active'",
        impact: 'medium',
        description: 'Optimizes queries for active user analytics'
      }
    end
    
    reports
  end
  
  def self.optimize_subscription_queries
    reports = []
    
    # Optimize subscription status queries
    unless index_exists?(:subscriptions, [:account_id, :status, :current_period_end])
      ActiveRecord::Migration.add_index :subscriptions, 
        [:account_id, :status, :current_period_end],
        name: 'index_subscriptions_comprehensive'
      
      reports << {
        type: 'composite_index',
        table: 'subscriptions',
        columns: [:account_id, :status, :current_period_end],
        impact: 'high',
        description: 'Optimizes subscription renewal and billing queries'
      }
    end
    
    reports
  end
  
  def self.optimize_payment_queries
    reports = []
    
    # Add index for payment processing queries
    unless index_exists?(:payments, [:status, :created_at])
      ActiveRecord::Migration.add_index :payments, [:status, :created_at],
        name: 'index_payments_on_status_and_created_at'
      
      reports << {
        type: 'composite_index',
        table: 'payments',
        columns: [:status, :created_at],
        impact: 'high',
        description: 'Optimizes payment status tracking and reporting'
      }
    end
    
    # Add index for failed payment retry logic
    unless index_exists?(:payments, :next_retry_at, where: "status = 'failed'")
      execute <<-SQL
        CREATE INDEX CONCURRENTLY index_failed_payments_on_retry_at
        ON payments (next_retry_at)
        WHERE status = 'failed';
      SQL
      
      reports << {
        type: 'partial_index',
        table: 'payments',
        columns: [:next_retry_at],
        condition: "status = 'failed'",
        impact: 'medium',
        description: 'Optimizes failed payment retry processing'
      }
    end
    
    reports
  end
end

# Connection pool optimization
class ConnectionPoolOptimizer
  def self.configure_optimal_pool
    # Calculate optimal pool size based on environment
    optimal_pool_size = calculate_optimal_pool_size
    
    ActiveRecord::Base.establish_connection(
      Rails.application.config.database_configuration[Rails.env].merge(
        pool: optimal_pool_size,
        checkout_timeout: 5,
        reaping_frequency: 10, # seconds
        dead_connection_timeout: 5
      )
    )
    
    Rails.logger.info "Configured database connection pool with #{optimal_pool_size} connections"
  end
  
  private
  
  def self.calculate_optimal_pool_size
    # Base calculation on expected concurrent requests
    base_size = ENV.fetch('MAX_THREADS', 5).to_i
    
    # Add buffer for background jobs
    worker_connections = ENV.fetch('SIDEKIQ_CONCURRENCY', 10).to_i
    
    # Total pool size with safety margin
    total_size = (base_size + worker_connections) * 1.2
    
    # Cap at reasonable maximum
    [total_size.to_i, 50].min
  end
end
```

### Database Monitoring & Alerting
```ruby
# Database performance monitoring
class DatabasePerformanceMonitor
  include ActiveModel::Model
  
  def self.monitor_database_health
    health_metrics = {
      connection_pool: analyze_connection_pool_health,
      query_performance: analyze_query_performance,
      lock_contention: analyze_lock_contention,
      index_usage: analyze_index_usage
    }
    
    # Generate alerts for performance issues
    performance_issues = detect_performance_issues(health_metrics)
    
    if performance_issues.any?
      DatabasePerformanceAlert.create!(
        alert_type: 'performance_degradation',
        metrics: health_metrics,
        issues: performance_issues,
        created_at: Time.current
      )
    end
    
    # Store metrics for trending
    DatabaseHealthMetric.create!(
      metrics: health_metrics,
      recorded_at: Time.current
    )
    
    health_metrics
  end
  
  private
  
  def self.analyze_connection_pool_health
    pool = ActiveRecord::Base.connection_pool
    
    {
      size: pool.size,
      available: pool.available_connection_count,
      active: pool.size - pool.available_connection_count,
      utilization: ((pool.size - pool.available_connection_count).to_f / pool.size * 100).round(2)
    }
  end
  
  def self.analyze_query_performance
    # Analyze slow queries from database logs
    slow_queries = fetch_recent_slow_queries
    
    {
      slow_query_count: slow_queries.count,
      average_slow_query_time: calculate_average_query_time(slow_queries),
      slowest_query: find_slowest_query(slow_queries),
      most_frequent_slow_table: find_most_queried_table(slow_queries)
    }
  end
  
  def self.analyze_lock_contention
    # Query database for lock information
    lock_stats = execute_lock_analysis_query
    
    {
      active_locks: lock_stats[:active_locks],
      waiting_queries: lock_stats[:waiting_queries],
      deadlock_count: lock_stats[:deadlock_count],
      max_lock_wait_time: lock_stats[:max_wait_time]
    }
  end
  
  def self.detect_performance_issues(metrics)
    issues = []
    
    # Check connection pool utilization
    if metrics[:connection_pool][:utilization] > 80
      issues << {
        type: 'high_connection_pool_utilization',
        severity: 'high',
        message: "Connection pool utilization at #{metrics[:connection_pool][:utilization]}%"
      }
    end
    
    # Check for excessive slow queries
    if metrics[:query_performance][:slow_query_count] > 50
      issues << {
        type: 'excessive_slow_queries',
        severity: 'medium',
        message: "#{metrics[:query_performance][:slow_query_count]} slow queries detected"
      }
    end
    
    # Check for lock contention
    if metrics[:lock_contention][:waiting_queries] > 10
      issues << {
        type: 'lock_contention',
        severity: 'high',
        message: "#{metrics[:lock_contention][:waiting_queries]} queries waiting for locks"
      }
    end
    
    issues
  end
end
```

## Development Commands

### Performance Testing Commands
```bash
# Application performance testing
cd $POWERNODE_ROOT/server && bundle exec rspec --tag performance     # Performance test suite
cd $POWERNODE_ROOT/frontend && npm run test:performance              # Frontend performance tests

# Load testing
ab -n 1000 -c 50 http://localhost:3000/api/v1/health    # Simple load test
wrk -t12 -c400 -d30s http://localhost:3000/            # High concurrency test

# Database performance
cd $POWERNODE_ROOT/server && rails runner "DatabaseOptimizationService.optimize_common_queries"
cd $POWERNODE_ROOT/server && rails runner "DatabasePerformanceMonitor.monitor_database_health"

# Cache performance
cd $POWERNODE_ROOT/server && rails runner "CachePerformanceMonitor.optimize_cache_usage"
redis-cli info memory                                # Redis memory usage
```

### Performance Analysis
```bash
# Memory profiling
cd $POWERNODE_ROOT/server && bundle exec ruby-prof --printer=graph --file=profile.html script/performance_test.rb

# Frontend bundle analysis
cd $POWERNODE_ROOT/frontend && npm run analyze                       # Webpack bundle analyzer
cd $POWERNODE_ROOT/frontend && npm run lighthouse                    # Lighthouse performance audit

# Database query analysis
cd $POWERNODE_ROOT/server && rails runner "QueryAnalyzer.analyze_recent_queries"
```

### Optimization Commands
```bash
# Asset optimization
cd $POWERNODE_ROOT/frontend && npm run build:optimized              # Optimized production build
cd $POWERNODE_ROOT/frontend && npm run optimize:images              # Image optimization

# Database optimization
cd $POWERNODE_ROOT/server && rails db:migrate:with_data             # Run migrations with data optimization
cd $POWERNODE_ROOT/server && bundle exec rails runner "ActiveRecord::Base.connection.execute('ANALYZE;')"
```

## Integration Points

### Platform Architect Coordination
- **Performance Requirements**: Define and validate system performance targets
- **Architecture Optimization**: Recommend architectural changes for performance improvements
- **Scaling Strategy**: Coordinate infrastructure scaling decisions based on performance data
- **Resource Planning**: Provide performance data for capacity and resource planning

### DevOps Engineer Integration
- **Infrastructure Scaling**: Collaborate on auto-scaling configurations and resource optimization
- **Monitoring Setup**: Configure performance monitoring and alerting in deployment pipelines
- **Load Testing Integration**: Integrate performance testing into CI/CD workflows
- **Resource Optimization**: Optimize container resources and Kubernetes configurations

### Backend/Frontend Specialist Integration
- **Code Optimization**: Identify and resolve performance bottlenecks in application code
- **Database Optimization**: Optimize queries, indexes, and database interactions
- **Caching Strategy**: Implement and optimize multi-layer caching across all components
- **API Performance**: Optimize API response times and throughput

## Quick Reference

### Performance Targets
```bash
# API Performance Targets
□ Response Time: < 200ms (95th percentile)
□ Throughput: > 1000 requests/second
□ Error Rate: < 0.1%
□ Database Query Time: < 100ms average

# Frontend Performance Targets  
□ First Contentful Paint: < 1.5s
□ Largest Contentful Paint: < 2.5s
□ Cumulative Layout Shift: < 0.1
□ First Input Delay: < 100ms

# Infrastructure Performance Targets
□ CPU Utilization: < 70% average
□ Memory Utilization: < 80%
□ Database Connection Pool: < 80% utilization
□ Cache Hit Rate: > 90%
```

### Critical Performance Commands
```bash
# Real-time performance monitoring
rails runner "PerformanceMonitor.current_metrics"   # Application metrics
redis-cli info stats                                # Redis performance
kubectl top pods --sort-by=memory                  # Container resource usage

# Performance optimization
rails runner "DatabaseOptimizationService.optimize_common_queries"
rails runner "CacheOptimizationService.optimize_cache_keys"
npm run build:analyze                               # Frontend bundle analysis
```

### Emergency Performance Response
- **High Response Times**: Scale horizontally and check database queries
- **Memory Issues**: Restart services and optimize memory usage
- **Database Bottlenecks**: Add read replicas and optimize queries
- **Cache Performance**: Clear cache and optimize cache keys
- **Frontend Issues**: Enable CDN caching and optimize bundles