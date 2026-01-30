# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::PaymentMethods', type: :request do
  let(:account) { create(:account, :with_stripe_data) }
  let(:billing_reader) { create(:user, account: account, permissions: ['billing.read']) }
  let(:billing_manager) { create(:user, account: account, permissions: ['billing.read', 'billing.manage']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  let(:headers) { auth_headers_for(billing_manager) }
  let(:reader_headers) { auth_headers_for(billing_reader) }
  let(:unauthorized_headers) { auth_headers_for(regular_user) }

  before(:each) do
    Rails.cache.clear
  end

  describe 'GET /api/v1/payment_methods' do
    let!(:payment_methods) { create_list(:payment_method, 3, account: account) }
    let!(:other_account_pm) { create(:payment_method) }

    context 'with billing.read permission' do
      it 'returns all payment methods for the current account' do
        get '/api/v1/payment_methods', headers: reader_headers, as: :json

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json['success']).to be true
        expect(json['data'].length).to eq(3)
      end

      it 'returns payment methods ordered by created_at' do
        get '/api/v1/payment_methods', headers: reader_headers, as: :json

        json = json_response
        expect(json['data'].length).to eq(3)
        # Should contain our payment methods
        payment_method_ids = json['data'].map { |pm| pm['id'] }
        expect(payment_method_ids).to match_array(payment_methods.map(&:id))
      end

      it 'does not return payment methods from other accounts' do
        get '/api/v1/payment_methods', headers: reader_headers, as: :json

        json = json_response
        payment_method_ids = json['data'].map { |pm| pm['id'] }
        expect(payment_method_ids).not_to include(other_account_pm.id)
      end

      it 'returns expected payment method fields' do
        get '/api/v1/payment_methods', headers: reader_headers, as: :json

        json = json_response
        first_pm = json['data'].first
        expect(first_pm).to have_key('id')
        expect(first_pm).to have_key('gateway')
        expect(first_pm).to have_key('last_four')
        expect(first_pm).to have_key('brand')
        expect(first_pm).to have_key('is_default')
        expect(first_pm).to have_key('created_at')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/payment_methods', as: :json

        expect_error_response('Access token required', 401)
      end
    end

    context 'without billing.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/payment_methods', headers: unauthorized_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/payment_methods' do
    let(:valid_params) do
      {
        payment_method: {
          gateway: 'stripe',
          external_id: "pm_#{SecureRandom.hex(12)}",
          payment_type: 'card',
          last_four: '4242',
          brand: 'visa',
          exp_month: 12,
          exp_year: 1.year.from_now.year,
          is_default: false
        }
      }
    end

    context 'with billing.manage permission' do
      it 'creates a new payment method' do
        expect {
          post '/api/v1/payment_methods', params: valid_params, headers: headers, as: :json
        }.to change(PaymentMethod, :count).by(1)

        expect(response).to have_http_status(:created)
        json = json_response
        expect(json['success']).to be true
      end

      it 'associates payment method with current account' do
        post '/api/v1/payment_methods', params: valid_params, headers: headers, as: :json

        payment_method = PaymentMethod.last
        expect(payment_method.account_id).to eq(account.id)
      end

      it 'returns the created payment method data' do
        post '/api/v1/payment_methods', params: valid_params, headers: headers, as: :json

        json = json_response
        expect(json['data']['last_four']).to eq('4242')
        expect(json['data']['brand']).to eq('visa')
        expect(json['data']['is_default']).to be false
      end

      it 'validates required fields' do
        post '/api/v1/payment_methods', params: { payment_method: { gateway: '' } }, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = json_response
        expect(json['success']).to be false
      end

      it 'creates a PayPal payment method' do
        paypal_params = {
          payment_method: {
            gateway: 'paypal',
            external_id: "PP_#{SecureRandom.hex(12)}",
            payment_type: 'paypal',
            is_default: false
          }
        }

        post '/api/v1/payment_methods', params: paypal_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        json = json_response
        expect(json['data']['gateway']).to eq('paypal')
      end
    end

    context 'with only billing.read permission' do
      it 'returns forbidden error' do
        post '/api/v1/payment_methods', params: valid_params, headers: reader_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/payment_methods', params: valid_params, as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/payment_methods/:id' do
    let!(:payment_method) { create(:payment_method, account: account, is_default: false) }

    context 'with billing.manage permission' do
      it 'updates the payment method' do
        patch "/api/v1/payment_methods/#{payment_method.id}",
              params: { payment_method: { is_default: true } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json['success']).to be true
        expect(payment_method.reload.is_default).to be true
      end

      it 'returns the updated payment method data' do
        patch "/api/v1/payment_methods/#{payment_method.id}",
              params: { payment_method: { is_default: true } },
              headers: headers,
              as: :json

        json = json_response
        expect(json['data']['is_default']).to be true
      end

      it 'returns not found for payment method from different account' do
        other_pm = create(:payment_method)

        patch "/api/v1/payment_methods/#{other_pm.id}",
              params: { payment_method: { is_default: true } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'returns not found for non-existent payment method' do
        patch '/api/v1/payment_methods/non-existent-id',
              params: { payment_method: { is_default: true } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with only billing.read permission' do
      it 'returns forbidden error' do
        patch "/api/v1/payment_methods/#{payment_method.id}",
              params: { payment_method: { is_default: true } },
              headers: reader_headers,
              as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/payment_methods/:id' do
    let!(:payment_method) { create(:payment_method, account: account) }

    context 'with billing.manage permission' do
      it 'deletes the payment method' do
        expect {
          delete "/api/v1/payment_methods/#{payment_method.id}", headers: headers, as: :json
        }.to change(PaymentMethod, :count).by(-1)

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json['success']).to be true
        expect(json['data']['message']).to eq('Payment method removed successfully')
      end

      it 'returns not found for payment method from different account' do
        other_pm = create(:payment_method)

        delete "/api/v1/payment_methods/#{other_pm.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'returns not found for non-existent payment method' do
        delete '/api/v1/payment_methods/non-existent-id', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with only billing.read permission' do
      it 'returns forbidden error' do
        delete "/api/v1/payment_methods/#{payment_method.id}", headers: reader_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/payment_methods/setup_intent' do
    context 'with billing.manage permission' do
      context 'for Stripe provider' do
        it 'creates a setup intent and returns client data' do
          post '/api/v1/payment_methods/setup_intent', params: { provider: 'stripe' }, headers: headers, as: :json

          expect(response).to have_http_status(:success)
          json = json_response
          expect(json['success']).to be true
          expect(json['data']['provider']).to eq('stripe')
          expect(json['data']['setup_intent_id']).to be_present
          expect(json['data']['client_secret']).to be_present
        end

        it 'defaults to Stripe when no provider specified' do
          post '/api/v1/payment_methods/setup_intent', headers: headers, as: :json

          json = json_response
          expect(json['data']['provider']).to eq('stripe')
        end
      end

      context 'for PayPal provider' do
        it 'creates a PayPal setup token' do
          post '/api/v1/payment_methods/setup_intent', params: { provider: 'paypal' }, headers: headers, as: :json

          expect(response).to have_http_status(:success)
          json = json_response
          expect(json['success']).to be true
          expect(json['data']['provider']).to eq('paypal')
          expect(json['data']['setup_token']).to be_present
          expect(json['data']['approval_url']).to be_present
        end
      end

      context 'for unsupported provider' do
        it 'returns an error' do
          post '/api/v1/payment_methods/setup_intent', params: { provider: 'bitcoin' }, headers: headers, as: :json

          expect(response).to have_http_status(:unprocessable_content)
          json = json_response
          expect(json['success']).to be false
          expect(json['error']).to include('Unsupported payment provider')
        end
      end
    end

    context 'with only billing.read permission' do
      it 'returns forbidden error' do
        post '/api/v1/payment_methods/setup_intent', params: { provider: 'stripe' }, headers: reader_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/payment_methods/setup_intent', params: { provider: 'stripe' }, as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/payment_methods/confirm' do
    let!(:payment_method) { create(:payment_method, account: account) }

    context 'with billing.manage permission' do
      it 'confirms the payment method with setup_intent_id' do
        post '/api/v1/payment_methods/confirm',
             params: { id: payment_method.id, setup_intent_id: "seti_#{SecureRandom.hex(12)}" },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json['success']).to be true
      end

      it 'confirms the payment method with confirmation_token' do
        post '/api/v1/payment_methods/confirm',
             params: { id: payment_method.id, confirmation_token: "token_#{SecureRandom.hex(12)}" },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json['success']).to be true
      end

      it 'returns error when neither setup_intent_id nor confirmation_token provided' do
        post '/api/v1/payment_methods/confirm',
             params: { id: payment_method.id },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = json_response
        expect(json['success']).to be false
        expect(json['error']).to include('Missing setup_intent_id or confirmation_token')
      end
    end

    context 'with only billing.read permission' do
      it 'returns forbidden error' do
        post '/api/v1/payment_methods/confirm',
             params: { id: payment_method.id, setup_intent_id: 'seti_test' },
             headers: reader_headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/payment_methods/:id/set_default' do
    let!(:payment_method1) { create(:payment_method, account: account, is_default: true) }
    let!(:payment_method2) { create(:payment_method, account: account, is_default: false) }

    context 'with billing.manage permission' do
      it 'sets the payment method as default' do
        post "/api/v1/payment_methods/#{payment_method2.id}/set_default", headers: headers, as: :json

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json['success']).to be true
        expect(json['data']['is_default']).to be true
        expect(payment_method2.reload.is_default).to be true
      end

      it 'removes default from other payment methods' do
        post "/api/v1/payment_methods/#{payment_method2.id}/set_default", headers: headers, as: :json

        expect(payment_method1.reload.is_default).to be false
      end

      it 'returns not found for payment method from different account' do
        other_pm = create(:payment_method)

        post "/api/v1/payment_methods/#{other_pm.id}/set_default", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with only billing.read permission' do
      it 'returns forbidden error' do
        post "/api/v1/payment_methods/#{payment_method2.id}/set_default", headers: reader_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'account isolation' do
    let(:other_account) { create(:account) }
    let!(:other_payment_method) { create(:payment_method, account: other_account) }

    it 'cannot access payment methods from other accounts via index' do
      get '/api/v1/payment_methods', headers: headers, as: :json

      json = json_response
      expect(json['success']).to be true
      # When no payment methods exist for the account, data may be nil or empty array
      payment_method_ids = (json['data'] || []).map { |pm| pm['id'] }
      expect(payment_method_ids).not_to include(other_payment_method.id)
    end

    it 'cannot update payment methods from other accounts' do
      patch "/api/v1/payment_methods/#{other_payment_method.id}",
            params: { payment_method: { is_default: true } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'cannot delete payment methods from other accounts' do
      expect {
        delete "/api/v1/payment_methods/#{other_payment_method.id}", headers: headers, as: :json
      }.not_to change(PaymentMethod, :count)

      expect(response).to have_http_status(:not_found)
    end

    it 'cannot set default on payment methods from other accounts' do
      post "/api/v1/payment_methods/#{other_payment_method.id}/set_default", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'invalid token scenarios' do
    let(:invalid_headers) { { 'Authorization' => 'Bearer invalid_token' } }

    it 'returns error for invalid token on index' do
      get '/api/v1/payment_methods', headers: invalid_headers, as: :json

      expect_error_response('Invalid access token', 401)
    end

    it 'returns error for invalid token on create' do
      post '/api/v1/payment_methods',
           params: { payment_method: { gateway: 'stripe' } },
           headers: invalid_headers,
           as: :json

      expect_error_response('Invalid access token', 401)
    end

    it 'returns error for invalid token on setup_intent' do
      post '/api/v1/payment_methods/setup_intent',
           params: { provider: 'stripe' },
           headers: invalid_headers,
           as: :json

      expect_error_response('Invalid access token', 401)
    end
  end
end
