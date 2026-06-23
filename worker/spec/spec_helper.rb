# frozen_string_literal: true

ENV['WORKER_ENV'] ||= 'test'
ENV['RAILS_ENV'] = 'test'

require 'bundler/setup'
require 'rspec'
require 'webmock/rspec'
require 'vcr'
require 'sidekiq'
require 'sidekiq/testing'

# Load the worker application
require_relative '../config/application'

# Configure test environment
PowernodeWorker.application.logger.level = Logger::ERROR

# Load support files
Dir[File.join(__dir__, 'support', '*.rb')].sort.each { |file| require file }

# Configure Sidekiq for testing
Sidekiq::Testing.fake! # Jobs don't run by default in tests

RSpec.configure do |config|
  # RSpec configuration
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # Test hooks
  config.before(:suite) do
    # Clear all jobs before running tests
    Sidekiq::Worker.clear_all
  end

  config.before(:each) do
    # Clear jobs between tests
    Sidekiq::Worker.clear_all
    # Reset WebMock stubs
    WebMock.reset!
    # Reset circuit breaker to prevent OPEN state from blocking subsequent tests
    CircuitBreaker::CircuitBreakerRegistry.instance.reset_breaker('backend_api')
  end

  config.after(:each) do
    # Clean up any remaining jobs
    Sidekiq::Worker.clear_all
  end

  # Include custom helpers
  config.include WorkerTestHelpers
  config.include ApiTestHelpers
  config.include JobTestHelpers
end

# Configure WebMock - disable all real HTTP connections to force stub usage
WebMock.disable_net_connect!

# --- Extension worker-spec discovery (generic seam) --------------------------
# Extensions keep their worker specs in-tree (extensions/<slug>/worker/spec),
# mirroring extension isolation — their jobs are already autoloaded by
# config/boot.rb. RSpec's default path only covers worker/spec, so on a full
# suite run we require each ENABLED extension's worker specs here. Enumeration
# mirrors config/boot.rb exactly: flat extensions/<slug> + extensions/private/<slug>
# ("private" is a grouping dir, never a slug), skipping anything disabled in
# config/extensions_state.json and any extension without components.worker.
#
# Skipped when the invocation names explicit files/dirs, so targeted runs stay
# fast and never double-load a spec the developer pointed at directly. To run a
# single extension's worker specs, pass its path, e.g.:
#   bundle exec rspec ../extensions/supply-chain/worker/spec
def private_extensions_active?
  return true if ENV['POWERNODE_INCLUDE_PRIVATE_EXTENSIONS'].to_s == '1'

  gemfile = defined?(Bundler) ? Bundler.default_gemfile.to_s : ''
  gemfile.end_with?('Gemfile.private')
rescue StandardError
  false
end

def load_extension_worker_specs
  # "Targeted" = an explicit existing file/dir path was passed positionally. We
  # deliberately test File.exist? (not a name/glob match) so option VALUES that
  # look spec-ish (e.g. --exclude-pattern '**/foo_spec.rb', --seed 123) don't
  # count — only real paths the developer pointed rspec at. A targeted run runs
  # exactly what was named (and never double-loads an ext spec named directly).
  targeted = ARGV.any? { |arg| arg !~ /\A-/ && File.exist?(arg) }
  return if targeted

  extensions_dir = File.expand_path('../../extensions', __dir__)
  return unless Dir.exist?(extensions_dir)

  disabled = begin
    state_file = File.expand_path('../../config/extensions_state.json', __dir__)
    File.exist?(state_file) ? Array(JSON.parse(File.read(state_file))['disabled']).map(&:to_s) : []
  rescue JSON::ParserError, IOError, SystemCallError
    []
  end

  ext_specs = []
  Dir.children(extensions_dir).sort.each do |s|
    next if s == 'private'
    ext_specs << [extensions_dir, s]
  end
  # Private extensions load their worker code only in full mode (private bundle /
  # POWERNODE_INCLUDE_PRIVATE_EXTENSIONS). In core mode their job constants are
  # absent, so requiring their specs would NameError — skip them, mirroring the
  # worker's own core/full split.
  if private_extensions_active?
    private_dir = File.join(extensions_dir, 'private')
    Dir.children(private_dir).sort.each { |s| ext_specs << [private_dir, s] } if Dir.exist?(private_dir)
  end

  ext_specs.each do |ext_root, slug|
    next if disabled.include?(slug)

    manifest_path = File.join(ext_root, slug, 'extension.json')
    next unless File.exist?(manifest_path)

    manifest = begin
      JSON.parse(File.read(manifest_path))
    rescue JSON::ParserError
      next
    end
    next unless manifest.dig('components', 'worker')

    spec_glob = File.join(ext_root, slug, 'worker', 'spec', '**', '*_spec.rb')
    Dir[spec_glob].sort.each { |f| require f }
  end
end

load_extension_worker_specs

# Configure VCR for HTTP recording
VCR.configure do |config|
  config.cassette_library_dir = "spec/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  # Allow HTTP connections when no cassette - let WebMock handle with stubs
  config.allow_http_connections_when_no_cassette = true
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [:method, :uri, :headers, :body]
  }

  # Ignore localhost requests - let WebMock handle them with stubs
  config.ignore_localhost = true
  config.ignore_hosts 'localhost', '127.0.0.1'

  # Filter sensitive data
  config.filter_sensitive_data('<BACKEND_API_URL>') { ENV['BACKEND_API_URL'] || 'http://localhost:3000' }
  config.filter_sensitive_data('<WORKER_TOKEN>') { ENV['WORKER_TOKEN'] || 'test-token' }
  config.filter_sensitive_data('<SERVICE_TOKEN>') { ENV['SERVICE_TOKEN'] || 'service-token' }
end