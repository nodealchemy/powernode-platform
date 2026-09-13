# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A6 — the automatic trigger (design §5.3).
RSpec.describe Platform::Investigation::TriggerEmitter do
  let(:account) { create(:account) }

  let(:subsystem) do
    create(:platform_component_status, account: account,
                                       component_kind: Platform::Investigation::Triggers::SUBSYSTEM_KIND,
                                       component_ref: "rails",
                                       verdict: Platform::ComponentStatus::DOWN)
  end

  def transition(row, to:, from: Platform::ComponentStatus::OK)
    { component_status_id: row.id, component_kind: row.component_kind,
      component_ref: row.component_ref, from: from, to: to }
  end

  around do |example|
    saved = Platform::Investigation::Triggers.kinds
    Platform::Investigation::Triggers.reset!
    example.run
  ensure
    Platform::Investigation::Triggers.reset!
    saved.each { |kind| Platform::Investigation::Triggers.register(kind) }
  end

  describe "the one transition core knows by itself" do
    it "investigates a platform_subsystem going down" do
      result = described_class.handle(transition: transition(subsystem, to: Platform::ComponentStatus::DOWN))

      expect(result[:opened]).to be(true)
      expect(result[:investigation].trigger).to eq(Platform::Investigation::TRIGGER_DOWN)
    end

    # G1: an automatic trigger has no person behind it, so ranking reaches the
    # security gate as machine-initiated spend.
    it "names no opener" do
      described_class.handle(transition: transition(subsystem, to: Platform::ComponentStatus::DOWN))

      expect(Platform::Investigation.last.opened_by_user_id).to be_nil
    end

    it "does not investigate a subsystem that merely degraded" do
      expect(described_class.handle(transition: transition(subsystem, to: Platform::ComponentStatus::DEGRADED)))
        .to be_nil
      expect(Platform::Investigation.count).to eq(0)
    end

    it "does not investigate another kind going down" do
      other = create(:platform_component_status, account: account, component_kind: "docker_host",
                                                 verdict: Platform::ComponentStatus::DOWN)

      expect(described_class.handle(transition: transition(other, to: Platform::ComponentStatus::DOWN))).to be_nil
      expect(Platform::Investigation.count).to eq(0)
    end

    # A reaped row is a transition to nil. There is nothing left to
    # investigate, and investigating one would open a row about a component
    # that no longer exists.
    it "does not investigate a reap" do
      expect(described_class.handle(transition: transition(subsystem, to: nil))).to be_nil
      expect(Platform::Investigation.count).to eq(0)
    end

    it "accepts a string-keyed transition, which is what a serialized one is" do
      raw = transition(subsystem, to: Platform::ComponentStatus::DOWN).transform_keys(&:to_s)

      expect(described_class.handle(transition: raw)[:opened]).to be(true)
    end
  end

  describe "the kinds an extension registers" do
    let(:component) do
      create(:platform_component_status, account: account, component_kind: "docker_host",
                                         verdict: Platform::ComponentStatus::DEGRADED)
    end
    let(:stuck_event) { { kind: "fleet.remediation_stuck" } }

    it "investigates an event kind that was registered" do
      Platform::Investigation::Triggers.register("fleet.remediation_stuck")

      result = described_class.handle(
        transition: transition(component, to: Platform::ComponentStatus::DEGRADED),
        events: [ stuck_event ]
      )

      expect(result[:opened]).to be(true)
      expect(result[:investigation].trigger).to eq(Platform::Investigation::TRIGGER_STUCK)
    end

    # THE OTHER ARM. Core names no extension event kind, so with nothing
    # registered the same event is not a trigger. If this passed with the
    # registry empty the seam would be decorative and core would carry the
    # extension's vocabulary in a constant.
    it "ignores the same event kind when nothing registered it" do
      expect(described_class.handle(
               transition: transition(component, to: Platform::ComponentStatus::DEGRADED),
               events: [ stuck_event ]
             )).to be_nil
      expect(Platform::Investigation.count).to eq(0)
    end

    it "reads a kind off an event object as well as a hash" do
      Platform::Investigation::Triggers.register("platform.component_down")
      event = create(:platform_status_event, :down, account: account,
                                                    component_kind: "docker_host",
                                                    component_ref: component.component_ref)

      result = described_class.handle(
        transition: transition(component, to: Platform::ComponentStatus::DEGRADED), events: [ event ]
      )

      expect(result[:opened]).to be(true)
    end
  end

  describe "the bounds are the service's, not this emitter's" do
    it "opens one investigation when the same transition fires twice" do
      described_class.handle(transition: transition(subsystem, to: Platform::ComponentStatus::DOWN))

      second = described_class.handle(transition: transition(subsystem, to: Platform::ComponentStatus::DOWN))

      expect(second).to eq(refused: Platform::InvestigationService::REFUSED_ALREADY_OPEN)
      expect(Platform::Investigation.count).to eq(1)
    end

    it "reports the cap rather than opening past it" do
      allow(Platform::InvestigationService).to receive(:daily_cap).and_return(0)

      expect(described_class.handle(transition: transition(subsystem, to: Platform::ComponentStatus::DOWN)))
        .to eq(refused: Platform::InvestigationService::REFUSED_DAILY_CAP)
    end
  end

  describe "it cannot break the thing it observes" do
    it "returns nil for a transition naming a component that is gone" do
      expect(described_class.handle(transition: { component_status_id: nil, component_kind: "x", to: "down" }))
        .to be_nil
    end

    it "returns nil rather than raising when the service blows up" do
      allow(Platform::InvestigationService).to receive(:new).and_raise("service exploded")

      expect(described_class.handle(transition: transition(subsystem, to: Platform::ComponentStatus::DOWN)))
        .to be_nil
    end

    it "ignores a transition that is not a hash" do
      expect(described_class.handle(transition: nil)).to be_nil
    end
  end

  describe "registration" do
    it "is wired into the status emitters, so a transition actually reaches it" do
      expect(Platform::Status::Emitters.registered?(:investigation)).to be(true)
    end
  end
end
