# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Reconciliation', type: :request do
  let(:service_token) { 'test-service-token' }
  let(:headers) { { 'X-Service-Token' => service_token } }

  before do
    allow(Rails.application.credentials).to receive(:dig).with(:worker_service, :api_token).and_return(service_token)
  end

  describe 'GET /api/v1/reconciliation/stripe_payments' do
    let(:account) { create(:account) }
    let(:subscription) { create(:subscription, account: account) }
    let(:invoice) { create(:invoice, subscription: subscription, account: account) }
    let!(:payment1) do
      create(:payment,
             account: account,
             invoice: invoice,
             payment_method: 'stripe_card',
             status: 'succeeded',
             created_at: 2.days.ago)
    end
    let!(:payment2) do
      create(:payment,
             account: account,
             invoice: invoice,
             payment_method: 'stripe_bank',
             status: 'succeeded',
             created_at: 1.day.ago)
    end

    let(:date_params) do
      {
        start_date: 3.days.ago.to_s,
        end_date: Time.current.to_s
      }
    end

    context 'with valid service token' do
      it 'returns Stripe payments for reconciliation' do
        get '/api/v1/reconciliation/stripe_payments', params: date_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        expect(data.length).to eq(2)
        expect(data.first).to include('id', 'amount_cents', 'currency', 'status', 'account_id', 'invoice_id')
      end
    end

    context 'without valid service token' do
      let(:invalid_headers) { { 'X-Service-Token' => 'invalid-token' } }

      it 'returns unauthorized error' do
        get '/api/v1/reconciliation/stripe_payments', params: date_params, headers: invalid_headers, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect_error_response('Unauthorized service request')
      end
    end
  end

  describe 'GET /api/v1/reconciliation/paypal_payments' do
    let(:account) { create(:account) }
    let(:subscription) { create(:subscription, account: account) }
    let(:invoice) { create(:invoice, subscription: subscription, account: account) }
    let!(:payment) do
      create(:payment,
             account: account,
             invoice: invoice,
             payment_method: 'paypal',
             status: 'succeeded',
             created_at: 1.day.ago)
    end

    let(:date_params) do
      {
        start_date: 3.days.ago.to_s,
        end_date: Time.current.to_s
      }
    end

    context 'with valid service token' do
      it 'returns PayPal payments for reconciliation' do
        get '/api/v1/reconciliation/paypal_payments', params: date_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        expect(data.length).to eq(1)
        expect(data.first).to include('id', 'amount_cents', 'currency', 'status', 'account_id')
      end
    end
  end

  describe 'POST /api/v1/reconciliation/report' do
    let(:report_params) do
      {
        reconciliation_date: Date.current.to_s,
        reconciliation_type: 'stripe',
        date_range: {
          start: 1.week.ago.to_s,
          end: Time.current.to_s
        },
        summary: { total: 100, matched: 95, discrepancies: 5 },
        discrepancies_count: 5,
        high_severity_count: 1,
        medium_severity_count: 4
      }
    end

    context 'with valid service token' do
      it 'creates a reconciliation report' do
        expect {
          post '/api/v1/reconciliation/report', params: report_params, headers: headers, as: :json
        }.to change { ReconciliationReport.count }.by(1)

        expect_success_response
        data = json_response_data
        expect(data).to have_key('report_id')
      end
    end
  end

  describe 'POST /api/v1/reconciliation/corrections' do
    let(:correction_params) do
      {
        type: 'create_missing_payment',
        provider: 'stripe',
        provider_payment_id: 'STRIPE-123',
        amount: 5000,
        currency: 'USD'
      }
    end

    context 'with create_missing_payment type' do
      it 'creates a missing payment log' do
        expect {
          post '/api/v1/reconciliation/corrections', params: correction_params, headers: headers, as: :json
        }.to change { MissingPaymentLog.count }.by(1)

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Missing payment logged for manual review')
        expect(data).to have_key('data')
      end
    end

    context 'with unknown correction type' do
      let(:correction_params) { { type: 'unknown_type' } }

      it 'returns bad request error' do
        post '/api/v1/reconciliation/corrections', params: correction_params, headers: headers, as: :json

        expect(response).to have_http_status(:bad_request)
        expect_error_response
      end
    end
  end

  describe 'POST /api/v1/reconciliation/flags' do
    let(:flag_params) do
      {
        type: 'amount_mismatch',
        provider: 'paypal',
        local_payment_id: SecureRandom.uuid,
        external_id: 'PAYPAL-123',
        requires_manual_review: true,
        local_amount: 5000,
        provider_amount: 5050
      }
    end

    context 'with valid service token' do
      it 'creates a reconciliation flag' do
        expect {
          post '/api/v1/reconciliation/flags', params: flag_params, headers: headers, as: :json
        }.to change { ReconciliationFlag.count }.by(1)

        expect_success_response
        data = json_response_data
        expect(data).to have_key('flag_id')
      end
    end
  end

  describe 'POST /api/v1/reconciliation/investigations' do
    let(:investigation_params) do
      {
        type: 'amount_discrepancy',
        local_payment_id: SecureRandom.uuid,
        provider_payment_id: 'PROVIDER-123',
        local_amount: 5000,
        provider_amount: 5050,
        difference: 50,
        requires_investigation: true
      }
    end

    context 'with valid service token' do
      it 'creates a reconciliation investigation' do
        expect {
          post '/api/v1/reconciliation/investigations', params: investigation_params, headers: headers, as: :json
        }.to change { ReconciliationInvestigation.count }.by(1)

        expect_success_response
        data = json_response_data
        expect(data).to have_key('investigation_id')
      end
    end
  end
end
