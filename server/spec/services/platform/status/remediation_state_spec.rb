# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::Status::RemediationState do
  let(:account) { create(:account) }
  let(:component) { create(:platform_component_status, account: account, component_kind: "node_instance") }
  let(:cs) { Platform::ComponentStatus }

  before do
    Platform::Remediation::Registry.reset!
    Platform::Runbook::Registry.reset!
  end

  after do
    Platform::Remediation::Registry.reset!
    Platform::Runbook::Registry.reset!
  end

  def register_lane(kind, state:, can_proceed: true)
    lane = Object.new
    lane.define_singleton_method(:key) { "fake_lane" }
    lane.define_singleton_method(:describe) do |_component, _k, account: nil|
      { state: state, can_proceed: can_proceed }
    end
    Platform::Remediation::Registry.register_lane(kind, lane)
  end

  def fact(overrides = {})
    { signal_kind: "instance.silent", fingerprint: "fp-1", approval_request_id: nil,
      last_outcome: nil, stuck: false }.merge(overrides)
  end

  describe "the six states" do
    it "derives none when nothing is signalling" do
      payload = described_class.derive(component, signals: [])

      expect(payload["state"]).to eq(cs::REMEDIATION_NONE)
      expect(component.reload.remediation["state"]).to eq(cs::REMEDIATION_NONE)
    end

    it "derives not_actuatable when no lane claims the kind" do
      payload = described_class.derive(component, signals: [ fact ])

      expect(payload["state"]).to eq(cs::REMEDIATION_NOT_ACTUATABLE)
    end

    it "derives auto_in_progress from the lane's own report" do
      register_lane("instance.silent", state: cs::REMEDIATION_AUTO_IN_PROGRESS)

      expect(described_class.derive(component, signals: [ fact ])["state"])
        .to eq(cs::REMEDIATION_AUTO_IN_PROGRESS)
    end

    it "derives awaiting_operator when an approval has been parked" do
      register_lane("instance.silent", state: cs::REMEDIATION_AUTO_IN_PROGRESS)

      expect(described_class.derive(component, signals: [ fact(approval_request_id: "req-1") ])["state"])
        .to eq(cs::REMEDIATION_AWAITING_OPERATOR)
    end

    it "derives stuck" do
      register_lane("instance.silent", state: cs::REMEDIATION_AUTO_IN_PROGRESS)

      expect(described_class.derive(component, signals: [ fact(stuck: true) ])["state"])
        .to eq(cs::REMEDIATION_STUCK)
    end

    it "derives remediated from a succeeded outcome" do
      register_lane("instance.silent", state: cs::REMEDIATION_AUTO_IN_PROGRESS)

      expect(described_class.derive(component, signals: [ fact(last_outcome: "succeeded") ])["state"])
        .to eq(cs::REMEDIATION_REMEDIATED)
    end

    it "writes a state the model accepts, for every one of the six" do
      cs::REMEDIATION_STATES.each do |state|
        component.update!(remediation: { "state" => state })
        expect(component.reload).to be_valid, "model rejected the derived state #{state}"
      end
    end
  end

  describe "precedence" do
    # A stuck remediation that also has an approval parked is still stuck.
    # Calling it awaiting_operator says the ball is in the operator's court
    # when the news is that the last attempt did not finish.
    it "ranks stuck above awaiting_operator on the same fact" do
      register_lane("instance.silent", state: cs::REMEDIATION_AUTO_IN_PROGRESS)

      expect(described_class.derive(component, signals: [ fact(stuck: true, approval_request_id: "req-1") ])["state"])
        .to eq(cs::REMEDIATION_STUCK)
    end

    it "ranks a failing outcome's lane state above a remediated sibling" do
      register_lane("a.kind", state: cs::REMEDIATION_AUTO_IN_PROGRESS)
      register_lane("b.kind", state: cs::REMEDIATION_AUTO_IN_PROGRESS)

      payload = described_class.derive(component, signals: [
        fact(signal_kind: "a.kind", fingerprint: "fp-a", last_outcome: "succeeded"),
        fact(signal_kind: "b.kind", fingerprint: "fp-b")
      ])

      expect(payload["state"]).to eq(cs::REMEDIATION_AUTO_IN_PROGRESS)
      expect(payload["signal_kind"]).to eq("b.kind")
    end

    it "ranks not_actuatable above auto_in_progress" do
      register_lane("handled.kind", state: cs::REMEDIATION_AUTO_IN_PROGRESS)

      payload = described_class.derive(component, signals: [
        fact(signal_kind: "handled.kind", fingerprint: "fp-a"),
        fact(signal_kind: "unclaimed.kind", fingerprint: "fp-b")
      ])

      expect(payload["state"]).to eq(cs::REMEDIATION_NOT_ACTUATABLE)
      expect(payload["signal_kind"]).to eq("unclaimed.kind")
    end

    # Both arms of the ladder, so a rank table that collapsed to a constant
    # cannot pass.
    it "orders the whole ladder" do
      ordered = [ cs::REMEDIATION_NONE, cs::REMEDIATION_REMEDIATED, cs::REMEDIATION_AUTO_IN_PROGRESS,
                  cs::REMEDIATION_NOT_ACTUATABLE, cs::REMEDIATION_AWAITING_OPERATOR, cs::REMEDIATION_STUCK ]
      ranks = ordered.map { |state| described_class.rank_of(state) }

      expect(ranks).to eq(ranks.sort)
      expect(ranks.uniq.size).to eq(ordered.size)
    end
  end

  describe "the persisted payload" do
    it "carries the worst fact's own identity and the routed runbook" do
      Platform::Runbook::Registry.register("instance.silent", doc: "docs/runbooks/silent.md#triage")
      register_lane("instance.silent", state: cs::REMEDIATION_AUTO_IN_PROGRESS)

      payload = described_class.derive(component, signals: [ fact(fingerprint: "occurrence-7") ])

      expect(payload.keys).to match_array(described_class::PAYLOAD_KEYS)
      expect(payload["signal_kind"]).to eq("instance.silent")
      expect(payload["fingerprint"]).to eq("occurrence-7")
      expect(payload["runbook"]).to include(kind: "doc", path: "docs/runbooks/silent.md")
    end

    it "carries every payload key even with no signals" do
      payload = described_class.derive(component, signals: [])

      expect(payload.keys).to match_array(described_class::PAYLOAD_KEYS)
      expect(payload["stuck"]).to be false
    end

    it "accepts symbol-keyed and string-keyed facts alike" do
      register_lane("instance.silent", state: cs::REMEDIATION_AUTO_IN_PROGRESS)

      symbolic = described_class.build(component, signals: [ fact(fingerprint: "fp-x") ])
      stringy  = described_class.build(component, signals: [ fact(fingerprint: "fp-x").transform_keys(&:to_s) ])

      expect(stringy).to eq(symbolic)
    end

    # A fact that came back through JSON carries "false", which is truthy in
    # Ruby and would mark every such component stuck.
    it "does not read the string \"false\" as stuck" do
      register_lane("instance.silent", state: cs::REMEDIATION_AUTO_IN_PROGRESS)

      expect(described_class.build(component, signals: [ fact(stuck: "false") ])["state"])
        .to eq(cs::REMEDIATION_AUTO_IN_PROGRESS)
      expect(described_class.build(component, signals: [ fact(stuck: "true") ])["state"])
        .to eq(cs::REMEDIATION_STUCK)
    end

    it "drops a fact with no signal kind rather than deriving from it" do
      expect(described_class.build(component, signals: [ fact(signal_kind: nil) ])["state"])
        .to eq(cs::REMEDIATION_NONE)
    end
  end

  describe ".build" do
    it "does not write" do
      register_lane("instance.silent", state: cs::REMEDIATION_AUTO_IN_PROGRESS)

      expect { described_class.build(component, signals: [ fact ]) }
        .not_to change { component.reload.remediation }
    end
  end

  describe "routing cost" do
    # A lane is a live gate check. Asking it twice for one fact is not free
    # and, for a lane that counts its own consultations, is not idempotent.
    it "consults the lane exactly once per fact" do
      lane = instance_double("Lane", key: "counting_lane")
      allow(lane).to receive(:describe).and_return(state: cs::REMEDIATION_AUTO_IN_PROGRESS, can_proceed: true)
      Platform::Remediation::Registry.register_lane("instance.silent", lane)

      described_class.derive(component, signals: [ fact ])

      expect(lane).to have_received(:describe).once
    end
  end
end
