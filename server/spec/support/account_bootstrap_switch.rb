# frozen_string_literal: true

# Test-env switch for Account's `after_create_commit :run_account_bootstrap`
# (System::AccountBootstrapService: Pro Cloud provider, regions, instance types and the
# node-module catalog/templates). It costs ~150 ms and ~215 SQL per account and almost
# no spec reads its output, so specs SKIP it by default
# (docs/operations/test-performance-profile-2026-10.md, slice S0).
#
# Opt in where a spec needs the real bootstrap:
#   it "...", :account_bootstrap do            # one example (wraps its let!/before too)
#   describe "...", :account_bootstrap do      # a group, incl. its let_it_be / before_all
#   with_account_bootstrap { create(:account) } # just the accounts created in the block
#
# Scope: only the callback is gated. Calling System::AccountBootstrapService directly is
# untouched, and so is `ensure_default_environments` (it still runs for every account).
# app/models/account.rb is not modified: the gate is prepended from here, so it exists only
# when rails_helper loads spec/support, never in development or production.
#
# Parallel/thread safety: the switch is a per-process depth counter (parallel_tests runs one
# process per lane, so lanes never share it). It is process-wide rather than thread-local on
# purpose, so accounts created on a helper thread inside a tagged example get the bootstrap
# too. Every enable is paired with a disable in an ensure / after hook, so it cannot outlive
# the example or group that turned it on; an unbalanced disable raises rather than being absorbed.
module AccountBootstrapSwitch
  MUTEX = Mutex.new
  @depth = 0

  class << self
    def enabled?
      @depth.positive?
    end

    def enable!
      MUTEX.synchronize { @depth += 1 }
    end

    def disable!
      MUTEX.synchronize do
        raise "AccountBootstrapSwitch.disable! without a matching enable! (unbalanced switch)" unless @depth.positive?

        @depth -= 1
      end
    end

    def with_bootstrap
      enable!
      yield
    ensure
      disable!
    end
  end

  # Prepended into Account; runs the real callback only while the switch is on.
  module AccountGate
    private

    def run_account_bootstrap
      return unless AccountBootstrapSwitch.enabled?

      super
    end
  end

  module Helpers
    def with_account_bootstrap(&)
      AccountBootstrapSwitch.with_bootstrap(&)
    end
  end
end

Account.prepend(AccountBootstrapSwitch::AccountGate)

RSpec.configure do |config|
  config.include AccountBootstrapSwitch::Helpers

  # Example-level tag. around(:example) also covers the example's let! / before hooks.
  config.around(:example, account_bootstrap: true) do |example|
    AccountBootstrapSwitch.with_bootstrap { example.run }
  end

  # Group-level tag: covers let_it_be / before_all, which create records in before(:context),
  # outside any example. Config-level context hooks run before the group's own before(:all)
  # and after its after(:all). The depth counter keeps nested tagged groups balanced.
  config.before(:context, account_bootstrap: true) { AccountBootstrapSwitch.enable! }
  config.after(:context, account_bootstrap: true) { AccountBootstrapSwitch.disable! }
end
