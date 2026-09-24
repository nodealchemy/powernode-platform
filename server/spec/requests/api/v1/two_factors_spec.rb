# frozen_string_literal: true

require 'rails_helper'

# IMP-99e8e4701150 — pending vs confirmed enrolment, re-auth-gated
# disable/regenerate, and one-way (bcrypt) backup-code digests. Replaces the
# pre-fix spec, which asserted the vulnerable behavior directly (enable
# activating 2FA and returning backup codes in one call, GET backup_codes
# re-fetching them at will, disable with no re-auth).
RSpec.describe 'Api::V1::TwoFactors', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  def totp_for(secret)
    ROTP::TOTP.new(secret).now
  end

  describe 'POST /api/v1/two_factor/enable' do
    context 'when 2FA is not enabled' do
      it 'starts a PENDING enrolment without activating 2FA' do
        post '/api/v1/two_factor/enable', headers: headers, as: :json

        expect_success_response
        expect(user.reload.two_factor_enabled?).to be false
        expect(user.two_factor_pending?).to be true
      end

      it 'returns the QR code and manual entry key, but no backup codes' do
        post '/api/v1/two_factor/enable', headers: headers, as: :json

        data = json_response['data']
        expect(data['qr_code']).to be_present
        expect(data['manual_entry_key']).to be_present
        expect(data).not_to have_key('backup_codes')
      end

      it 're-enabling while pending replaces the pending secret' do
        post '/api/v1/two_factor/enable', headers: headers, as: :json
        first_key = json_response['data']['manual_entry_key']

        post '/api/v1/two_factor/enable', headers: headers, as: :json
        second_key = json_response['data']['manual_entry_key']

        expect(second_key).not_to eq(first_key)
      end
    end

    context 'when 2FA is already confirmed/enabled' do
      before { user.enable_two_factor! }

      it 'returns conflict error' do
        post '/api/v1/two_factor/enable', headers: headers, as: :json

        expect_error_response('Two-factor authentication is already enabled for this account', 409)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/two_factor/enable', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/two_factor/verify_setup' do
    context 'with a valid token against the pending secret' do
      before { post '/api/v1/two_factor/enable', headers: headers, as: :json }

      it 'activates 2FA (confirmed, not just pending)' do
        secret = user.reload.two_factor_pending_secret

        post '/api/v1/two_factor/verify_setup',
             params: { token: totp_for(secret) },
             headers: headers,
             as: :json

        expect_success_response
        user.reload
        expect(user.two_factor_enabled?).to be true
        expect(user.two_factor_pending?).to be false
      end

      it 'returns backup codes exactly once, in the verify_setup response' do
        secret = user.reload.two_factor_pending_secret

        post '/api/v1/two_factor/verify_setup',
             params: { token: totp_for(secret) },
             headers: headers,
             as: :json

        codes = json_response['data']['backup_codes']
        expect(codes).to be_an(Array)
        expect(codes.length).to be > 0
      end

      it 'persists only bcrypt digests, never the plaintext codes' do
        secret = user.reload.two_factor_pending_secret

        post '/api/v1/two_factor/verify_setup',
             params: { token: totp_for(secret) },
             headers: headers,
             as: :json

        plain_codes = json_response['data']['backup_codes']
        stored = user.reload.backup_codes
        expect(stored).to be_present
        expect(stored & plain_codes).to be_empty
        expect(stored).to all(match(/\A\$2[aby]?\$/))
      end
    end

    context 'with an invalid token' do
      before { post '/api/v1/two_factor/enable', headers: headers, as: :json }

      it 'returns error and does not activate 2FA' do
        post '/api/v1/two_factor/verify_setup',
             params: { token: '000000' },
             headers: headers,
             as: :json

        expect_error_response('Invalid verification token', 400)
        expect(user.reload.two_factor_enabled?).to be false
      end
    end

    context 'without a token parameter' do
      it 'returns error' do
        post '/api/v1/two_factor/verify_setup',
             params: {},
             headers: headers,
             as: :json

        expect_error_response('Verification token is required', 400)
      end
    end

    context 'when no enrolment was ever started' do
      it 'returns error' do
        post '/api/v1/two_factor/verify_setup',
             params: { token: '123456' },
             headers: headers,
             as: :json

        expect_error_response('Two-factor authentication setup not found', 400)
      end
    end

    context 'when the pending secret has expired' do
      before do
        post '/api/v1/two_factor/enable', headers: headers, as: :json
        user.reload.update_column(:two_factor_pending_expires_at, 1.minute.ago)
      end

      it 'returns an expiry-specific error' do
        post '/api/v1/two_factor/verify_setup',
             params: { token: '123456' },
             headers: headers,
             as: :json

        expect_error_response('Two-factor setup has expired', 400)
      end
    end

    context 'when 2FA is already confirmed' do
      before { user.enable_two_factor! }

      it 'returns conflict error' do
        post '/api/v1/two_factor/verify_setup',
             params: { token: '123456' },
             headers: headers,
             as: :json

        expect_error_response('Two-factor authentication is already enabled for this account', 409)
      end
    end
  end

  describe 'DELETE /api/v1/two_factor/disable' do
    context 'when 2FA is confirmed' do
      let!(:secret) { user.enable_two_factor! }

      it 'refuses with no code' do
        delete '/api/v1/two_factor/disable', headers: headers, as: :json

        expect_error_response('A valid authentication code or backup code is required', 422)
        expect(user.reload.two_factor_enabled?).to be true
      end

      it 'refuses with an invalid code' do
        delete '/api/v1/two_factor/disable', params: { code: '000000' }, headers: headers, as: :json

        expect_error_response('A valid authentication code or backup code is required', 422)
        expect(user.reload.two_factor_enabled?).to be true
      end

      it 'refuses with an empty code' do
        delete '/api/v1/two_factor/disable', params: { code: '' }, headers: headers, as: :json

        expect_error_response('A valid authentication code or backup code is required', 422)
        expect(user.reload.two_factor_enabled?).to be true
      end

      it 'a wrong code never returns 401 (the frontend would read that as an expired session)' do
        delete '/api/v1/two_factor/disable', params: { code: '000000' }, headers: headers, as: :json

        expect(response).not_to have_http_status(:unauthorized)
      end

      it 'disables with a valid TOTP code' do
        delete '/api/v1/two_factor/disable', params: { code: totp_for(secret) }, headers: headers, as: :json

        expect_success_response
        user.reload
        expect(user.two_factor_enabled?).to be false
        expect(user.two_factor_secret).to be_nil
        expect(user.backup_codes).to be_nil
      end

      it 'disables with a valid, unused backup code' do
        # Regenerate through the model to get a known plaintext code for this example
        # (only digests are stored/retrievable after generation).
        plain_codes = user.regenerate_backup_codes!

        delete '/api/v1/two_factor/disable', params: { code: plain_codes.first }, headers: headers, as: :json

        expect_success_response
        expect(user.reload.two_factor_enabled?).to be false
      end
    end

    context 'when 2FA is not enabled' do
      it 'returns error' do
        delete '/api/v1/two_factor/disable', headers: headers, as: :json

        expect_error_response('Two-factor authentication is not enabled for this account', 400)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        delete '/api/v1/two_factor/disable', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/two_factor/status' do
    context 'when 2FA is confirmed' do
      before { user.enable_two_factor! }

      it 'returns enabled status' do
        get '/api/v1/two_factor/status', headers: headers, as: :json

        expect_success_response
        expect(json_response['data']['two_factor_enabled']).to be true
      end

      it 'returns backup codes count' do
        get '/api/v1/two_factor/status', headers: headers, as: :json

        expect(json_response['data']).to have_key('backup_codes_count')
      end

      it 'returns enabled_at timestamp' do
        get '/api/v1/two_factor/status', headers: headers, as: :json

        expect(json_response['data']).to have_key('enabled_at')
      end
    end

    context 'when 2FA is only pending (not confirmed)' do
      before { post '/api/v1/two_factor/enable', headers: headers, as: :json }

      it 'still reports disabled status' do
        get '/api/v1/two_factor/status', headers: headers, as: :json

        expect(json_response['data']['two_factor_enabled']).to be false
      end
    end

    context 'when 2FA is not enabled' do
      it 'returns disabled status' do
        get '/api/v1/two_factor/status', headers: headers, as: :json

        expect_success_response
        expect(json_response['data']['two_factor_enabled']).to be false
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/two_factor/status', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/two_factor/regenerate_backup_codes' do
    context 'when 2FA is confirmed' do
      let!(:secret) { user.enable_two_factor! }

      it 'refuses with no code' do
        post '/api/v1/two_factor/regenerate_backup_codes', headers: headers, as: :json

        expect_error_response('A valid authentication code or backup code is required', 422)
      end

      it 'refuses with an empty code' do
        post '/api/v1/two_factor/regenerate_backup_codes', params: { code: '' }, headers: headers, as: :json

        expect_error_response('A valid authentication code or backup code is required', 422)
      end

      it 'refuses with an invalid code' do
        post '/api/v1/two_factor/regenerate_backup_codes', params: { code: '000000' }, headers: headers, as: :json

        expect_error_response('A valid authentication code or backup code is required', 422)
      end

      it 'a wrong code never returns 401 (the frontend would read that as an expired session)' do
        post '/api/v1/two_factor/regenerate_backup_codes', params: { code: '000000' }, headers: headers, as: :json

        expect(response).not_to have_http_status(:unauthorized)
      end

      it 'regenerates with a valid TOTP code and returns new codes once' do
        original_digests = user.backup_codes.dup

        post '/api/v1/two_factor/regenerate_backup_codes',
             params: { code: totp_for(secret) },
             headers: headers,
             as: :json

        expect_success_response
        codes = json_response['data']['backup_codes']
        expect(codes).to be_an(Array)
        expect(codes.length).to be > 0
        expect(user.reload.backup_codes).not_to eq(original_digests)
      end

      it 'invalidates the previous codes' do
        old_codes = user.regenerate_backup_codes!

        post '/api/v1/two_factor/regenerate_backup_codes',
             params: { code: totp_for(secret) },
             headers: headers,
             as: :json

        expect(user.reload.verify_backup_code(old_codes.first)).to be false
      end
    end

    context 'when 2FA is not enabled' do
      it 'returns error' do
        post '/api/v1/two_factor/regenerate_backup_codes', headers: headers, as: :json

        expect_error_response('Two-factor authentication must be enabled to regenerate backup codes', 400)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/two_factor/regenerate_backup_codes', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/two_factor/backup_codes' do
    it 'no longer exists as a route' do
      get '/api/v1/two_factor/backup_codes', headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
