# frozen_string_literal: true

require "rails_helper"

# JSON-RPC 2.0 conformance for error responses.
#
# Method handlers receive only `params`, never the envelope, so they render
# errors with a nil id. JSON-RPC 2.0 reserves a null id for requests whose id
# could not be detected (parse errors, malformed envelopes); every other error
# MUST echo the request id, or a client multiplexing concurrent requests over
# one connection cannot correlate the failure back to its call.
RSpec.describe "MCP Streamable HTTP - JSON-RPC error id", type: :request do
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

  def jsonrpc_request(method:, params: {}, id: 1)
    { jsonrpc: "2.0", id: id, method: method, params: params }.to_json
  end

  describe "errors rendered inside a method handler" do
    it "echoes the request id for a missing tools/call parameter" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "tools/call", params: { "arguments" => {} }, id: 7),
           headers: headers

      expect(json_response["error"]["code"]).to eq(-32602)
      expect(json_response["id"]).to eq(7)
    end

    it "echoes the request id for a missing resources/read parameter" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "resources/read", params: {}, id: "req-abc"),
           headers: headers

      expect(json_response["error"]["code"]).to eq(-32602)
      expect(json_response["id"]).to eq("req-abc")
    end

    it "echoes the request id for a missing prompts/get parameter" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "prompts/get", params: {}, id: 42),
           headers: headers

      expect(json_response["error"]["code"]).to eq(-32602)
      expect(json_response["id"]).to eq(42)
    end
  end

  describe "errors where the id genuinely cannot be determined" do
    it "returns a null id for unparseable JSON" do
      post mcp_endpoint, params: "{not json", headers: headers

      expect(json_response["error"]["code"]).to eq(-32700)
      expect(json_response["id"]).to be_nil
    end
  end
end
