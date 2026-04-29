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

# Merge extension schedules into the Sidekiq config's :scheduler section.
# sidekiq-scheduler reads config[:scheduler][:schedule] during its startup
# callback and handles symbol→string key conversion internally via
# Utils.stringify_keys, so we don't need to pre-stringify here.
#
# Disabled extensions (per config/extensions_state.json) are skipped so the
# scheduler doesn't enqueue jobs whose classes aren't loaded — that would
# otherwise produce a flood of "uninitialized constant" NameError retries.
worker_root = File.expand_path('..', __dir__)
extensions_dir = File.join(worker_root, '..', 'extensions')
disabled_extensions_for_cron = begin
  state_file = File.join(worker_root, '..', 'config', 'extensions_state.json')
  if File.exist?(state_file)
    Array(JSON.parse(File.read(state_file))['disabled']).map(&:to_s)
  else
    []
  end
rescue JSON::ParserError, IOError, SystemCallError
  []
end

if Dir.exist?(extensions_dir)
  Dir.children(extensions_dir).sort.each do |slug|
    next if disabled_extensions_for_cron.include?(slug)

    Dir[File.join(extensions_dir, slug, 'worker', 'config', 'sidekiq_*.yml')].each do |yml|
      Sidekiq.configure_server do |config|
        ext_yaml = YAML.safe_load(ERB.new(File.read(yml)).result, permitted_classes: [Symbol])
        if ext_yaml&.dig(:schedule)
          scheduler_config = config[:scheduler] ||= {}
          schedule = scheduler_config[:schedule] ||= {}
          ext_yaml[:schedule].each { |k, v| schedule[k] = v }
        end
      end
    end
  end
end

Sidekiq.configure_server do |config|
  concurrency = ENV.fetch('WORKER_CONCURRENCY', '25').to_i
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'), size: concurrency + 10 }

  # Fast shutdown: on SIGTERM, signal training sessions to exit their tick loop
  # immediately instead of waiting for Sidekiq's 300s timeout.
  # Also stop venue WS managers to prevent reconnect loops during shutdown.
  # Guarded with defined? so the worker boots without the trading extension.
  config.on(:quiet) do
    TradingTrainingSessionJob.shutdown_requested! if defined?(TradingTrainingSessionJob)
    Trading::KalshiWsManager.instance.force_stop! rescue nil if defined?(Trading::KalshiWsManager)
    Trading::PolymarketWsManager.instance.force_stop! rescue nil if defined?(Trading::PolymarketWsManager)
  end

  # Fast recovery: on startup, dispatch pending sessions via the runner and
  # evaluate paused sessions via the overseer — no wait for the next cron tick.
  # Also re-dispatch runners for active live strategies (they die on restart).
  # The 3s sleep lets Redis and HTTP connections establish first.
  # Guarded with defined? so the worker boots without the trading extension.
  config.on(:startup) do
    TradingTrainingSessionJob.reset_shutdown_flag! if defined?(TradingTrainingSessionJob)
    Thread.new do
      sleep 3

      # Clear stale runner locks from the old process — they reference dead JIDs
      Sidekiq.redis do |conn|
        conn.keys("strategy_runner_lock:*").each { |k| conn.del(k) }
        conn.keys("job_disabled:TradingStrategyRunnerJob:*").each { |k| conn.del(k) }
        conn.keys("job_executions:TradingStrategyRunnerJob:*").each { |k| conn.del(k) }
      end

      TradingTrainingSessionRunnerJob.perform_async if defined?(TradingTrainingSessionRunnerJob)
      TradingSessionManagerCycleJob.perform_async if defined?(TradingSessionManagerCycleJob)
      TradingPortfolioManagerCycleJob.perform_async if defined?(TradingPortfolioManagerCycleJob)
      TradingProvingGroundManagerCycleJob.perform_async if defined?(TradingProvingGroundManagerCycleJob)
    rescue StandardError => e
      PowernodeWorker.logger.warn("[StartupHook] Startup recovery dispatch failed: #{e.message}")
    end
  end
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