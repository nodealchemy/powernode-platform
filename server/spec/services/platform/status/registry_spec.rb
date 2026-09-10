# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A1 — the generic seam.
RSpec.describe Platform::Status::Registry do
  # The registry is process-global. Snapshot and restore rather than reset!,
  # so a spec cannot silently delete the kinds the application registered at
  # boot and leave a later spec measuring an empty registry.
  around do |example|
    saved = described_class.contributors
    described_class.reset!
    example.run
  ensure
    described_class.reset!
    saved.each { |kind, contributor| described_class.register(kind, contributor) }
  end

  let(:contributor) { instance_double("contributor", each_component: nil) }

  it "registers, fetches and lists a kind" do
    described_class.register("fake_kind", contributor)

    expect(described_class.fetch("fake_kind")).to be(contributor)
    expect(described_class.registered?("fake_kind")).to be(true)
    expect(described_class.kinds).to eq(%w[fake_kind])
    expect(described_class.contributors).to eq("fake_kind" => contributor)
  end

  it "reports an unregistered kind as absent, both arms" do
    expect(described_class.fetch("never_registered")).to be_nil
    expect(described_class.registered?("never_registered")).to be(false)

    described_class.register("never_registered", contributor)
    expect(described_class.registered?("never_registered")).to be(true)
  end

  it "is idempotent and last-write-wins, so a to_prepare reload replaces rather than raises" do
    replacement = instance_double("replacement", each_component: nil)

    described_class.register("fake_kind", contributor)
    expect { described_class.register("fake_kind", replacement) }.not_to raise_error

    expect(described_class.fetch("fake_kind")).to be(replacement)
    expect(described_class.kinds.size).to eq(1)
  end

  it "unregisters a kind and returns what it removed" do
    described_class.register("fake_kind", contributor)

    expect(described_class.unregister("fake_kind")).to be(contributor)
    expect(described_class.registered?("fake_kind")).to be(false)
    expect(described_class.unregister("fake_kind")).to be_nil
  end

  it "refuses a blank kind and an object that cannot enumerate" do
    expect { described_class.register("", contributor) }.to raise_error(ArgumentError, /kind must be present/)
    expect { described_class.register("fake_kind", Object.new) }.to raise_error(ArgumentError, /each_component/)
    expect(described_class.kinds).to be_empty
  end

  it "hands readers a frozen copy, so a concurrent registration cannot mutate a set being iterated" do
    described_class.register("fake_kind", contributor)
    snapshot = described_class.contributors

    expect(snapshot).to be_frozen
    described_class.register("second_kind", contributor)
    expect(snapshot.keys).to eq(%w[fake_kind])
    expect(described_class.kinds).to contain_exactly("fake_kind", "second_kind")
  end

  it "normalizes the key so a symbol and a padded string are the same kind" do
    described_class.register(:fake_kind, contributor)

    expect(described_class.fetch("fake_kind")).to be(contributor)
    expect(described_class.fetch(" fake_kind ")).to be(contributor)
  end
end
