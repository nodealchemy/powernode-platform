# frozen_string_literal: true

require_relative 'boot'

# Sidekiq and sidekiq-scheduler MUST be required at the top level so that
# sidekiq-scheduler's Sidekiq.configure_server block runs during boot and
# registers its startup callback. If deferred into a method (e.g. inside
# PowernodeWorker#initialize), the callback is never registered because
# Sidekiq CLI never instantiates the class — it just requires this file.
require 'sidekiq'
require 'sidekiq/web'
require 'sidekiq-scheduler'

# Merge enterprise billing schedules into the Sidekiq config's :scheduler
# section. sidekiq-scheduler reads config[:scheduler][:schedule] during its
# startup callback and handles symbol→string key conversion internally via
# Utils.stringify_keys, so we don't need to pre-stringify here.
worker_root = File.expand_path('..', __dir__)
enterprise_file = File.join(worker_root, '..', 'extensions', 'enterprise', 'worker', 'config', 'sidekiq_billing.yml')
if File.exist?(enterprise_file)
  Sidekiq.configure_server do |config|
    billing_yaml = YAML.safe_load(ERB.new(File.read(enterprise_file)).result, permitted_classes: [Symbol])
    if billing_yaml&.dig(:schedule)
      scheduler_config = config[:scheduler] ||= {}
      schedule = scheduler_config[:schedule] ||= {}
      billing_yaml[:schedule].each { |k, v| schedule[k] = v }
    end
  end
end

Sidekiq.configure_server do |config|
  concurrency = ENV.fetch('WORKER_CONCURRENCY', '25').to_i
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'), size: concurrency + 5 }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'), size: 5 }
end

# Configure Sidekiq web interface with custom authentication
Sidekiq::Web.use(SidekiqWebAuth)

# Main application class for Powernode Worker Service
class PowernodeWorker
  def self.application
    @application ||= new
  end

  # Convenience class method to access logger
  def self.logger
    application.logger
  end

  def initialize
    @root = File.expand_path('..', __dir__)
    load_environment
    setup_logging
    setup_action_mailer
    setup_service_authentication
  end

  attr_reader :root

  def env
    ENV['WORKER_ENV'] || ENV['RAILS_ENV'] || 'development'
  end

  def config
    @config ||= Configuration.new
  end

  def logger
    @logger
  end

  private

  def load_environment
    require 'dotenv'
    Dotenv.load(File.join(@root, '.env'), File.join(@root, ".env.#{env}"))
  end

  def setup_logging
    require 'logger'
    log_level = env == 'development' ? Logger::DEBUG : Logger::INFO
    
    @logger = Logger.new(STDOUT)
    @logger.level = log_level
    @logger.formatter = proc do |severity, datetime, progname, msg|
      "[#{datetime}] #{severity} [WORKER] [#{progname}] #{msg}\n"
    end
    
    # Note: Sidekiq 7+ doesn't support setting logger directly
    # Sidekiq will use its own logger configuration
  end

  def setup_action_mailer
    # Configure ActionMailer for standalone worker
    ActionMailer::Base.view_paths = [File.join(@root, 'app', 'views')]
    ActionMailer::Base.logger = @logger
    
    # Configure delivery method based on environment
    if env == 'test'
      # In test environment, use test delivery method (emails stored in memory, not sent)
      ActionMailer::Base.delivery_method = :test
      ActionMailer::Base.perform_deliveries = true
      ActionMailer::Base.raise_delivery_errors = false
      @logger.info "ActionMailer configured for test environment (delivery simulation)"
    else
      # In development/production, emails will be sent via configured provider
      ActionMailer::Base.delivery_method = :smtp # This will be overridden by EmailConfigurationService
      ActionMailer::Base.perform_deliveries = true
      ActionMailer::Base.raise_delivery_errors = true
      @logger.info "ActionMailer configured for #{env} environment (real email delivery)"
    end
  end

  def setup_service_authentication
    # Validate required environment variables
    required_env_vars = {
      'WORKER_ID' => config.worker_id,
      'JWT_SECRET_KEY' => config.jwt_secret_key,
      'BACKEND_API_URL' => config.backend_api_url,
      'REDIS_URL' => ENV['REDIS_URL']
    }

    missing_vars = required_env_vars.select { |_, v| v.blank? }.keys

    if missing_vars.any?
      @logger.error "Missing required environment variables: #{missing_vars.join(', ')}"
      @logger.error "Worker cannot start without these configurations"
      exit 1 unless %w[development test].include?(env)
    end

    @logger.info "Worker service authentication configured (JWT mode)"
  end

  # Configuration class
  class Configuration
    def initialize
      @backend_api_url = ENV.fetch('BACKEND_API_URL', 'http://localhost:3000')
      @worker_id = ENV['WORKER_ID']
      @jwt_secret_key = ENV['JWT_SECRET_KEY']
      @sidekiq_web_port = ENV.fetch('SIDEKIQ_WEB_PORT', '4567')
      @worker_concurrency = ENV.fetch('WORKER_CONCURRENCY', '5').to_i
      @worker_queues = ENV.fetch('WORKER_QUEUES', 'default,reports,billing,webhooks').split(',')
    end

    attr_reader :backend_api_url, :worker_id, :jwt_secret_key, :sidekiq_web_port,
                :worker_concurrency, :worker_queues

    def api_timeout
      ENV.fetch('API_TIMEOUT', '120').to_i
    end

    def max_retry_attempts
      ENV.fetch('MAX_RETRY_ATTEMPTS', '3').to_i
    end
  end
end