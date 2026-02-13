# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::ApiReferenceTool do
  let(:account) { create(:account) }
  let(:tool) { described_class.new(account: account) }

  describe ".definition" do
    it "returns a valid tool definition" do
      defn = described_class.definition
      expect(defn[:name]).to eq("get_api_reference")
      expect(defn[:description]).to be_present
      expect(defn[:parameters]).to include(:section)
    end

    it "marks section as optional" do
      expect(described_class.definition[:parameters][:section][:required]).to be false
    end
  end

  describe ".permitted?" do
    it "requires ai.agents.read permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("ai.agents.read")
    end
  end

  describe "#execute" do
    let(:reference_path) { Ai::Tools::ApiReferenceTool::API_REFERENCE_PATH }

    context "when reference file exists" do
      before do
        allow(File).to receive(:exist?).with(reference_path).and_return(true)
        allow(File).to receive(:read).with(reference_path).and_return(<<~MD)
          # API Reference

          ## Workflows

          Create and manage workflows.

          ## Agents

          Deploy and manage agents.

          ## Teams

          Team operations.
        MD
      end

      it "returns the full reference" do
        result = tool.execute(params: {})
        expect(result[:success]).to be true
        expect(result[:reference]).to include("API Reference")
        expect(result[:sections]).to be_an(Array)
      end

      it "extracts section headers" do
        result = tool.execute(params: {})
        expect(result[:sections]).to include("Workflows", "Agents", "Teams")
      end

      it "filters by section" do
        result = tool.execute(params: { section: "Agents" })
        expect(result[:success]).to be true
        expect(result[:reference]).to include("Agents")
        expect(result[:reference]).not_to include("## Workflows")
      end

      it "returns full content when section is not found" do
        result = tool.execute(params: { section: "Nonexistent" })
        expect(result[:success]).to be true
        expect(result[:reference]).to include("API Reference")
      end
    end

    context "when reference file does not exist" do
      before do
        allow(File).to receive(:exist?).with(reference_path).and_return(false)
      end

      it "returns error" do
        result = tool.execute(params: {})
        expect(result[:success]).to be false
        expect(result[:error]).to match(/not found/)
      end
    end
  end
end
