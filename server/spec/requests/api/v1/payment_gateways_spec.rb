# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::PaymentGateways', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:admin_user) { create(:user, :admin, account: account) }

  let(:headers) { auth_headers_for(user) }
  let(:admin_headers) { auth_headers_for(admin_user) }

  before do
    # Grant admin payment permission
    admin_user.roles.first.permissions.create!(name: 'admin.settings.payment')
  end

  describe 'GET /api/v1/payment_gateways' do
    it 'returns gateway overview without authentication' do
      get '/api/v1/payment_gateways', as: :json

      expect_success_response
      data = json_response_data
      expect(data['gateways']).to be_present
      expect(data['gateways']).to have_key('stripe')
      expect(data['gateways']).to have_key('paypal')
      expect(data['status']).to be_present
      expect(data['statistics']).to be_present
    end

    it 'includes gateway configurations' do
      get '/api/v1/payment_gateways', as: :json

      expect_success_response
      data = json_response_data
      stripe_config = data['gateways']['stripe']
      expect(stripe_config['provider']).to eq('stripe')
      expect(stripe_config['name']).to eq('Stripe')
      expect(stripe_config).to have_key('enabled')
      expect(stripe_config).to have_key('supported_methods')
    end

    it 'includes gateway statistics' do
      get '/api/v1/payment_gateways', as: :json

      expect_success_response
      data = json_response_data
      expect(data['statistics']).to have_key('stripe')
      expect(data['statistics']).to have_key('paypal')
      expect(data['statistics']).to have_key('overall')
    end

    it 'includes recent transactions' do
      invoice = create(:invoice, account: account)
      create(:payment, :succeeded, account: account, invoice: invoice)

      get '/api/v1/payment_gateways', as: :json

      expect_success_response
      data = json_response_data
      expect(data['recent_transactions']).to be_an(Array)
    end
  end

  describe 'GET /api/v1/payment_gateways/:id' do
    context 'with admin.settings.payment permission' do
      it 'returns stripe gateway details' do
        get '/api/v1/payment_gateways/stripe', headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['gateway']).to eq('stripe')
        expect(data['configuration']).to be_present
        expect(data['status']).to be_present
        expect(data['transactions']).to be_an(Array)
        expect(data['webhooks']).to be_an(Array)
        expect(data['statistics']).to be_present
      end

      it 'returns paypal gateway details' do
        get '/api/v1/payment_gateways/paypal', headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['gateway']).to eq('paypal')
        expect(data['configuration']).to be_present
      end

      it 'returns error for invalid gateway' do
        get '/api/v1/payment_gateways/invalid', headers: admin_headers, as: :json

        expect_error_response('Invalid gateway', 404)
      end
    end

    context 'without admin.settings.payment permission' do
      it 'returns forbidden error' do
        get '/api/v1/payment_gateways/stripe', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH /api/v1/payment_gateways/:id' do
    context 'with admin.settings.payment permission' do
      it 'updates stripe configuration' do
        config_params = {
          configuration: {
            publishable_key: 'pk_test_newkey123456789012345678',
            secret_key: 'sk_test_newsecret123456789012345678',
            enabled: true,
            test_mode: true
          }
        }

        patch '/api/v1/payment_gateways/stripe',
              params: config_params,
              headers: admin_headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data['gateway']).to eq('stripe')
        expect(data['configuration']).to be_present
      end

      it 'updates paypal configuration' do
        config_params = {
          configuration: {
            client_id: 'new_client_id_1234567890',
            client_secret: 'new_secret_1234567890',
            mode: 'sandbox',
            enabled: true,
            test_mode: true
          }
        }

        patch '/api/v1/payment_gateways/paypal',
              params: config_params,
              headers: admin_headers,
              as: :json

        expect_success_response
      end

      it 'validates stripe key format' do
        config_params = {
          configuration: {
            secret_key: 'invalid_key',
            enabled: true
          }
        }

        patch '/api/v1/payment_gateways/stripe',
              params: config_params,
              headers: admin_headers,
              as: :json

        expect_error_response(
          'Secret key format is invalid (must start with sk_test_ or sk_live_)',
          422
        )
      end

      it 'validates paypal mode' do
        config_params = {
          configuration: {
            client_id: 'valid_client_id_123',
            client_secret: 'valid_secret_123',
            mode: 'invalid',
            enabled: true
          }
        }

        patch '/api/v1/payment_gateways/paypal',
              params: config_params,
              headers: admin_headers,
              as: :json

        expect_error_response(
          "Mode must be either 'sandbox' or 'live'",
          422
        )
      end

      it 'returns error for invalid gateway' do
        patch '/api/v1/payment_gateways/invalid',
              params: { configuration: {} },
              headers: admin_headers,
              as: :json

        expect_error_response('Invalid gateway', 404)
      end
    end

    context 'without admin.settings.payment permission' do
      it 'returns forbidden error' do
        patch '/api/v1/payment_gateways/stripe',
              params: { configuration: {} },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/payment_gateways/:id/test_connection' do
    context 'with admin.settings.payment permission' do
      it 'starts gateway connection test' do
        # Mock the worker client
        allow_any_instance_of(WorkerHttpClient).to receive(:post).and_return(
          double(code: 200, body: '{}')
        )

        post '/api/v1/payment_gateways/stripe/test_connection',
             headers: admin_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['job_id']).to be_present
        expect(data['status']).to eq('pending')
        expect(data).to have_key('poll_url')
      end

      it 'creates gateway connection job record' do
        allow_any_instance_of(WorkerHttpClient).to receive(:post).and_return(
          double(code: 200, body: '{}')
        )

        expect {
          post '/api/v1/payment_gateways/stripe/test_connection',
               headers: admin_headers,
               as: :json
        }.to change { GatewayConnectionJob.count }.by(1)
      end

      it 'returns error for invalid gateway' do
        post '/api/v1/payment_gateways/invalid/test_connection',
             headers: admin_headers,
             as: :json

        expect_error_response('Invalid gateway', 404)
      end
    end

    context 'without admin.settings.payment permission' do
      it 'returns forbidden error' do
        post '/api/v1/payment_gateways/stripe/test_connection',
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/payment_gateways/:id/webhook_events' do
    context 'with admin.settings.payment permission' do
      it 'returns webhook events for gateway' do
        # Create webhook events
        WebhookEvent.create!(
          provider: 'stripe',
          event_type: 'payment_intent.succeeded',
          status: 'processed',
          external_id: 'evt_test_123',
          payload: {}
        )

        get '/api/v1/payment_gateways/stripe/webhook_events',
            headers: admin_headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['events']).to be_an(Array)
        expect(data['pagination']).to be_present
      end

      it 'paginates webhook events' do
        get '/api/v1/payment_gateways/stripe/webhook_events',
            params: { page: 1, per_page: 10 },
            headers: admin_headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['pagination']['current_page']).to eq(1)
        expect(data['pagination']['per_page']).to eq(10)
      end
    end
  end

  describe 'GET /api/v1/payment_gateways/:id/transactions' do
    context 'with admin.settings.payment permission' do
      it 'returns transactions for gateway' do
        get '/api/v1/payment_gateways/stripe/transactions',
            headers: admin_headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['transactions']).to be_an(Array)
        expect(data['pagination']).to be_present
      end

      it 'paginates transactions' do
        get '/api/v1/payment_gateways/stripe/transactions',
            params: { page: 1, per_page: 5 },
            headers: admin_headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['pagination']['per_page']).to eq(5)
      end
    end
  end
end
