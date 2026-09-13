# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A2 — the mirror seam's own contract,
# independent of the runner that fans out through it.
RSpec.describe Platform::Status::Emitters do
  around do |example|
    saved = described_class.handlers.dup
    described_class.reset!
    example.run
  ensure
    described_class.reset!
    saved.each { |name, handler| described_class.register(name, handler) }
  end

  let(:transition) { { component_kind: "fake_kind", component_ref: "a", from: "ok", to: "down" } }
  let(:events) { [] }

  describe "registration" do
    it "accepts a block and a callable, and lists both" do
      described_class.register(:from_block) { |**| nil }
      described_class.register(:from_callable, ->(**) { nil })

      expect(described_class.names).to contain_exactly(:from_block, :from_callable)
      expect(described_class.registered?(:from_block)).to be(true)
      expect(described_class.registered?(:never_registered)).to be(false)
    end

    it "REPLACES rather than stacks on re-registration, so a to_prepare reload does not mirror twice" do
      calls = []
      described_class.register(:mirror) { |**| calls << :first }
      described_class.register(:mirror) { |**| calls << :second }

      described_class.notify(transition: transition, events: events)

      expect(calls).to eq([ :second ])
      expect(described_class.names).to eq([ :mirror ])
    end

    it "refuses something that cannot be called" do
      expect { described_class.register(:bad, Object.new) }
        .to raise_error(ArgumentError, /status emitter/)
    end

    it "unregisters" do
      described_class.register(:mirror) { |**| nil }

      expect(described_class.unregister(:mirror)).to be_present
      expect(described_class.registered?(:mirror)).to be(false)
    end
  end

  describe ".notify" do
    it "passes the transition and the events to every emitter" do
      seen = []
      described_class.register(:one) { |transition:, events:| seen << [ :one, transition[:to], events ] }
      described_class.register(:two) { |transition:, events:| seen << [ :two, transition[:to], events ] }

      count = described_class.notify(transition: transition, events: events)

      expect(count).to eq(2)
      expect(seen).to contain_exactly([ :one, "down", events ], [ :two, "down", events ])
    end

    it "swallows a raising emitter and still runs the others" do
      reached = false
      described_class.register(:explodes) { |**| raise "mirror exploded" }
      described_class.register(:survivor) { |**| reached = true }

      expect { described_class.notify(transition: transition, events: events) }.not_to raise_error
      expect(reached).to be(true)
    end

    it "is a no-op with nothing registered" do
      expect(described_class.notify(transition: transition, events: events)).to eq(0)
    end

    it "lets an emitter register another without corrupting the iteration" do
      described_class.register(:registrar) do |**|
        described_class.register(:late) { |**| nil }
      end

      expect { described_class.notify(transition: transition, events: events) }.not_to raise_error
      expect(described_class.names).to contain_exactly(:registrar, :late)
    end
  end
end
