# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Billing', type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan, price: 99.99, billing_cycle: 'monthly') }
  let(:subscription) do
    Subscription.create!(
      account: account,
      plan: plan,
      status: 'active',
      current_period_start: 1.month.ago,
      current_period_end: Time.current,
    )
  end

  # Service token authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'POST /api/v1/internal/billing/process_renewal' do
    context 'with service token authentication' do
      it 'processes subscription renewal' do
        post '/api/v1/internal/billing/process_renewal',
             params: { subscription_id: subscription.id },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'subscription_id' => subscription.id,
          'status' => 'active'
        )

        subscription.reload
        expect(subscription.current_period_start).to be_within(1.minute).of(Time.current)
        expect(subscription.current_period_end).to be_within(1.minute).of(1.month.from_now)
      end

      it 'updates subscription status when provided' do
        post '/api/v1/internal/billing/process_renewal',
             params: { subscription_id: subscription.id, status: 'trialing' },
             headers: internal_headers,
             as: :json

        expect_success_response

        subscription.reload
        expect(subscription.status).to eq('trialing')
      end

      it 'calculates period end based on billing cycle' do
        subscription.plan.update!(billing_cycle: 'yearly')

        post '/api/v1/internal/billing/process_renewal',
             params: { subscription_id: subscription.id },
             headers: internal_headers,
             as: :json

        expect_success_response

        subscription.reload
        expect(subscription.current_period_end).to be_within(1.minute).of(1.year.from_now)
      end
    end

    context 'when subscription does not exist' do
      it 'returns not found error' do
        post '/api/v1/internal/billing/process_renewal',
             params: { subscription_id: 'nonexistent-id' },
             headers: internal_headers,
             as: :json

        expect_error_response('Subscription not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/billing/process_renewal',
             params: { subscription_id: subscription.id },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/billing/retry_payment' do
    let(:invoice) { create(:invoice, account: account, subscription: subscription) }

    context 'with service token authentication' do
      it 'retries payment for subscription' do
        post '/api/v1/internal/billing/retry_payment',
             params: { subscription_id: subscription.id, invoice_id: invoice.id },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'success' => true,
          'subscription_id' => subscription.id,
          'invoice_id' => invoice.id
        )
      end

      it 'retries payment without invoice_id' do
        post '/api/v1/internal/billing/retry_payment',
             params: { subscription_id: subscription.id },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['subscription_id']).to eq(subscription.id)
        expect(response_data['data']['invoice_id']).to be_nil
      end
    end

    context 'when subscription does not exist' do
      it 'returns not found error' do
        post '/api/v1/internal/billing/retry_payment',
             params: { subscription_id: 'nonexistent-id' },
             headers: internal_headers,
             as: :json

        expect_error_response('Subscription not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/billing/retry_payment',
             params: { subscription_id: subscription.id },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/billing/process_payment' do
    let(:invoice) do
      inv = create(:invoice, account: account, subscription: subscription)
      inv.update_columns(subtotal_cents: 9999, total_cents: 9999, status: 'open')
      inv.reload
    end
    let(:payment_method) { create(:payment_method, account: account) }

    context 'with service token authentication' do
      it 'processes payment for invoice' do
        post '/api/v1/internal/billing/process_payment',
             params: {
               invoice_id: invoice.id,
               status: 'succeeded',
               payment_method_id: payment_method.id
             },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'invoice_id' => invoice.id,
          'status' => 'succeeded'
        )

        invoice.reload
        expect(invoice.status).to eq('paid')
        expect(invoice.paid_at).to be_present
      end

      it 'creates payment record with metadata' do
        metadata = { transaction_id: 'tx_123', gateway: 'stripe' }

        post '/api/v1/internal/billing/process_payment',
             params: {
               invoice_id: invoice.id,
               status: 'succeeded',
               payment_method_id: payment_method.id,
               metadata: metadata
             },
             headers: internal_headers,
             as: :json

        expect_success_response

        payment = invoice.payments.last
        expect(payment.metadata).to include('transaction_id' => 'tx_123')
      end

      it 'does not mark invoice as paid when payment is not succeeded' do
        post '/api/v1/internal/billing/process_payment',
             params: {
               invoice_id: invoice.id,
               status: 'pending',
               payment_method_id: payment_method.id
             },
             headers: internal_headers,
             as: :json

        expect_success_response

        invoice.reload
        expect(invoice.status).not_to eq('paid')
      end
    end

    context 'when invoice does not exist' do
      it 'returns not found error' do
        post '/api/v1/internal/billing/process_payment',
             params: { invoice_id: 'nonexistent-id' },
             headers: internal_headers,
             as: :json

        expect_error_response('Invoice not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/billing/process_payment',
             params: { invoice_id: invoice.id },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/billing/generate_invoice' do
    context 'with service token authentication' do
      it 'generates invoice for subscription' do
        post '/api/v1/internal/billing/generate_invoice',
             params: { subscription_id: subscription.id },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include('invoice_number')
        expect(response_data['data']['status']).to eq('open')

        invoice = Invoice.find(response_data['data']['id'])
        expect(invoice.subscription).to eq(subscription)
        expect(invoice.account).to eq(account)
      end

      it 'generates invoice with custom description and type' do
        post '/api/v1/internal/billing/generate_invoice',
             params: {
               subscription_id: subscription.id,
               description: 'Annual subscription fee',
               invoice_type: 'renewal'
             },
             headers: internal_headers,
             as: :json

        expect_success_response

        invoice = Invoice.last
        expect(invoice.metadata['description']).to eq('Annual subscription fee')
        expect(invoice.metadata['invoice_type']).to eq('renewal')
      end

      it 'sets billing period from subscription' do
        post '/api/v1/internal/billing/generate_invoice',
             params: { subscription_id: subscription.id },
             headers: internal_headers,
             as: :json

        expect_success_response

        invoice = Invoice.last
        expect(invoice.metadata['billing_period_start']).to eq(subscription.current_period_start.iso8601)
        expect(invoice.metadata['billing_period_end']).to eq(subscription.current_period_end.iso8601)
      end
    end

    context 'when subscription does not exist' do
      it 'returns not found error' do
        post '/api/v1/internal/billing/generate_invoice',
             params: { subscription_id: 'nonexistent-id' },
             headers: internal_headers,
             as: :json

        expect_error_response('Subscription not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/billing/generate_invoice',
             params: { subscription_id: subscription.id },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/billing/suspend_subscription' do
    context 'with service token authentication' do
      it 'suspends subscription' do
        post '/api/v1/internal/billing/suspend_subscription',
             params: { subscription_id: subscription.id, reason: 'payment_failure' },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'subscription_id' => subscription.id,
          'status' => 'suspended'
        )

        subscription.reload
        expect(subscription.status).to eq('suspended')
        expect(subscription.metadata['suspended_at']).to be_present
        expect(subscription.metadata['suspension_reason']).to eq('payment_failure')
      end

      it 'uses default reason when not provided' do
        post '/api/v1/internal/billing/suspend_subscription',
             params: { subscription_id: subscription.id },
             headers: internal_headers,
             as: :json

        expect_success_response

        subscription.reload
        expect(subscription.metadata['suspension_reason']).to eq('payment_failure')
      end
    end

    context 'when subscription does not exist' do
      it 'returns not found error' do
        post '/api/v1/internal/billing/suspend_subscription',
             params: { subscription_id: 'nonexistent-id' },
             headers: internal_headers,
             as: :json

        expect_error_response('Subscription not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/billing/suspend_subscription',
             params: { subscription_id: subscription.id },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/billing/cancel_subscription' do
    context 'with service token authentication' do
      it 'cancels subscription' do
        post '/api/v1/internal/billing/cancel_subscription',
             params: { subscription_id: subscription.id, reason: 'billing_failure' },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'subscription_id' => subscription.id,
          'status' => 'canceled'
        )

        subscription.reload
        expect(subscription.status).to eq('canceled')
        expect(subscription.canceled_at).to be_present
        expect(subscription.metadata['cancellation_reason']).to eq('billing_failure')
      end

      it 'uses default reason when not provided' do
        post '/api/v1/internal/billing/cancel_subscription',
             params: { subscription_id: subscription.id },
             headers: internal_headers,
             as: :json

        expect_success_response

        subscription.reload
        expect(subscription.metadata['cancellation_reason']).to eq('billing_failure')
      end
    end

    context 'when subscription does not exist' do
      it 'returns not found error' do
        post '/api/v1/internal/billing/cancel_subscription',
             params: { subscription_id: 'nonexistent-id' },
             headers: internal_headers,
             as: :json

        expect_error_response('Subscription not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/billing/cancel_subscription',
             params: { subscription_id: subscription.id },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/billing/cleanup' do
    context 'with service token authentication' do
      it 'performs billing cleanup' do
        post '/api/v1/internal/billing/cleanup',
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'stale_invoices_archived',
          'expired_trials_processed',
          'orphaned_payments_cleaned',
          'cleanup_at'
        )
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/billing/cleanup', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/billing/health_report' do
    context 'with service token authentication' do
      it 'records health report' do
        post '/api/v1/internal/billing/health_report',
             params: { queue_size: 42 },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'processing_queue_size' => 42
        )
        expect(response_data['data']).to have_key('pending_invoices_count')
        expect(response_data['data']).to have_key('overdue_invoices_count')
        expect(response_data['data']).to have_key('suspended_subscriptions_count')
        expect(response_data['data']).to have_key('failed_payments_24h')
        expect(response_data['data']).to have_key('reported_at')
      end

      it 'caches health report' do
        post '/api/v1/internal/billing/health_report',
             params: { queue_size: 10 },
             headers: internal_headers,
             as: :json

        expect_success_response

        cached_report = Rails.cache.read('billing_health_report')
        expect(cached_report).to be_present
        expect(cached_report[:processing_queue_size]).to eq(10)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/billing/health_report', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/billing/reactivate_suspended_accounts' do
    let!(:suspended_subscription) do
      Subscription.create!(
        account: create(:account),
        plan: plan,
        status: 'suspended',
        metadata: {
          'suspended_at' => 2.days.ago.iso8601,
          'suspension_reason' => 'payment_failure'
        }
      )
    end

    context 'with service token authentication' do
      it 'reactivates specific subscription' do
        post '/api/v1/internal/billing/reactivate_suspended_accounts',
             params: { subscription_id: suspended_subscription.id },
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'subscription_id' => suspended_subscription.id,
          'status' => 'active'
        )

        suspended_subscription.reload
        expect(suspended_subscription.status).to eq('active')
        expect(suspended_subscription.metadata).not_to have_key('suspended_at')
        expect(suspended_subscription.metadata).not_to have_key('suspension_reason')
      end

      it 'performs batch reactivation when no subscription_id provided' do
        post '/api/v1/internal/billing/reactivate_suspended_accounts',
             headers: internal_headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'reactivated_count',
          'subscription_ids'
        )
      end
    end

    context 'when subscription does not exist' do
      it 'returns not found error' do
        post '/api/v1/internal/billing/reactivate_suspended_accounts',
             params: { subscription_id: 'nonexistent-id' },
             headers: internal_headers,
             as: :json

        expect_error_response('Subscription not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/internal/billing/reactivate_suspended_accounts', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
