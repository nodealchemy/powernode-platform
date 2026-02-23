# frozen_string_literal: true

require_relative "boot"
require_relative "version"

# Only require necessary Rails components for API-only application
require "rails"

# Core components needed for API functionality
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "active_job/railtie"
require "rails/test_unit/railtie"

# ActionCable needed for real-time broadcasting functionality
begin
  require "action_cable/engine"
rescue LoadError
  # ActionCable not available, create stub for tests
  module ActionCable
    class Connection
      class Base; end
    end
    class Channel
      class Base; end
    end
    def self.server
      @server ||= Object.new.tap do |obj|
        def obj.broadcast(channel, data); end
      end
    end
  end
end

# Skip ActionText, ActionMailbox, ActionView, and ActiveStorage
# These are not needed for API-only applications

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Server
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])


    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Add cookie middleware for HttpOnly refresh token cookies (WP8 security hardening)
    config.middleware.use ActionDispatch::Cookies

    # Track boot time for uptime calculations
    config.boot_time = Time.current

    # Application version configuration
    config.version = Powernode::Version.current

    # Configure Redis for caching and session store
    if Rails.env.production? || ENV["REDIS_URL"]
      config.cache_store = :redis_cache_store, { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
    else
      config.cache_store = :memory_store
    end

    # CSRF Protection Configuration for API
    config.x.csrf_protection_enabled = false # Disabled by default, can be enabled via admin settings
    config.x.csrf_token_expiry = 2.hours
    config.x.csrf_token_header_name = "X-CSRF-Token"
    config.x.csrf_allow_parameter = false # API should use headers only
    config.x.csrf_require_ssl = Rails.env.production? # Require HTTPS in production

    # Add worker activity tracking middleware
    require Rails.root.join("app/middleware/worker_activity_tracker")
    config.middleware.use WorkerActivityTracker

    # Add proxy security validator middleware
    require Rails.root.join("app/middleware/proxy_security_validator")
    config.middleware.use ProxySecurityValidator

    # Add request inspector for DDoS protection (only in production/staging)
    if Rails.env.production? || Rails.env.staging? || ENV["ENABLE_DDOS_PROTECTION"] == "true"
      require Rails.root.join("app/middleware/request_inspector")
      config.middleware.use RequestInspector
    end

    # Add security headers middleware for all responses
    require Rails.root.join("app/middleware/security_headers")
    config.middleware.use SecurityHeaders
  end
end
