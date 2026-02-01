# frozen_string_literal: true

require "rails_helper"

RSpec.describe A2a::AgentCardService do
  let(:base_url) { "https://api.powernode.io" }

  describe ".platform_card" do
    subject(:card) { described_class.platform_card(base_url) }

    it "returns a valid agent card structure" do
      expect(card).to include(
        :name,
        :description,
        :url,
        :version,
        :protocolVersion,
        :capabilities,
        :authentication,
        :skills
      )
    end

    it "has correct platform name" do
      expect(card[:name]).to eq("Powernode")
    end

    it "has correct A2A URL" do
      expect(card[:url]).to eq("#{base_url}/a2a")
    end

    it "includes streaming capability" do
      expect(card[:capabilities][:streaming]).to be true
    end

    it "includes push notifications capability" do
      expect(card[:capabilities][:pushNotifications]).to be true
    end

    it "includes authentication schemes" do
      expect(card[:authentication][:schemes]).to include("bearer", "api_key")
    end

    it "includes skills from the registry" do
      expect(card[:skills]).to be_an(Array)
      expect(card[:skills]).not_to be_empty

      skill = card[:skills].first
      expect(skill).to include(:id, :name, :description)
    end

    it "includes input/output modes" do
      expect(card[:defaultInputModes]).to include("text/plain", "application/json")
      expect(card[:defaultOutputModes]).to include("text/plain", "application/json")
    end

    it "includes documentation URL" do
      expect(card[:documentation][:url]).to eq("#{base_url}/api-docs")
    end
  end

  describe ".agent_card" do
    let(:account) { create(:account) }
    let(:agent_card) { create(:ai_agent_card, account: account, name: "Test Agent") }

    subject(:card) { described_class.agent_card(agent_card, base_url) }

    it "returns nil for nil agent_card" do
      expect(described_class.agent_card(nil, base_url)).to be_nil
    end

    it "returns agent-specific card" do
      expect(card[:name]).to eq("Test Agent")
    end

    it "includes agent's capabilities" do
      expect(card[:capabilities]).to be_a(Hash)
    end

    it "includes agent's authentication config" do
      expect(card[:authentication]).to be_a(Hash)
    end

    it "uses agent's input/output modes" do
      expect(card[:defaultInputModes]).to eq(agent_card.default_input_modes)
    end
  end
end
