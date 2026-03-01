# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Payments', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account) }

  let(:headers) { auth_headers_for(user) }
  let(:other_headers) { auth_headers_for(other_user) }

  describe 'GET /api/v1/payments' do
    let(:plan) { create(:plan) }
    let(:subscription) { create(:subscription, account: account, plan: plan) }
    let(:invoice) { create(:invoice, account: account, subscription: subscription) }
    let!(:payment1) { create(:payment, :succeeded, account: account, invoice: invoice) }
    let!(:payment2) { create(:payment, :failed, account: account, invoice: invoice) }
    let!(:other_payment) { create(:payment, account: other_account, invoice: create(:invoice, account: other_account)) }

    it 'returns list of payments for current account' do
      get '/api/v1/payments', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['payments']).to be_an(Array)
      expect(data['payments'].length).to eq(2)
      expect(data['payments'].none? { |p| p['id'] == other_payment.id }).to be true
      expect(data['pagination']).to be_present
    end

    it 'includes payment details' do
      get '/api/v1/payments', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      payment_data = data['payments'].first
      expect(payment_data).to have_key('id')
      expect(payment_data).to have_key('amount')
      expect(payment_data).to have_key('currency')
      expect(payment_data).to have_key('status')
      expect(payment_data).to have_key('provider')
      expect(payment_data).to have_key('invoice')
      expect(payment_data).to have_key('subscription')
    end

    it 'paginates results' do
      get '/api/v1/payments?page=1&per_page=1',
          headers: headers,
          as: :json

      expect_success_response
      data = json_response_data
      expect(data['payments'].length).to eq(1)
      expect(data['pagination']['page']).to eq(1)
      expect(data['pagination']['per_page']).to eq(1)
      expect(data['pagination']['total']).to eq(2)
    end

    it 'limits maximum per_page to 100' do
      get '/api/v1/payments?per_page=500',
          headers: headers,
          as: :json

      expect_success_response
      data = json_response_data
      expect(data['pagination']['per_page']).to eq(100)
    end

    it 'orders payments by created_at descending' do
      payment1.update!(created_at: 2.days.ago)
      payment2.update!(created_at: 1.day.ago)

      get '/api/v1/payments', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['payments'].first['id']).to eq(payment2.id)
      expect(data['payments'].last['id']).to eq(payment1.id)
    end

    it 'includes invoice data in payment' do
      get '/api/v1/payments', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      payment_data = data['payments'].first
      expect(payment_data['invoice']).to be_present
      expect(payment_data['invoice']['id']).to eq(invoice.id)
      expect(payment_data['invoice']).to have_key('invoice_number')
    end

    it 'includes subscription data in payment' do
      get '/api/v1/payments', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      payment_data = data['payments'].first
      expect(payment_data['subscription']).to be_present
      expect(payment_data['subscription']['id']).to eq(subscription.id)
      expect(payment_data['subscription']).to have_key('plan_name')
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/payments', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/payments/:id' do
    let(:invoice) { create(:invoice, account: account) }
    let(:payment) { create(:payment, :succeeded, account: account, invoice: invoice) }
    let(:other_payment) { create(:payment, account: other_account, invoice: create(:invoice, account: other_account)) }

    it 'returns payment details' do
      get "/api/v1/payments/#{payment.id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['id']).to eq(payment.id)
      expect(data['amount']).to be_present
      expect(data['currency']).to eq('USD')
      expect(data['status']).to eq('succeeded')
      expect(data).to have_key('provider')
      expect(data).to have_key('created_at')
      expect(data).to have_key('updated_at')
    end

    it 'includes payment method information' do
      get "/api/v1/payments/#{payment.id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('payment_method_last4')
    end

    it 'includes processing timestamps' do
      get "/api/v1/payments/#{payment.id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to have_key('processed_at')
      expect(data).to have_key('failed_at')
    end

    it 'includes failure information for failed payments' do
      failed_payment = create(:payment, :failed, account: account, invoice: invoice)

      get "/api/v1/payments/#{failed_payment.id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['status']).to eq('failed')
      expect(data['failure_reason']).to be_present
    end

    it 'returns not found for non-existent payment' do
      get "/api/v1/payments/#{SecureRandom.uuid}", headers: headers, as: :json

      expect_error_response('Payment not found', 404)
    end

    it 'returns not found for payment from different account' do
      get "/api/v1/payments/#{other_payment.id}", headers: headers, as: :json

      expect_error_response('Payment not found', 404)
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/payments/#{payment.id}", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end
end
