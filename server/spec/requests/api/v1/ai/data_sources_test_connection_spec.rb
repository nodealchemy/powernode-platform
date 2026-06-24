# frozen_string_literal: true

require 'rails_helper'

# Focused security spec for POST /api/v1/ai/data_sources/:id/test_connection.
#
# The endpoint issues an outbound HTTP request to a user-controlled
# api_base_url with the data source's decrypted API key attached as a Bearer
# token. Without an SSRF guard, an attacker can point the URL at an internal
# host (cloud metadata, loopback, RFC1918) to (a) reach internal services and
# (b) exfiltrate the credential to a host they control. These specs pin that
# such URLs are rejected BEFORE any request is made and the secret is never sent.
RSpec.describe 'Api::V1::Ai::DataSources test_connection (SSRF)', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.data_sources.read' ]) }
  let(:headers) { auth_headers_for(user) }

  let(:secret_key) { 'super-secret-bearer-token' }

  def build_source(url)
    ds = create(:ai_data_source, :requires_auth, account: account, api_base_url: url)
    create(:ai_data_source_credential, account: account, data_source: ds,
                                       encrypted_api_key: secret_key, is_active: true, is_default: true)
    ds
  end

  context 'when api_base_url points at an internal / disallowed host' do
    # Loopback, RFC1918, and the cloud metadata link-local address are all in
    # HttpConnectionFactory::BLOCKED_CIDRS.
    %w[
      http://127.0.0.1/v1/ping
      http://169.254.169.254/latest/meta-data/
      http://10.0.0.5/internal
    ].each do |bad_url|
      it "rejects #{bad_url} without issuing a request or leaking the credential" do
        data_source = build_source(bad_url)

        post "/api/v1/ai/data_sources/#{data_source.id}/test_connection", headers: headers, as: :json

        # No outbound HTTP request must have been attempted at all.
        expect(a_request(:any, /.*/)).not_to have_been_made

        expect_success_response
        body = json_response
        payload = body['data'] || body
        expect(payload['success']).to be(false)
        # The credential must never appear anywhere in the response.
        expect(response.body).not_to include(secret_key)
      end
    end
  end

  context 'when api_base_url is a normal public host' do
    let(:good_url) { 'https://api.example.com/health' }

    before do
      # validate_url! resolves the host; pin it to a public address so the SSRF
      # guard passes deterministically without real DNS, then stub the response.
      allow(Ai::DataSources::HttpConnectionFactory)
        .to receive(:validate_url!).and_call_original
      allow(Ai::DataSources::HttpConnectionFactory)
        .to receive(:validate_url!).with(satisfy { |u| u.to_s.include?('api.example.com') })
        .and_return(true)

      stub_request(:get, good_url).to_return(status: 200, body: '{"ok":true}',
                                             headers: { 'Content-Type' => 'application/json' })
    end

    it 'allows the request and reports success' do
      data_source = build_source(good_url)

      post "/api/v1/ai/data_sources/#{data_source.id}/test_connection", headers: headers, as: :json

      expect_success_response
      body = json_response
      payload = body['data'] || body
      expect(payload['success']).to be(true)
      expect(payload['status_code']).to eq(200)
      expect(a_request(:get, good_url)).to have_been_made
    end
  end
end
