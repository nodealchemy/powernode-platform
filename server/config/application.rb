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

    # Track boot time for uptime calculations
    config.boot_time = Time.current

    # Configure Redis for caching and session store
    if Rails.env.production? || ENV['REDIS_URL']
      config.cache_store = :redis_cache_store, { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
    else
      config.cache_store = :memory_store
    end
  end
end
