# frozen_string_literal: true

require "rails_helper"
require "openssl"
require "base64"

# The restricted-principal arm of session ownership (instance mTLS). An
# instance's session is owned by (principal_kind, principal_subject_id); its
# own reconnect within the grace period still reactivates it, and ANOTHER
# instance presenting that session id neither reactivates nor refreshes it.
# Core never names the system extension: an instance here is any object the
# instance_resolver seam returns that answers #id and #account.
RSpec.describe "MCP session ownership for an instance principal", type: :request do
  let(:fake_instance) { Struct.new(:id, :account, :status) }
  let(:account) { create(:account) }
  let(:instance_a) { fake_instance.new(SecureRandom.uuid, account, "running") }
  let(:instance_b) { fake_instance.new(SecureRandom.uuid, account, "running") }
  let(:ca) { build_ca }

  def build_ca
    key = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse("/CN=Spec Internal CA")
    cert.issuer = cert.subject
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    cert.public_key = key
    ef = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    cert.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
    cert.sign(key, nil)
    [ key, cert ]
  end

  def leaf(cn)
    key = OpenSSL::PKey.generate_key("ED25519")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 2
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer = ca[1].subject
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600
    cert.public_key = key
    cert.sign(ca[0], nil)
    cert
  end

  around do |example|
    orig_ca = Security::MtlsTrust.own_ca_provider
    orig_resolver = Mcp::Principal.instance_resolver
    orig_grant = Mcp::Principal.tool_grant_resolver
    Security::MtlsTrust.own_ca_provider = -> { ca[1].to_pem }
    known = { instance_a.id => instance_a, instance_b.id => instance_b }
    Mcp::Principal.instance_resolver = ->(cn) { known[cn] }
    example.run
  ensure
    Security::MtlsTrust.own_ca_provider = orig_ca
    Mcp::Principal.instance_resolver = orig_resolver
    Mcp::Principal.tool_grant_resolver = orig_grant
  end

  def headers_for(instance, session_id: nil)
    { "Content-Type" => "application/json", "Accept" => "application/json",
      "X-Forwarded-Tls-Client-Cert" => Base64.strict_encode64(leaf(instance.id).to_der) }
      .merge(session_id ? { "Mcp-Session-Id" => session_id } : {})
  end

  def rpc(method, params = {})
    { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json
  end

  def initialize_as(instance)
    post "/api/v1/mcp/message",
         params: rpc("initialize", { "protocolVersion" => "2025-11-25",
                                     "clientInfo" => { "name" => "node-agent", "version" => "1" } }),
         headers: headers_for(instance)
    McpSession.find_by!(session_token: response.headers["Mcp-Session-Id"])
  end

  def revoke_within_grace!(session)
    session.update_columns(status: "revoked", revoked_at: 10.seconds.ago, last_activity_at: 2.hours.ago)
    expect(session.reload).to be_reactivatable
  end

  it "records the instance as the session's owner" do
    session = initialize_as(instance_a)
    expect(session.principal_kind).to be_present
    expect(session.principal_subject_id.to_s).to eq(instance_a.id)
  end

  it "reactivates the instance's own session revoked within the grace period" do
    session = initialize_as(instance_a)
    revoke_within_grace!(session)

    post "/api/v1/mcp/message", params: rpc("ping"), headers: headers_for(instance_a, session_id: session.session_token)

    expect(session.reload.status).to eq("active")
  end

  it "does not reactivate or refresh it for another instance" do
    session = initialize_as(instance_a)
    revoke_within_grace!(session)

    post "/api/v1/mcp/message", params: rpc("ping"), headers: headers_for(instance_b, session_id: session.session_token)
    expect(session.reload.status).to eq("revoked")

    session.update_columns(status: "active", revoked_at: nil)
    before = session.reload.last_activity_at
    post "/api/v1/mcp/message", params: rpc("ping"), headers: headers_for(instance_b, session_id: session.session_token)
    expect(session.reload.last_activity_at).to be_within(1.second).of(before)
  end
end
