# frozen_string_literal: true

require "rails_helper"

RSpec.describe Powernode::BillingBridge do
  # BillingBridge is process-global mutable state (populated by the business
  # extension at boot when present). Capture and restore everything we touch
  # so these specs cannot leak registration state into other examples.
  around do |example|
    original = {
      subscription_model: described_class.subscription_model,
      payment_model: described_class.payment_model,
      plan_model: described_class.plan_model,
      revenue_snapshot_model: described_class.revenue_snapshot_model,
      provisioning_quota_handler: described_class.provisioning_quota_handler
    }
    example.run
  ensure
    described_class.subscription_model = original[:subscription_model]
    described_class.payment_model = original[:payment_model]
    described_class.plan_model = original[:plan_model]
    described_class.revenue_snapshot_model = original[:revenue_snapshot_model]
    described_class.provisioning_quota_handler = original[:provisioning_quota_handler]
  end

  let(:account) { instance_double(Account, id: "acct-1") }
  let(:mission) { double("Mission", id: "mission-1") }

  describe ".check_provisioning_quota" do
    context "in core mode (no handler registered)" do
      before { described_class.provisioning_quota_handler = nil }

      it "allows by default" do
        expect(described_class.check_provisioning_quota(account: account, mission: mission))
          .to eq({ allowed: true })
      end
    end

    context "with a registered handler" do
      it "passes account and mission through to the handler" do
        received = nil
        described_class.provisioning_quota_handler = lambda do |account:, mission:|
          received = { account: account, mission: mission }
          { allowed: true }
        end

        described_class.check_provisioning_quota(account: account, mission: mission)

        expect(received).to eq({ account: account, mission: mission })
      end

      it "returns the handler's allow verdict verbatim" do
        described_class.provisioning_quota_handler = ->(account:, mission:) { { allowed: true } }

        expect(described_class.check_provisioning_quota(account: account, mission: mission))
          .to eq({ allowed: true })
      end

      it "blocks provisioning when the handler denies, preserving the denial payload" do
        denial = { allowed: false, payload: { reason: "quota_exceeded", limit: 3, used: 3 } }
        described_class.provisioning_quota_handler = ->(account:, mission:) { denial }

        result = described_class.check_provisioning_quota(account: account, mission: mission)

        expect(result[:allowed]).to be(false)
        expect(result[:payload]).to eq({ reason: "quota_exceeded", limit: 3, used: 3 })
      end
    end

    context "when the handler raises (deliberate fail-open)" do
      before do
        described_class.provisioning_quota_handler = lambda do |account:, mission:|
          raise StandardError, "billing backend unreachable"
        end
      end

      it "fails OPEN — a broken billing extension must not block core provisioning" do
        expect(described_class.check_provisioning_quota(account: account, mission: mission))
          .to eq({ allowed: true })
      end

      it "logs the handler failure so the fail-open is observable" do
        expect(Rails.logger).to receive(:error)
          .with(a_string_including("provisioning quota handler failed: billing backend unreachable"))

        described_class.check_provisioning_quota(account: account, mission: mission)
      end

      it "does not swallow non-StandardError exceptions" do
        described_class.provisioning_quota_handler = ->(account:, mission:) { raise NotImplementedError, "abstract" }

        expect { described_class.check_provisioning_quota(account: account, mission: mission) }
          .to raise_error(NotImplementedError)
      end
    end
  end

  describe ".reset!" do
    it "clears all registered models and the quota handler back to core mode" do
      described_class.subscription_model = Class.new
      described_class.payment_model = Class.new
      described_class.plan_model = Class.new
      described_class.revenue_snapshot_model = Class.new
      described_class.provisioning_quota_handler = ->(account:, mission:) { { allowed: false, payload: {} } }

      described_class.reset!

      expect(described_class.subscription_model).to be_nil
      expect(described_class.payment_model).to be_nil
      expect(described_class.plan_model).to be_nil
      expect(described_class.revenue_snapshot_model).to be_nil
      expect(described_class.provisioning_quota_handler).to be_nil
      expect(described_class.check_provisioning_quota(account: account, mission: mission))
        .to eq({ allowed: true })
    end
  end
end
