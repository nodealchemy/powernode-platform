# frozen_string_literal: true

require "rails_helper"

# The tool registry has always carried an outputSchema, but tools/call only
# ever returned the JSON-serialized text block — so the schema described a
# structured result the server never sent.
#
# structuredContent (2025-06-18) and the tool title/annotations fields
# (2025-06-18 / 2025-03-26) must never reach a client on an older revision,
# which is what most of these examples assert.
RSpec.describe "MCP Streamable HTTP - structured tool output", type: :request do
  let(:account) { create(:account) }
  let(:user) { user_with_permissions("ai.agents.read", "ai.loops.read", "ai.loops.execute", account: account) }
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
  let(:legacy_headers) { base_headers.merge("MCP-Protocol-Version" => "2024-11-05") }
  let(:mcp_endpoint) { "/api/v1/mcp/message" }

  def jsonrpc_request(method:, params: {}, id: 1)
    { jsonrpc: "2.0", id: id, method: method, params: params }.to_json
  end

  def call_tool(headers:, name: "platform.list_agents")
    post mcp_endpoint,
         params: jsonrpc_request(method: "tools/call", params: { "name" => name, "arguments" => {} }),
         headers: headers
  end

  describe "tools/call structured output" do
    before do
      allow(::Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool)
        .and_return({ success: true, agents: [] })
    end

    it "returns structuredContent for a 2025-11-25 client" do
      call_tool(headers: modern_headers)

      result = json_response["result"]
      expect(result["structuredContent"]).to eq({ "success" => true, "agents" => [] })
      # Unstructured content remains for backward compatibility
      expect(result["content"].first["type"]).to eq("text")
    end

    it "returns structuredContent for a 2025-06-18 client" do
      call_tool(headers: base_headers.merge("MCP-Protocol-Version" => "2025-06-18"))

      expect(json_response["result"]["structuredContent"]).to be_a(Hash)
    end

    it "wraps non-object results so structuredContent stays an object" do
      allow(::Ai::Tools::McpPlatformToolRegistrar).to receive(:execute_tool).and_return([1, 2, 3])

      call_tool(headers: modern_headers)

      expect(json_response["result"]["structuredContent"]).to eq({ "result" => [1, 2, 3] })
    end

    it "does NOT leak structuredContent to a 2024-11-05 client" do
      call_tool(headers: legacy_headers)

      expect(json_response["result"]).not_to have_key("structuredContent")
    end

    it "does NOT leak structuredContent when the revision is unknown (spec default 2025-03-26)" do
      call_tool(headers: base_headers)

      expect(json_response["result"]).not_to have_key("structuredContent")
    end
  end

  describe "tools/list metadata by revision" do
    before do
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(
        [{ name: "list_agents", description: "List agents", parameters: {} }]
      )
      stub_const("Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS", [])
    end

    it "includes title, outputSchema, and readOnlyHint annotations for a modern client" do
      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: modern_headers

      tool = json_response["result"]["tools"].first
      expect(tool["title"]).to eq("List Agents")
      expect(tool["outputSchema"]["type"]).to eq("object")
      expect(tool["annotations"]).to eq({ "readOnlyHint" => true })
    end

    it "returns the legacy shape (no title/outputSchema/annotations) for a 2024-11-05 client" do
      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: legacy_headers

      tool = json_response["result"]["tools"].first
      expect(tool.keys).to contain_exactly("name", "description", "inputSchema")
    end

    # The manifest the ActionCable catalog publishes has carried the declared
    # envelope (success / error / data with the pending approval body) since
    # IMP-e809396f9eda, but tools/list — the only schema a streamable-HTTP
    # client ever sees, and the transport real agents use — advertised a bare
    # {"type" => "object"}. A strict client could not learn from the wire that
    # a success:true response may be a PARKED action with nothing applied.
    # One source of truth: McpPlatformToolRegistrar.default_output_schema.
    it "advertises the declared result envelope, not a bare object schema" do
      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: modern_headers

      tool = json_response["result"]["tools"].first
      expect(tool["outputSchema"]).to eq(
        ::Ai::Tools::McpPlatformToolRegistrar.default_output_schema.deep_stringify_keys
      )
      expect(tool["outputSchema"]["properties"]).to include("success", "error", "data")
      expect(tool["outputSchema"]["properties"]["data"]["properties"]).to include(
        "pending", "action_category", "deferred_operation_id", "approval_request_id"
      )
      expect(tool["outputSchema"]["required"]).to eq(["success"])
    end

    # Introspection tools (platform.health, platform.metrics, ...) are served by
    # Ai::Introspection::McpToolRegistrar.execute_tool, which returns the metrics
    # / health service hash DIRECTLY — no success/error/data envelope. Handing
    # them the platform envelope would advertise `required: ["success"]` for a
    # result that never carries `success`, so a strict client would reject every
    # valid introspection response. They keep the generic object schema.
    it "does NOT give introspection tools the platform result envelope" do
      stub_const(
        "Ai::Introspection::McpToolRegistrar::INTROSPECTION_TOOLS",
        [{ id: "platform.health", description: "Health", input_schema: { "type" => "object" } }]
      )

      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: modern_headers

      tool = json_response["result"]["tools"].find { |t| t["name"] == "platform.health" }
      expect(tool["outputSchema"]).to eq({ "type" => "object" })
    end

    it "does not mark non-read-only tools with readOnlyHint" do
      allow(::Ai::Tools::PlatformApiToolRegistry).to receive(:tool_definitions).and_return(
        [{ name: "create_agent", description: "Create agent", parameters: {} }]
      )

      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: modern_headers

      tool = json_response["result"]["tools"].first
      expect(tool).not_to have_key("annotations")
    end
  end

  # IMP-7e84ae0ccc91 (operator ruling R4, 2026-09-03: "keep the envelope,
  # shrink the wire"). The proposed mechanism — hoist the per-tool envelope
  # behind one shared JSON-Schema $defs and put a $ref on every entry — is
  # NOT implementable on this transport, and these two examples are the
  # executable form of why, so the next reader does not re-derive it:
  #
  #   1. Every tools/list `outputSchema` is a STANDALONE JSON-Schema document.
  #      MCP defines no cross-entry definitions store, and the reference
  #      client compiles every entry the moment tools/list returns —
  #      @modelcontextprotocol/sdk 1.29.0 client/index.js
  #      Client#cacheToolMetadata -> AjvJsonSchemaValidator#getValidator ->
  #      ajv.compile(tool.outputSchema) — so a $ref whose target lives in
  #      another entry, in the result's _meta, or at a server URL raises
  #      "can't resolve reference" INSIDE listTools (no rescue around the
  #      compile) and the client loses the whole catalog. Any client that
  #      validates each entry in isolation fails the same way. Intra-entry
  #      $defs/$ref is resolvable but duplicates nothing: the envelope
  #      repeats no sub-schema within itself.
  #   2. The wire is ALREADY shrunk: Rack::Deflater (config/application.rb)
  #      compresses the response when the client negotiates gzip, and the
  #      612+ identical schemas are exactly what LZ77 removes. Measured
  #      2026-09-03 on the full registry (624 tools/list entries = 615
  #      platform + 9 introspection): raw body 1,106,376 B, of which
  #      outputSchema 671,118 B — exactly 615 x 1,091 B envelope + 9 x 17 B
  #      generic object schema; gzip wire 109,888 B (10.1x). Gzip shrinks the
  #      NETWORK cost only: the 1 MB figure is the payload a client still
  #      parses, and a client that omits Accept-Encoding still receives it.
  #
  # The first example pins property 1 (any $ref on this transport is a
  # regression); the second pins property 2 (the wire stays deflated and
  # bounded), each against the REAL registry rather than a stub.
  describe "tools/list outputSchema wire properties (full registry)" do
    let(:tools) do
      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: modern_headers
      json_response["result"]["tools"]
    end

    # Deep walk: a $ref / $dynamicRef anywhere in a schema, not only at the top.
    def ref_keys_in(node, path = "")
      case node
      when Hash
        node.flat_map do |k, v|
          here = k.to_s.start_with?("$ref", "$dynamicRef") ? [ "#{path}/#{k}" ] : []
          here + ref_keys_in(v, "#{path}/#{k}")
        end
      when Array
        node.each_with_index.flat_map { |v, i| ref_keys_in(v, "#{path}[#{i}]") }
      else
        []
      end
    end

    it "keeps every outputSchema self-contained — no $ref on any entry" do
      expect(tools.size).to be > 100 # the real catalog, not a stub

      offenders = tools.filter_map do |tool|
        refs = ref_keys_in(tool["outputSchema"])
        [ tool["name"], refs ] if refs.any?
      end

      expect(offenders).to(
        eq([]),
        "#{offenders.size} tools/list entries carry a $ref in outputSchema " \
        "(first: #{offenders.first.inspect}). Each outputSchema is compiled " \
        "as a standalone document by the reference client " \
        "(Client#cacheToolMetadata -> ajv.compile) the moment tools/list " \
        "returns; an unresolvable $ref there drops the ENTIRE catalog for " \
        "that client. Inline the schema — see the comment above this describe."
      )
    end

    # 256 KiB is a tripwire, not a target: measured 109,888 B on 2026-09-03
    # (624 tools). It reddens if the MCP route ever stops being deflated
    # (Rack::Deflater removed or bypassed) or the catalog's compressed size
    # more than doubles — both are events the operator wants to hear about
    # before an agent's first tools/list of the day is a megabyte.
    let(:wire_bytes_ceiling) { 256 * 1024 }

    it "delivers the full catalog deflated and under the wire ceiling when gzip is negotiated" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "tools/list"),
           headers: modern_headers.merge("Accept-Encoding" => "gzip")

      expect(response.headers["Content-Encoding"]).to eq("gzip")
      wire_bytes = response.body.bytesize
      expect(wire_bytes).to be < wire_bytes_ceiling,
        "tools/list gzip wire is #{wire_bytes} B, over the #{wire_bytes_ceiling} B " \
        "ceiling. Either the MCP route lost Rack::Deflater or the catalog's " \
        "compressed size doubled since 2026-09-03 (109,888 B / 624 tools)."
    end
  end
end
