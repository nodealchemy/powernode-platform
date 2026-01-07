# frozen_string_literal: true

require_relative 'boot'

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
    setup_sidekiq
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

  def setup_sidekiq
    require 'sidekiq'
    require 'sidekiq/web'
    require 'sidekiq-scheduler'

    Sidekiq.configure_server do |config|
      config.redis = {
        url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
        size: 20
      }

      # Load scheduler configuration from sidekiq.yml
      config.on(:startup) do
        schedule_file = File.join(@root || File.expand_path('../..', __dir__), 'config', 'sidekiq.yml')
        if File.exist?(schedule_file)
          Sidekiq.schedule = YAML.safe_load(ERB.new(File.read(schedule_file)).result, permitted_classes: [Symbol], aliases: true).fetch(:schedule, {})
          SidekiqScheduler::Scheduler.instance.reload_schedule!
        end
      end
    end

    Sidekiq.configure_client do |config|
      config.redis = {
        url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
        size: 5
      }
    end

    # Configure Sidekiq web interface with custom authentication
    Sidekiq::Web.use(SidekiqWebAuth)
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
    # Ensure service token is available
    unless config.worker_token
      @logger.error "WORKER_TOKEN not configured - worker cannot authenticate with backend"
      exit 1
    end
    
    @logger.info "Worker service authentication configured"
  end

  # Configuration class
  class Configuration
    def initialize
      @backend_api_url = ENV.fetch('BACKEND_API_URL', 'http://localhost:3000')
      @worker_token = ENV['WORKER_TOKEN']
      @sidekiq_web_port = ENV.fetch('SIDEKIQ_WEB_PORT', '4567')
      @worker_concurrency = ENV.fetch('WORKER_CONCURRENCY', '5').to_i
      @worker_queues = ENV.fetch('WORKER_QUEUES', 'default,reports,billing,webhooks').split(',')
    end

    attr_reader :backend_api_url, :worker_token, :sidekiq_web_port, 
                :worker_concurrency, :worker_queues

    def api_timeout
      ENV.fetch('API_TIMEOUT', '120').to_i
    end

    def max_retry_attempts
      ENV.fetch('MAX_RETRY_ATTEMPTS', '3').to_i
    end
  end
end