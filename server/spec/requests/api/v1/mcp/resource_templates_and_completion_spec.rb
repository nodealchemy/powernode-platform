# frozen_string_literal: true

require "rails_helper"

# resources/templates/list and completion/complete are part of every protocol
# revision this server supports (2024-11-05 onward) but had no dispatch entry
# at all — both returned -32601 while resources and prompts were advertised as
# capabilities.
RSpec.describe "MCP Streamable HTTP - resource templates and completion", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("ai.agents.read", "ai.workflows.read", account: account) }
  let(:oauth_app) { create(:oauth_application, :mcp_client) }
  let(:oauth_token) do
    create(:oauth_access_token, oauth_app: oauth_app, resource_owner_id: user.id, scopes: "read write")
  end
  let(:base_headers) do
    {
      "Authorization" => "Bearer #{oauth_token.plaintext_token}",
      "Content-Type" => "application/json"
    }
  end
  let(:modern_headers) { base_headers.merge("MCP-Protocol-Version" => "2025-11-25") }
  let(:mcp_endpoint) { "/api/v1/mcp/message" }

  def jsonrpc_request(method:, params: {}, id: 1)
    { jsonrpc: "2.0", id: id, method: method, params: params }.to_json
  end

  describe "resources/templates/list" do
    it "lists the URI templates for all native resource types" do
      post mcp_endpoint, params: jsonrpc_request(method: "resources/templates/list"), headers: modern_headers

      result = json_response["result"]
      templates = result["resourceTemplates"]
      expect(templates).to be_an(Array)
      expect(templates.map { |t| t["uriTemplate"] }).to contain_exactly(
        "powernode://kb/articles/{slug}",
        "powernode://ai/agents/{id}",
        "powernode://ai/prompts/{slug}"
      )
      expect(templates).to all(include("name", "uriTemplate"))
    end
  end

  describe "completion/complete" do
    it "completes resource template arguments from live data" do
      category = create(:kb_category)
      create(:kb_article, :published, category: category, author: user, title: "Alpha Guide", slug: "alpha-guide")
      create(:kb_article, :published, category: category, author: user, title: "Beta Guide", slug: "beta-guide")

      post mcp_endpoint,
           params: jsonrpc_request(method: "completion/complete", params: {
             "ref" => { "type" => "ref/resource", "uri" => "powernode://kb/articles/{slug}" },
             "argument" => { "name" => "slug", "value" => "al" }
           }),
           headers: modern_headers

      completion = json_response["result"]["completion"]
      expect(completion["values"]).to eq(["alpha-guide"])
      expect(completion["hasMore"]).to be(false)
      expect(completion["total"]).to eq(1)
    end

    it "completes prompt arguments from enumerated options" do
      create(:shared_prompt_template, account: account, created_by: user,
             name: "Toned", slug: "toned", content: "Say it {{ tone }}",
             variables: [{ "name" => "tone", "type" => "string", "required" => true,
                           "options" => %w[formal friendly fierce] }])

      post mcp_endpoint,
           params: jsonrpc_request(method: "completion/complete", params: {
             "ref" => { "type" => "ref/prompt", "name" => "toned" },
             "argument" => { "name" => "tone", "value" => "f" }
           }),
           headers: modern_headers

      completion = json_response["result"]["completion"]
      expect(completion["values"]).to contain_exactly("formal", "friendly", "fierce")
    end

    it "returns empty values for arguments without completion data" do
      create(:shared_prompt_template, account: account, created_by: user,
             name: "Plain", slug: "plain", content: "Hello {{ name }}",
             variables: [{ "name" => "name", "type" => "string", "required" => true }])

      post mcp_endpoint,
           params: jsonrpc_request(method: "completion/complete", params: {
             "ref" => { "type" => "ref/prompt", "name" => "plain" },
             "argument" => { "name" => "name", "value" => "x" }
           }),
           headers: modern_headers

      expect(json_response["result"]["completion"]["values"]).to eq([])
    end

    it "returns -32602 for an unknown ref type" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "completion/complete", params: {
             "ref" => { "type" => "ref/bogus" },
             "argument" => { "name" => "x", "value" => "y" }
           }),
           headers: modern_headers

      expect(json_response["error"]["code"]).to eq(-32602)
    end

    it "returns -32602 for an unknown prompt" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "completion/complete", params: {
             "ref" => { "type" => "ref/prompt", "name" => "does-not-exist" },
             "argument" => { "name" => "x", "value" => "y" }
           }),
           headers: modern_headers

      expect(json_response["error"]["code"]).to eq(-32602)
    end
  end

  describe "the completions capability now matches reality" do
    def capabilities_for(version)
      post mcp_endpoint,
           params: {
             jsonrpc: "2.0", id: 1, method: "initialize",
             params: { "protocolVersion" => version, "capabilities" => {}, "clientInfo" => { "name" => "spec" } }
           }.to_json,
           headers: base_headers
      json_response["result"]["capabilities"]
    end

    it "is advertised from 2025-03-26, the revision that introduced the flag" do
      expect(capabilities_for("2025-11-25")).to have_key("completions")
      expect(capabilities_for("2025-03-26")).to have_key("completions")
    end

    it "is not advertised on 2024-11-05, which predates the flag" do
      expect(capabilities_for("2024-11-05")).not_to have_key("completions")
    end
  end
end
