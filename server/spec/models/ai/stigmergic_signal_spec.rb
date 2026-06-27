# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::StigmergicSignal do
  let(:account) { create(:account) }

  def signal(type)
    described_class.new(
      account: account, signal_type: type, signal_key: "k",
      strength: 0.5, decay_rate: 0.05
    )
  end

  describe "signal_type validation" do
    it "accepts the core base categories" do
      %w[pheromone pressure beacon warning discovery entry].each do |t|
        expect(signal(t)).to be_valid, "expected #{t.inspect} to be valid"
      end
    end

    # Core and extensions emit namespaced/semantic signal types and perceivers
    # query by exactly these (e.g. "system.capacity_pressure"). A closed enum
    # silently rejected them, so the stigmergic layer dropped most signals.
    # The validation must accept any well-formed namespaced token.
    it "accepts namespaced signal types from any subsystem" do
      %w[system.capacity_pressure system.fleet_error_pressure system.region_busy
         ext.custom_pressure subsystem.some_signal].each do |t|
        expect(signal(t)).to be_valid, "expected #{t.inspect} to be valid"
      end
    end

    it "rejects blank or malformed signal types" do
      [nil, "", "Has Space", "UPPER", "bad/slash", ".leading", "trailing."].each do |t|
        expect(signal(t)).not_to be_valid, "expected #{t.inspect} to be invalid"
      end
    end
  end
end
