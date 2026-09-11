# frozen_string_literal: true

require "rails_helper"

# B5b — one flag predicate, and a per-target guard inside the rate limiter's
# hourly window. Real Ai::RemediationLog rows and no stubbed counts: the guard
# is a query, so the table is the oracle. A provider id that resolves to no
# row makes provider_failover log "skipped", which is still an audit row the
# guard must see.
RSpec.describe Ai::SelfHealing::RemediationDispatcher, "B5b guards", type: :service do
  let(:account) { create(:account) }
  let(:provider_a) { SecureRandom.uuid }
  let(:provider_b) { SecureRandom.uuid }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  def breaker_opened(provider_id, acct = account)
    described_class.dispatch(account: acct, trigger_source: "spec", trigger_event: "circuit_breaker_opened",
                             context: { service_type: "provider", provider_id: provider_id })
  end

  def logged(action, provider_id, acct = account)
    Ai::RemediationLog.where(account: acct, action_type: action)
                      .where("before_state ->> 'provider_id' = ?", provider_id).count
  end

  describe ".enabled?" do
    it "is the self_healing_remediation flag, read both ways" do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:self_healing_remediation).and_return(true)
      expect(described_class.enabled?).to be(true)

      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:self_healing_remediation).and_return(false)
      expect(described_class.enabled?).to be(false)
    end

    it "is what dispatch consults: off acts on nothing" do
      allow(described_class).to receive(:enabled?).and_return(false)

      expect { breaker_opened(provider_a) }.not_to change(Ai::RemediationLog, :count)
    end
  end

  describe "one action per target per window" do
    before { allow(described_class).to receive(:enabled?).and_return(true) }

    it "acts once when the same target is dispatched twice in the window" do
      breaker_opened(provider_a)
      breaker_opened(provider_a)

      expect(logged("provider_failover", provider_a)).to eq(1)
    end

    it "still acts for a different target in the same window" do
      breaker_opened(provider_a)
      breaker_opened(provider_b)

      expect(logged("provider_failover", provider_a)).to eq(1)
      expect(logged("provider_failover", provider_b)).to eq(1)
    end

    it "acts again for the same target once the window has passed" do
      breaker_opened(provider_a)
      Ai::RemediationLog.update_all(executed_at: 61.minutes.ago)
      breaker_opened(provider_a)

      expect(logged("provider_failover", provider_a)).to eq(2)
    end

    it "does not count another action type against the same target" do
      described_class.dispatch(account: account, trigger_source: "spec", trigger_event: "execution_degradation",
                               context: { provider_id: provider_a })
      breaker_opened(provider_a)

      expect(logged("model_downgrade", provider_a)).to eq(1)
      expect(logged("provider_failover", provider_a)).to eq(1)
    end

    it "does not count another account's action against this account's target" do
      other = create(:account)
      breaker_opened(provider_a, other)
      breaker_opened(provider_a)

      expect(logged("provider_failover", provider_a, other)).to eq(1)
      expect(logged("provider_failover", provider_a)).to eq(1)
    end
  end
end
