# frozen_string_literal: true

require "rails_helper"

RSpec.describe Platform::Remediation::Registry do
  # A minimal lane. Deliberately NOT a subclass of Platform::Remediation::Lane
  # in every example: the registry accepts a duck type, and a spec that only
  # ever registers subclasses would not prove that.
  let(:lane) { instance_double("Lane", describe: {}, key: "fake_lane") }

  before { described_class.reset! }
  after  { described_class.reset! }

  describe ".register_lane" do
    it "registers and resolves a lane by signal kind" do
      described_class.register_lane("instance.silent", lane)

      expect(described_class.lane_for("instance.silent")).to be(lane)
      expect(described_class.registered?("instance.silent")).to be true
    end

    it "accepts a plain duck type that answers #describe" do
      duck = Object.new
      def duck.describe(_component, _kind, account: nil) = { state: "none" }

      expect { described_class.register_lane("duck.kind", duck) }.not_to raise_error
      expect(described_class.lane_for("duck.kind")).to be(duck)
    end

    it "refuses an object that cannot describe" do
      expect { described_class.register_lane("bad.kind", Object.new) }
        .to raise_error(ArgumentError, /must respond to #describe/)
      expect(described_class.lane_for("bad.kind")).to be_nil
    end

    it "refuses a blank signal kind" do
      expect { described_class.register_lane("  ", lane) }
        .to raise_error(ArgumentError, /must be present/)
    end

    # to_prepare re-runs per reload; re-registering must replace, not raise.
    it "is idempotent and last-write-wins" do
      other = instance_double("OtherLane", describe: {})
      described_class.register_lane("instance.silent", lane)
      described_class.register_lane("instance.silent", other)

      expect(described_class.lane_for("instance.silent")).to be(other)
      expect(described_class.lanes.size).to eq(1)
    end

    it "normalizes the kind so a symbol and a padded string are one key" do
      described_class.register_lane(:"instance.silent", lane)

      expect(described_class.lane_for(" instance.silent ")).to be(lane)
    end
  end

  describe ".lanes" do
    it "hands out a frozen copy so a reader cannot mutate the live store" do
      described_class.register_lane("a.kind", lane)
      copy = described_class.lanes

      expect(copy).to be_frozen
      expect { copy["b.kind"] = lane }.to raise_error(FrozenError)
      expect(described_class.lane_for("b.kind")).to be_nil
    end
  end

  describe ".unregister" do
    it "removes the lane and returns it" do
      described_class.register_lane("a.kind", lane)

      expect(described_class.unregister("a.kind")).to be(lane)
      expect(described_class.lane_for("a.kind")).to be_nil
    end

    it "returns nil for a kind that was never registered" do
      expect(described_class.unregister("never.registered")).to be_nil
    end
  end

  # THE DEFAULT. Not decoration: design §5.1 makes "no lane" the answer for
  # every platform_subsystem recommendation, and that property is a
  # consequence of core registering nothing.
  describe "the empty default" do
    it "claims no signal kind of its own after reset" do
      expect(described_class.lanes).to be_empty
      expect(described_class.lane_for("platform_subsystem.anything")).to be_nil
    end
  end
end
