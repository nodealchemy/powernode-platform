# frozen_string_literal: true

# Prometheus metrics configuration for Powernode Platform
# Disabled for development - only test environment stubs remain
if Rails.env.test? || true  # Force disable Prometheus
  # Test environment - create stub module
  module PowernodeMetrics
    def self.method_missing(method, *args, &block)
      # Return a stub object that responds to common methods
      stub = Object.new
      def stub.observe(*args); end
      stub
    end
    
    def self.track_api_request(*args); end
    def self.track_payment(*args); end
    def self.track_authentication(*args); end
    def self.track_webhook(*args); end
    def self.track_background_job(*args); end
    def self.update_subscription_metrics; end
    def self.update_user_metrics; end
    def self.update_revenue_metrics; end
  end

  # Stub middleware for tests
  class MetricsMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    end
  end
else
  # Production/Development environment
  require 'prometheus_exporter/server'
  require 'prometheus_exporter/client'
  require 'prometheus_exporter/instrumentation'

  # Configure Prometheus exporter
  begin
    PrometheusExporter::Client.default = PrometheusExporter::LocalClient.new
  rescue => e
    Rails.logger.warn "Failed to initialize Prometheus exporter: #{e.message}"
  end

  # Custom metrics registry
  module PowernodeMetrics
    extend self

    # Business metrics
    def self.subscription_gauge
      @subscription_gauge ||= PrometheusExporter::Client.default.register(:gauge, 
        "powernode_subscriptions_total", 
        "Total number of active subscriptions",
        [:status, :plan_name]
      )
    end

    def self.user_gauge
      @user_gauge ||= PrometheusExporter::Client.default.register(:gauge,
        "powernode_users_total",
        "Total number of users",
        [:status, :role]
      )
    end

    def self.payment_counter
      @payment_counter ||= PrometheusExporter::Client.default.register(:counter,
        "powernode_payments_total",
        "Total number of payments processed",
        [:status, :provider, :amount_range]
      )
    end

    def self.api_request_counter
      @api_request_counter ||= PrometheusExporter::Client.default.register(:counter,
        "powernode_api_requests_total",
        "Total API requests",
        [:method, :endpoint, :status]
      )
    end

    def self.api_response_time
      @api_response_time ||= PrometheusExporter::Client.default.register(:histogram,
        "powernode_api_response_time_seconds",
        "API response time in seconds",
        [:method, :endpoint],
        buckets: [0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
      )
    end

    def self.background_job_counter
      @background_job_counter ||= PrometheusExporter::Client.default.register(:counter,
        "powernode_background_jobs_total",
        "Total background jobs processed",
        [:job_class, :status, :queue]
      )
    end

    def self.background_job_duration
      @background_job_duration ||= PrometheusExporter::Client.default.register(:histogram,
        "powernode_background_job_duration_seconds",
        "Background job execution time",
        [:job_class, :queue],
        buckets: [0.1, 0.5, 1.0, 5.0, 10.0, 30.0, 60.0]
      )
    end

    def self.subscription_revenue_gauge
      @subscription_revenue_gauge ||= PrometheusExporter::Client.default.register(:gauge,
        "powernode_subscription_revenue_dollars",
        "Total subscription revenue in dollars",
        [:period, :plan_name]
      )
    end

    def self.authentication_counter
      @authentication_counter ||= PrometheusExporter::Client.default.register(:counter,
        "powernode_authentication_attempts_total",
        "Authentication attempts",
        [:status, :method]
      )
    end

    def self.webhook_counter
      @webhook_counter ||= PrometheusExporter::Client.default.register(:counter,
        "powernode_webhook_events_total",
        "Webhook events received",
        [:provider, :event_type, :status]
      )
    end

    # Update business metrics
    def self.update_subscription_metrics
      Subscription.joins(:plan).group(:status, 'plans.name').count.each do |(status, plan_name), count|
        subscription_gauge.observe(count, status: status, plan_name: plan_name || 'unknown')
      end
    end

    def self.update_user_metrics
      User.joins(:roles).group(:status, 'roles.name').count.each do |(status, role), count|
        user_gauge.observe(count, status: status || 'active', role: role || 'member')
      end
    end

    def self.update_revenue_metrics
      # Monthly revenue
      monthly_revenue = Subscription.active
                                   .joins(:plan)
                                   .group('plans.name')
                                   .sum('plans.price_cents')
      
      monthly_revenue.each do |plan_name, revenue|
        subscription_revenue_gauge.observe(
          revenue.to_f / 100, # Convert cents to dollars
          period: 'monthly',
          plan_name: plan_name
        )
      end

      # Annual revenue projection
      annual_revenue = monthly_revenue.transform_values { |v| v * 12 }
      annual_revenue.each do |plan_name, revenue|
        subscription_revenue_gauge.observe(
          revenue.to_f / 100,
          period: 'annual',
          plan_name: plan_name
        )
      end
    end

    # Track API request
    def self.track_api_request(method, endpoint, status, duration)
      api_request_counter.observe(1, method: method, endpoint: endpoint, status: status)
      api_response_time.observe(duration, method: method, endpoint: endpoint)
    end

    # Track payment
    def self.track_payment(status, provider, amount_cents)
      amount_range = case amount_cents
                     when 0..999 then 'under_10'
                     when 1000..4999 then '10_to_50'
                     when 5000..9999 then '50_to_100'
                     when 10000..49999 then '100_to_500'
                     else 'over_500'
                     end
      
      payment_counter.observe(1, 
        status: status, 
        provider: provider, 
        amount_range: amount_range
      )
    end

    # Track authentication
    def self.track_authentication(status, method = 'password')
      authentication_counter.observe(1, status: status, method: method)
    end

    # Track webhook
    def self.track_webhook(provider, event_type, status)
      webhook_counter.observe(1, 
        provider: provider, 
        event_type: event_type, 
        status: status
      )
    end

    # Track background job
    def self.track_background_job(job_class, status, queue, duration = nil)
      background_job_counter.observe(1, 
        job_class: job_class, 
        status: status, 
        queue: queue
      )
      
      if duration
        background_job_duration.observe(duration, 
          job_class: job_class, 
          queue: queue
        )
      end
    end
  end

  # Middleware for API request tracking
  class MetricsMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      start_time = Time.current
      
      status, headers, response = @app.call(env)
      
      duration = Time.current - start_time
      method = env['REQUEST_METHOD']
      path = env['PATH_INFO']
      
      # Normalize endpoint for metrics (remove IDs)
      endpoint = normalize_endpoint(path)
      
      PowernodeMetrics.track_api_request(method, endpoint, status.to_s, duration)
      
      [status, headers, response]
    end

    private

    def normalize_endpoint(path)
      path.gsub(/\/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/, '/:id')
          .gsub(/\/\d+/, '/:id')
          .gsub(/\/[a-f0-9]+/, '/:id')
    end
  end

  # Schedule periodic metric updates
  if defined?(Rails::Server) || Rails.env.production?
    Thread.new do
      loop do
        begin
          PowernodeMetrics.update_subscription_metrics
          PowernodeMetrics.update_user_metrics
          PowernodeMetrics.update_revenue_metrics
        rescue => e
          Rails.logger.error "Error updating metrics: #{e.message}"
        end
        
        sleep 60 # Update every minute
      end
    end
  end
end