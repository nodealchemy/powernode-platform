# frozen_string_literal: true

require "rails_helper"

# Worker callback endpoint for the relocated ExternalAgentCardFetchJob.
# The worker performs the external HTTP GET and posts the raw outcome here;
# this endpoint does the A2A parse/validate/persist (pattern B — all model/DB
# access stays on the server).
RSpec.describe "Api::V1::Internal::ExternalAgents#card_result", type: :request do
  include_context "internal api auth"

  let(:agent) do
    create(:external_agent, account: internal_account,
                            agent_card_url: "https://example.com/.well-known/agent-card.json",
                            health_status: "unknown")
  end

  let(:path) { "/api/v1/internal/external_agents/#{agent.id}/card_result" }

  let(:valid_card) do
    {
      "name" => "External Agent",
      "url" => "https://example.com/a2a",
      "version" => "1.0.0",
      "skills" => [ { "id" => "test.skill", "name" => "Test", "description" => "d", "tags" => [] } ],
      "capabilities" => { "streaming" => true }
    }
  end

  it "requires worker mTLS authentication" do
    post path, params: { http_status: 200, body: valid_card.to_json }, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  context "with a successful fetch outcome { http_status, body }" do
    it "parses, validates, and persists the card; returns 2xx" do
      post path,
           params: { http_status: 200, body: valid_card.to_json },
           headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig("data", "outcome")).to eq("success")

      agent.reload
      expect(agent.cached_card["name"]).to eq("External Agent")
      expect(agent.card_version).to eq("1.0.0")
      expect(agent.skills.first["id"]).to eq("test.skill")
      expect(agent.capabilities["streaming"]).to be true
      expect(agent.health_status).to eq("healthy")
    end

    it "is idempotent — applying the same result twice yields the same state" do
      2.times do
        post path, params: { http_status: 200, body: valid_card.to_json },
                   headers: service_headers, as: :json
        expect(response).to have_http_status(:ok)
      end

      expect(agent.reload.health_status).to eq("healthy")
    end
  end

  context "with a failure outcome { error }" do
    it "marks the agent unhealthy and returns 2xx" do
      post path, params: { error: "Connection refused" },
                 headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig("data", "outcome")).to eq("failed")

      agent.reload
      expect(agent.health_status).to eq("unhealthy")
      expect(agent.health_details["error"]).to eq("Connection refused")
    end
  end

  context "with a malformed body (invalid JSON)" do
    it "never 500s — returns 2xx and marks the agent unhealthy" do
      post path, params: { http_status: 200, body: "not json at all" },
                 headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response).not_to have_http_status(:internal_server_error)

      agent.reload
      expect(agent.health_status).to eq("unhealthy")
      expect(agent.health_details["error"]).to include("Invalid JSON")
    end
  end

  context "with a body missing required A2A fields" do
    it "returns 2xx and marks the agent unhealthy" do
      post path, params: { http_status: 200, body: { "description" => "no name/url" }.to_json },
                 headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      agent.reload
      expect(agent.health_status).to eq("unhealthy")
      expect(agent.health_details["error"]).to include("missing required fields")
    end
  end

  context "when the agent no longer exists" do
    it "returns 2xx as an idempotent no-op (no worker retry storm)" do
      post "/api/v1/internal/external_agents/#{SecureRandom.uuid}/card_result",
           params: { http_status: 200, body: valid_card.to_json },
           headers: service_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig("data", "reason")).to eq("agent_not_found")
    end
  end
end
