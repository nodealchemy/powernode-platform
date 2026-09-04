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

      it "blocks provisioning when the handler denies, preserving extra handler keys" do
        denial = { allowed: false, payload: { reason: "quota_exceeded", limit: 3, used: 3 } }
        described_class.provisioning_quota_handler = ->(account:, mission:) { denial }

        result = described_class.check_provisioning_quota(account: account, mission: mission)

        expect(result[:allowed]).to be(false)
        # Diagnostic keys the handler supplied survive normalization...
        expect(result[:payload]).to include(reason: "quota_exceeded", limit: 3, used: 3)
        # ...and the canonical contract keys are filled in regardless.
        expect(result[:payload].keys).to include(*described_class::UPGRADE_PAYLOAD_KEYS)
      end
    end

    # (2) One denial contract. Every denial the bridge emits carries the SAME
    # key set, whatever the handler chose to return, so UpgradeRequiredCard
    # never has to branch on which producer denied.
    describe "denial payload contract" do
      it "normalizes a sparse handler payload to the canonical key set" do
        described_class.provisioning_quota_handler = lambda do |account:, mission:|
          { allowed: false, payload: { reason: "no_subscription" } }
        end

        payload = described_class.check_provisioning_quota(account: account, mission: mission)[:payload]

        expect(payload[:requires_upgrade]).to be(true)
        expect(payload[:reason]).to eq("no_subscription")
        expect(payload).to have_key(:cap)
        expect(payload[:cap]).to be_nil
        expect(payload).to have_key(:upgrade_url)
        expect(payload[:upgrade_url]).to be_nil
      end

      it "passes through cap and upgrade_url when the handler supplies them" do
        described_class.provisioning_quota_handler = lambda do |account:, mission:|
          {
            allowed: false,
            payload: {
              requires_upgrade: true, reason: "max_active_instances_exceeded",
              cap: 3, upgrade_url: "/checkout"
            }
          }
        end

        payload = described_class.check_provisioning_quota(account: account, mission: mission)[:payload]

        expect(payload[:requires_upgrade]).to be(true)
        expect(payload[:reason]).to eq("max_active_instances_exceeded")
        expect(payload[:cap]).to eq(3)
        expect(payload[:upgrade_url]).to eq("/checkout")
      end

      it "coerces a symbol reason to a string so the wire shape is stable" do
        described_class.provisioning_quota_handler = lambda do |account:, mission:|
          { allowed: false, payload: { reason: :free_hours_exhausted } }
        end

        payload = described_class.check_provisioning_quota(account: account, mission: mission)[:payload]

        expect(payload[:reason]).to eq("free_hours_exhausted")
      end

      # A string-keyed payload (JSON round-trip, a hash built from params) must
      # not leave the real value stranded under its string twin while the
      # canonical symbol key reads nil.
      it "reads handler values whether the handler used symbol or string keys" do
        described_class.provisioning_quota_handler = lambda do |account:, mission:|
          { allowed: false, payload: { "reason" => "no_subscription", "cap" => 5, "upgrade_url" => "/plans" } }
        end

        payload = described_class.check_provisioning_quota(account: account, mission: mission)[:payload]

        expect(payload[:reason]).to eq("no_subscription")
        expect(payload[:cap]).to eq(5)
        expect(payload[:upgrade_url]).to eq("/plans")
      end

      # The contract constant must BE the key set, not merely a subset of it —
      # otherwise a fifth key added to upgrade_payload and not to the constant
      # slips past every `include(*KEYS)` assertion.
      it "builds exactly the keys UPGRADE_PAYLOAD_KEYS declares" do
        expect(described_class.upgrade_payload(reason: "x").keys)
          .to eq(described_class::UPGRADE_PAYLOAD_KEYS)
      end

      # A denial with no usable reason must NOT render as "you hit your plan's
      # limit" — that is a false statement to the user, and it is the exact
      # failure the degraded reason exists to prevent.
      it "substitutes the degraded reason rather than emitting a blank one" do
        described_class.provisioning_quota_handler = ->(account:, mission:) { { allowed: false } }

        payload = described_class.check_provisioning_quota(account: account, mission: mission)[:payload]

        expect(payload[:reason]).to eq(described_class::DEGRADED_QUOTA_REASON)
        expect(payload[:reason]).not_to eq("")
      end

      it "leaves an allow verdict untouched — no payload is invented" do
        described_class.provisioning_quota_handler = ->(account:, mission:) { { allowed: true } }

        expect(described_class.check_provisioning_quota(account: account, mission: mission))
          .to eq({ allowed: true })
      end
    end

    # (1) A quota guard that answers "allowed" when it errors is not a guard.
    # Default posture is DENY; degraded-open is available but must be the
    # caller's explicit, visible choice.
    context "when the handler raises" do
      before do
        described_class.provisioning_quota_handler = lambda do |account:, mission:|
          raise StandardError, "billing backend unreachable"
        end
      end

      it "fails CLOSED by default" do
        result = described_class.check_provisioning_quota(account: account, mission: mission)

        expect(result[:allowed]).to be(false)
      end

      it "emits the canonical denial contract for the degraded case" do
        payload = described_class.check_provisioning_quota(account: account, mission: mission)[:payload]

        expect(payload[:requires_upgrade]).to be(true)
        expect(payload[:reason]).to eq(described_class::DEGRADED_QUOTA_REASON)
        expect(payload).to have_key(:cap)
        expect(payload[:cap]).to be_nil
        expect(payload).to have_key(:upgrade_url)
        expect(payload[:upgrade_url]).to be_nil
      end

      it "uses a reason distinct from any real plan-limit denial" do
        expect(described_class::DEGRADED_QUOTA_REASON).to eq("quota_check_unavailable")
      end

      it "allows ONLY when the caller explicitly opts into degraded-open" do
        expect(described_class.check_provisioning_quota(account: account, mission: mission, on_error: :allow))
          .to eq({ allowed: true })
      end

      it "treats an explicit on_error: :deny the same as the default" do
        expect(described_class.check_provisioning_quota(account: account, mission: mission, on_error: :deny)[:allowed])
          .to be(false)
      end

      it "logs the handler failure and the posture it applied" do
        expect(Rails.logger).to receive(:error).with(
          a_string_including("provisioning quota handler failed")
            .and(a_string_including("billing backend unreachable"))
            .and(a_string_including("on_error=deny"))
        )

        described_class.check_provisioning_quota(account: account, mission: mission)
      end

      it "does not swallow non-StandardError exceptions" do
        described_class.provisioning_quota_handler = ->(account:, mission:) { raise NotImplementedError, "abstract" }

        expect { described_class.check_provisioning_quota(account: account, mission: mission) }
          .to raise_error(NotImplementedError)
      end

      # The mode is validated BEFORE the handler runs, so a typo can never be
      # swallowed by the very rescue whose posture it selects.
      it "rejects an unknown on_error mode instead of guessing a posture" do
        expect { described_class.check_provisioning_quota(account: account, mission: mission, on_error: :alow) }
          .to raise_error(ArgumentError, /on_error must be one of/)
      end
    end

    # A handler that returns garbage is a BROKEN handler. It must land on the
    # same fail-closed posture as one that raises — not slip past the contract
    # and blow up in the caller with a NoMethodError.
    context "when the handler returns something that is not a verdict Hash" do
      [ nil, false, true, "denied", 42 ].each do |junk|
        it "fails closed on #{junk.inspect} rather than handing it to the caller" do
          described_class.provisioning_quota_handler = ->(account:, mission:) { junk }

          result = described_class.check_provisioning_quota(account: account, mission: mission)

          expect(result[:allowed]).to be(false)
          expect(result[:payload][:reason]).to eq(described_class::DEGRADED_QUOTA_REASON)
        end
      end

      it "honours an explicit degraded-open opt-in for a junk verdict too" do
        described_class.provisioning_quota_handler = ->(account:, mission:) { nil }

        expect(described_class.check_provisioning_quota(account: account, mission: mission, on_error: :allow))
          .to eq({ allowed: true })
      end
    end

    # The envelope needs the same symbol/string tolerance as the payload —
    # reading `allowed` symbol-only turns a string-keyed ALLOW into a denial
    # with an empty reason, and a truthy non-true value into a fail-OPEN.
    context "when the handler keys or types the verdict unusually" do
      it "reads a string-keyed allow as an allow" do
        described_class.provisioning_quota_handler = ->(account:, mission:) { { "allowed" => true } }

        expect(described_class.check_provisioning_quota(account: account, mission: mission)[:allowed])
          .to be(true)
      end

      it "reads a string-keyed denial as a denial and still contracts the payload" do
        described_class.provisioning_quota_handler = lambda do |account:, mission:|
          { "allowed" => false, "payload" => { "reason" => "no_subscription" } }
        end

        result = described_class.check_provisioning_quota(account: account, mission: mission)

        expect(result[:allowed]).to be(false)
        expect(result[:payload][:reason]).to eq("no_subscription")
      end

      it "does not treat a truthy non-true allowed value as permission to provision" do
        described_class.provisioning_quota_handler = ->(account:, mission:) { { allowed: "false" } }

        expect(described_class.check_provisioning_quota(account: account, mission: mission)[:allowed])
          .to be(false)
      end
    end

    context "when no handler is registered" do
      before { described_class.provisioning_quota_handler = nil }

      # Absence of a billing extension is not a failure — it is core mode.
      # The fail-CLOSED posture must not leak into it.
      it "still allows, regardless of on_error" do
        expect(described_class.check_provisioning_quota(account: account, mission: mission, on_error: :deny))
          .to eq({ allowed: true })
      end
    end
  end

  describe ".reset!" do
    it "clears all registered models and both provisioning handlers back to core mode" do
      described_class.subscription_model = Class.new
      described_class.payment_model = Class.new
      described_class.plan_model = Class.new
      described_class.revenue_snapshot_model = Class.new
      described_class.provisioning_quota_handler = ->(account:, mission:) { { allowed: false, payload: {} } }
      described_class.provisioning_meter_handler = ->(node_instance:, event:) { raise "never" }

      described_class.reset!

      expect(described_class.subscription_model).to be_nil
      expect(described_class.payment_model).to be_nil
      expect(described_class.plan_model).to be_nil
      expect(described_class.revenue_snapshot_model).to be_nil
      expect(described_class.provisioning_quota_handler).to be_nil
      expect(described_class.provisioning_meter_handler).to be_nil
      expect(described_class.check_provisioning_quota(account: account, mission: mission))
        .to eq({ allowed: true })
    end
  end
end
