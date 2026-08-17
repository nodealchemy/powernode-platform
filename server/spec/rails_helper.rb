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

# Schema-staleness guard — deliberately NOT maintain_test_schema!.
#
# The Rails default (ActiveRecord::Migration.maintain_test_schema!) silently
# invokes `db:test:prepare` when it thinks the schema is stale, which PURGES and
# reloads the test database. That auto-purge is hostile here twice over:
#   1. It can deadlock/half-complete when other rspec processes (parallel specs,
#      concurrent worktree sessions) hold connections — leaving a dropped/empty
#      schema_migrations behind, and a hand-edited schema.rb makes it trigger
#      spuriously.
#   2. Reloading the CORE-ONLY schema.rb re-assumes the private-extension engine
#      migrations as applied WITHOUT running them, silently destroying the
#      business_*/trading_* tables that scripts/prepare-extension-test-db.sh
#      built (see that script's header for the full mechanism).
#
# So instead: a READ-ONLY pending-migration check that never mutates the DB and
# fails loudly with the sanctioned recovery path.
begin
  ActiveRecord::Migration.check_all_pending!
rescue ActiveRecord::PendingMigrationError => e
  abort(<<~MSG)
    [rails_helper] The test database schema is stale (pending migrations).

    Auto-recovery via db:test:prepare is DISABLED here: the purge it performs can
    deadlock against concurrent rspec processes and silently drops the private-
    extension tables (core-only schema.rb re-assumes engine migrations unrun).

    Recover with:
        bash scripts/prepare-extension-test-db.sh

    (run from the repo root of THIS checkout/worktree; it rebuilds the isolated
    test DB including private-extension tables — see the script header.)

    #{e.message.strip}
  MSG
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

  # FactoryBot configuration — load every ACTIVE extension's factories and
  # spec-support helpers. Active extensions are resolved through the same
  # discovery the Gemfile uses (extensions_loader_helper), so this honors the
  # public/private split, the POWERNODE_INCLUDE_PRIVATE_EXTENSIONS flag, and the
  # config/extensions_state.json disabled list — i.e. only extensions whose gems
  # (and therefore models) are actually loaded contribute factories. Keeping the
  # loader generic means a future extension needs zero edits here, and it avoids
  # two hazards of hardcoding each extension by name: stale paths, and loading an
  # on-disk-but-inactive extension's factories whose models aren't loaded.
  #
  # Factories are loaded individually with DuplicateDefinitionError recovery so
  # an extension factory can override a core factory of the same name (e.g.
  # :invoice_line_item exists in both core and the business extension).
  require_relative "../../extensions_loader_helper"
  discover_extension_gems.each do |_slug, rel_server_path|
    ext_server = Rails.root.join(rel_server_path)

    factories_dir = ext_server.join("spec", "factories")
    if factories_dir.exist?
      Dir[factories_dir.join("**/*.rb")].sort.each do |factory_file|
        load factory_file
      rescue FactoryBot::DuplicateDefinitionError => e
        # Extension factory overrides core — unregister core version and retry
        factory_name = e.message.sub("Factory already registered: ", "")
        FactoryBot::Internal.factories.instance_variable_get(:@items).delete(factory_name)
        load factory_file
      end
    end

    # Extension spec-support helpers. Extension specs run mounted into the parent
    # and `require "rails_helper"`, so their support helpers (e.g.
    # WorkerMtlsAuthHelpers) need explicit loading here. Scoped to *_helpers.rb
    # so we don't re-trigger an extension's simplecov/coverage bootstrap.
    support_dir = ext_server.join("spec", "support")
    if support_dir.exist?
      Dir[support_dir.join("**/*_helpers.rb")].sort.each { |f| require f }
    end
  end

  config.include FactoryBot::Syntax::Methods

  # Time travel helpers (travel_to, freeze_time, etc.)
  config.include ActiveSupport::Testing::TimeHelpers

  # Database cleaner configuration
  #
  # With use_transactional_fixtures = true, Rails wraps each test in a
  # transaction that rolls back automatically. DatabaseCleaner is only needed
  # for the initial suite cleanup and for tests that explicitly require
  # truncation (e.g., multi-threaded performance tests).
  #
  # Allow non-localhost DATABASE_URL. DatabaseCleaner's safeguard rejects
  # remote URLs by default ("ENV['DATABASE_URL'] is set to a remote URL"),
  # which trips in CI where the test DB lives on the docker bridge gateway
  # (172.17.0.1 — the act runner job container can't reach 127.0.0.1 of
  # the sidecar; see extensions/system/.gitea/workflows/ci.yaml). Test
  # databases aren't real prod targets; opt out so the safeguard doesn't
  # block legitimate CI runs.
  DatabaseCleaner.allow_remote_database_url = true
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
      # Clear join tables first to avoid FK violations during deletion
      ActiveRecord::Base.connection.execute("DELETE FROM role_permissions")
      DatabaseCleaner.clean_with(:deletion, except: %w[ar_internal_metadata schema_migrations])
    rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, ActiveRecord::InvalidForeignKey => e
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

    # Redis gets the same clean slate the database above just got.
    #
    # Nothing in the suite has ever cleaned Redis, and unlike the DB there is no
    # transaction to roll back — cache writes are keyed by the account the
    # example built, so once that account is deleted the keys are unreachable
    # AND immortal. On a long-lived dev box that accumulated 425,484 orphaned
    # keys / 10.6 GB across ~82,000 dead account UUIDs and took the node down
    # (2026-08-17). Powernode::Redis now isolates the suite onto TEST_DATABASE,
    # which makes flushing safe to do unconditionally: this can only ever reach
    # a database no application environment is configured to use.
    #
    # Guarded because Redis is not a hard dependency of every spec run — a unit
    # run on a box with no Redis should not fail at :suite over a cache reset.
    begin
      redis = Powernode::Redis.client
      current_db = redis.connection[:db]
      if current_db == Powernode::Redis::TEST_DATABASE
        redis.flushdb
      else
        warn "[rails_helper] Skipping Redis flush: expected db " \
             "#{Powernode::Redis::TEST_DATABASE}, connected to #{current_db.inspect}. " \
             "Refusing to flush a database the suite does not own."
      end
    rescue StandardError => e
      warn "[rails_helper] Redis unavailable, skipping flush: #{e.class}: #{e.message}"
    end
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
