# frozen_string_literal: true

require "rails_helper"

# Pins the test-env account-bootstrap switch (spec/support/account_bootstrap_switch.rb):
# a plain `create(:account)` must NOT run `Account#run_account_bootstrap`
# (System::AccountBootstrapService, ~150 ms and ~215 SQL per account), an example or
# group tagged `:account_bootstrap` must run it, and the default must come back after
# a tagged example or group. ensure_default_environments is NOT gated and must still run.
#
# The examples are order-independent: each asserts against its own account.
RSpec.describe "Account bootstrap switch (test env)" do
  # The bootstrap's signature row: AccountBootstrapService#seed_provider!.
  def bootstrapped?(account)
    System::Provider.exists?(account_id: account.id, name: System::AccountBootstrapService::DEFAULT_PROVIDER_NAME)
  end

  before do
    skip "system extension not loaded (core mode): no bootstrap to gate" unless defined?(System::AccountBootstrapService)
  end

  it "does not run the bootstrap for a default create(:account)" do
    account = create(:account)

    expect(bootstrapped?(account)).to be(false)
    expect(System::NodeTemplate.where(account_id: account.id)).not_to exist
  end

  it "still creates the default environments" do
    account = create(:account)

    expect(Ai::Environment.where(account_id: account.id)).to exist
  end

  it "runs the bootstrap for an example tagged :account_bootstrap", :account_bootstrap do
    account = create(:account)

    expect(bootstrapped?(account)).to be(true)
    expect(System::NodeTemplate.where(account_id: account.id)).to exist
  end

  it "runs it inside a with_account_bootstrap block and restores the default after it" do
    inside = with_account_bootstrap { create(:account) }
    after = create(:account)

    expect(bootstrapped?(inside)).to be(true)
    expect(bootstrapped?(after)).to be(false)
  end

  it "restores the default even when the block raises" do
    expect { with_account_bootstrap { raise ArgumentError, "boom" } }.to raise_error(ArgumentError)

    expect(bootstrapped?(create(:account))).to be(false)
  end

  it "raises on an unbalanced disable instead of absorbing it" do
    expect { AccountBootstrapSwitch.disable! }.to raise_error(RuntimeError, /unbalanced/)

    expect(bootstrapped?(create(:account))).to be(false)
  end

  describe "a group tagged :account_bootstrap", :account_bootstrap do
    let_it_be(:group_account) { create(:account) }

    it "runs it for let_it_be / before_all accounts created outside the example" do
      expect(bootstrapped?(group_account)).to be(true)
    end

    it "runs it for accounts created inside the example" do
      expect(bootstrapped?(create(:account))).to be(true)
    end
  end

  describe "an untagged group" do
    let_it_be(:group_account) { create(:account) }

    it "skips it for let_it_be accounts" do
      expect(bootstrapped?(group_account)).to be(false)
    end
  end

  # Ordered so the tagged example runs first; the untagged one proves it did not leak.
  describe "default restored after a tagged example", order: :defined do
    it "runs it while tagged", :account_bootstrap do
      expect(bootstrapped?(create(:account))).to be(true)
    end

    it "skips it again in the next untagged example" do
      expect(bootstrapped?(create(:account))).to be(false)
    end
  end

  describe "default restored after a tagged group", order: :defined do
    describe "tagged", :account_bootstrap do
      it "runs it" do
        expect(bootstrapped?(create(:account))).to be(true)
      end
    end

    describe "untagged sibling" do
      it "skips it" do
        expect(bootstrapped?(create(:account))).to be(false)
      end
    end
  end
end
