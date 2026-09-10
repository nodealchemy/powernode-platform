# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::RemediationRouter do
  let(:account) { create(:account) }
  let(:component) { create(:platform_component_status, account: account, component_kind: "platform_subsystem") }

  before do
    Platform::Remediation::Registry.reset!
    Platform::Runbook::Registry.reset!
  end

  after do
    Platform::Remediation::Registry.reset!
    Platform::Runbook::Registry.reset!
  end

  # A lane that reports exactly what the example hands it, so every assertion
  # about pass-through is about the ROUTER and not about a fixture's opinion.
  # NOTE the positional `key`. With a keyword argument here, Ruby would parse
  # the trailing bare hash at every call site as keywords and `report` would
  # arrive empty — examples would then pass or fail for a reason that has
  # nothing to do with the router.
  def fake_lane(report, key = "fake_lane")
    lane = Object.new
    lane.define_singleton_method(:key) { key }
    lane.define_singleton_method(:describe) { |_component, _kind, account: nil| report }
    lane.define_singleton_method(:proceed!) { |*, **| raise "core must never call proceed!" }
    lane
  end

  def doc_source(map)
    source = Object.new
    source.define_singleton_method(:for) { |kind| map[kind.to_s] }
    source
  end

  describe "no lane claims the signal" do
    it "reports not_actuatable with NoLaneForSignal" do
      result = described_class.route(component, signal_kind: "instance.silent")

      expect(result[:state]).to eq(Platform::ComponentStatus::REMEDIATION_NOT_ACTUATABLE)
      expect(result[:reason]).to eq(described_class::NO_LANE)
      expect(result[:can_proceed]).to be false
      expect(result[:lane_key]).to be_nil
    end

    # The runbook is core's, and it is the whole value of the no-lane screen.
    it "still resolves the runbook" do
      Platform::Runbook::Registry.register_source(
        doc_source("instance.silent" => { "doc" => "docs/runbooks/silent.md#triage" })
      )

      result = described_class.route(component, signal_kind: "instance.silent")

      expect(result[:state]).to eq(Platform::ComponentStatus::REMEDIATION_NOT_ACTUATABLE)
      expect(result[:runbook]).to include(kind: "doc", path: "docs/runbooks/silent.md", anchor: "triage")
    end

    it "carries a 'none' runbook when nothing is bound, rather than omitting the key" do
      result = described_class.route(component, signal_kind: "instance.silent")

      expect(result).to have_key(:runbook)
      expect(result[:runbook]).to eq(kind: "none", known: false, reason: "NotRegistered")
    end
  end

  describe "a registered lane" do
    # Design §5.1's oracle: a lane whose consent budget is exhausted reports
    # that it cannot proceed, and the router reports what the lane reported.
    it "passes a consent-exhausted report through verbatim" do
      Platform::Remediation::Registry.register_lane(
        "instance.silent",
        fake_lane(
          state: Platform::ComponentStatus::REMEDIATION_AWAITING_OPERATOR,
          lane_key: "fleet_autonomy",
          policy: "require_approval",
          consent: { remaining: 0, budget: 3 },
          disruption: { remaining: 1, window: "1h" },
          environment_ceiling: "supervised",
          blast_radius: { instances: 2 },
          can_proceed: false,
          reason: "ConsentBudgetExhausted"
        )
      )

      result = described_class.route(component, signal_kind: "instance.silent")

      expect(result[:state]).to eq(Platform::ComponentStatus::REMEDIATION_AWAITING_OPERATOR)
      expect(result[:can_proceed]).to be false
      expect(result[:consent]).to eq(remaining: 0, budget: 3)
      expect(result[:policy]).to eq("require_approval")
      expect(result[:disruption]).to eq(remaining: 1, window: "1h")
      expect(result[:environment_ceiling]).to eq("supervised")
      expect(result[:blast_radius]).to eq(instances: 2)
      expect(result[:reason]).to eq("ConsentBudgetExhausted")
    end

    it "passes a proceedable report through verbatim too" do
      Platform::Remediation::Registry.register_lane(
        "instance.silent",
        fake_lane(
          state: Platform::ComponentStatus::REMEDIATION_AUTO_IN_PROGRESS,
          lane_key: "fleet_autonomy",
          policy: "auto_approve",
          consent: { remaining: 3, budget: 3 },
          disruption: {},
          environment_ceiling: nil,
          blast_radius: nil,
          can_proceed: true,
          reason: nil
        )
      )

      result = described_class.route(component, signal_kind: "instance.silent")

      expect(result[:state]).to eq(Platform::ComponentStatus::REMEDIATION_AUTO_IN_PROGRESS)
      expect(result[:can_proceed]).to be true
      expect(result[:reason]).to be_nil
    end

    it "accepts a string-keyed report and answers symbol-keyed" do
      Platform::Remediation::Registry.register_lane(
        "instance.silent",
        fake_lane("state" => Platform::ComponentStatus::REMEDIATION_STUCK,
                  "can_proceed" => false,
                  "reason" => "PreviousAttemptFailed")
      )

      result = described_class.route(component, signal_kind: "instance.silent")

      expect(result[:state]).to eq(Platform::ComponentStatus::REMEDIATION_STUCK)
      expect(result[:reason]).to eq("PreviousAttemptFailed")
    end

    it "fills in the lane_key from the lane when the report omits it" do
      Platform::Remediation::Registry.register_lane(
        "instance.silent",
        fake_lane({ state: Platform::ComponentStatus::REMEDIATION_NONE }, "named_lane")
      )

      expect(described_class.route(component, signal_kind: "instance.silent")[:lane_key])
        .to eq("named_lane")
    end

    it "keeps extra evidence the lane reported" do
      Platform::Remediation::Registry.register_lane(
        "instance.silent",
        fake_lane(state: Platform::ComponentStatus::REMEDIATION_NONE, evidence: %w[a b])
      )

      expect(described_class.route(component, signal_kind: "instance.silent")[:evidence]).to eq(%w[a b])
    end

    # Core's runbook is core's. A lane that returns one does not overwrite it.
    it "does not let a lane overwrite the runbook" do
      Platform::Runbook::Registry.register_source(
        doc_source("instance.silent" => { "doc" => "docs/runbooks/silent.md#triage" })
      )
      Platform::Remediation::Registry.register_lane(
        "instance.silent",
        fake_lane(state: Platform::ComponentStatus::REMEDIATION_NONE, runbook: { kind: "doc", doc: "IMPOSTOR" })
      )

      expect(described_class.route(component, signal_kind: "instance.silent")[:runbook])
        .to include(doc: "docs/runbooks/silent.md#triage")
    end
  end

  # INV-1 — design §5.1's named oracle, both arms. The refusal is the LANE's;
  # the router must not paraphrase it, and must not spread it to a sibling.
  describe "INV-1 self-management refusal" do
    let(:self_hosting) do
      create(:platform_component_status, account: account,
                                         component_kind: "node_instance", component_ref: "self-hosting-instance")
    end
    let(:sibling) do
      create(:platform_component_status, account: account,
                                         component_kind: "node_instance", component_ref: "some-other-instance")
    end

    let(:inv1_reason) { "INV-1: refusing to remediate the instance hosting this control plane" }

    before do
      lane = Object.new
      lane.define_singleton_method(:key) { "fleet_autonomy" }
      reason = inv1_reason
      lane.define_singleton_method(:describe) do |component_status, _kind, account: nil|
        if component_status.component_ref == "self-hosting-instance"
          { state: Platform::ComponentStatus::REMEDIATION_NOT_ACTUATABLE,
            can_proceed: false, reason: reason }
        else
          { state: Platform::ComponentStatus::REMEDIATION_AUTO_IN_PROGRESS,
            can_proceed: true, reason: nil }
        end
      end
      Platform::Remediation::Registry.register_lane("instance.unreachable", lane)
    end

    it "passes the lane's refusal through in the lane's own words" do
      result = described_class.route(self_hosting, signal_kind: "instance.unreachable")

      expect(result[:state]).to eq(Platform::ComponentStatus::REMEDIATION_NOT_ACTUATABLE)
      expect(result[:can_proceed]).to be false
      # The reason string is the LANE's, not one core manufactured. Asserted
      # against core's own vocabulary too, so a router that quietly replaced
      # the text with NoLaneForSignal cannot pass.
      expect(result[:reason]).to eq(inv1_reason)
      expect(result[:reason]).not_to eq(described_class::NO_LANE)
    end

    it "does not apply the refusal to a sibling component" do
      result = described_class.route(sibling, signal_kind: "instance.unreachable")

      expect(result[:state]).to eq(Platform::ComponentStatus::REMEDIATION_AUTO_IN_PROGRESS)
      expect(result[:can_proceed]).to be true
      expect(result[:reason]).to be_nil
    end
  end

  describe "a misbehaving lane" do
    it "refuses a state outside the model's vocabulary rather than passing it on" do
      Platform::Remediation::Registry.register_lane(
        "instance.silent",
        fake_lane(state: "pending", can_proceed: false, reason: "the lane's own reason")
      )

      result = described_class.route(component, signal_kind: "instance.silent")

      expect(result[:state]).to eq(Platform::ComponentStatus::REMEDIATION_NOT_ACTUATABLE)
      expect(result[:reason]).to eq(described_class::UNKNOWN_STATE)
      expect(result[:lane_key]).to eq("fake_lane")
    end

    it "reports a raising lane rather than rendering 'nothing to do'" do
      lane = Object.new
      lane.define_singleton_method(:key) { "exploding_lane" }
      lane.define_singleton_method(:describe) { |*, **| raise "boom" }
      Platform::Remediation::Registry.register_lane("instance.silent", lane)

      result = described_class.route(component, signal_kind: "instance.silent")

      expect(result[:state]).to eq(Platform::ComponentStatus::REMEDIATION_NOT_ACTUATABLE)
      expect(result[:reason]).to eq(described_class::LANE_ERROR)
      expect(result[:lane_key]).to eq("exploding_lane")
    end

    it "treats a non-Hash report as an unknown state" do
      Platform::Remediation::Registry.register_lane("instance.silent", fake_lane("not a hash"))

      expect(described_class.route(component, signal_kind: "instance.silent")[:reason])
        .to eq(described_class::UNKNOWN_STATE)
    end
  end

  # THE INVARIANT. Core resolves and reports; the lane's own gate decides.
  describe "core never actuates" do
    it "never calls #proceed! on a registered lane" do
      lane = instance_double("Lane", key: "spy_lane")
      allow(lane).to receive(:describe).and_return(
        state: Platform::ComponentStatus::REMEDIATION_AUTO_IN_PROGRESS, can_proceed: true
      )
      allow(lane).to receive(:proceed!)
      Platform::Remediation::Registry.register_lane("instance.silent", lane)

      described_class.route(component, signal_kind: "instance.silent")

      expect(lane).to have_received(:describe).once
      expect(lane).not_to have_received(:proceed!)
    end

    # A can_proceed the LANE said false about stays false, and core offers no
    # second opinion — there is no core-side arithmetic that could raise it.
    it "reports can_proceed false even when the lane's own numbers look ample" do
      Platform::Remediation::Registry.register_lane(
        "instance.silent",
        fake_lane(state: Platform::ComponentStatus::REMEDIATION_NOT_ACTUATABLE,
                  consent: { remaining: 99, budget: 100 },
                  can_proceed: false, reason: "the lane said no")
      )

      result = described_class.route(component, signal_kind: "instance.silent")

      expect(result[:can_proceed]).to be false
      expect(result[:reason]).to eq("the lane said no")
    end
  end
end
