# frozen_string_literal: true

require "rails_helper"
require "openssl"

# Federation mTLS Phase 2 (S5.3) — core auth hardening, proven end-to-end.
#
# Once peer CAs share the Traefik client-auth bundle, a presented cert must be
# cryptographically verified against OUR CA before its CN is trusted, so a
# peer-CA-signed cert cannot impersonate a worker. Exercised on the worker_auth
# route (which includes MtlsClientAuthentication).
RSpec.describe "Core mTLS auth hardening", type: :request do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account, email_verified: true) }
  let(:worker)  { create(:worker, :system_worker, status: "active") }
  let(:path)    { "/api/v1/worker_auth/authenticate_user" }
  let(:params)  { { email: user.email, password: TestUsers::PASSWORD } }

  before do
    # Isolate the mTLS gate: make the user-auth half always succeed.
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
    allow(User).to receive(:find_by).with(email: user.email).and_return(user)
    allow(user).to receive(:authenticate).and_return(true)
  end

  def forwarded(cn, cert_pem)
    {
      "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{cn}")),
      "X-Forwarded-Tls-Client-Cert"      => CGI.escape(cert_pem),
      "Content-Type"                     => "application/json"
    }
  end

  # A leaf issued by OUR CA (the provider the extension injects at boot).
  def our_ca_cert_pem(cn)
    key = OpenSSL::PKey.generate_key("ED25519")
    csr = OpenSSL::X509::Request.new
    csr.version = 0
    csr.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
    csr.public_key = key
    csr.sign(key, nil)
    System::InternalCaService.issue_certificate(csr_pem: csr.to_pem, common_name: cn)[:cert_pem]
  end

  # A leaf from a FOREIGN CA that merely cloned our CA's CN — the symmetric-peer
  # impersonation attempt.
  def foreign_ca_cert_pem(cn)
    ca_key = OpenSSL::PKey.generate_key("ED25519")
    ca = OpenSSL::X509::Certificate.new
    ca.version = 2; ca.serial = 1; ca.not_before = Time.now - 60; ca.not_after = Time.now + 3600
    ca.subject = OpenSSL::X509::Name.parse("/CN=Powernode Internal CA"); ca.issuer = ca.subject
    ca.public_key = ca_key
    ef = OpenSSL::X509::ExtensionFactory.new(ca, ca)
    ca.add_extension(ef.create_extension("basicConstraints", "CA:TRUE", true))
    ca.sign(ca_key, nil)

    leaf_key = OpenSSL::PKey.generate_key("ED25519")
    leaf = OpenSSL::X509::Certificate.new
    leaf.version = 2; leaf.serial = 2; leaf.not_before = Time.now - 60; leaf.not_after = Time.now + 3600
    leaf.subject = OpenSSL::X509::Name.parse("/CN=#{cn}"); leaf.issuer = ca.subject
    leaf.public_key = leaf_key
    leaf.sign(ca_key, nil)
    leaf.to_pem
  end

  it "authenticates a worker cert signed by OUR CA" do
    post path, params: params,
         headers: forwarded(worker.node_instance_id, our_ca_cert_pem(worker.node_instance_id)),
         as: :json
    expect(response).not_to have_http_status(:unauthorized)
  end

  it "REJECTS a foreign-CA cert that clones a worker's CN (impersonation guard)" do
    post path, params: params,
         headers: forwarded(worker.node_instance_id, foreign_ca_cert_pem(worker.node_instance_id)),
         as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "still accepts the Info-only header when no PEM is forwarded (graceful)" do
    post path, params: params,
         headers: {
           "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{worker.node_instance_id}")),
           "Content-Type" => "application/json"
         }, as: :json
    expect(response).not_to have_http_status(:unauthorized)
  end
end
