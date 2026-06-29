# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Mcp::Resources", type: :request do
  let(:account) { create(:account) }
  # mcp.tools.read is the capability guard the controller shares with its
  # sibling PromptsController/McpToolsController.
  let(:user) { create(:user, account: account, permissions: ["mcp.tools.read"]) }
  let(:json_headers) { auth_headers_for(user).merge("Content-Type" => "application/json") }

  # A connected MCP server whose capabilities advertise resources, so the
  # controller's #discover_resources returns a non-empty list and #set_resource
  # can resolve :id for the read action (which proceeds past the connected?
  # guard in #read_resource_content).
  let(:resource_uri) { "file:///tmp/test.txt" }

  let(:mcp_server) do
    create(:mcp_server, :connected, account: account).tap do |server|
      server.update!(
        capabilities: server.capabilities.merge(
          "resources" => true,
          "discovered_resources" => [
            {
              "id" => "resource_1",
              "uri" => resource_uri,
              "name" => "Test Resource",
              "description" => "A resource for testing",
              "mimeType" => "text/plain"
            }
          ]
        )
      )
    end
  end

  let(:resource_id) { "resource_1" }
  let(:read_path) { "/api/v1/mcp/mcp_servers/#{mcp_server.id}/resources/#{resource_id}/read" }

  # The resource-read path: #read must read the resource synchronously through
  # the server-side Mcp::ResourceService and return its content. (It previously
  # called WorkerJobService.execute_mcp_resource_read — a method that does not
  # exist — which raised NoMethodError that escaped the WorkerServiceError rescue
  # and 500'd on every connected-server read. Same fix as PromptsController#execute.)
  describe "POST read" do
    it "reads the resource via Mcp::ResourceService and returns its content" do
      expect_any_instance_of(Mcp::ResourceService)
        .to receive(:read_resource).with(resource_uri)
        .and_return({ success: true, content: "hello", mime_type: "text/plain", uri: resource_uri })

      post read_path, headers: json_headers

      expect(response).to have_http_status(:ok)
      data = json_response["data"]
      expect(data["uri"]).to eq(resource_uri)
      expect(data["content"]).to eq("hello")
      expect(data["mime_type"]).to eq("text/plain")
    end

    it "returns 200 with null content (no 500) when the service reports failure" do
      allow_any_instance_of(Mcp::ResourceService)
        .to receive(:read_resource)
        .and_return({ success: false, error: "boom" })

      post read_path, headers: json_headers

      expect(response).to have_http_status(:ok)
      data = json_response["data"]
      expect(data["content"]).to be_nil
      expect(data["mime_type"]).to be_nil
    end
  end

  # Authorization: this controller previously had NO capability guard (its sibling
  # PromptsController did). Account/server ownership was already enforced via
  # #set_mcp_server, but any authenticated member could list/read resources.
  describe "capability authorization" do
    let(:unprivileged_user) { create(:user, account: account, permissions: []) }
    let(:unprivileged_headers) { auth_headers_for(unprivileged_user).merge("Content-Type" => "application/json") }

    it "forbids index without mcp.tools.read" do
      get "/api/v1/mcp/mcp_servers/#{mcp_server.id}/resources", headers: unprivileged_headers

      expect(response).to have_http_status(:forbidden)
    end

    it "forbids read without mcp.tools.read" do
      post read_path, headers: unprivileged_headers

      expect(response).to have_http_status(:forbidden)
    end
  end

  # Cross-tenant ownership is enforced by #set_mcp_server
  # (current_user.account.mcp_servers.find) — a foreign account's server is never
  # resolvable, so its resources can't be listed or read. (Documents that the
  # cross-tenant IDOR does not reproduce: this was already scoped.)
  describe "cross-tenant server ownership" do
    let(:other_account) { create(:account) }
    let(:foreign_server) do
      create(:mcp_server, :connected, account: other_account).tap do |server|
        server.update!(
          capabilities: server.capabilities.merge(
            "resources" => true,
            "discovered_resources" => [
              { "id" => "resource_1", "uri" => resource_uri, "name" => "X", "mimeType" => "text/plain" }
            ]
          )
        )
      end
    end

    it "cannot list resources on another account's server (404)" do
      get "/api/v1/mcp/mcp_servers/#{foreign_server.id}/resources", headers: json_headers

      expect(response).to have_http_status(:not_found)
    end

    it "cannot read a resource on another account's server (404)" do
      post "/api/v1/mcp/mcp_servers/#{foreign_server.id}/resources/#{resource_id}/read", headers: json_headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
