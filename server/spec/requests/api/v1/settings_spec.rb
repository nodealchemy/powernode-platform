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

      # IMP-94728a788498: the account default network is writable through this
      # surface (blind merge into Account#settings), so it must be READABLE
      # here too — a key that can be set but never read back can only be
      # debugged with DB access once a bad value starts failing composes.
      it 'reads back the provisioning default network setting it can write' do
        account.update!(settings: (account.settings || {}).merge('default_sdwan_network_id' => 'net-42'))

        get '/api/v1/settings', headers: headers, as: :json

        expect_success_response
        expect(json_response_data['account_settings']['default_sdwan_network_id']).to eq('net-42')
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
    # IMP-e639a38f4d8c — this one endpoint carries FOUR sections with two
    # different owners. `user_preferences`, `notification_preferences` and
    # `security_settings` all write columns on the CALLER'S OWN User row, so
    # every authenticated user may write them. `account_settings` is the only
    # section SettingsUpdateService routes at the shared Account row — both its
    # jsonb `settings` column and the direct `name`/`subdomain`/`billing_email`/
    # `tax_id` fields — so it is gated on `admin.settings.update`, the same
    # permission Api::V1::AccountsController#update already requires for the
    # same column. The privileged caller below therefore appears ONLY in the
    # account_settings contexts.
    let(:account_admin) { create(:user, :owner, account: account) }
    let(:account_admin_headers) { auth_headers_for(account_admin) }

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

    # IMP-94728a788498: UNSTUBBED round-trip — the real SettingsUpdateService
    # must both persist the account default network key and read it back in
    # its own response (its current_account_settings is a second hand-rolled
    # copy of the controller's; both must carry the key).
    #
    # IMP-e639a38f4d8c: exercised as a caller who HOLDS admin.settings.update.
    # These examples previously ran as the plain :manager above and were green
    # — that greenness WAS the vulnerability, not a contract to preserve. The
    # write-time value screen they assert is unchanged: it governs WHAT is
    # written, this gate governs WHO writes.
    context 'writing the provisioning default network setting (real service)' do
      it 'persists the key and reads it back in the response' do
        put '/api/v1/settings',
            params: { settings: { account_settings: { default_sdwan_network_id: 'net-77' } } },
            headers: account_admin_headers, as: :json

        expect_success_response
        expect(account.reload.settings['default_sdwan_network_id']).to eq('net-77')
        expect(json_response_data.dig('settings', 'account_settings', 'default_sdwan_network_id')
                 .presence || json_response_data.dig('account_settings', 'default_sdwan_network_id'))
          .to eq('net-77')
      end

      # IMP-529b8514bbc6 — WRITE-SIDE SCREEN, defence in depth.
      #
      # The composer refuses at COMPOSE time to stand up bare compute for a
      # plan that would resolve its network from a default that could never be
      # an id. Nothing stopped that value being stored, so the refusal reached
      # whoever provisioned next rather than whoever typed it. The read-side
      # guard is unchanged and still authoritative for anything already in the
      # column; this only stops the surface producing new ones.
      it 'refuses a default network that could never be a network id' do
        account.update!(settings: (account.settings || {}).merge(
          'default_sdwan_network_id' => 'net-good', 'timezone' => 'UTC'
        ))

        put '/api/v1/settings',
            params: { settings: { account_settings: { default_sdwan_network_id: { id: 7 } } } },
            headers: account_admin_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
        expect(json_response.to_s).to include('default_sdwan_network_id')
        # The screen fires BEFORE any account write, so the stored value is
        # untouched. (The service's ActiveRecord::Rollback is the belt-and-
        # braces for a mixed payload; under transactional fixtures that
        # rollback is a no-op, so this assertion is carried by the early
        # refusal, not by the transaction.)
        expect(account.reload.settings['default_sdwan_network_id']).to eq('net-good')
      end

      it 'refuses a numeric default that is not the unset zero' do
        put '/api/v1/settings',
            params: { settings: { account_settings: { default_sdwan_network_id: 12_345 } } },
            headers: account_admin_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(account.reload.settings['default_sdwan_network_id']).to be_nil
      end

      # The screen must accept everything the composer accepts, or it becomes a
      # second, stricter opinion about the same key — the drift the shared
      # classifier exists to prevent.
      it 'accepts the explicit opt-out and the blank/zero "no default" values' do
        [ 'none', '', 0, nil ].each do |value|
          put '/api/v1/settings',
              params: { settings: { account_settings: { default_sdwan_network_id: value } } },
              headers: account_admin_headers, as: :json

          expect(response).to have_http_status(:ok), "rejected #{value.inspect}"
          # Accepted AND stored — a silent drop would satisfy the status alone.
          expect(account.reload.settings).to have_key('default_sdwan_network_id')
          expect(account.settings['default_sdwan_network_id']).to eq(value)
        end
      end
    end

    # IMP-e639a38f4d8c — WHO may write account-wide state.
    #
    # `Account#settings` is shared, account-wide configuration: the company
    # profile the serializer exposes (company_size, industry, website, phone,
    # address, logo_url), the provisioning default network
    # (default_sdwan_network_id, which decides the fabric every future instance
    # lands on), and — because the merge is blind — any key any consumer reads
    # out of that column. The same code path also writes the account's
    # `name`, `subdomain`, `billing_email` and `tax_id` directly.
    #
    # None of that is a user's own preference, and the OTHER writer of the same
    # column (Api::V1::AccountsController#update) has always required
    # `admin.settings.update`. This surface did not, which made it the more
    # capable of the two doors: AccountsController permits :settings as a
    # SCALAR, so strong params drops a Hash there, while this one permits
    # `account_settings: {}` and could write anything.
    #
    # The oracle here is ABSENCE OF EFFECT, not status: a guard that writes the
    # row and then reports 403 would satisfy a status assertion. The stored
    # values are seeded first so these compare a real value against a real
    # value, never nil against nil. The status lives in its own example.
    context 'when the caller lacks admin.settings.update' do
      before do
        account.update!(settings: (account.settings || {}).merge(
          'default_sdwan_network_id' => 'net-preexisting',
          'industry' => 'aerospace'
        ))
      end

      it 'leaves the stored account settings UNCHANGED' do
        put '/api/v1/settings',
            params: { settings: { account_settings: {
              default_sdwan_network_id: 'net-seized', industry: 'seized'
            } } },
            headers: headers, as: :json

        expect(account.reload.settings['default_sdwan_network_id']).to eq('net-preexisting')
        expect(account.settings['industry']).to eq('aerospace')
      end

      it 'leaves the account identity fields the same section writes UNCHANGED' do
        original_name = account.name
        original_subdomain = account.subdomain
        original_billing_email = account.billing_email

        put '/api/v1/settings',
            params: { settings: { account_settings: {
              name: 'Seized Co', subdomain: 'seized', billing_email: 'attacker@example.com'
            } } },
            headers: headers, as: :json

        account.reload
        expect(account.name).to eq(original_name)
        expect(account.subdomain).to eq(original_subdomain)
        expect(account.billing_email).to eq(original_billing_email)
      end

      # The runtime shape a partial-write bug actually takes: one request
      # carrying BOTH a section the caller may write and one they may not. The
      # gate is a before_action, so the whole request fails closed — the
      # permitted half must not land either, or the endpoint becomes a way to
      # discover the gate by watching which half took effect.
      it 'fails the WHOLE request closed on a mixed self-service + account payload' do
        # Seeded so the preference assertion below compares a real value to a
        # real value rather than nil to nil.
        user.update!(preferences: { 'theme' => 'light' })

        put '/api/v1/settings',
            params: { settings: {
              user_preferences: { theme: 'dark' },
              account_settings: { industry: 'seized' }
            } },
            headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect(account.reload.settings['industry']).to eq('aerospace')
        expect(user.reload.preferences['theme']).to eq('light')
      end

      it 'responds 403' do
        put '/api/v1/settings',
            params: { settings: { account_settings: { industry: 'seized' } } },
            headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end

      # The gate must not swallow the three self-service sections that share
      # this endpoint — they write the CALLER'S OWN User row, and the frontend
      # sends them here for every user (ThemeContext and ProfilePage both PUT
      # user_preferences with no account_settings at all).
      it 'still lets the same caller write their own preferences' do
        put '/api/v1/settings',
            params: { settings: { user_preferences: { theme: 'dark' } } },
            headers: headers, as: :json

        expect_success_response
        expect(user.reload.preferences['theme']).to eq('dark')
      end

      it 'still lets the same caller write their own notification preferences' do
        put '/api/v1/settings',
            params: { settings: { notification_preferences: { marketing_emails: true } } },
            headers: headers, as: :json

        expect_success_response
        expect(user.reload.notification_preferences['marketing_emails']).to be true
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
