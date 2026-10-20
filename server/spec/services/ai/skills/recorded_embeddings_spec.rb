# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Skills::RecordedEmbeddings do
  describe ".merge_owned" do
    before do
      allow(described_class).to receive(:native_keys) do |owner|
        { "core" => Set["core-text"], "extensions/x" => Set["ext-text"] }.fetch(owner, Set.new)
      end
    end

    it "prefers the owner whose own batch contains the text on a differing collision, and warns" do
      expect(Rails.logger).to receive(:warn).with(/ext-text recorded differently/)
      merged = described_class.merge_owned([ [ "core", { "ext-text" => "CORE" } ], [ "extensions/x", { "ext-text" => "EXT" } ] ])
      expect(merged["ext-text"]).to eq("EXT")
    end

    it "keeps core's vector when the text is native to neither (or to core), whatever the order" do
      merged = described_class.merge_owned([ [ "core", { "core-text" => "CORE", "shared" => "C" } ],
                                             [ "extensions/x", { "core-text" => "EXT", "shared" => "E" } ] ])
      expect(merged).to include("core-text" => "CORE", "shared" => "C")
    end

    it "merges identical vectors silently" do
      expect(Rails.logger).not_to receive(:warn)
      merged = described_class.merge_owned([ [ "core", { "a" => "V" } ], [ "extensions/x", { "a" => "V", "b" => "W" } ] ])
      expect(merged).to eq("a" => "V", "b" => "W")
    end
  end

  it "round-trips a vector through the compact encoding" do
    vector = Array.new(1536) { |i| Math.sin(i) }
    decoded = described_class.decode(described_class.encode(vector))
    full = described_class.normalise(vector.first(described_class::DIMENSIONS))
    expect(Ai::Skills::LexicalEmbedder.cosine(decoded, full)).to be > 0.999
  end
end
