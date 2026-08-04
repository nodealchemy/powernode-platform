# frozen_string_literal: true

require "rails_helper"
require "openssl"
require "base64"

# AI/MCP workload substrate L2 — instance principals authenticate to the platform
# MCP endpoint via their node mTLS client cert (Traefik-forwarded), verified
# against OUR CA. Additive to the OAuth path.
RSpec.describe "MCP instance mTLS authentication", type: :request do
  def build_ca(cn)
    key = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer = cert.subject
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    cert.public_key = key
    ef = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
    cert.sign(key, nil)
    [ key, cert ]
  end

  def leaf(cn, ca_key, ca_cert)
    key = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 2
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer = ca_cert.subject
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    cert.public_key = key
    cert.sign(ca_key, nil)
    cert
  end

  let(:ca) { build_ca("Powernode Internal CA") }
  let(:instance) { create(:system_node_instance, status: "running") }

  around do |example|
    orig_ca = Security::MtlsTrust.own_ca_provider
    orig_resolver = Mcp::Principal.instance_resolver
    orig_grant = Mcp::Principal.tool_grant_resolver
    Security::MtlsTrust.own_ca_provider = -> { ca[1].to_pem }
    Mcp::Principal.instance_resolver = lambda do |cn|
      System::NodeInstance.where(id: cn).where.not(status: "terminated").first
    end
    example.run
    Security::MtlsTrust.own_ca_provider = orig_ca
    Mcp::Principal.instance_resolver = orig_resolver
    Mcp::Principal.tool_grant_resolver = orig_grant
  end

  def post_tools_list(headers)
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }.merge(headers)
  end

  # Traefik forwards the leaf as bare base64 DER (the real wire format).
  def cert_header(cert)
    { "X-Forwarded-Tls-Client-Cert" => Base64.strict_encode64(cert.to_der) }
  end

  it "authenticates a valid instance cert but is DEFAULT-DENY (empty catalog, no grant)" do
    post_tools_list(cert_header(leaf(instance.id, ca[0], ca[1])))
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("result", "tools")).to eq([])
  end

  it "scopes the catalog to granted tool patterns when a grant is present" do
    Mcp::Principal.tool_grant_resolver = ->(_i) { %w[platform.system_find_node_with_gpu platform.health] }
    post_tools_list(cert_header(leaf(instance.id, ca[0], ca[1])))
    names = JSON.parse(response.body).dig("result", "tools").map { |t| t["name"] }
    expect(names).to include("platform.system_find_node_with_gpu")
    expect(names).not_to include("platform.system_destroy_instance")
  end

  it "denies tools/call for an ungranted tool (no internal-caller bypass)" do
    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 2, method: "tools/call",
                   params: { name: "platform.system_destroy_instance", arguments: {} } }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
                  .merge(cert_header(leaf(instance.id, ca[0], ca[1])))
    expect(response.body).to include("not permitted")
  end

  # IMP-e8138c2714fb — the grant is checked against the TOOL NAME, but a
  # multi-action tool used to run whatever :action the caller supplied. An
  # instance granted only a benign read tool could name a destroy-shaped sibling
  # on the same tool class and reach it, defeating both the destructive deny
  # overlay and the tool's per-action permission map in one argument.
  it "denies a destructive sibling ACTION smuggled into a granted benign tool" do
    Mcp::Principal.tool_grant_resolver = ->(_i) { %w[platform.read_shared_memory] }
    executed = []
    allow_any_instance_of(Ai::Tools::MemoryTool).to receive(:execute) do |_tool, params:|
      executed << params[:action]
      { success: true }
    end

    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 7, method: "tools/call",
                   params: { name: "platform.read_shared_memory",
                             arguments: { action: "delete_shared_memory",
                                          pool_id: "default", key: "secrets" } } }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
                  .merge(cert_header(leaf(instance.id, ca[0], ca[1])))

    expect(executed).to be_empty
    expect(JSON.parse(response.body).dig("error", "code")).to eq(-32001)
  end

  it "still runs a granted tool whose action agrees with its name" do
    Mcp::Principal.tool_grant_resolver = ->(_i) { %w[platform.read_shared_memory] }
    executed = []
    allow_any_instance_of(Ai::Tools::MemoryTool).to receive(:execute) do |_tool, params:|
      executed << params[:action]
      { success: true }
    end

    post "/api/v1/mcp/message",
         params: { jsonrpc: "2.0", id: 8, method: "tools/call",
                   params: { name: "platform.read_shared_memory",
                             arguments: { pool_id: "default", key: "secrets" } } }.to_json,
         headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
                  .merge(cert_header(leaf(instance.id, ca[0], ca[1])))

    expect(executed).to eq([ "read_shared_memory" ])
  end

  it "rejects with 401 when neither a cert nor a token is present" do
    post_tools_list({})
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a node cert signed by a FOREIGN CA (falls through to OAuth → 401)" do
    foreign = build_ca("Powernode Internal CA")
    post_tools_list(cert_header(leaf(instance.id, foreign[0], foreign[1])))
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a valid cert whose CN is not a live instance" do
    post_tools_list(cert_header(leaf(SecureRandom.uuid, ca[0], ca[1])))
    expect(response).to have_http_status(:unauthorized)
  end
end
