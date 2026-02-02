# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Settings', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, :manager, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/settings/public' do
    context 'without authentication' do
      it 'returns public settings including copyright text' do
        get '/api/v1/settings/public', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('copyright_text')
        expect(data['copyright_text']).to include(Date.current.year.to_s)
      end
    end
  end

  describe 'GET /api/v1/settings' do
    context 'with authentication' do
      it 'returns user settings and preferences' do
        get '/api/v1/settings', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('user_preferences')
        expect(data).to have_key('account_settings')
        expect(data).to have_key('notification_preferences')
        expect(data).to have_key('security_settings')
      end

      it 'returns default user preferences' do
        get '/api/v1/settings', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        prefs = data['user_preferences']
        expect(prefs['theme']).to eq('light')
        expect(prefs['language']).to eq('en')
        expect(prefs['timezone']).to eq('UTC')
      end

      it 'returns account settings' do
        get '/api/v1/settings', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        account_settings = data['account_settings']
        expect(account_settings['name']).to eq(account.name)
        expect(account_settings).to have_key('subdomain')
      end

      it 'returns security settings' do
        get '/api/v1/settings', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        security = data['security_settings']
        expect(security).to have_key('email_verified')
        expect(security).to have_key('two_factor_enabled')
        expect(security).to have_key('login_history')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/settings', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PUT /api/v1/settings' do
    let(:valid_params) do
      {
        settings: {
          user_preferences: {
            theme: 'dark',
            language: 'es'
          }
        }
      }
    end

    context 'with valid params' do
      it 'updates settings successfully' do
        allow_any_instance_of(SettingsUpdateService).to receive(:call).and_return({
          success: true,
          data: { updated: true }
        })

        put '/api/v1/settings', params: valid_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Settings updated successfully')
      end
    end

    context 'with invalid params' do
      it 'returns error when update fails' do
        allow_any_instance_of(SettingsUpdateService).to receive(:call).and_return({
          success: false,
          errors: [ 'Invalid settings' ]
        })

        put '/api/v1/settings', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end
  end

  describe 'GET /api/v1/settings/notifications' do
    context 'with authentication' do
      it 'returns notification preferences' do
        get '/api/v1/settings/notifications', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('email_notifications')
        expect(data).to have_key('invoice_notifications')
        expect(data).to have_key('security_alerts')
      end

      it 'returns default notification preferences' do
        get '/api/v1/settings/notifications', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['email_notifications']).to be true
        expect(data['security_alerts']).to be true
      end
    end
  end

  describe 'PUT /api/v1/settings/notifications' do
    let(:notification_params) do
      {
        notifications: {
          email_notifications: false,
          marketing_emails: true
        }
      }
    end

    context 'with valid params' do
      it 'updates notification preferences' do
        put '/api/v1/settings/notifications', params: notification_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Notification preferences updated')
      end
    end

    context 'with invalid params' do
      it 'returns error when update fails' do
        # Create the user first, then set up stub
        user # trigger let
        allow_any_instance_of(User).to receive(:update).with(hash_including(:notification_preferences)).and_return(false)

        put '/api/v1/settings/notifications', params: notification_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'GET /api/v1/settings/preferences' do
    context 'with authentication' do
      it 'returns user preferences' do
        get '/api/v1/settings/preferences', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('theme')
        expect(data).to have_key('language')
        expect(data).to have_key('timezone')
        expect(data).to have_key('dashboard_layout')
      end
    end
  end

  describe 'PUT /api/v1/settings/preferences' do
    let(:preference_params) do
      {
        preferences: {
          theme: 'dark',
          language: 'es',
          timezone: 'America/New_York'
        }
      }
    end

    context 'with valid params' do
      it 'updates user preferences' do
        put '/api/v1/settings/preferences', params: preference_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('User preferences updated')
      end
    end

    context 'with invalid params' do
      it 'returns error when update fails' do
        # Create the user first, then set up stub
        user # trigger let
        allow_any_instance_of(User).to receive(:update).with(hash_including(:preferences)).and_return(false)

        put '/api/v1/settings/preferences', params: preference_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
