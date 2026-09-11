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

  # The guard's key is the provider's UUID, not the text it arrived as. The
  # action resolves the provider through the uuid type, which accepts upper
  # case, no hyphens and braces, so the guard must store and compare that same
  # normalized value; an id the type rejects must not act at all.
  describe "one provider, whatever form its id arrives in" do
    before { allow(described_class).to receive(:enabled?).and_return(true) }

    def failovers
      Ai::RemediationLog.where(account: account, action_type: "provider_failover")
    end

    {
      "UPPERCASE" => ->(id) { id.upcase },
      "hyphenless" => ->(id) { id.delete("-") },
      "{braced}" => ->(id) { "{#{id}}" }
    }.each do |form, variant|
      it "acts once when the same provider comes back #{form} in the window" do
        breaker_opened(provider_a)
        breaker_opened(variant.call(provider_a))

        expect(failovers.count).to eq(1)
      end

      it "stores a #{form} id canonically, so the canonical id is then refused" do
        breaker_opened(variant.call(provider_a))
        breaker_opened(provider_a)

        expect(failovers.count).to eq(1)
        expect(failovers.pick(Arel.sql("before_state ->> 'provider_id'"))).to eq(provider_a)
      end

      it "still acts for a different provider sent #{form}" do
        breaker_opened(provider_a)
        breaker_opened(variant.call(provider_b))

        expect(failovers.count).to eq(2)
      end
    end

    it "acts once when a model downgrade's source id comes back in another form" do
      degrade = lambda do |source_id|
        described_class.dispatch(account: account, trigger_source: "spec", trigger_event: "execution_degradation",
                                 context: { source_id: source_id })
      end
      degrade.call(provider_a)
      degrade.call(provider_a.upcase)

      expect(Ai::RemediationLog.where(account: account, action_type: "model_downgrade").count).to eq(1)
    end

    [ ->(id) { " #{id} " }, ->(_id) { "not-a-uuid" } ].each_with_index do |bad, i|
      it "refuses a provider id the uuid type rejects, logging nothing (form #{i + 1})" do
        expect { breaker_opened(bad.call(provider_a)) }.not_to change(Ai::RemediationLog, :count)
      end
    end
  end
end
