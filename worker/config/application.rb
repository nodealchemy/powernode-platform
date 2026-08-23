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

# Extensions live flat under extensions/<slug>; private ones under
# extensions/private/<slug>. "private" is a grouping dir, never a slug.
extension_specs = []
if Dir.exist?(extensions_dir)
  Dir.children(extensions_dir).sort.each do |s|
    next if s == 'private'
    extension_specs << [extensions_dir, s]
  end
  private_dir = File.join(extensions_dir, 'private')
  if Dir.exist?(private_dir)
    Dir.children(private_dir).sort.each { |s| extension_specs << [private_dir, s] }
  end
end

unless extension_specs.empty?
  extension_specs.each do |ext_root, slug|
    next if disabled_extensions_for_cron.include?(slug)

    Dir[File.join(ext_root, slug, 'worker', 'config', 'sidekiq_*.yml')].each do |yml|
      Sidekiq.configure_server do |config|
        ext_yaml = YAML.safe_load(ERB.new(File.read(yml)).result, permitted_classes: [Symbol])
        if ext_yaml&.dig(:schedule)
          scheduler_config = config[:scheduler] ||= {}
          schedule = scheduler_config[:schedule] ||= {}
          ext_yaml[:schedule].each { |k, v| schedule[k] = v }
        end

        # Extensions may also contribute Sidekiq queues to the main worker's
        # default capsule — the same generic seam as schedules. Core names none.
        if ext_yaml&.dig(:queues)
          config[:queues] ||= []
          ext_yaml[:queues].each { |q| config[:queues] << q unless config[:queues].include?(q) }
        end
      end
    end

    # Generic extension worker-lifecycle seam: an extension may ship a
    # worker/config/lifecycle.rb that registers its own Sidekiq on(:startup)/
    # on(:quiet) callbacks (e.g. venue WS-manager shutdown, startup recovery).
    # Its worker classes are already loaded by config/boot.rb. Core names no
    # specific extension here.
    lifecycle = File.join(ext_root, slug, 'worker', 'config', 'lifecycle.rb')
    load lifecycle if File.exist?(lifecycle)
  end
end

Sidekiq.configure_server do |config|
  concurrency = ENV.fetch('WORKER_CONCURRENCY', '25').to_i
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'), size: concurrency + 10 }

  # Dedicated capsule for long-running codebase-intelligence jobs
  # (AiCodebaseIndexJob / AiCodeAnalysisJob → index, prune_stale).
  # Its own thread pool isolates these multi-minute, embedding-heavy scans from
  # the main pool, so a long index never head-of-line-blocks other queues.
  # Concurrency 1 serializes code-intel work (the index completes before any
  # analysis runs) which also prevents concurrent scans from contending on the
  # pgvector HNSW index. Override with CODE_INTEL_CONCURRENCY.
  config.capsule("code_intel") do |cap|
    cap.concurrency = ENV.fetch('CODE_INTEL_CONCURRENCY', '1').to_i
    cap.queues = %w[code_intel]
  end

  # Sidekiq's DEFAULT error handler logs the whole job hash — args included — on
  # every raised job exception. That is a job-argument log sink separate from the
  # ones BaseJob and JobsController own, and Sidekiq owns its own logger config
  # (see setup_logging), so it must be cleaned at the context. The logic lives in
  # JobArgRedaction because this block does not run under RSpec.
  default_error_handlers = config.error_handlers.dup
  config.error_handlers.replace([
    lambda do |exception, ctx, cfg|
      safe_ctx = JobArgRedaction.sanitize_context(ctx)
      default_error_handlers.each { |handler| handler.call(exception, safe_ctx, cfg) }
    end
  ])
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