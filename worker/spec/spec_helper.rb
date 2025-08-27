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

# Configure WebMock
WebMock.disable_net_connect!(allow_localhost: true)

# Configure VCR for HTTP recording
VCR.configure do |config|
  config.cassette_library_dir = "spec/vcr_cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!
  # Allow HTTP connections when no cassette is present for test flexibility
  config.allow_http_connections_when_no_cassette = true
  config.default_cassette_options = {
    record: :once,
    match_requests_on: [:method, :uri, :headers, :body]
  }
  
  # Filter sensitive data
  config.filter_sensitive_data('<BACKEND_API_URL>') { ENV['BACKEND_API_URL'] || 'http://localhost:3000' }
  config.filter_sensitive_data('<WORKER_TOKEN>') { ENV['WORKER_TOKEN'] || 'test-token' }
  config.filter_sensitive_data('<SERVICE_TOKEN>') { ENV['SERVICE_TOKEN'] || 'service-token' }
end