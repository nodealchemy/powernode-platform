# frozen_string_literal: true

require 'rails_helper'
require 'openssl'
require 'cgi'

RSpec.describe 'Api::V1::EmailSettings', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, account: account, permissions: [ 'admin.settings.email' ]) }
  let(:regular_user) { create(:user, account: account) }
  let(:admin_headers) { auth_headers_for(admin_user) }
  let(:user_headers) { auth_headers_for(regular_user) }

  describe 'GET /api/v1/email_settings' do
    context 'with admin permission' do
      before do
        allow(AdminSetting).to receive(:get).and_call_original
        allow(AdminSetting).to receive(:get).with('email_provider', anything).and_return('smtp')
        allow(AdminSetting).to receive(:get).with('smtp_host', anything).and_return('smtp.example.com')
        allow(AdminSetting).to receive(:get).with('smtp_port', anything).and_return(587)
      end

      it 'returns email settings' do
        get '/api/v1/email_settings', headers: admin_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to have_key('provider')
        expect(response_data['data']).to have_key('smtp_host')
        expect(response_data['data']).to have_key('smtp_port')
      end

      it 'includes provider-specific settings' do
        get '/api/v1/email_settings', headers: admin_headers, as: :json

        response_data = json_response

        expect(response_data['data']).to have_key('sendgrid_api_key')
        expect(response_data['data']).to have_key('ses_region')
        expect(response_data['data']).to have_key('mailgun_domain')
      end

      it 'includes email behavior settings' do
        get '/api/v1/email_settings', headers: admin_headers, as: :json

        response_data = json_response

        expect(response_data['data']).to have_key('email_verification_expiry_hours')
        expect(response_data['data']).to have_key('password_reset_expiry_hours')
        expect(response_data['data']).to have_key('max_email_retries')
      end
    end

    context 'secret exposure to human (UI) callers' do
      let(:plaintext_password) { 'sup3r-s3cret-smtp-pw' }
      let(:plaintext_sendgrid) { 'SG.real-sendgrid-key' }

      before do
        # Persist secrets through the controller's write path so they are encrypted at rest
        put '/api/v1/email_settings',
            params: { email_settings: { smtp_password: plaintext_password, sendgrid_api_key: plaintext_sendgrid } },
            headers: admin_headers, as: :json
      end

      it 'never returns plaintext secret values in show' do
        get '/api/v1/email_settings', headers: admin_headers, as: :json

        body = response.body
        expect(body).not_to include(plaintext_password)
        expect(body).not_to include(plaintext_sendgrid)

        data = json_response['data']
        expect(data['smtp_password']).not_to eq(plaintext_password)
        expect(data['sendgrid_api_key']).not_to eq(plaintext_sendgrid)
      end

      it 'exposes set-indicators instead of secret values' do
        get '/api/v1/email_settings', headers: admin_headers, as: :json

        data = json_response['data']
        expect(data['smtp_password_set']).to be(true)
        expect(data['sendgrid_api_key_set']).to be(true)
      end

      it 'persists secrets encrypted at rest (not plaintext)' do
        stored = AdminSetting.get('smtp_password_encrypted', '')
        expect(stored).to be_present
        expect(stored).not_to eq(plaintext_password)
        # Round-trips back to the original via the credential encryption service
        expect(Security::CredentialEncryptionService.decrypt_value(stored)).to eq(plaintext_password)
      end

      it 'returns real decrypted secrets to the worker (mail send path)' do
        # The worker caller needs the real secrets to configure ActionMailer.
        worker = create(:worker, status: 'active', account: account)
        worker_jwt = Security::JwtService.encode(
          { sub: worker.id, type: 'worker', version: Security::JwtService::CURRENT_TOKEN_VERSION }
        )
        worker_headers = { 'Authorization' => "Bearer #{worker_jwt}", 'Content-Type' => 'application/json' }

        get '/api/v1/email_settings', headers: worker_headers, as: :json

        data = json_response['data']
        expect(data['smtp_password']).to eq(plaintext_password)
        expect(data['sendgrid_api_key']).to eq(plaintext_sendgrid)
      end
    end

    # IMP-79557320ede0 — the reveal used to be gated on `current_worker.present?`
    # alone. Worker identity can be established from the forwarded subject-CN
    # header ALONE (Security::MtlsTrust#verify_request's no-PEM branch), which is
    # a header the client controls unless the reverse proxy strips it — and core
    # cannot prove that strip for routers it does not write. Composed with a
    # worker CN that may be a published constant (a dev-bootstrapped database
    # keeps Workers::EnsureSystemWorker::DEV_SENTINEL_NODE_ID forever), that
    # handed decrypted SMTP/provider credentials to an unauthenticated caller.
    #
    # The oracle is the BODY, never the status: the whole defect is a 200 that
    # returns too much, so a status assertion cannot tell reveal from mask.
    context 'worker identity that is NOT cryptographically verified' do
      let(:plaintext_password) { 'sup3r-s3cret-smtp-pw' }
      let(:plaintext_sendgrid) { 'SG.real-sendgrid-key' }
      let(:worker_cn) { Workers::EnsureSystemWorker::DEV_SENTINEL_NODE_ID }
      let!(:worker) { create(:worker, status: 'active', account: account, node_instance_id: worker_cn) }

      # `def`, not `let`: these mint fresh material per call, and a memoized
      # helper can pass against unfixed code by reusing one already-verified
      # object across examples.
      def build_ca(cn)
        key  = OpenSSL::PKey::RSA.new(2048)
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial  = 1
        cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
        cert.issuer  = cert.subject
        cert.public_key = key.public_key
        cert.not_before = Time.now - 3600
        cert.not_after  = Time.now + 3600
        ef = OpenSSL::X509::ExtensionFactory.new(cert, cert)
        cert.add_extension(ef.create_extension('basicConstraints', 'CA:TRUE', true))
        cert.sign(key, OpenSSL::Digest.new('SHA256'))
        [ key, cert ]
      end

      def sign_leaf(cn, ca_key, ca_cert)
        key  = OpenSSL::PKey::RSA.new(2048)
        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial  = 2
        cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
        cert.issuer  = ca_cert.subject
        cert.public_key = key.public_key
        cert.not_before = Time.now - 3600
        cert.not_after  = Time.now + 3600
        cert.sign(ca_key, OpenSSL::Digest.new('SHA256'))
        cert
      end

      def forged_info_header
        { Security::MtlsTrust::SUBJECT_HEADER => CGI.escape(%(Subject="CN=#{worker_cn}")) }
      end

      def fetch_settings(headers)
        get '/api/v1/email_settings', headers: headers, as: :json
        json_response['data']
      end

      # The mask the endpoint hands a caller who may not see the secrets: the
      # value is blanked, the "is it configured" indicator still tells the truth.
      def expect_masked(data)
        expect(data['smtp_password']).to eq('')
        expect(data['sendgrid_api_key']).to eq('')
        expect(data['ses_secret_key']).to eq('')
        expect(data['mailgun_api_key']).to eq('')
        expect(data['smtp_password_set']).to be(true)
        expect(data['sendgrid_api_key_set']).to be(true)
        # Non-secret delivery config still flows — this is a MASK, not a denial.
        expect(data['smtp_host']).to eq('smtp.example.com')
        expect(response.body).not_to include(plaintext_password)
        expect(response.body).not_to include(plaintext_sendgrid)
      end

      around do |example|
        original = Security::MtlsTrust.own_ca_provider
        Security::MtlsTrust.own_ca_provider = -> { our_ca[1].to_pem }
        example.run
        Security::MtlsTrust.own_ca_provider = original
      end

      before do
        put '/api/v1/email_settings',
            params: { email_settings: {
              smtp_password: plaintext_password,
              sendgrid_api_key: plaintext_sendgrid,
              ses_secret_key: 'ses-secret-value',
              mailgun_api_key: 'mailgun-key-value',
              smtp_host: 'smtp.example.com'
            } },
            headers: admin_headers, as: :json
      end

      let(:our_ca) { build_ca('Powernode Internal CA') }

      it 'MASKS the secrets for a forged forwarded-CN header with no client cert' do
        # No PEM, no bearer token — exactly what an unauthenticated caller can
        # send if the header survives the ingress.
        data = fetch_settings(forged_info_header)

        expect(response).to have_http_status(:ok) # authenticated as the worker...
        expect_masked(data)                       # ...but shown nothing secret
      end

      it 'MASKS the secrets when a forwarded PEM fails verification, even alongside a forged CN header' do
        # A foreign CA signs a leaf cloning the worker CN, and the Info header is
        # forged too. Strict-first verification must NOT downgrade to the header.
        foreign = build_ca('Some Other CA')
        leaf = sign_leaf(worker_cn, foreign[0], foreign[1])

        data = fetch_settings(
          forged_info_header.merge(Security::MtlsTrust::PEM_HEADER => CGI.escape(leaf.to_pem))
        )

        expect(response).to have_http_status(:unauthorized)
        expect(response.body).not_to include(plaintext_password)
        expect(response.body).not_to include(plaintext_sendgrid)
      end

      # POSITIVE CONTROL — without this, a mask is indistinguishable from a
      # broken endpoint that reveals nothing to anybody.
      it 'REVEALS the real secrets to a worker whose forwarded cert verifies against our CA' do
        leaf = sign_leaf(worker_cn, our_ca[0], our_ca[1])

        data = fetch_settings(Security::MtlsTrust::PEM_HEADER => CGI.escape(leaf.to_pem))

        expect(response).to have_http_status(:ok)
        expect(data['smtp_password']).to eq(plaintext_password)
        expect(data['sendgrid_api_key']).to eq(plaintext_sendgrid)
        expect(data['ses_secret_key']).to eq('ses-secret-value')
        expect(data['mailgun_api_key']).to eq('mailgun-key-value')
      end

      # POSITIVE CONTROL — the other unforgeable identity. The bearer worker
      # token is signature-checked, so narrowing must not disturb it.
      it 'REVEALS the real secrets to a worker presenting a signed worker JWT' do
        jwt = Security::JwtService.encode(
          { sub: worker.id, type: 'worker', version: Security::JwtService::CURRENT_TOKEN_VERSION }
        )

        data = fetch_settings('Authorization' => "Bearer #{jwt}", 'Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        expect(data['smtp_password']).to eq(plaintext_password)
        expect(data['sendgrid_api_key']).to eq(plaintext_sendgrid)
      end

      it 'MASKS the secrets for a human admin (the 782f119f6 hardening, unchanged)' do
        data = fetch_settings(admin_headers)

        expect(response).to have_http_status(:ok)
        expect_masked(data)
      end
    end

    context 'without admin permission' do
      it 'returns forbidden error' do
        get '/api/v1/email_settings', headers: user_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/email_settings', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PUT /api/v1/email_settings' do
    let(:update_params) do
      {
        email_settings: {
          email_provider: 'smtp',
          smtp_host: 'new-smtp.example.com',
          smtp_port: 465,
          smtp_from_address: 'noreply@example.com'
        }
      }
    end

    context 'with admin permission' do
      before do
        allow(AdminSetting).to receive(:set).and_return(true)
        allow(WorkerJobService).to receive(:enqueue_refresh_email_settings).and_return(true)
      end

      it 'updates email settings' do
        put '/api/v1/email_settings', params: update_params, headers: admin_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('updated successfully')
      end

      it 'handles worker service errors gracefully' do
        allow(WorkerJobService).to receive(:enqueue_refresh_email_settings)
          .and_raise(WorkerJobService::WorkerServiceError.new('Service unavailable'))

        put '/api/v1/email_settings', params: update_params, headers: admin_headers, as: :json

        # Should still succeed even if worker notification fails
        expect_success_response
      end
    end

    context 'without admin permission' do
      it 'returns forbidden error' do
        put '/api/v1/email_settings', params: update_params, headers: user_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/email_settings/test' do
    context 'with admin permission' do
      before do
        allow(WorkerJobService).to receive(:enqueue_test_email).and_return(true)
      end

      it 'sends test email' do
        post '/api/v1/email_settings/test',
             params: { email: 'test@example.com' },
             headers: admin_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('Test email queued')
      end

      it 'requires email address' do
        post '/api/v1/email_settings/test',
             params: {},
             headers: admin_headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'handles worker service errors' do
        allow(WorkerJobService).to receive(:enqueue_test_email)
          .and_raise(WorkerJobService::WorkerServiceError.new('Service unavailable'))

        post '/api/v1/email_settings/test',
             params: { email: 'test@example.com' },
             headers: admin_headers,
             as: :json

        expect(response).to have_http_status(:service_unavailable)
      end
    end

    context 'without admin permission' do
      it 'returns forbidden error' do
        post '/api/v1/email_settings/test',
             params: { email: 'test@example.com' },
             headers: user_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
