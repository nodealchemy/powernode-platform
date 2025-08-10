require_relative 'boot'

# Main application class for Powernode Worker Service
class PowernodeWorker
  def self.application
    @application ||= new
  end

  def initialize
    @root = File.expand_path('..', __dir__)
    load_environment
    setup_sidekiq
    setup_logging
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
    
    Sidekiq.configure_server do |config|
      config.redis = { 
        url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
        size: 20
      }
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

  def setup_service_authentication
    # Ensure service token is available
    unless config.service_token
      @logger.error "SERVICE_TOKEN not configured - worker cannot authenticate with backend"
      exit 1
    end
    
    @logger.info "Worker service authentication configured"
  end

  # Configuration class
  class Configuration
    def initialize
      @backend_api_url = ENV.fetch('BACKEND_API_URL', 'http://localhost:3000')
      @service_token = ENV['SERVICE_TOKEN']
      @sidekiq_web_port = ENV.fetch('SIDEKIQ_WEB_PORT', '4567')
      @worker_concurrency = ENV.fetch('WORKER_CONCURRENCY', '5').to_i
      @worker_queues = ENV.fetch('WORKER_QUEUES', 'default,reports,billing,webhooks').split(',')
    end

    attr_reader :backend_api_url, :service_token, :sidekiq_web_port, 
                :worker_concurrency, :worker_queues

    def api_timeout
      ENV.fetch('API_TIMEOUT', '30').to_i
    end

    def max_retry_attempts
      ENV.fetch('MAX_RETRY_ATTEMPTS', '3').to_i
    end
  end
end