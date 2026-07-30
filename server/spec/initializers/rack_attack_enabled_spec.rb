# frozen_string_literal: true

require "rails_helper"

# The predicate that governs throttling existed TWICE with different meaning:
# the config (line ~9) excluded test, the runtime helper did not, and every
# throttle proc calls the helper. So auth throttles ran live during the suite
# with real limits (auth_login_by_email 5/hour, password reset 3/hour) over a
# 1-hour window shared by the whole run.
#
# The symptom was not an obvious one. It made spec/requests/api/v1/auth/
# passwords_spec.rb order- and timing-dependent: five failures with HTTP 429 on
# one machine and zero on another, from identical code and an identical suite.
# It read as an environment difference, which is the most expensive kind of
# false lead.
RSpec.describe Rack::Attack, "rate limiting predicate" do
  it "is disabled in the test environment" do
    expect(Rails.env.test?).to be(true)
    expect(described_class.rate_limiting_enabled?).to be(false),
      "rate limiting is LIVE during the test suite — auth throttles will fire " \
      "and make any spec that makes repeated auth requests order-dependent"
  end

  # The actual defect was drift between two definitions of one idea, so this
  # asserts they agree rather than asserting a particular value.
  it "agrees with the config it is derived from" do
    expect(described_class.rate_limiting_enabled?)
      .to eq(Rails.application.config.rate_limiting_enabled)
  end

  # THE regression test. The old helper read ENV directly, so it returned true
  # wherever DISABLE_RATE_LIMITING was absent — which is precisely how the two
  # machines differed: dev has a .env setting it, the sandbox has no .env at
  # all, so identical code throttled on one and not the other.
  #
  # Stubbing the variable away must NOT re-enable throttling, because the
  # predicate now derives from a config computed at boot from Rails.env. Under
  # the old implementation this example fails.
  it "stays disabled in test even when DISABLE_RATE_LIMITING is absent" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("DISABLE_RATE_LIMITING").and_return(nil)

    expect(described_class.rate_limiting_enabled?).to be(false),
      "the predicate is reading ENV directly again — auth throttles will fire " \
      "on any machine without a .env, making auth specs order-dependent"
  end
end
