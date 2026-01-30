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
    let(:payment_method1) { create(:payment_method, account: account, gateway: 'stripe', payment_type: 'card') }
    let(:payment_method2) { create(:payment_method, account: account, gateway: 'stripe', payment_type: 'bank') }
    let!(:payment1) do
      create(:payment,
             account: account,
             invoice: invoice,
             payment_method: payment_method1,
             status: 'succeeded',
             created_at: 2.days.ago)
    end
    let!(:payment2) do
      create(:payment,
             account: account,
             invoice: invoice,
             payment_method: payment_method2,
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
        get "/api/v1/reconciliation/stripe_payments?start_date=#{date_params[:start_date]}&end_date=#{date_params[:end_date]}", headers: headers, as: :json

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
        get "/api/v1/reconciliation/stripe_payments?start_date=#{date_params[:start_date]}&end_date=#{date_params[:end_date]}", headers: invalid_headers, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect_error_response('Unauthorized service request')
      end
    end
  end

  describe 'GET /api/v1/reconciliation/paypal_payments' do
    let(:account) { create(:account) }
    let(:subscription) { create(:subscription, account: account) }
    let(:invoice) { create(:invoice, subscription: subscription, account: account) }
    let(:paypal_payment_method) { create(:payment_method, :paypal, account: account) }
    let!(:payment) do
      create(:payment,
             account: account,
             invoice: invoice,
             payment_method: paypal_payment_method,
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
        get "/api/v1/reconciliation/paypal_payments?start_date=#{date_params[:start_date]}&end_date=#{date_params[:end_date]}", headers: headers, as: :json

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
        reconciliation_type: 'daily',
        gateway: 'stripe',
        report_date: Date.current.to_s,
        report_type: 'daily',
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
    let!(:account) { create(:account) }
    let(:subscription) { create(:subscription, account: account) }
    let(:invoice) { create(:invoice, subscription: subscription, account: account) }
    let(:payment_method) { create(:payment_method, account: account, gateway: 'stripe', payment_type: 'card') }

    let(:correction_params) do
      {
        type: 'create_missing_payment',
        provider: 'stripe',
        provider_payment_id: 'pi_test_123',
        amount: 5000,
        currency: 'USD'
      }
    end

    context 'with create_missing_payment type' do
      context 'when account can be determined from existing payment' do
        let!(:existing_payment) do
          create(:payment,
                 account: account,
                 invoice: invoice,
                 payment_method: payment_method,
                 status: 'succeeded',
                 metadata: { 'stripe_payment_intent_id' => 'pi_test_123' })
        end

        it 'creates a missing payment log using account from existing payment' do
          expect {
            post '/api/v1/reconciliation/corrections', params: correction_params, headers: headers, as: :json
          }.to change { MissingPaymentLog.count }.by(1)

          expect_success_response
          data = json_response_data
          expect(data).to have_key('log_id')

          log = MissingPaymentLog.find(data['log_id'])
          expect(log.account_id).to eq(account.id)
        end
      end

      context 'when account_id is explicitly provided' do
        let(:correction_params_with_account) do
          correction_params.merge(account_id: account.id)
        end

        it 'creates a missing payment log using explicit account_id' do
          expect {
            post '/api/v1/reconciliation/corrections', params: correction_params_with_account, headers: headers, as: :json
          }.to change { MissingPaymentLog.count }.by(1)

          expect_success_response
          data = json_response_data
          expect(data).to have_key('log_id')

          log = MissingPaymentLog.find(data['log_id'])
          expect(log.account_id).to eq(account.id)
        end
      end

      context 'when account cannot be determined' do
        let(:orphan_correction_params) do
          {
            type: 'create_missing_payment',
            provider: 'stripe',
            provider_payment_id: 'pi_unknown_orphan',
            amount: 5000,
            currency: 'USD'
          }
        end

        it 'returns unprocessable entity error' do
          post '/api/v1/reconciliation/corrections', params: orphan_correction_params, headers: headers, as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          expect_error_response('Cannot determine account for missing payment')
        end
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
    let(:reconciliation_report) { create(:reconciliation_report) }

    let(:flag_params) do
      {
        type: 'amount_mismatch',
        reconciliation_report_id: reconciliation_report.id,
        description: 'Amount mismatch detected for PayPal payment',
        severity: 'high',
        transaction_id: 'PAYPAL-123',
        amount_cents: 50.0
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
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:reconciliation_report) { create(:reconciliation_report) }
    let(:reconciliation_flag) do
      ReconciliationFlag.create!(
        reconciliation_report: reconciliation_report,
        flag_type: 'amount_mismatch',
        description: 'Test flag for investigation',
        severity: 'high'
      )
    end

    let(:investigation_params) do
      {
        reconciliation_flag_id: reconciliation_flag.id,
        investigator_id: user.id,
        notes: 'Investigating amount discrepancy'
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
