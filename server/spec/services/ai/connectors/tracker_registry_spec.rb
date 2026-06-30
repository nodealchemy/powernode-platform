# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Connectors::TrackerRegistry do
  # Snapshot/restore so boot-registered adapters survive these mutations.
  around do |example|
    saved = described_class.adapters.dup
    described_class.reset!
    example.run
    described_class.reset!
    saved.each { |name, adapter| described_class.register(name, adapter) }
  end

  let(:issue_adapter) { double("issue_adapter", create_issue: { ok: true }) }

  it "registers and looks up an adapter by name" do
    described_class.register(:demo, issue_adapter)

    expect(described_class.adapter(:demo)).to eq(issue_adapter)
    expect(described_class.registered?(:demo)).to be(true)
  end

  it "lists registered names and the adapters map" do
    described_class.register(:demo, issue_adapter)

    expect(described_class.names).to include(:demo)
    expect(described_class.adapters[:demo]).to eq(issue_adapter)
  end

  it "normalizes string names to symbols" do
    described_class.register("demo", issue_adapter)

    expect(described_class.adapter(:demo)).to eq(issue_adapter)
  end

  it "accepts an error-only (error-tracker) adapter" do
    error_adapter = double("error_adapter", report_error: { ok: true })

    expect { described_class.register(:err, error_adapter) }.not_to raise_error
  end

  it "rejects an object that is neither an issue nor error tracker" do
    expect { described_class.register(:bad, Object.new) }
      .to raise_error(ArgumentError, /must respond to #create_issue or #report_error/)
  end

  it "unregisters and resets adapters (isolation)" do
    described_class.register(:demo, issue_adapter)
    described_class.unregister(:demo)
    expect(described_class.registered?(:demo)).to be(false)

    described_class.register(:demo, issue_adapter)
    described_class.reset!
    expect(described_class.names).to be_empty
  end
end
