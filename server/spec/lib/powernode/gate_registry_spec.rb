# frozen_string_literal: true

require "rails_helper"

# IMP-bc4cae11fe19 — the registration seam extensions use to declare their gate
# mechanisms at boot (mirrors Ai::InterventionPolicy.register_categories!).
# Coverage of the CORE declarations themselves lives in
# gate_registry_coherence_spec.rb; this file pins the seam's contract.
RSpec.describe Powernode::GateRegistry do
  # The registry is process-global boot state (like the extension registry), so
  # every mutation here is undone — a leaked test entry would leak into the
  # coherence guard's census in the same process.
  after do
    described_class.instance_variable_get(:@mechanisms)&.delete("Fake::Ext::Gate")
  end

  describe ".register!" do
    it "records an extension-declared mechanism with its species" do
      entry = described_class.register!(
        mechanism: "Fake::Ext::Gate", species: :workflow, owner: "system",
        entry_points: %w[approve!], description: "test"
      )

      expect(entry).to be_frozen
      expect(described_class.registered?("Fake::Ext::Gate")).to be(true)
      expect(described_class.species_of("Fake::Ext::Gate")).to eq(:workflow)
      expect(described_class.for_species(:workflow).map(&:mechanism)).to include("Fake::Ext::Gate")
      expect(described_class.core_entries.map(&:mechanism)).not_to include("Fake::Ext::Gate")
    end

    it "replaces on re-registration rather than duplicating (engine reload safety)" do
      2.times do |i|
        described_class.register!(mechanism: "Fake::Ext::Gate", species: :policy,
                                  owner: "system", entry_points: [ "gate_#{i}!" ])
      end

      expect(described_class.entries.count { |e| e.mechanism == "Fake::Ext::Gate" }).to eq(1)
      expect(described_class.entry_for("Fake::Ext::Gate").entry_points).to eq(%w[gate_1!])
    end

    it "refuses a species outside the declared vocabulary" do
      expect do
        described_class.register!(mechanism: "Fake::Ext::Gate", species: :verdict,
                                  owner: "system", entry_points: %w[check])
      end.to raise_error(ArgumentError, /unknown gate species/)
      expect(described_class.registered?("Fake::Ext::Gate")).to be(false)
    end

    it "refuses a mechanism with no entry points and a blank name" do
      expect do
        described_class.register!(mechanism: "Fake::Ext::Gate", species: :policy,
                                  owner: "system", entry_points: [])
      end.to raise_error(ArgumentError, /entry_points/)
      expect do
        described_class.register!(mechanism: " ", species: :policy,
                                  owner: "system", entry_points: %w[x])
      end.to raise_error(ArgumentError, /mechanism name/)
    end
  end

  describe "species vocabulary" do
    it "is exactly the two declared species — a third is a deliberate decision, not an addition" do
      expect(described_class::SPECIES).to contain_exactly(:policy, :workflow)
    end
  end
end
