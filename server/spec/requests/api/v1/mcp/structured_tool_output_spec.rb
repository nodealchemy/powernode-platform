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
  #      612+ identical schemas are exactly what LZ77 removes. Gzip shrinks
  #      the NETWORK cost only: the ~1 MB figure below is the payload a
  #      client still parses, and a client that omits Accept-Encoding still
  #      receives it.
  #
  # What DID shrink (amended R4 ruling, 2026-09-03): the descriptions, not
  # the envelope. Cutting every listing entry to its first sentence
  # (LIST_DESCRIPTION_LIMIT — see the describe below) and moving the long
  # form behind platform.describe_tool measures, over ONE session on ONE
  # checkout, full registry, user principal, one page of 625 entries (616
  # platform + 9 introspection):
  #
  #      BEFORE  raw 1,109,260 B — descriptions   120,227 B (248 entries over
  #                                160 chars, longest 1,477); gzip 110,483 B
  #      AFTER   raw 1,037,808 B — descriptions    48,941 B (longest exactly
  #                                160); gzip 84,143 B (12.33x deflate)
  #
  # The outputSchema envelope is IDENTICAL either way at 672,209 B — exactly
  # 616 x 1,091 B envelope + 9 x 17 B generic object schema — which is what
  # makes this a description delta and not an envelope one.
  #
  # ONE CHECKOUT ON PURPOSE. Earlier runs of the same measurement recorded
  # 1,106,704 B / 110,010 B, 1,106,376 B / 109,888 B and 1,105,655 B /
  # 109,653 B (all at 624 entries, before platform.describe_tool existed).
  # The raw body tracks the extension checkout's DESCRIPTION TEXT, which
  # moves whenever an extension verb is reworded, so a before from one
  # checkout and an after from another measures the rewording as much as the
  # change. Do not mix a number from an older run into the pair above.
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

    # 160 KiB is a tripwire, not a target: measured 84,143 B on 2026-09-03
    # (625 tools, one-line descriptions; the same catalog with the long-form
    # descriptions was 110,483 B under a 256 KiB ceiling, before
    # IMP-7e84ae0ccc91 cut the listing to one line per tool). It reddens if
    # the MCP route ever stops being deflated (Rack::Deflater removed or
    # bypassed), if the long-form descriptions ever creep back into the
    # listing, or if the catalog's compressed size nearly doubles — all
    # events the operator wants to hear about before an agent's first
    # tools/list of the day is a megabyte.
    let(:wire_bytes_ceiling) { 160 * 1024 }

    it "delivers the full catalog deflated and under the wire ceiling when gzip is negotiated" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "tools/list"),
           headers: modern_headers.merge("Accept-Encoding" => "gzip")

      expect(response.headers["Content-Encoding"]).to eq("gzip")
      wire_bytes = response.body.bytesize
      expect(wire_bytes).to be < wire_bytes_ceiling,
        "tools/list gzip wire is #{wire_bytes} B, over the #{wire_bytes_ceiling} B " \
        "ceiling. Either the MCP route lost Rack::Deflater, the long-form " \
        "descriptions are back in the listing, or the catalog's compressed " \
        "size nearly doubled since 2026-09-03 (84,143 B / 625 tools)."
    end
  end

  # IMP-7e84ae0ccc91 (operator ruling R4, amended 2026-09-03: "drop
  # descriptions and provide a mechanism to retrieve tool details on-demand").
  # tools/list carries ONE LINE per tool — the first sentence, hard-capped at
  # LIST_DESCRIPTION_LIMIT and cut at a word boundary with an ellipsis — and
  # platform.describe_tool returns the FULL entry on demand. Both are built by
  # the same Mcp::ToolCatalog, so the summary and the detail cannot drift.
  describe "tools/list one-line descriptions + platform.describe_tool (full registry)" do
    let(:limit) { Api::V1::Mcp::StreamableHttpController::LIST_DESCRIPTION_LIMIT }
    let(:tools) do
      post mcp_endpoint, params: jsonrpc_request(method: "tools/list"), headers: modern_headers
      json_response["result"]["tools"]
    end

    def describe_tool(name)
      post mcp_endpoint,
           params: jsonrpc_request(method: "tools/call",
                                   params: { "name" => "platform.describe_tool", "arguments" => { "name" => name } }),
           headers: modern_headers
      json_response["result"]["structuredContent"]
    end

    # A literal alongside the constant, on purpose: a constant-only assertion
    # stays green if someone lifts the cap to 5,000 and the wire regrows.
    it "caps the limit itself at one line" do
      expect(limit).to be_between(80, 200)
    end

    it "lists every tool with a description no longer than LIST_DESCRIPTION_LIMIT" do
      expect(tools.size).to be > 100 # the real catalog, not a stub

      offenders = tools.select { |t| t["description"].to_s.length > limit }.map do |t|
        [t["name"], t["description"].to_s.length]
      end
      expect(offenders).to(
        eq([]),
        "#{offenders.size} tools/list entries exceed LIST_DESCRIPTION_LIMIT (#{limit}) " \
        "(first: #{offenders.first.inspect}). The listing carries ONE LINE per tool; " \
        "the long-form text is served by platform.describe_tool."
      )
    end

    it "advertises platform.describe_tool in the listing, read-only" do
      entry = tools.find { |t| t["name"] == "platform.describe_tool" }
      expect(entry).not_to be_nil
      expect(entry["annotations"]).to eq({ "readOnlyHint" => true })
      expect(entry["inputSchema"]["required"]).to eq(["name"])
    end

    it "returns the untruncated description for a tool whose text exceeds the limit" do
      # Pick from the REAL registry: the longest declared description.
      name, full = ::Ai::Tools::PlatformApiToolRegistry.tool_definitions
        .map { |d| ["platform.#{d[:name]}", d[:description].to_s] }
        .max_by { |(_, d)| d.length }
      expect(full.length).to be > limit # otherwise this example proves nothing

      listed = tools.find { |t| t["name"] == name }
      expect(listed["description"].length).to be <= limit
      expect(listed["description"]).to end_with("…")

      result = describe_tool(name)
      expect(result["success"]).to be(true)
      detail = result["data"]
      expect(detail["name"]).to eq(name)
      expect(detail["description"]).to eq(full)
      expect(detail["truncated"]).to be(true)
      expect(detail["summary"]).to eq(listed["description"])
    end

    it "returns exactly the tools/list entry (plus the full text) — same builder, no drift" do
      listed = tools.find { |t| t["name"] == "platform.list_agents" }
      detail = describe_tool("platform.list_agents")["data"]

      expect(detail["inputSchema"]).to eq(listed["inputSchema"])
      expect(detail["outputSchema"]).to eq(listed["outputSchema"])
      expect(detail["annotations"]).to eq(listed["annotations"])
      expect(detail["title"]).to eq(listed["title"])
      expect(detail).to have_key("truncated")
    end

    it "describes an introspection tool with its own (generic) family schema" do
      detail = describe_tool("platform.health")["data"]
      expect(detail["outputSchema"]).to eq({ "type" => "object" })
      expect(detail["truncated"]).to be(false)
    end

    it "answers an unknown name with the nearest matches, not a bare -32602" do
      result = describe_tool("platform.list_agent")
      expect(response).to have_http_status(:ok)
      expect(json_response).not_to have_key("error")
      expect(result["success"]).to be(false)
      expect(result["error"]).to include("platform.list_agent")
      expect(result["nearest_matches"]).to include("platform.list_agents")
    end

    it "mentions platform.describe_tool in the server instructions so clients discover it" do
      post mcp_endpoint,
           params: jsonrpc_request(method: "initialize", params: {
             "protocolVersion" => "2025-11-25", "capabilities" => {}, "clientInfo" => { "name" => "t", "version" => "1" }
           }),
           headers: base_headers
      expect(json_response["result"]["instructions"]).to include("platform.describe_tool")
    end

    # The legacy ActionCable `tools/describe` path (Mcp::ProtocolService
    # #describe_tool) reads from the SAME builder for a platform name, so the
    # two transports cannot answer two different entries.
    it "serves the legacy tools/describe path from the shared builder" do
      service = ::Mcp::ProtocolService.new(account: account, connection_id: "spec")
      detail = service.describe_tool("platform.list_agents", user: user)
      listed = tools.find { |t| t["name"] == "platform.list_agents" }

      expect(detail["inputSchema"]).to eq(listed["inputSchema"])
      expect(detail["outputSchema"]).to eq(listed["outputSchema"])
      expect(detail["description"]).to eq(
        ::Ai::Tools::PlatformApiToolRegistry.tool_definitions.find { |d| d[:name] == "list_agents" }[:description]
      )
    end

    # ...and it must NOT become an unscoped door onto the platform catalog.
    # #list_tools on this class is documented fail-closed ("without a principal
    # and an account to scope against we advertise nothing rather than the
    # unfiltered catalog"); the describe half has to hold the same line, or an
    # unauthenticated ActionCable route would read every advertised entry.
    it "fails closed on the legacy path when no user is scoped" do
      service = ::Mcp::ProtocolService.new(account: account, connection_id: "spec")

      expect { service.describe_tool("platform.list_agents") }
        .to raise_error(::Mcp::ProtocolService::ToolNotFoundError)
    end
  end
end
