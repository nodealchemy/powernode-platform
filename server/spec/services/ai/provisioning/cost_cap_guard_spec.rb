# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Provisioning::CostCapGuard, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }

  def attribute_cost!(amount_usd, account_obj: account, on: Date.current)
    create(
      :ai_cost_attribution,
      account: account_obj,
      provider: provider,
      amount_usd: amount_usd,
      attribution_date: on
    )
  end

  describe ".allow?" do
    context "when the account has no subscription (free-tier fallback)" do
      it "uses the $0.50 default daily cap" do
        result = described_class.allow?(account: account)
        expect(result.ok?).to be true
        expect(result.payload[:cap]).to eq(0.50)
        expect(result.payload[:remaining]).to eq(0.50)
      end

      it "blocks when spend reaches the default cap" do
        attribute_cost!(0.40)
        attribute_cost!(0.10)

        result = described_class.allow?(account: account)
        expect(result.cap_exceeded?).to be true
        expect(result.payload[:spent]).to be_within(0.0001).of(0.50)
        expect(result.payload[:cap]).to eq(0.50)
      end

      it "ignores spend on prior days" do
        attribute_cost!(0.49, on: Date.yesterday)

        result = described_class.allow?(account: account)
        expect(result.ok?).to be true
        expect(result.payload[:spent]).to eq(0.0)
      end
    end

    context "when the plan exposes a max_llm_spend_per_day_usd limit" do
      let(:plan_limits) { { "max_llm_spend_per_day_usd" => 5.0 } }
      let(:plan) { instance_double("Plan", limits: plan_limits) }
      let(:subscription) { instance_double("Subscription", plan: plan) }

      before do
        # Account doesn't define `active_subscription` until Slice C lands;
        # graft it on per-test so verify_partial_doubles still passes.
        account.define_singleton_method(:active_subscription) { nil }
        allow(account).to receive(:active_subscription).and_return(subscription)
      end

      it "raises the cap to the plan's daily allowance" do
        attribute_cost!(2.50)

        result = described_class.allow?(account: account)
        expect(result.ok?).to be true
        expect(result.payload[:cap]).to eq(5.0)
        expect(result.payload[:remaining]).to be_within(0.0001).of(2.5)
      end

      it "returns cap_exceeded once the higher cap is hit" do
        attribute_cost!(5.00)

        result = described_class.allow?(account: account)
        expect(result.cap_exceeded?).to be true
        expect(result.payload[:cap]).to eq(5.0)
      end
    end

    context "when an explicit max_spend_usd_per_day override is supplied" do
      it "uses the override regardless of plan limits" do
        attribute_cost!(1.00)

        result = described_class.allow?(account: account, max_spend_usd_per_day: 10.0)
        expect(result.ok?).to be true
        expect(result.payload[:cap]).to eq(10.0)
        expect(result.payload[:remaining]).to be_within(0.0001).of(9.0)
      end

      it "still blocks once the override cap is reached" do
        attribute_cost!(0.30)

        result = described_class.allow?(account: account, max_spend_usd_per_day: 0.25)
        expect(result.cap_exceeded?).to be true
      end
    end

    context "when the plan limit is zero / blank" do
      let(:plan_limits) { { "max_llm_spend_per_day_usd" => 0 } }
      let(:plan) { instance_double("Plan", limits: plan_limits) }
      let(:subscription) { instance_double("Subscription", plan: plan) }

      it "falls back to the default cap" do
        account.define_singleton_method(:active_subscription) { nil }
        allow(account).to receive(:active_subscription).and_return(subscription)
        result = described_class.allow?(account: account)
        expect(result.payload[:cap]).to eq(described_class::DEFAULT_DAILY_CAP_USD)
      end
    end

    it "scopes spend to the supplied account" do
      other_account = create(:account)
      attribute_cost!(0.40, account_obj: other_account)

      result = described_class.allow?(account: account)
      expect(result.ok?).to be true
      expect(result.payload[:spent]).to eq(0.0)
    end
  end
end
