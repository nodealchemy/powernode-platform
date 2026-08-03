# frozen_string_literal: true

require "rails_helper"

# A server capability is a promise. Advertising one the server does not
# implement is worse than omitting it: a conforming client takes the server at
# its word and calls a method that does not exist.
RSpec.describe "MCP Streamable HTTP - capability advertisement", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("ai.agents.read", account: account) }
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:oauth_token) do
    create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id, scopes: "read write")
  end
  let(:headers) do
    {
      "Authorization" => "Bearer #{oauth_token.plaintext_token}",
      "Content-Type" => "application/json"
    }
  end
  let(:mcp_endpoint) { "/api/v1/mcp/message" }

  def initialize_request(version: "2025-11-25", id: 1)
    {
      jsonrpc: "2.0",
      id: id,
      method: "initialize",
      params: { "protocolVersion" => version, "capabilities" => {}, "clientInfo" => { "name" => "spec" } }
    }.to_json
  end

  def capabilities_for(version)
    post mcp_endpoint, params: initialize_request(version: version), headers: headers
    json_response["result"]["capabilities"]
  end

  describe "resources.subscribe" do
    # resources/subscribe has no handler in this controller; revision
    # 2026-07-28 removed the method outright in favour of subscriptions/listen.
    it "is not advertised, because the method is not implemented" do
      expect(capabilities_for("2025-11-25")["resources"]).to include("subscribe" => false)
    end

    it "matches reality: calling resources/subscribe is method-not-found" do
      post mcp_endpoint,
           params: { jsonrpc: "2.0", id: 2, method: "resources/subscribe", params: { "uri" => "x" } }.to_json,
           headers: headers

      expect(json_response["error"]["code"]).to eq(-32601)
    end
  end

  describe "ServerCapabilities shape" do
    it "does not nest protocolVersion inside capabilities" do
      # protocolVersion belongs at the top level of the initialize result.
      caps = capabilities_for("2025-11-25")

      expect(caps).not_to have_key("protocolVersion")
    end

    it "reports protocolVersion at the top level of the result" do
      post mcp_endpoint, params: initialize_request(version: "2025-11-25"), headers: headers

      expect(json_response["result"]["protocolVersion"]).to eq("2025-11-25")
    end

    it "does not advertise logging (logging/setLevel is unimplemented)" do
      expect(capabilities_for("2025-11-25")).not_to have_key("logging")
    end

    it "still advertises the capabilities that are implemented" do
      caps = capabilities_for("2025-11-25")

      expect(caps["tools"]).to eq("listChanged" => true)
      expect(caps["prompts"]).to eq("listChanged" => false)
      expect(caps["resources"]).to include("listChanged" => true)
    end
  end

  describe "older revisions" do
    it "advertises the same honest shape on the oldest supported revision" do
      caps = capabilities_for("2024-11-05")

      expect(caps["resources"]).to include("subscribe" => false)
      expect(caps).not_to have_key("protocolVersion")
    end
  end
end
