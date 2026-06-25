# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Mcp::Prompts", type: :request do
  let(:account) { create(:account) }

  # A connected MCP server whose capabilities advertise prompts, so the
  # controller's #discover_prompts returns a non-empty list and #set_prompt
  # can resolve :id for show/execute.
  let(:mcp_server) do
    create(:mcp_server, :connected, account: account).tap do |server|
      server.update!(
        capabilities: server.capabilities.merge(
          "discovered_prompts" => [
            {
              "id" => "prompt_1",
              "name" => "summarize",
              "description" => "Summarize text",
              "arguments" => [
                { "name" => "text", "description" => "Text to summarize", "required" => true }
              ]
            }
          ]
        )
      )
    end
  end

  let(:prompt_id) { "prompt_1" }

  let(:index_path)   { "/api/v1/mcp/mcp_servers/#{mcp_server.id}/prompts" }
  let(:show_path)    { "/api/v1/mcp/mcp_servers/#{mcp_server.id}/prompts/#{prompt_id}" }
  let(:execute_path) { "/api/v1/mcp/mcp_servers/#{mcp_server.id}/prompts/#{prompt_id}/execute" }

  describe "authorization" do
    context "when the user has no permissions" do
      let(:user) { create(:user, account: account, permissions: []) }

      it "forbids GET index" do
        get index_path, headers: auth_headers_for(user)
        expect(response).to have_http_status(:forbidden)
      end

      it "forbids GET show" do
        get show_path, headers: auth_headers_for(user)
        expect(response).to have_http_status(:forbidden)
      end

      it "forbids POST execute" do
        post execute_path,
             params: { arguments: { text: "hello" } }.to_json,
             headers: auth_headers_for(user)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when the user holds mcp.tools.read" do
      let(:user) { create(:user, account: account, permissions: [ "mcp.tools.read" ]) }

      it "permits GET index" do
        get index_path, headers: auth_headers_for(user)
        expect(response).not_to have_http_status(:forbidden)
      end

      it "permits GET show" do
        get show_path, headers: auth_headers_for(user)
        expect(response).not_to have_http_status(:forbidden)
      end

      it "forbids POST execute (read does not grant execute)" do
        post execute_path,
             params: { arguments: { text: "hello" } }.to_json,
             headers: auth_headers_for(user)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when the user holds mcp.tools.execute" do
      let(:user) { create(:user, account: account, permissions: [ "mcp.tools.execute" ]) }

      # Force the server to report as disconnected so #execute_prompt
      # short-circuits before reaching the worker service. This keeps the
      # assertion focused on authorization (gate passes -> not forbidden),
      # independent of downstream prompt-dispatch behaviour.
      before do
        allow_any_instance_of(McpServer).to receive(:connected?).and_return(false)
      end

      it "permits POST execute" do
        post execute_path,
             params: { arguments: { text: "hello" } }.to_json,
             headers: auth_headers_for(user)
        expect(response).not_to have_http_status(:forbidden)
      end
    end
  end

  # The prompt-dispatch path: #execute must run the prompt synchronously through
  # the server-side Mcp::PromptService and return its messages. (It previously
  # called WorkerJobService.execute_mcp_prompt — a method that does not exist —
  # which raised NoMethodError -> 500 on every connected-server dispatch.)
  describe "prompt execution dispatch" do
    let(:user) { create(:user, account: account, permissions: [ "mcp.tools.execute" ]) }
    let(:json_headers) { auth_headers_for(user).merge("Content-Type" => "application/json") }

    it "executes the prompt via Mcp::PromptService and returns its messages" do
      messages = [ { "role" => "user", "content" => "Summarize: hello" } ]
      expect_any_instance_of(Mcp::PromptService)
        .to receive(:execute_prompt).with("summarize", anything)
        .and_return({ success: true, messages: messages, description: "Summarize text" })

      post execute_path, params: { arguments: { text: "hello" } }.to_json, headers: json_headers

      expect(response).to have_http_status(:ok)
      data = json_response["data"]
      expect(data["prompt_id"]).to eq("prompt_1")
      expect(data["messages"]).to eq(messages)
    end

    it "returns 422 with the service error when prompt execution fails" do
      allow_any_instance_of(Mcp::PromptService)
        .to receive(:execute_prompt)
        .and_return({ success: false, error: "upstream prompt error" })

      post execute_path, params: { arguments: { text: "hello" } }.to_json, headers: json_headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
