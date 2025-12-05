# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::ProcessWebhookJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before { mock_powernode_worker_config }

  let(:stripe_invoice_payload) do
    {
      'data' => {
        'object' => {
          'id' => 'in_12345',
          'amount_paid' => 9999,
          'currency' => 'usd',
          'status' => 'paid',
          'customer' => 'cus_12345',
          'subscription' => 'sub_12345',
          'payment_intent' => 'pi_12345'
        }
      }
    }
  end

  let(:stripe_subscription_payload) do
    {
      'data' => {
        'object' => {
          'id' => 'sub_12345',
          'customer' => 'cus_12345',
          'status' => 'active',
          'current_period_start' => Time.now.to_i,
          'current_period_end' => (Time.now + 30.days).to_i,
          'items' => {
            'data' => [
              {
                'price' => { 'id' => 'price_12345' },
                'quantity' => 1
              }
            ]
          }
        }
      }
    }
  end

  describe '#execute' do
    context 'when processing Stripe payment succeeded webhook' do
      let(:webhook_data) do
        {
          'provider' => 'stripe',
          'event_type' => 'invoice.payment_succeeded',
          'payload' => stripe_invoice_payload
        }
      end

      before do
        stub_backend_api_success(:post, '/api/v1/webhooks/payment_succeeded', {
          'success' => true
        })
      end

      it 'processes the webhook successfully' do
        result = described_class.new.execute(webhook_data)

        expect(result['success']).to be true
      end

      it 'sends payment data to backend API' do
        described_class.new.execute(webhook_data)

        expect_api_request(:post, '/api/v1/webhooks/payment_succeeded')
      end

      it 'extracts payment data correctly' do
        described_class.new.execute(webhook_data)

        expect_api_request(:post, '/api/v1/webhooks/payment_succeeded') do |request|
          body = JSON.parse(request.body)
          expect(body['payment_data']['external_id']).to eq('in_12345')
          expect(body['payment_data']['amount_cents']).to eq(9999)
          expect(body['provider']).to eq('stripe')
        end
      end
    end

    context 'when processing Stripe payment failed webhook' do
      let(:webhook_data) do
        {
          'provider' => 'stripe',
          'event_type' => 'invoice.payment_failed',
          'payload' => stripe_invoice_payload
        }
      end

      before do
        stub_backend_api_success(:post, '/api/v1/webhooks/payment_failed', {
          'success' => true,
          'subscription_id' => 'sub_12345'
        })
      end

      it 'processes the webhook and schedules retry' do
        expect(Billing::PaymentRetryJob).to receive(:perform_in).with(1.hour, 'sub_12345', 'webhook_failure')

        result = described_class.new.execute(webhook_data)

        expect(result['success']).to be true
      end
    end

    context 'when processing Stripe subscription updated webhook' do
      let(:webhook_data) do
        {
          'provider' => 'stripe',
          'event_type' => 'customer.subscription.updated',
          'payload' => stripe_subscription_payload
        }
      end

      before do
        stub_backend_api_success(:post, '/api/v1/webhooks/subscription_updated', {
          'success' => true
        })
      end

      it 'processes subscription update successfully' do
        result = described_class.new.execute(webhook_data)

        expect(result['success']).to be true
      end

      it 'extracts subscription data correctly' do
        described_class.new.execute(webhook_data)

        expect_api_request(:post, '/api/v1/webhooks/subscription_updated') do |request|
          body = JSON.parse(request.body)
          expect(body['subscription_data']['external_id']).to eq('sub_12345')
          expect(body['subscription_data']['status']).to eq('active')
        end
      end
    end

    context 'when processing Stripe subscription deleted webhook' do
      let(:webhook_data) do
        {
          'provider' => 'stripe',
          'event_type' => 'customer.subscription.deleted',
          'payload' => stripe_subscription_payload
        }
      end

      before do
        stub_backend_api_success(:post, '/api/v1/webhooks/subscription_cancelled', {
          'success' => true
        })
      end

      it 'processes subscription cancellation successfully' do
        result = described_class.new.execute(webhook_data)

        expect(result['success']).to be true
        expect_api_request(:post, '/api/v1/webhooks/subscription_cancelled')
      end
    end

    context 'when processing PayPal webhook' do
      let(:paypal_webhook_data) do
        {
          'provider' => 'paypal',
          'event_type' => 'PAYMENT.CAPTURE.COMPLETED',
          'payload' => {
            'resource' => {
              'id' => 'pay_12345',
              'amount' => { 'total' => '99.99', 'currency' => 'USD' },
              'state' => 'completed',
              'parent_payment' => 'parent_12345'
            }
          }
        }
      end

      before do
        allow_any_instance_of(Webhooks::PaypalWebhookProcessorJob).to receive(:process_webhook)
          .and_return({ success: true, message: 'PayPal webhook processed' })
      end

      it 'delegates to PayPal processor' do
        result = described_class.new.execute(paypal_webhook_data)

        expect(result['success']).to be true
      end
    end

    context 'when provider is unknown' do
      let(:webhook_data) do
        {
          'provider' => 'unknown_provider',
          'event_type' => 'some_event',
          'payload' => {}
        }
      end

      it 'returns failure with error message' do
        result = described_class.new.execute(webhook_data)

        expect(result['success']).to be false
        expect(result['error']).to include('Unsupported provider')
      end

      it 'logs a warning' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(webhook_data)

        expect_logged(:warn, /Unknown webhook provider/)
      end
    end

    context 'when required params are missing' do
      it 'raises error for missing provider' do
        expect {
          described_class.new.execute({ 'event_type' => 'test', 'payload' => {} })
        }.to raise_error(ArgumentError, /provider/)
      end

      it 'raises error for missing event_type' do
        expect {
          described_class.new.execute({ 'provider' => 'stripe', 'payload' => {} })
        }.to raise_error(ArgumentError, /event_type/)
      end

      it 'raises error for missing payload' do
        expect {
          described_class.new.execute({ 'provider' => 'stripe', 'event_type' => 'test' })
        }.to raise_error(ArgumentError, /payload/)
      end
    end

    context 'when API call fails' do
      let(:webhook_data) do
        {
          'provider' => 'stripe',
          'event_type' => 'invoice.payment_succeeded',
          'payload' => stripe_invoice_payload
        }
      end

      before do
        # Mock api_client to raise ApiError directly (avoids retry delays in tests)
        mock_api_client = instance_double(BackendApiClient)
        allow_any_instance_of(described_class).to receive(:api_client).and_return(mock_api_client)
        allow(mock_api_client).to receive(:post).and_raise(
          BackendApiClient::ApiError.new('Server error', 500)
        )
      end

      it 'returns failure result' do
        result = described_class.new.execute(webhook_data)

        expect(result['success']).to be false
        expect(result['error']).to include('Server error')
      end

      it 'logs error message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(webhook_data)

        expect_logged(:error, /Failed to process/)
      end
    end

    context 'when handling unhandled event types' do
      let(:webhook_data) do
        {
          'provider' => 'stripe',
          'event_type' => 'some.unhandled.event',
          'payload' => {}
        }
      end

      it 'returns success with message' do
        result = described_class.new.execute(webhook_data)

        expect(result['success']).to be true
        expect(result['message']).to eq('Event type not handled')
      end

      it 'logs info about unhandled event' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(webhook_data)

        expect_logged(:info, /Unhandled Stripe event/)
      end
    end
  end

  describe 'sidekiq options' do
    it 'uses webhooks queue' do
      expect(described_class.sidekiq_options['queue']).to eq('webhooks')
    end

    it 'has limited retries' do
      expect(described_class.sidekiq_options['retry']).to eq(2)
    end
  end

  describe 'data extraction' do
    context 'Stripe payment data' do
      let(:job) { described_class.new }

      it 'extracts payment data from invoice payload' do
        data = job.send(:extract_stripe_payment_data, stripe_invoice_payload)

        expect(data[:external_id]).to eq('in_12345')
        expect(data[:amount_cents]).to eq(9999)
        expect(data[:currency]).to eq('usd')
        expect(data[:customer_id]).to eq('cus_12345')
        expect(data[:subscription_id]).to eq('sub_12345')
      end
    end

    context 'Stripe subscription data' do
      let(:job) { described_class.new }

      it 'extracts subscription data from payload' do
        data = job.send(:extract_stripe_subscription_data, stripe_subscription_payload)

        expect(data[:external_id]).to eq('sub_12345')
        expect(data[:customer_id]).to eq('cus_12345')
        expect(data[:status]).to eq('active')
        expect(data[:plan_id]).to eq('price_12345')
        expect(data[:quantity]).to eq(1)
      end
    end

    context 'PayPal payment data' do
      let(:job) { described_class.new }
      let(:paypal_payload) do
        {
          'resource' => {
            'id' => 'pay_12345',
            'amount' => { 'total' => '99.99', 'currency' => 'USD' },
            'state' => 'completed',
            'parent_payment' => 'parent_12345'
          }
        }
      end

      it 'extracts payment data from PayPal payload' do
        data = job.send(:extract_paypal_payment_data, paypal_payload)

        expect(data[:external_id]).to eq('pay_12345')
        expect(data[:amount_cents]).to eq(9999)
        expect(data[:currency]).to eq('USD')
        expect(data[:status]).to eq('completed')
      end
    end
  end
end
