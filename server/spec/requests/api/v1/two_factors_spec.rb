# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::TwoFactors', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'POST /api/v1/two_factor/enable' do
    context 'when 2FA is not enabled' do
      it 'enables two-factor authentication' do
        post '/api/v1/two_factor/enable', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to have_key('qr_code')
        expect(response_data['data']).to have_key('manual_entry_key')
        expect(response_data['data']).to have_key('backup_codes')
      end

      it 'returns backup codes' do
        post '/api/v1/two_factor/enable', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['backup_codes']).to be_an(Array)
        expect(response_data['data']['backup_codes'].length).to be > 0
      end

      it 'returns QR code for authenticator app' do
        post '/api/v1/two_factor/enable', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['qr_code']).to be_present
      end

      it 'returns manual entry key' do
        post '/api/v1/two_factor/enable', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['manual_entry_key']).to be_present
      end
    end

    context 'when 2FA is already enabled' do
      before do
        user.enable_two_factor!
      end

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
    before do
      user.enable_two_factor!
    end

    context 'with valid token' do
      it 'verifies setup successfully' do
        # Generate a valid TOTP token
        totp = ROTP::TOTP.new(user.two_factor_secret)
        valid_token = totp.now

        post '/api/v1/two_factor/verify_setup',
             params: { token: valid_token },
             headers: headers,
             as: :json

        expect_success_response
        expect(json_response['message']).to include('verified successfully')
      end
    end

    context 'with invalid token' do
      it 'returns error' do
        post '/api/v1/two_factor/verify_setup',
             params: { token: '000000' },
             headers: headers,
             as: :json

        expect_error_response('Invalid verification token', 400)
      end
    end

    context 'without token parameter' do
      it 'returns error' do
        post '/api/v1/two_factor/verify_setup',
             params: {},
             headers: headers,
             as: :json

        expect_error_response('Verification token is required', 400)
      end
    end

    context 'when 2FA setup not started' do
      let(:user_without_2fa) { create(:user, account: account) }
      let(:headers) { auth_headers_for(user_without_2fa) }

      it 'returns error' do
        post '/api/v1/two_factor/verify_setup',
             params: { token: '123456' },
             headers: headers,
             as: :json

        expect_error_response('Two-factor authentication setup not found', 400)
      end
    end
  end

  describe 'DELETE /api/v1/two_factor/disable' do
    context 'when 2FA is enabled' do
      before do
        user.enable_two_factor!
      end

      it 'disables two-factor authentication' do
        delete '/api/v1/two_factor/disable', headers: headers, as: :json

        expect_success_response
        expect(json_response['message']).to include('disabled')

        user.reload
        expect(user.two_factor_enabled?).to be false
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
    context 'when 2FA is enabled' do
      before do
        user.enable_two_factor!
      end

      it 'returns enabled status' do
        get '/api/v1/two_factor/status', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['two_factor_enabled']).to be true
      end

      it 'returns backup codes count' do
        get '/api/v1/two_factor/status', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('backup_codes_count')
      end

      it 'returns enabled_at timestamp' do
        get '/api/v1/two_factor/status', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('enabled_at')
      end
    end

    context 'when 2FA is not enabled' do
      it 'returns disabled status' do
        get '/api/v1/two_factor/status', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['two_factor_enabled']).to be false
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
    context 'when 2FA is enabled' do
      before do
        user.enable_two_factor!
      end

      it 'regenerates backup codes successfully' do
        original_codes = user.two_factor_backup_codes.dup

        post '/api/v1/two_factor/regenerate_backup_codes', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['backup_codes']).to be_an(Array)
        expect(response_data['data']['backup_codes']).not_to eq(original_codes)
      end

      it 'returns new set of backup codes' do
        post '/api/v1/two_factor/regenerate_backup_codes', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['backup_codes'].length).to be > 0
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
    context 'when 2FA is enabled' do
      before do
        user.enable_two_factor!
      end

      it 'returns backup codes' do
        get '/api/v1/two_factor/backup_codes', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['backup_codes']).to be_an(Array)
      end

      it 'returns generated_at timestamp' do
        get '/api/v1/two_factor/backup_codes', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('generated_at')
      end
    end

    context 'when 2FA is not enabled' do
      it 'returns error' do
        get '/api/v1/two_factor/backup_codes', headers: headers, as: :json

        expect_error_response('Two-factor authentication is not enabled', 400)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/two_factor/backup_codes', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end
end
