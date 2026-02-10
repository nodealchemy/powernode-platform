# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
# Uncomment the line below in case you have `--require rails_helper` in the `.rspec` file
# that will avoid rails generators crashing because migrations haven't been run yet
# return unless Rails.env.test?
require 'rspec/rails'
# Add additional requires below this line. Rails is not loaded until this point!
require 'factory_bot_rails'
require 'database_cleaner/active_record'
require 'shoulda/matchers'
require 'webmock/rspec'
require 'vcr'

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

# Ensures that the test database schema matches the current schema file.
# If there are pending migrations it will invoke `db:test:prepare` to
# recreate the test database by loading the schema.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end
RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [
    Rails.root.join('spec/fixtures')
  ]

  # Wrap each test in a database transaction that rolls back after the test.
  # This is fast, avoids table locks, and prevents deadlocks between processes.
  config.use_transactional_fixtures = true

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # FactoryBot configuration
  config.include FactoryBot::Syntax::Methods

  # Time travel helpers (travel_to, freeze_time, etc.)
  config.include ActiveSupport::Testing::TimeHelpers

  # Database cleaner configuration
  #
  # With use_transactional_fixtures = true, Rails wraps each test in a
  # transaction that rolls back automatically. DatabaseCleaner is only needed
  # for the initial suite cleanup and for tests that explicitly require
  # truncation (e.g., multi-threaded performance tests).
  config.before(:suite) do
    # Under parallel_tests, databases are already clean (parallel:prepare runs
    # db:purge + db:schema:load) and permissions are seeded by parallel:seed_permissions.
    # Skip the heavy truncation to avoid PG::OutOfMemory from max_locks_per_transaction.
    # Use deletion instead of truncation for initial cleanup.
    # TRUNCATE requires AccessExclusiveLock which deadlocks with
    # AccessShareLock held by concurrent rspec processes running tests.
    # DELETE only needs RowExclusiveLock, avoiding deadlocks entirely.
    retries = 0
    begin
      DatabaseCleaner.clean_with(:deletion, except: %w[ar_internal_metadata schema_migrations])
    rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout => e
      retries += 1
      if retries <= 3
        sleep(retries * 2)
        retry
      else
        raise
      end
    end

    # Load permissions configuration
    require Rails.root.join('config', 'permissions')

    # Sync all roles from the Permissions module configuration
    # This ensures all standardized roles exist in test database
    Role.sync_from_config!
  end

  # Only use DatabaseCleaner for tests tagged with truncation: true
  # (e.g., multi-threaded tests that need committed data visible across threads)
  config.before(:each, truncation: true) do
    self.class.use_transactional_tests = false
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.start
  end

  config.after(:each, truncation: true) do
    DatabaseCleaner.clean
    self.class.use_transactional_tests = true
  end

  # RSpec Rails uses metadata to mix in different behaviours to your tests,
  # for example enabling you to call `get` and `post` in request specs. e.g.:
  #
  #     RSpec.describe UsersController, type: :request do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/8-0/rspec-rails
  #
  # You can also this infer these behaviours automatically by location, e.g.
  # /spec/models would pull in the same behaviour as `type: :model` but this
  # behaviour is considered legacy and will be removed in a future version.
  #
  # To enable this behaviour uncomment the line below.
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")
end
