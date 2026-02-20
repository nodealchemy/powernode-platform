# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP Streamable HTTP", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("ai.agents.read", "ai.workflows.read", "ai.workflows.execute", account: account) }
  let(:headers) { auth_headers_for(user) }
  let(:mcp_endpoint) { "/api/v1/mcp/message" }

  def jsonrpc_request(method:, params: {}, id: 1)
    { jsonrpc: "2.0", id: id, method: method, params: params }.to_json
  end

  def jsonrpc_notification(method:, params: {})
    { jsonrpc: "2.0", method: method, params: params }.to_json
  end

  # ===========================================================================
  # Section 1: Authentication
  # ===========================================================================
  describe "Authentication" do
    describe "per-user MCP token auth" do
      let(:token_result) { UserToken.create_token_for_user(user, type: "mcp", name: "test-token") }
      let(:raw_token) { token_result[:token] }
      let(:user_token) { token_result[:user_token] }

      it "authenticates with pnmcp_ prefixed token" do
        mcp_headers = {
          "Authorization" => "Bearer pnmcp_#{raw_token}",
          "Content-Type" => "application/json"
        }

        post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: mcp_headers

        expect(response).to have_http_status(:ok)
        expect(json_response["result"]).to eq({})
      end

      it "authenticates without pnmcp_ prefix for backward compatibility" do
        mcp_headers = {
          "Authorization" => "Bearer #{raw_token}",
          "Content-Type" => "application/json"
        }

        post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: mcp_headers

        expect(response).to have_http_status(:ok)
        expect(json_response["result"]).to eq({})
      end

      it "sets @mcp_token for permission intersection" do
        mcp_headers = {
          "Authorization" => "Bearer pnmcp_#{raw_token}",
          "Content-Type" => "application/json"
        }

        # Verify that the token is passed through to platform tool calls
        allow(::Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool) do |_tool_id, **kwargs|
          expect(kwargs[:token]).to be_a(UserToken)
          expect(kwargs[:token].id).to eq(user_token.id)
          { success: true }
        end

        post mcp_endpoint,
             params: jsonrpc_request(method: "tools/call", params: { "name" => "platform.list_agents", "arguments" => {} }),
             headers: mcp_headers

        expect(response).to have_http_status(:ok)
      end

      it "calls touch_last_used! on the token" do
        mcp_headers = {
          "Authorization" => "Bearer pnmcp_#{raw_token}",
          "Content-Type" => "application/json"
        }

        expect { post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: mcp_headers }
          .to change { user_token.reload.last_used_at }
      end

      it "rejects expired MCP token" do
        user_token.update_columns(created_at: 3.hours.ago, expires_at: 1.hour.ago)

        mcp_headers = {
          "Authorization" => "Bearer pnmcp_#{raw_token}",
          "Content-Type" => "application/json"
        }

        post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: mcp_headers

        # Falls through to JWT fallback which also fails
        expect(response).to have_http_status(:unauthorized)
      end

      it "rejects revoked MCP token" do
        user_token.revoke!

        mcp_headers = {
          "Authorization" => "Bearer pnmcp_#{raw_token}",
          "Content-Type" => "application/json"
        }

        post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: mcp_headers

        # Falls through to JWT fallback which also fails
        expect(response).to have_http_status(:unauthorized)
      end

      it "rejects token when user is inactive" do
        user.update!(status: "inactive")

        mcp_headers = {
          "Authorization" => "Bearer pnmcp_#{raw_token}",
          "Content-Type" => "application/json"
        }

        post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: mcp_headers

        expect(response).to have_http_status(:ok)
        expect(json_response["error"]["code"]).to eq(-32001)
      end

      it "rejects token when account is inactive" do
        account.update!(status: "suspended")

        mcp_headers = {
          "Authorization" => "Bearer pnmcp_#{raw_token}",
          "Content-Type" => "application/json"
        }

        post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: mcp_headers

        expect(response).to have_http_status(:ok)
        expect(json_response["error"]["code"]).to eq(-32001)
      end
    end

    describe "static env token auth" do
      let(:static_token) { "test-static-mcp-token-12345" }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("POWERNODE_MCP_TOKEN").and_return(static_token)
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:[]).with("POWERNODE_MCP_USER_EMAIL").and_return(user.email)
      end

      it "authenticates with static env token" do
        mcp_headers = {
          "Authorization" => "Bearer #{static_token}",
          "Content-Type" => "application/json"
        }

        post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: mcp_headers

        expect(response).to have_http_status(:ok)
        expect(json_response["result"]).to eq({})
      end

      it "rejects invalid static token (falls through to JWT which also fails)" do
        mcp_headers = {
          "Authorization" => "Bearer wrong-token",
          "Content-Type" => "application/json"
        }

        post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: mcp_headers

        # Token doesn't match static env var → falls through to JWT → JWT rejects → 401
        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe "JWT fallback auth" do
      it "authenticates with valid JWT" do
        post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: headers

        expect(response).to have_http_status(:ok)
        expect(json_response["result"]).to eq({})
      end
    end

    describe "auth priority" do
      let(:token_result) { UserToken.create_token_for_user(user, type: "mcp", name: "priority-test") }
      let(:raw_token) { token_result[:token] }
      let(:static_token) { "static-priority-token" }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("POWERNODE_MCP_TOKEN").and_return(static_token)
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:[]).with("POWERNODE_MCP_USER_EMAIL").and_return(user.email)
      end

      it "prioritizes MCP token over static token and JWT" do
        # Use the MCP token — should authenticate via user token path (not static)
        mcp_headers = {
          "Authorization" => "Bearer pnmcp_#{raw_token}",
          "Content-Type" => "application/json"
        }

        post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: mcp_headers

        expect(response).to have_http_status(:ok)
        expect(json_response["result"]).to eq({})
        # Verify the token was used (last_used_at updated)
        expect(token_result[:user_token].reload.last_used_at).to be_present
      end
    end

    describe "invalid auth" do
      it "returns error with invalid bearer token" do
        invalid_headers = {
          "Authorization" => "Bearer totally-invalid-token",
          "Content-Type" => "application/json"
        }

        post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: invalid_headers

        # Falls through all auth modes — JWT fallback returns unauthorized
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns error with missing authorization header" do
        post mcp_endpoint,
             params: jsonrpc_request(method: "ping"),
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # ===========================================================================
  # Section 2: Request Parsing & JSON-RPC Validation
  # ===========================================================================
  describe "Request Parsing & JSON-RPC Validation" do
    it "processes a valid JSON-RPC request" do
      post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: headers

      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body["jsonrpc"]).to eq("2.0")
      expect(body["id"]).to eq(1)
      expect(body["result"]).to eq({})
    end

    it "returns -32700 for invalid JSON" do
      post mcp_endpoint,
           params: "this is not valid json{{{",
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32700)
      expect(json_response["error"]["message"]).to include("Parse error")
    end

    it "returns -32600 for JSON array (batching)" do
      post mcp_endpoint,
           params: [{ jsonrpc: "2.0", id: 1, method: "ping" }].to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32600)
      expect(json_response["error"]["message"]).to include("batching")
    end

    it "returns -32600 when jsonrpc field is missing" do
      post mcp_endpoint,
           params: { id: 1, method: "ping" }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32600)
    end

    it "returns -32600 when jsonrpc version is wrong" do
      post mcp_endpoint,
           params: { jsonrpc: "1.0", id: 1, method: "ping" }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32600)
    end

    it "returns -32600 when method is missing" do
      post mcp_endpoint,
           params: { jsonrpc: "2.0", id: 1 }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32600)
    end

    it "returns -32600 when method is not a string" do
      post mcp_endpoint,
           params: { jsonrpc: "2.0", id: 1, method: 42 }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32600)
    end

    it "returns -32600 when method is empty string" do
      post mcp_endpoint,
           params: { jsonrpc: "2.0", id: 1, method: "" }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32600)
    end

    it "tolerates extra fields in the request" do
      post mcp_endpoint,
           params: { jsonrpc: "2.0", id: 1, method: "ping", extra: "field", meta: { foo: "bar" } }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["result"]).to eq({})
    end
  end

  # ===========================================================================
  # Section 3: Notifications
  # ===========================================================================
  describe "Notifications" do
    it "returns 202 for notifications/initialized" do
      post mcp_endpoint,
           params: jsonrpc_notification(method: "notifications/initialized"),
           headers: headers

      expect(response).to have_http_status(:accepted)
      expect(response.body).to be_empty
    end

    it "returns 202 for notifications/cancelled" do
      post mcp_endpoint,
           params: jsonrpc_notification(method: "notifications/cancelled"),
           headers: headers

      expect(response).to have_http_status(:accepted)
      expect(response.body).to be_empty
    end

    it "returns 202 for unknown notification methods" do
      post mcp_endpoint,
           params: jsonrpc_notification(method: "notifications/custom_event"),
           headers: headers

      expect(response).to have_http_status(:accepted)
      expect(response.body).to be_empty
    end

    it "returns 202 for notification with params" do
      post mcp_endpoint,
           params: jsonrpc_notification(method: "notifications/initialized", params: { reason: "ready" }),
           headers: headers

      expect(response).to have_http_status(:accepted)
      expect(response.body).to be_empty
    end
  end

  # ===========================================================================
  # Section 4: initialize
  # ===========================================================================
  describe "initialize method" do
    before do
      allow(::Mcp::ProtocolService).to receive(:negotiate_protocol_version).and_return("2025-06-18")
    end

    it "returns capabilities, serverInfo, and protocolVersion" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "initialize", params: { "protocolVersion" => "2025-06-18" }),
           headers: headers

      expect(response).to have_http_status(:ok)
      result = json_response["result"]
      expect(result["protocolVersion"]).to eq("2025-06-18")
      expect(result["capabilities"]).to be_a(Hash)
      expect(result["serverInfo"]).to include("name" => "Powernode AI Platform")
      expect(result["serverInfo"]["version"]).to be_a(String)
    end

    it "creates an McpSession in the database" do
      expect {
        post mcp_endpoint,
             params: jsonrpc_request(method: "initialize", params: { "protocolVersion" => "2025-06-18" }),
             headers: headers
      }.to change(McpSession, :count).by(1)
    end

    it "sets Mcp-Session-Id response header" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "initialize", params: { "protocolVersion" => "2025-06-18" }),
           headers: headers

      expect(response.headers["Mcp-Session-Id"]).to be_present
    end

    it "creates session with correct user, account, and protocol_version" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "initialize", params: { "protocolVersion" => "2025-06-18" }),
           headers: headers

      session = McpSession.last
      expect(session.user_id).to eq(user.id)
      expect(session.account_id).to eq(account.id)
      expect(session.protocol_version).to eq("2025-06-18")
    end

    it "stores client_info from params" do
      client_info = { "name" => "Claude Code", "version" => "1.0.0" }

      post mcp_endpoint,
           params: jsonrpc_request(method: "initialize", params: {
             "protocolVersion" => "2025-06-18",
             "clientInfo" => client_info
           }),
           headers: headers

      session = McpSession.last
      expect(session.client_info).to eq(client_info)
    end

    it "returns -32602 for unsupported protocol version" do
      allow(::Mcp::ProtocolService).to receive(:negotiate_protocol_version).and_return(nil)

      post mcp_endpoint,
           params: jsonrpc_request(method: "initialize", params: { "protocolVersion" => "1999-01-01" }),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32602)
      expect(json_response["error"]["message"]).to include("Unsupported protocol version")
    end

    it "sets expires_at on the session" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "initialize", params: { "protocolVersion" => "2025-06-18" }),
           headers: headers

      session = McpSession.last
      expect(session.expires_at).to be > Time.current
      expect(session.expires_at).to be <= 25.hours.from_now
    end
  end

  # ===========================================================================
  # Section 5: ping
  # ===========================================================================
  describe "ping method" do
    it "returns empty result hash" do
      post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["result"]).to eq({})
    end

    it "works with integer id" do
      post mcp_endpoint, params: jsonrpc_request(method: "ping", id: 42), headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["id"]).to eq(42)
      expect(json_response["result"]).to eq({})
    end

    it "works with string id" do
      post mcp_endpoint, params: jsonrpc_request(method: "ping", id: "abc-123"), headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["id"]).to eq("abc-123")
      expect(json_response["result"]).to eq({})
    end
  end

  # ===========================================================================
  # Section 6: tools/list
  # ===========================================================================
  describe "tools/list method" do
    before do
      allow_any_instance_of(::Mcp::ProtocolService).to receive(:list_tools).and_return({ "tools" => [] })
      allow_any_instance_of(::Mcp::ProtocolService).to receive(:build_server_capabilities).and_return({})
    end

    let(:stub_tool_definitions) do
      [
        {
          name: "list_agents",
          description: "List all AI agents",
          parameters: {
            status: { type: "string", description: "Filter by status", required: false }
          }
        }
      ]
    end

    it "returns a tools array" do
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return([])

      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["result"]["tools"]).to be_an(Array)
    end

    it "includes platform tools with 'platform.' prefix" do
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(stub_tool_definitions)

      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: headers

      tools = json_response["result"]["tools"]
      platform_tools = tools.select { |t| t["name"].start_with?("platform.") }
      expect(platform_tools).not_to be_empty
      expect(platform_tools.first["name"]).to eq("platform.list_agents")
    end

    it "includes inputSchema on platform tools" do
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(stub_tool_definitions)

      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: headers

      tools = json_response["result"]["tools"]
      platform_tool = tools.find { |t| t["name"] == "platform.list_agents" }
      expect(platform_tool["inputSchema"]).to be_a(Hash)
      expect(platform_tool["inputSchema"]["type"]).to eq("object")
      expect(platform_tool["inputSchema"]["properties"]).to have_key("status")
    end

    it "includes description on platform tools" do
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(stub_tool_definitions)

      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: headers

      tools = json_response["result"]["tools"]
      platform_tool = tools.find { |t| t["name"] == "platform.list_agents" }
      expect(platform_tool["description"]).to eq("List all AI agents")
    end

    it "returns successfully with valid authentication" do
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return([])

      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["jsonrpc"]).to eq("2.0")
      expect(json_response["id"]).to eq(1)
    end
  end

  # ===========================================================================
  # Section 7: tools/call
  # ===========================================================================
  describe "tools/call method" do
    it "returns -32602 when name is missing" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "tools/call", params: { "arguments" => {} }),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32602)
      expect(json_response["error"]["message"]).to include("Missing required parameter: name")
    end

    it "returns error for unknown tool" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "tools/call", params: { "name" => "nonexistent_tool" }),
           headers: headers

      expect(response).to have_http_status(:ok)
      # Non-platform tool dispatched to ProtocolService which raises ToolNotFoundError
      expect(json_response["error"]).to be_present
    end

    it "passes token for permission intersection on platform tool call" do
      token_result = UserToken.create_token_for_user(user, type: "mcp", name: "tool-test")
      mcp_headers = {
        "Authorization" => "Bearer pnmcp_#{token_result[:token]}",
        "Content-Type" => "application/json"
      }

      allow(::Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool) do |tool_id, **kwargs|
        expect(tool_id).to eq("platform.list_agents")
        expect(kwargs[:token]).to eq(token_result[:user_token])
        expect(kwargs[:user]).to eq(user)
        expect(kwargs[:account]).to eq(account)
        { success: true, agents: [] }
      end

      post mcp_endpoint,
           params: jsonrpc_request(method: "tools/call", params: {
             "name" => "platform.list_agents",
             "arguments" => {}
           }),
           headers: mcp_headers

      expect(response).to have_http_status(:ok)
    end

    it "wraps result in MCP content format" do
      allow(::Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool).and_return({ success: true })

      post mcp_endpoint,
           params: jsonrpc_request(method: "tools/call", params: {
             "name" => "platform.list_agents",
             "arguments" => {}
           }),
           headers: headers

      expect(response).to have_http_status(:ok)
      result = json_response["result"]
      expect(result["content"]).to be_an(Array)
      expect(result["content"].first["type"]).to eq("text")
      expect(result["content"].first["text"]).to be_a(String)
    end

    it "handles platform tool with empty arguments" do
      allow(::Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool).and_return({ agents: [] })

      post mcp_endpoint,
           params: jsonrpc_request(method: "tools/call", params: {
             "name" => "platform.list_agents"
           }),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["result"]["content"]).to be_present
    end

    it "handles non-platform tool via ProtocolService" do
      protocol_service = instance_double(::Mcp::ProtocolService)
      allow(::Mcp::ProtocolService).to receive(:new).and_return(protocol_service)
      allow(protocol_service).to receive(:invoke_tool).and_return({
        result: { output: "done" }
      })

      post mcp_endpoint,
           params: jsonrpc_request(method: "tools/call", params: {
             "name" => "custom_tool",
             "arguments" => { "input" => "test" }
           }),
           headers: headers

      expect(response).to have_http_status(:ok)
    end
  end

  # ===========================================================================
  # Section 8: resources/list
  # ===========================================================================
  describe "resources/list method" do
    it "returns a resources array" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "resources/list"),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["result"]["resources"]).to be_an(Array)
    end

    it "includes KB articles, agents, workflows, and prompts" do
      # Create resources
      category = create(:kb_category)
      create(:kb_article, :published, category: category, author: user)
      create(:ai_agent, account: account, status: "active")
      create(:ai_workflow, :active, account: account, creator: user)
      create(:shared_prompt_template, account: account, created_by: user)

      post mcp_endpoint,
           params: jsonrpc_request(method: "resources/list"),
           headers: headers

      resources = json_response["result"]["resources"]
      uris = resources.map { |r| r["uri"] }

      expect(uris.any? { |u| u.start_with?("powernode://kb/articles/") }).to be true
      expect(uris.any? { |u| u.start_with?("powernode://ai/agents/") }).to be true
      expect(uris.any? { |u| u.start_with?("powernode://ai/workflows/") }).to be true
      expect(uris.any? { |u| u.start_with?("powernode://ai/prompts/") }).to be true
    end

    it "returns empty resources when no data exists" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "resources/list"),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["result"]["resources"]).to eq([])
    end

    it "supports cursor pagination" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "resources/list", params: { "cursor" => "kb/articles:0" }),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["result"]).to have_key("resources")
    end
  end

  # ===========================================================================
  # Section 9: resources/read
  # ===========================================================================
  describe "resources/read method" do
    let(:category) { create(:kb_category) }

    it "reads a KB article by URI" do
      article = create(:kb_article, :published, category: category, author: user,
                       title: "Test Article", content: "Article body content")

      post mcp_endpoint,
           params: jsonrpc_request(method: "resources/read", params: {
             "uri" => "powernode://kb/articles/#{article.slug}"
           }),
           headers: headers

      expect(response).to have_http_status(:ok)
      result = json_response["result"]
      expect(result["contents"]).to be_an(Array)
      expect(result["contents"].first["uri"]).to include(article.slug)
      expect(result["contents"].first["mimeType"]).to eq("text/plain")
      expect(result["contents"].first["text"]).to eq("Article body content")
    end

    it "reads an agent by URI" do
      agent = create(:ai_agent, account: account, status: "active", name: "Read Test Agent")

      post mcp_endpoint,
           params: jsonrpc_request(method: "resources/read", params: {
             "uri" => "powernode://ai/agents/#{agent.id}"
           }),
           headers: headers

      expect(response).to have_http_status(:ok)
      result = json_response["result"]
      expect(result["contents"]).to be_an(Array)
      expect(result["contents"].first["mimeType"]).to eq("application/json")
      parsed_text = JSON.parse(result["contents"].first["text"])
      expect(parsed_text["name"]).to eq("Read Test Agent")
    end

    it "returns error for unknown resource URI" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "resources/read", params: {
             "uri" => "powernode://kb/articles/nonexistent-slug"
           }),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]).to be_present
    end

    it "returns -32602 when uri param is missing" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "resources/read", params: {}),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32602)
      expect(json_response["error"]["message"]).to include("Missing required parameter: uri")
    end

    it "returns error for invalid URI scheme" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "resources/read", params: {
             "uri" => "http://example.com/not-a-powernode-uri"
           }),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]).to be_present
    end
  end

  # ===========================================================================
  # Section 10: prompts/list
  # ===========================================================================
  describe "prompts/list method" do
    it "returns prompts from PromptTemplate" do
      create(:shared_prompt_template, account: account, created_by: user, name: "My Prompt")

      post mcp_endpoint,
           params: jsonrpc_request(method: "prompts/list"),
           headers: headers

      expect(response).to have_http_status(:ok)
      prompts = json_response["result"]["prompts"]
      expect(prompts).to be_an(Array)
      expect(prompts.length).to eq(1)
    end

    it "returns empty when no templates exist" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "prompts/list"),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["result"]["prompts"]).to eq([])
    end

    it "includes arguments schema from variable definitions" do
      create(:shared_prompt_template, :review, account: account, created_by: user)

      post mcp_endpoint,
           params: jsonrpc_request(method: "prompts/list"),
           headers: headers

      prompts = json_response["result"]["prompts"]
      prompt = prompts.first
      expect(prompt["arguments"]).to be_an(Array)
      expect(prompt["arguments"].any? { |a| a["name"] == "code" }).to be true
    end
  end

  # ===========================================================================
  # Section 11: prompts/get
  # ===========================================================================
  describe "prompts/get method" do
    let!(:template) do
      create(:shared_prompt_template, account: account, created_by: user,
             name: "Greet User", slug: "greet-user",
             content: "Hello {{ name }}, welcome!",
             variables: [
               { "name" => "name", "type" => "string", "required" => true, "description" => "User name" }
             ])
    end

    # Stub PromptTemplate#render since Liquid gem may not be loaded in test env
    before do
      allow_any_instance_of(Shared::PromptTemplate).to receive(:render) do |tmpl, variables|
        content = tmpl.content.dup
        variables.each { |k, v| content.gsub!("{{ #{k} }}", v.to_s) }
        content
      end
    end

    it "renders template with provided variables" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "prompts/get", params: {
             "name" => "greet-user",
             "arguments" => { "name" => "Alice" }
           }),
           headers: headers

      expect(response).to have_http_status(:ok)
      result = json_response["result"]
      expect(result["description"]).to be_present
      expect(result["messages"]).to be_an(Array)
      expect(result["messages"].first["role"]).to eq("user")
      expect(result["messages"].first["content"]["text"]).to include("Alice")
    end

    it "returns -32602 when required arguments are missing" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "prompts/get", params: {
             "name" => "greet-user",
             "arguments" => {}
           }),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32602)
      expect(json_response["error"]["message"]).to include("Missing required variable")
    end

    it "returns error when prompt is not found" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "prompts/get", params: {
             "name" => "nonexistent-prompt",
             "arguments" => {}
           }),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32602)
      expect(json_response["error"]["message"]).to include("Prompt not found")
    end

    it "returns -32602 when name param is missing" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "prompts/get", params: { "arguments" => {} }),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32602)
      expect(json_response["error"]["message"]).to include("Missing required parameter: name")
    end
  end

  # ===========================================================================
  # Section 12: Exception handling
  # ===========================================================================
  describe "Exception handling" do
    it "maps PermissionDeniedError to -32001" do
      allow_any_instance_of(Api::V1::Mcp::StreamableHttpController)
        .to receive(:dispatch_method)
        .and_raise(::Mcp::ProtocolService::PermissionDeniedError, "Access denied")

      post mcp_endpoint, params: jsonrpc_request(method: "tools/call", params: { "name" => "test" }), headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32001)
      expect(json_response["error"]["message"]).to include("Access denied")
    end

    it "maps ToolNotFoundError to -32601" do
      allow_any_instance_of(Api::V1::Mcp::StreamableHttpController)
        .to receive(:dispatch_method)
        .and_raise(::Mcp::ProtocolService::ToolNotFoundError, "Tool not found: test_tool")

      post mcp_endpoint, params: jsonrpc_request(method: "tools/call", params: { "name" => "test" }), headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32601)
      expect(json_response["error"]["message"]).to include("Tool not found")
    end

    it "maps ArgumentError to -32602" do
      allow_any_instance_of(Api::V1::Mcp::StreamableHttpController)
        .to receive(:dispatch_method)
        .and_raise(ArgumentError, "Invalid parameter value")

      post mcp_endpoint, params: jsonrpc_request(method: "tools/call", params: { "name" => "test" }), headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32602)
      expect(json_response["error"]["message"]).to include("Invalid parameter value")
    end

    it "maps StandardError to -32603" do
      allow_any_instance_of(Api::V1::Mcp::StreamableHttpController)
        .to receive(:dispatch_method)
        .and_raise(StandardError, "Something went wrong")

      post mcp_endpoint, params: jsonrpc_request(method: "tools/call", params: { "name" => "test" }), headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32603)
      expect(json_response["error"]["message"]).to include("Internal error")
    end
  end

  # ===========================================================================
  # Section 13: DELETE /message (session termination)
  # ===========================================================================
  describe "DELETE /message" do
    before do
      allow(::Mcp::ProtocolService).to receive(:negotiate_protocol_version).and_return("2025-06-18")
    end

    let!(:session) do
      McpSession.create!(
        user: user,
        account: account,
        protocol_version: "2025-06-18",
        client_info: {},
        ip_address: "127.0.0.1",
        user_agent: "test",
        expires_at: 24.hours.from_now
      )
    end

    it "revokes session by Mcp-Session-Id header" do
      delete mcp_endpoint,
             headers: headers.merge("Mcp-Session-Id" => session.session_token)

      expect(session.reload.status).to eq("revoked")
    end

    it "returns 200 OK" do
      delete mcp_endpoint,
             headers: headers.merge("Mcp-Session-Id" => session.session_token)

      expect(response).to have_http_status(:ok)
    end

    it "is idempotent — no session header still returns 200" do
      delete mcp_endpoint, headers: headers

      expect(response).to have_http_status(:ok)
    end

    it "changes session status to revoked" do
      expect {
        delete mcp_endpoint,
               headers: headers.merge("Mcp-Session-Id" => session.session_token)
      }.to change { session.reload.status }.from("active").to("revoked")
    end
  end

  # ===========================================================================
  # Section 14: Response headers
  # ===========================================================================
  describe "Response headers" do
    it "includes MCP-Protocol-Version on success response" do
      post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: headers

      expect(response.headers["MCP-Protocol-Version"]).to be_present
    end

    it "includes MCP-Protocol-Version on error response" do
      post mcp_endpoint,
           params: { jsonrpc: "1.0", id: 1, method: "ping" }.to_json,
           headers: headers

      expect(response.headers["MCP-Protocol-Version"]).to be_present
    end

    it "MCP-Protocol-Version matches the controller constant" do
      post mcp_endpoint, params: jsonrpc_request(method: "ping"), headers: headers

      expect(response.headers["MCP-Protocol-Version"]).to eq("2025-06-18")
    end
  end

  # ===========================================================================
  # Section 15: Session activity tracking
  # ===========================================================================
  describe "Session activity tracking" do
    before do
      allow(::Mcp::ProtocolService).to receive(:negotiate_protocol_version).and_return("2025-06-18")
    end

    it "updates last_activity_at when Mcp-Session-Id is present" do
      session = McpSession.create!(
        user: user,
        account: account,
        protocol_version: "2025-06-18",
        client_info: {},
        ip_address: "127.0.0.1",
        user_agent: "test",
        expires_at: 24.hours.from_now
      )

      original_activity = session.last_activity_at

      # Small delay to ensure time difference
      travel_to(1.minute.from_now) do
        post mcp_endpoint,
             params: jsonrpc_request(method: "ping"),
             headers: headers.merge("Mcp-Session-Id" => session.session_token)

        expect(session.reload.last_activity_at).to be > original_activity
      end
    end
  end

  # ===========================================================================
  # Section 16: Method not found
  # ===========================================================================
  describe "unknown method" do
    it "returns -32601 for unknown method" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "unknown/method"),
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response["error"]["code"]).to eq(-32601)
      expect(json_response["error"]["message"]).to include("Method not found")
    end
  end
end
