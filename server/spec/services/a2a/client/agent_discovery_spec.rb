# frozen_string_literal: true

require "rails_helper"

RSpec.describe A2a::Client::AgentDiscovery do
  describe ".fetch_card" do
    let(:agent_card_url) { "https://example.com/.well-known/agent-card.json" }
    let(:valid_card) do
      {
        "name" => "External Agent",
        "url" => "https://example.com/a2a",
        "version" => "1.0.0",
        "skills" => []
      }
    end

    context "when successful" do
      before do
        stub_request(:get, agent_card_url)
          .to_return(status: 200, body: valid_card.to_json, headers: { "Content-Type" => "application/json" })
      end

      it "returns the agent card" do
        result = described_class.fetch_card(agent_card_url)

        expect(result[:success]).to be true
        expect(result[:card]["name"]).to eq("External Agent")
      end
    end

    context "when HTTP error" do
      before do
        stub_request(:get, agent_card_url)
          .to_return(status: 404)
      end

      it "returns error" do
        result = described_class.fetch_card(agent_card_url)

        expect(result[:success]).to be false
        expect(result[:error]).to include("404")
      end
    end

    context "when invalid JSON" do
      before do
        stub_request(:get, agent_card_url)
          .to_return(status: 200, body: "not json")
      end

      it "returns error" do
        result = described_class.fetch_card(agent_card_url)

        expect(result[:success]).to be false
        expect(result[:error]).to include("Invalid JSON")
      end
    end

    context "when missing required fields" do
      before do
        stub_request(:get, agent_card_url)
          .to_return(status: 200, body: { "description" => "test" }.to_json)
      end

      it "returns error" do
        result = described_class.fetch_card(agent_card_url)

        expect(result[:success]).to be false
        expect(result[:error]).to include("missing required fields")
      end
    end
  end

  describe ".discover" do
    let(:base_url) { "https://example.com" }
    let(:well_known_url) { "https://example.com/.well-known/agent-card.json" }
    let(:valid_card) do
      {
        "name" => "External Agent",
        "url" => "https://example.com/a2a"
      }
    end

    before do
      stub_request(:get, well_known_url)
        .to_return(status: 200, body: valid_card.to_json)
    end

    it "fetches card from well-known path" do
      result = described_class.discover(base_url)

      expect(result[:success]).to be true
      expect(result[:card]["name"]).to eq("External Agent")
    end
  end

  describe ".health_check" do
    let(:agent_card_url) { "https://example.com/.well-known/agent-card.json" }
    let(:a2a_url) { "https://example.com/a2a" }
    let(:valid_card) do
      {
        "name" => "External Agent",
        "url" => a2a_url,
        "version" => "1.0.0"
      }
    end

    context "when healthy" do
      before do
        stub_request(:get, agent_card_url)
          .to_return(status: 200, body: valid_card.to_json)
        stub_request(:get, a2a_url)
          .to_return(status: 200)
      end

      it "returns healthy status" do
        result = described_class.health_check(agent_card_url)

        expect(result[:healthy]).to be true
        expect(result[:response_time_ms]).to be_present
      end
    end

    context "when card unreachable" do
      before do
        stub_request(:get, agent_card_url)
          .to_return(status: 500)
      end

      it "returns unhealthy status" do
        result = described_class.health_check(agent_card_url)

        expect(result[:healthy]).to be false
        expect(result[:error]).to be_present
      end
    end
  end

  describe ".bulk_discover" do
    let(:urls) do
      [
        "https://agent1.example.com",
        "https://agent2.example.com"
      ]
    end

    before do
      stub_request(:get, "https://agent1.example.com/.well-known/agent-card.json")
        .to_return(status: 200, body: { "name" => "Agent 1", "url" => "https://agent1.example.com/a2a" }.to_json)
      stub_request(:get, "https://agent2.example.com/.well-known/agent-card.json")
        .to_return(status: 200, body: { "name" => "Agent 2", "url" => "https://agent2.example.com/a2a" }.to_json)
    end

    it "discovers multiple agents in parallel" do
      results = described_class.bulk_discover(urls)

      expect(results.keys).to match_array(urls)
      expect(results[urls.first][:card]["name"]).to eq("Agent 1")
      expect(results[urls.last][:card]["name"]).to eq("Agent 2")
    end
  end
end
