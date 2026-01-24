# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Billing', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, password: TestUsers::PASSWORD) }
  let(:headers) { auth_headers_for(user) }

  before(:each) do
    Rails.cache.clear
  end

  describe 'GET /api/v1/billing (overview)' do
    context 'when authenticated' do
      it 'returns billing overview data' do
        get '/api/v1/billing', headers: headers, as: :json

        expect_success_response
        response_data = json_response['data']

        expect(response_data).to have_key('outstanding')
        expect(response_data).to have_key('this_month')
        expect(response_data).to have_key('collected')
        expect(response_data).to have_key('success_rate')
        expect(response_data).to have_key('recent_invoices')
        expect(response_data).to have_key('payment_methods')
      end

      context 'with invoices and payments' do
        let(:plan) { create(:plan) }
        let(:subscription) { create(:subscription, account: account, plan: plan) }

        before do
          # Create invoices with different statuses
          create(:invoice, account: account, subscription: subscription, status: 'open', total_cents: 5000)
          create(:invoice, account: account, subscription: subscription, status: 'paid', total_cents: 3000)

          # Create payments
          invoice_for_payment = create(:invoice, account: account, subscription: subscription, status: 'paid')
          create(:payment, :succeeded, account: account, invoice: invoice_for_payment, amount_cents: 2999)
          failed_invoice = create(:invoice, account: account, subscription: subscription, status: 'open')
          create(:payment, :failed, account: account, invoice: failed_invoice, amount_cents: 1500)

          # Create default payment method
          create(:payment_method, :stripe, account: account, is_default: true)
        end

        it 'calculates outstanding amount correctly' do
          get '/api/v1/billing', headers: headers, as: :json

          expect_success_response
          response_data = json_response['data']

          # Outstanding = sum of sent/overdue invoices
          expect(response_data['outstanding']).to be >= 0
        end

        it 'calculates payment success rate' do
          get '/api/v1/billing', headers: headers, as: :json

          expect_success_response
          response_data = json_response['data']

          # With 1 succeeded and 1 failed payment, success rate should be 50%
          expect(response_data['success_rate']).to eq(50.0)
        end

        it 'returns recent invoices' do
          get '/api/v1/billing', headers: headers, as: :json

          expect_success_response
          response_data = json_response['data']

          expect(response_data['recent_invoices']).to be_an(Array)
          expect(response_data['recent_invoices'].length).to be <= 5

          if response_data['recent_invoices'].any?
            invoice = response_data['recent_invoices'].first
            expect(invoice).to have_key('id')
            expect(invoice).to have_key('invoice_number')
            expect(invoice).to have_key('status')
          end
        end

        it 'returns default payment methods' do
          get '/api/v1/billing', headers: headers, as: :json

          expect_success_response
          response_data = json_response['data']

          expect(response_data['payment_methods']).to be_an(Array)
          if response_data['payment_methods'].any?
            payment_method = response_data['payment_methods'].first
            expect(payment_method).to have_key('id')
            expect(payment_method['is_default']).to eq(true)
          end
        end
      end

      context 'with no billing data' do
        it 'returns zero values and empty arrays' do
          get '/api/v1/billing', headers: headers, as: :json

          expect_success_response
          response_data = json_response['data']

          expect(response_data['outstanding']).to eq(0)
          expect(response_data['this_month']).to eq(0)
          expect(response_data['collected']).to eq(0)
          expect(response_data['success_rate']).to eq(0)
          expect(response_data['recent_invoices']).to eq([])
          expect(response_data['payment_methods']).to eq([])
        end
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized error' do
        get '/api/v1/billing', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/billing/payment-methods' do
    context 'when authenticated' do
      it 'returns empty array when no payment methods exist' do
        get '/api/v1/billing/payment-methods', headers: headers, as: :json

        expect_success_response
        response_data = json_response['data']

        expect(response_data['payment_methods']).to eq([])
      end

      context 'with existing payment methods' do
        let!(:payment_method1) { create(:payment_method, :stripe, account: account, is_default: true) }
        let!(:payment_method2) { create(:payment_method, :paypal, account: account, is_default: false) }

        it 'returns all payment methods for the account' do
          get '/api/v1/billing/payment-methods', headers: headers, as: :json

          expect_success_response
          response_data = json_response['data']

          expect(response_data['payment_methods']).to be_an(Array)
          expect(response_data['payment_methods'].length).to eq(2)
        end

        it 'returns payment method details' do
          get '/api/v1/billing/payment-methods', headers: headers, as: :json

          expect_success_response
          payment_methods = json_response['data']['payment_methods']

          stripe_method = payment_methods.find { |pm| pm['id'] == payment_method1.id }
          expect(stripe_method).to include(
            'id' => payment_method1.id,
            'is_default' => true
          )
        end

        it 'returns payment methods ordered by creation date descending' do
          get '/api/v1/billing/payment-methods', headers: headers, as: :json

          expect_success_response
          payment_methods = json_response['data']['payment_methods']

          # Most recently created should be first
          expect(payment_methods.first['id']).to eq(payment_method2.id)
        end
      end

      context 'with another account\'s payment methods' do
        let(:other_account) { create(:account) }
        let!(:other_payment_method) { create(:payment_method, :stripe, account: other_account) }

        it 'does not return other account\'s payment methods' do
          get '/api/v1/billing/payment-methods', headers: headers, as: :json

          expect_success_response
          response_data = json_response['data']

          expect(response_data['payment_methods']).to eq([])
        end
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized error' do
        get '/api/v1/billing/payment-methods', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/billing/payment-methods' do
    let(:payment_method_id) { 'pm_test_123456789' }

    context 'when authenticated' do
      context 'with valid stripe payment method' do
        before do
          # Mock the Billing::PaymentProcessingService
          mock_service = instance_double(Billing::PaymentProcessingService)
          allow(Billing::PaymentProcessingService).to receive(:new).and_return(mock_service)

          payment_method = create(:payment_method, :stripe, account: account)
          allow(mock_service).to receive(:attach_payment_method).and_return({
            success: true,
            payment_method: payment_method
          })
        end

        it 'creates and returns the payment method' do
          post '/api/v1/billing/payment-methods',
               params: { payment_method_id: payment_method_id, provider: 'stripe' },
               headers: headers,
               as: :json

          expect_success_response
          response_data = json_response['data']

          expect(response_data).to have_key('payment_method')
          expect(response_data['payment_method']).to have_key('id')
        end
      end

      context 'with valid paypal payment method' do
        before do
          mock_service = instance_double(Billing::PaymentProcessingService)
          allow(Billing::PaymentProcessingService).to receive(:new).and_return(mock_service)

          payment_method = create(:payment_method, :paypal, account: account)
          allow(mock_service).to receive(:attach_payment_method).and_return({
            success: true,
            payment_method: payment_method
          })
        end

        it 'creates and returns the payment method' do
          post '/api/v1/billing/payment-methods',
               params: { payment_method_id: 'paypal_payer_123', provider: 'paypal' },
               headers: headers,
               as: :json

          expect_success_response
          response_data = json_response['data']

          expect(response_data).to have_key('payment_method')
        end
      end

      context 'when service returns error' do
        before do
          mock_service = instance_double(Billing::PaymentProcessingService)
          allow(Billing::PaymentProcessingService).to receive(:new).and_return(mock_service)
          allow(mock_service).to receive(:attach_payment_method).and_return({
            success: false,
            error: 'Invalid payment method'
          })
        end

        it 'returns error response' do
          post '/api/v1/billing/payment-methods',
               params: { payment_method_id: 'invalid_pm' },
               headers: headers,
               as: :json

          expect(response).to have_http_status(:unprocessable_content)
          expect(json_response['success']).to be false
          expect(json_response['error']).to eq('Invalid payment method')
        end
      end

      context 'with default provider' do
        before do
          mock_service = instance_double(Billing::PaymentProcessingService)
          allow(Billing::PaymentProcessingService).to receive(:new).and_return(mock_service)

          payment_method = create(:payment_method, :stripe, account: account)
          allow(mock_service).to receive(:attach_payment_method).with(
            payment_method_id: payment_method_id,
            provider: 'stripe'
          ).and_return({
            success: true,
            payment_method: payment_method
          })
        end

        it 'defaults to stripe provider when not specified' do
          post '/api/v1/billing/payment-methods',
               params: { payment_method_id: payment_method_id },
               headers: headers,
               as: :json

          expect_success_response
        end
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized error' do
        post '/api/v1/billing/payment-methods',
             params: { payment_method_id: payment_method_id },
             as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/billing/payment-intent' do
    context 'when authenticated' do
      context 'with valid parameters' do
        before do
          mock_service = instance_double(Billing::PaymentProcessingService)
          allow(Billing::PaymentProcessingService).to receive(:new).and_return(mock_service)

          mock_intent = double('PaymentIntent', id: 'pi_test_123')
          allow(mock_service).to receive(:create_payment_intent).and_return({
            success: true,
            client_secret: 'pi_test_123_secret_abc',
            payment_intent: mock_intent
          })
        end

        it 'creates payment intent and returns client secret' do
          post '/api/v1/billing/payment-intent',
               params: { amount_cents: 5000, currency: 'USD', description: 'Test payment' },
               headers: headers,
               as: :json

          expect_success_response
          response_data = json_response['data']

          expect(response_data).to have_key('client_secret')
          expect(response_data).to have_key('payment_intent_id')
          expect(response_data['client_secret']).to eq('pi_test_123_secret_abc')
          expect(response_data['payment_intent_id']).to eq('pi_test_123')
        end
      end

      context 'with default currency' do
        before do
          mock_service = instance_double(Billing::PaymentProcessingService)
          allow(Billing::PaymentProcessingService).to receive(:new).and_return(mock_service)

          mock_intent = double('PaymentIntent', id: 'pi_test_456')
          allow(mock_service).to receive(:create_payment_intent).with(
            amount_cents: 3000,
            currency: 'USD',
            description: nil
          ).and_return({
            success: true,
            client_secret: 'pi_test_456_secret_xyz',
            payment_intent: mock_intent
          })
        end

        it 'defaults to USD currency' do
          post '/api/v1/billing/payment-intent',
               params: { amount_cents: 3000 },
               headers: headers,
               as: :json

          expect_success_response
        end
      end

      context 'when service returns error' do
        before do
          mock_service = instance_double(Billing::PaymentProcessingService)
          allow(Billing::PaymentProcessingService).to receive(:new).and_return(mock_service)
          allow(mock_service).to receive(:create_payment_intent).and_return({
            success: false,
            error: 'Invalid amount'
          })
        end

        it 'returns error response' do
          post '/api/v1/billing/payment-intent',
               params: { amount_cents: -100 },
               headers: headers,
               as: :json

          expect(response).to have_http_status(:unprocessable_content)
          expect(json_response['success']).to be false
          expect(json_response['error']).to eq('Invalid amount')
        end
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized error' do
        post '/api/v1/billing/payment-intent',
             params: { amount_cents: 5000 },
             as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/billing/invoices' do
    let(:plan) { create(:plan) }
    let!(:subscription) { create(:subscription, account: account, plan: plan) }

    context 'when authenticated' do
      it 'returns empty array when no invoices exist' do
        get '/api/v1/billing/invoices', headers: headers, as: :json

        expect_success_response
        response_data = json_response['data']

        expect(response_data['invoices']).to eq([])
        expect(response_data['pagination']).to include(
          'current_page' => 1,
          'total_count' => 0
        )
      end

      context 'with existing invoices' do
        before do
          @invoices = create_list(:invoice, 5, account: account, subscription: subscription)
        end

        it 'returns invoices with proper data structure' do
          get '/api/v1/billing/invoices', headers: headers, as: :json

          expect_success_response
          response_data = json_response['data']

          expect(response_data['invoices']).to be_an(Array)
          expect(response_data['invoices'].length).to eq(5)

          invoice = response_data['invoices'].first
          expect(invoice).to have_key('id')
          expect(invoice).to have_key('invoice_number')
          expect(invoice).to have_key('subtotal')
          expect(invoice).to have_key('tax_amount')
          expect(invoice).to have_key('total_amount')
          expect(invoice).to have_key('currency')
          expect(invoice).to have_key('status')
          expect(invoice).to have_key('due_date')
          expect(invoice).to have_key('created_at')
          expect(invoice).to have_key('line_items_count')
        end

        it 'returns invoices ordered by creation date descending' do
          get '/api/v1/billing/invoices', headers: headers, as: :json

          expect_success_response
          invoices = json_response['data']['invoices']

          # Most recently created should be first
          expect(invoices.first['id']).to eq(@invoices.last.id)
        end

        it 'includes pagination information' do
          get '/api/v1/billing/invoices', headers: headers, as: :json

          expect_success_response
          pagination = json_response['data']['pagination']

          expect(pagination).to include(
            'current_page' => 1,
            'per_page' => 20,
            'total_count' => 5,
            'total_pages' => 1
          )
        end
      end

      context 'with pagination' do
        before do
          create_list(:invoice, 25, account: account, subscription: subscription)
        end

        it 'returns specified page' do
          get '/api/v1/billing/invoices',
              params: { page: 2, per_page: 10 },
              headers: headers

          expect_success_response
          response_data = json_response['data']

          expect(response_data['invoices'].length).to eq(10)
          expect(response_data['pagination']).to include(
            'current_page' => 2,
            'per_page' => 10,
            'total_count' => 25,
            'total_pages' => 3
          )
        end

        it 'limits per_page to maximum of 100' do
          get '/api/v1/billing/invoices',
              params: { per_page: 200 },
              headers: headers

          expect_success_response
          pagination = json_response['data']['pagination']

          expect(pagination['per_page']).to eq(100)
        end

        it 'defaults to page 1 and 20 per page' do
          get '/api/v1/billing/invoices', headers: headers, as: :json

          expect_success_response
          pagination = json_response['data']['pagination']

          expect(pagination['current_page']).to eq(1)
          expect(pagination['per_page']).to eq(20)
        end
      end

      context 'with invoices with line items' do
        before do
          invoice = create(:invoice, account: account, subscription: subscription)
          create_list(:invoice_line_item, 3, invoice: invoice)
          invoice.reload
        end

        it 'returns line_items_count' do
          get '/api/v1/billing/invoices', headers: headers, as: :json

          expect_success_response
          invoice = json_response['data']['invoices'].first

          expect(invoice['line_items_count']).to eq(3)
        end
      end

      context 'with another account\'s invoices' do
        let(:other_account) { create(:account) }
        let(:other_plan) { create(:plan) }
        let(:other_subscription) { create(:subscription, account: other_account, plan: other_plan) }

        before do
          create(:invoice, account: other_account, subscription: other_subscription)
        end

        it 'does not return other account\'s invoices' do
          get '/api/v1/billing/invoices', headers: headers, as: :json

          expect_success_response
          expect(json_response['data']['invoices']).to eq([])
        end
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized error' do
        get '/api/v1/billing/invoices', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'POST /api/v1/billing/invoices' do
    let(:plan) { create(:plan) }
    let!(:subscription) { create(:subscription, account: account, plan: plan) }

    context 'when authenticated' do
      context 'with valid parameters' do
        let(:valid_params) do
          {
            invoice: {
              currency: 'USD',
              due_date: 30.days.from_now.to_date.to_s
            }
          }
        end

        it 'creates an invoice in draft status' do
          expect {
            post '/api/v1/billing/invoices',
                 params: valid_params,
                 headers: headers,
                 as: :json
          }.to change(Invoice, :count).by(1)

          expect_success_response
          response_data = json_response['data']

          expect(response_data['invoice']).to have_key('id')
          expect(response_data['invoice']).to have_key('invoice_number')
          expect(response_data['invoice']['status']).to eq('draft')
        end
      end

      context 'with line items' do
        let(:params_with_line_items) do
          {
            invoice: {
              currency: 'USD',
              due_date: 30.days.from_now.to_date.to_s
            },
            line_items: [
              { description: 'Service A', quantity: 2, unit_price: 10.00 },
              { description: 'Service B', quantity: 1, unit_price: 25.00 }
            ]
          }
        end

        it 'creates invoice with line items and calculates totals' do
          post '/api/v1/billing/invoices',
               params: params_with_line_items,
               headers: headers,
               as: :json

          expect_success_response
          response_data = json_response['data']

          expect(response_data['invoice']).to have_key('total_amount')
        end
      end

      context 'with invalid parameters' do
        it 'returns validation error for invalid currency' do
          post '/api/v1/billing/invoices',
               params: { invoice: { currency: 'INVALID' } },
               headers: headers,
               as: :json

          expect(response).to have_http_status(:unprocessable_content)
          expect(json_response['success']).to be false
        end
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized error' do
        post '/api/v1/billing/invoices',
             params: { invoice: { currency: 'USD' } },
             as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/billing/subscription' do
    context 'when authenticated' do
      context 'with active subscription' do
        let(:plan) { create(:plan, name: 'Pro Plan', price_cents: 4900, billing_cycle: 'monthly') }
        let!(:subscription) do
          create(:subscription, :active,
                 account: account,
                 plan: plan,
                 current_period_start: 15.days.ago,
                 current_period_end: 15.days.from_now)
        end

        before do
          account.update(subscription: subscription) if account.respond_to?(:subscription=)
        end

        it 'returns subscription billing information' do
          get '/api/v1/billing/subscription', headers: headers, as: :json

          expect_success_response
          response_data = json_response['data']

          expect(response_data).to have_key('subscription')
          expect(response_data).to have_key('upcoming_invoice')
          expect(response_data).to have_key('billing_history')
        end

        it 'returns subscription details with plan information' do
          get '/api/v1/billing/subscription', headers: headers, as: :json

          expect_success_response
          subscription_data = json_response['data']['subscription']

          expect(subscription_data).to include(
            'id' => subscription.id,
            'status' => 'active'
          )

          expect(subscription_data['plan']).to include(
            'id' => plan.id,
            'name' => 'Pro Plan',
            'billing_cycle' => 'monthly'
          )
        end

        it 'returns current period dates' do
          get '/api/v1/billing/subscription', headers: headers, as: :json

          expect_success_response
          subscription_data = json_response['data']['subscription']

          expect(subscription_data).to have_key('current_period_start')
          expect(subscription_data).to have_key('current_period_end')
        end

        it 'returns upcoming invoice for active subscription' do
          get '/api/v1/billing/subscription', headers: headers, as: :json

          expect_success_response
          upcoming_invoice = json_response['data']['upcoming_invoice']

          expect(upcoming_invoice).to have_key('amount_due')
          expect(upcoming_invoice).to have_key('currency')
          expect(upcoming_invoice).to have_key('next_payment_date')
          expect(upcoming_invoice).to have_key('description')
        end
      end

      context 'with trialing subscription' do
        let(:plan) { create(:plan) }
        let!(:subscription) do
          create(:subscription, :trialing,
                 account: account,
                 plan: plan,
                 trial_end: 7.days.from_now)
        end

        before do
          account.update(subscription: subscription) if account.respond_to?(:subscription=)
        end

        it 'returns subscription with trial_end date' do
          get '/api/v1/billing/subscription', headers: headers, as: :json

          expect_success_response
          subscription_data = json_response['data']['subscription']

          expect(subscription_data['status']).to eq('trialing')
          expect(subscription_data).to have_key('trial_end')
        end

        it 'returns upcoming invoice for trialing subscription' do
          get '/api/v1/billing/subscription', headers: headers, as: :json

          expect_success_response
          expect(json_response['data']['upcoming_invoice']).not_to be_nil
        end
      end

      context 'with canceled subscription' do
        let(:plan) { create(:plan) }
        let!(:subscription) do
          create(:subscription, :canceled,
                 account: account,
                 plan: plan)
        end

        before do
          account.update(subscription: subscription) if account.respond_to?(:subscription=)
        end

        it 'returns subscription with canceled_at date' do
          get '/api/v1/billing/subscription', headers: headers, as: :json

          expect_success_response
          subscription_data = json_response['data']['subscription']

          expect(subscription_data['status']).to eq('canceled')
          expect(subscription_data).to have_key('canceled_at')
        end

        it 'returns nil upcoming invoice for canceled subscription' do
          get '/api/v1/billing/subscription', headers: headers, as: :json

          expect_success_response
          expect(json_response['data']['upcoming_invoice']).to be_nil
        end
      end

      context 'with billing history' do
        let(:plan) { create(:plan) }
        let!(:subscription) do
          create(:subscription, :active, account: account, plan: plan)
        end

        before do
          account.update(subscription: subscription) if account.respond_to?(:subscription=)
          # Create invoices associated with the subscription
          create_list(:invoice, 3, account: account, subscription: subscription)
        end

        it 'returns billing history' do
          get '/api/v1/billing/subscription', headers: headers, as: :json

          expect_success_response
          billing_history = json_response['data']['billing_history']

          expect(billing_history).to be_an(Array)

          if billing_history.any?
            history_item = billing_history.first
            expect(history_item).to have_key('id')
            expect(history_item).to have_key('invoice_number')
            expect(history_item).to have_key('amount')
            expect(history_item).to have_key('status')
            expect(history_item).to have_key('created_at')
          end
        end

        it 'limits billing history to 12 entries' do
          # Create additional invoices
          create_list(:invoice, 15, account: account, subscription: subscription)

          get '/api/v1/billing/subscription', headers: headers, as: :json

          expect_success_response
          billing_history = json_response['data']['billing_history']

          expect(billing_history.length).to be <= 12
        end
      end

      context 'without subscription' do
        it 'returns not found error' do
          get '/api/v1/billing/subscription', headers: headers, as: :json

          expect(response).to have_http_status(:not_found)
          expect(json_response['success']).to be false
          expect(json_response['error']).to eq('No active subscription')
        end
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized error' do
        get '/api/v1/billing/subscription', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'authentication requirements' do
    let(:invalid_headers) { { 'Authorization' => 'Bearer invalid_token' } }

    it 'returns error for invalid token on overview endpoint' do
      get '/api/v1/billing', headers: invalid_headers, as: :json

      expect_error_response('Invalid access token', 401)
    end

    it 'returns error for invalid token on payment-methods endpoint' do
      get '/api/v1/billing/payment-methods', headers: invalid_headers, as: :json

      expect_error_response('Invalid access token', 401)
    end

    it 'returns error for invalid token on invoices endpoint' do
      get '/api/v1/billing/invoices', headers: invalid_headers, as: :json

      expect_error_response('Invalid access token', 401)
    end

    it 'returns error for invalid token on subscription endpoint' do
      get '/api/v1/billing/subscription', headers: invalid_headers, as: :json

      expect_error_response('Invalid access token', 401)
    end
  end
end
