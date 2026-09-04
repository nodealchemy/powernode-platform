# frozen_string_literal: true

require "rails_helper"

# IMP-01b1e152f667 — the meter seam. BillingBridge exposed a quota handler and
# four model accessors but NOTHING for provisioning metering, so the public
# extensions/system provisioning path had to name the private meter service
# directly. This is the seam that lets it stop.
RSpec.describe Powernode::BillingBridge, ".record_provisioning_event" do
  # Process-global mutable state, populated by the business extension at boot
  # when present. The `.reset!` example below wipes ALL of it, so capture and
  # restore the whole registration — not just the meter handler — or every
  # extension-loaded example that runs after this file sees a nil quota
  # handler and a bridge that silently allows.
  around do |example|
    original = {
      subscription_model: described_class.subscription_model,
      payment_model: described_class.payment_model,
      plan_model: described_class.plan_model,
      revenue_snapshot_model: described_class.revenue_snapshot_model,
      provisioning_quota_handler: described_class.provisioning_quota_handler,
      provisioning_meter_handler: described_class.provisioning_meter_handler
    }
    example.run
  ensure
    described_class.subscription_model = original[:subscription_model]
    described_class.payment_model = original[:payment_model]
    described_class.plan_model = original[:plan_model]
    described_class.revenue_snapshot_model = original[:revenue_snapshot_model]
    described_class.provisioning_quota_handler = original[:provisioning_quota_handler]
    described_class.provisioning_meter_handler = original[:provisioning_meter_handler]
  end

  let(:node_instance) { double("node instance", id: "ni-1") }

  context "in core mode (no handler registered)" do
    before { described_class.provisioning_meter_handler = nil }

    it "reports nothing recorded, naming the no-handler reason" do
      expect(described_class.record_provisioning_event(node_instance: node_instance, event: "created"))
        .to eq({ recorded: false, reason: described_class::NO_METER_HANDLER_REASON })
    end

    # Core mode is the normal state of a self-hosted install, not an outage.
    it "does not log an error" do
      expect(Rails.logger).not_to receive(:error)

      described_class.record_provisioning_event(node_instance: node_instance, event: "created")
    end
  end

  context "with a registered handler" do
    it "passes node_instance and event through to the handler" do
      received = nil
      described_class.provisioning_meter_handler = lambda do |node_instance:, event:|
        received = { node_instance: node_instance, event: event }
      end

      described_class.record_provisioning_event(node_instance: node_instance, event: "terminated")

      expect(received).to eq({ node_instance: node_instance, event: "terminated" })
    end

    it "reports the event recorded" do
      described_class.provisioning_meter_handler = ->(node_instance:, event:) { :a_usage_row }

      expect(described_class.record_provisioning_event(node_instance: node_instance, event: "created"))
        .to eq({ recorded: true })
    end
  end

  # FAILURE POSTURE — decided, not inherited: the meter fails OPEN.
  #
  # Unlike the quota check, metering runs AFTER the billable state change (the
  # instance row exists / the terminate transition has fired). There is nothing
  # left to guard: a raise here cannot un-provision the machine, it can only
  # turn a real, successful provision into a failed Result for a machine that
  # exists and is billing. The loss is made VISIBLE instead — an error-level
  # log and a `recorded: false` return the caller can distinguish from success.
  context "when the handler raises" do
    before do
      described_class.provisioning_meter_handler = lambda do |node_instance:, event:|
        raise StandardError, "billing backend unreachable"
      end
    end

    it "fails OPEN — returns rather than raising" do
      expect {
        described_class.record_provisioning_event(node_instance: node_instance, event: "created")
      }.not_to raise_error
    end

    it "reports the failure with a reason distinct from the no-handler case" do
      result = described_class.record_provisioning_event(node_instance: node_instance, event: "created")

      expect(result).to eq({ recorded: false, reason: described_class::METER_HANDLER_FAILED_REASON })
      expect(described_class::METER_HANDLER_FAILED_REASON).not_to eq(described_class::NO_METER_HANDLER_REASON)
    end

    # A lost meter row is lost revenue: error, not warn, and it names the
    # event and instance so the row can be reconstructed.
    it "logs the failure at error level with the event, the instance and the posture" do
      expect(Rails.logger).to receive(:error).with(
        a_string_including("provisioning meter handler failed")
          .and(a_string_including("billing backend unreachable"))
          .and(a_string_including("event=created"))
          .and(a_string_including("node_instance_id=ni-1"))
          .and(a_string_including("posture=open"))
      )

      described_class.record_provisioning_event(node_instance: node_instance, event: "created")
    end

    it "does not swallow non-StandardError exceptions" do
      described_class.provisioning_meter_handler = ->(node_instance:, event:) { raise NotImplementedError, "abstract" }

      expect { described_class.record_provisioning_event(node_instance: node_instance, event: "created") }
        .to raise_error(NotImplementedError)
    end
  end

  describe ".reset!" do
    it "clears the meter handler along with the rest of the registration" do
      described_class.provisioning_meter_handler = ->(node_instance:, event:) { nil }

      described_class.reset!

      expect(described_class.provisioning_meter_handler).to be_nil
    end
  end
end
