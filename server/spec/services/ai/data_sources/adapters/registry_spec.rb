# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DataSources::Adapters::Registry do
  # A minimal protocol carrier — avoids a DB round-trip for the registry, which
  # only reads #protocol off the data source.
  def source_with_protocol(protocol)
    instance_double(Ai::DataSource, protocol: protocol)
  end

  describe ".for" do
    it "resolves the 'rest' protocol to the generic RestAdapter" do
      adapter = described_class.for(source_with_protocol("rest"))

      expect(adapter).to be_an_instance_of(Ai::DataSources::Adapters::RestAdapter)
    end

    it "resolves the 'custom' protocol to the RestAdapter (hand-rolled template, not a bespoke class)" do
      adapter = described_class.for(source_with_protocol("custom"))

      expect(adapter).to be_an_instance_of(Ai::DataSources::Adapters::RestAdapter)
    end

    it "falls back to the generic RestAdapter for an unknown protocol" do
      adapter = described_class.for(source_with_protocol("graphql"))

      expect(adapter).to be_an_instance_of(Ai::DataSources::Adapters::RestAdapter)
    end

    it "falls back to the generic RestAdapter for a blank protocol" do
      expect(described_class.for(source_with_protocol("")))
        .to be_an_instance_of(Ai::DataSources::Adapters::RestAdapter)
    end

    it "falls back to the generic RestAdapter for a nil data source" do
      expect(described_class.for(nil)).to be_an_instance_of(Ai::DataSources::Adapters::RestAdapter)
    end

    it "normalizes case + surrounding whitespace before lookup" do
      expect(described_class.for(source_with_protocol("  REST  ")))
        .to be_an_instance_of(Ai::DataSources::Adapters::RestAdapter)
    end

    it "accepts a raw protocol token (String) directly, not just a data source" do
      expect(described_class.for("rest")).to be_an_instance_of(Ai::DataSources::Adapters::RestAdapter)
    end

    it "returns an object conforming to the adapter contract (build_request + parse)" do
      adapter = described_class.for(source_with_protocol("rest"))

      expect(adapter).to respond_to(:build_request)
      expect(adapter).to respond_to(:parse)
    end

    it "resolves against a real persisted data source's protocol column" do
      ds = create(:ai_data_source, protocol: "rest")

      expect(described_class.for(ds)).to be_an_instance_of(Ai::DataSources::Adapters::RestAdapter)
    end
  end

  describe ".known_protocol?" do
    it "is true for registered protocols" do
      expect(described_class.known_protocol?("rest")).to be(true)
      expect(described_class.known_protocol?("custom")).to be(true)
    end

    it "is true regardless of case/whitespace" do
      expect(described_class.known_protocol?(" REST ")).to be(true)
    end

    it "is false for an unregistered protocol that only hits the generic fallback" do
      expect(described_class.known_protocol?("graphql")).to be(false)
    end
  end

  describe ".protocols" do
    it "lists the registered protocol tokens" do
      expect(described_class.protocols).to contain_exactly("rest", "custom")
    end
  end
end
