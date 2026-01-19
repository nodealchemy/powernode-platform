# frozen_string_literal: true

require 'rails_helper'

# Stub PayPal SDK module for tests (actual PayPal SDK not installed in worker)
module PayPal
  module SDK
    def self.configure(**options); end

    module Core
      module Exceptions
        class UnauthorizedAccess < StandardError; end
      end
    end
  end
end

RSpec.describe Billing::PaymentReconciliationJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before do
    mock_powernode_worker_config
    # Set required PayPal environment variables for testing
    stub_const('ENV', ENV.to_h.merge(
      'PAYPAL_CLIENT_ID' => 'test-paypal-client-id',
      'PAYPAL_CLIENT_SECRET' => 'test-paypal-client-secret',
      'PAYPAL_MODE' => 'sandbox'
    ))
  end

  let(:reconciliation_type) { 'daily' }

  let(:local_stripe_payments) do
    [
      {
        'id' => SecureRandom.uuid,
        'amount_cents' => 2999,
        'metadata' => { 'stripe_charge_id' => 'ch_123' }
      },
      {
        'id' => SecureRandom.uuid,
        'amount_cents' => 4999,
        'metadata' => { 'stripe_charge_id' => 'ch_456' }
      }
    ]
  end

  let(:stripe_api_payments) do
    [
      {
        id: 'ch_123',
        amount: 2999,
        currency: 'usd',
        created: 1.day.ago.to_i,
        status: 'succeeded',
        payment_intent: 'pi_123',
        customer: 'cus_123',
        description: 'Test charge'
      },
      {
        id: 'ch_456',
        amount: 4999,
        currency: 'usd',
        created: 1.day.ago.to_i,
        status: 'succeeded',
        payment_intent: 'pi_456',
        customer: 'cus_456',
        description: 'Test charge 2'
      }
    ]
  end

  describe '#execute' do
    context 'with daily reconciliation (no discrepancies)' do
      before do
        stub_backend_api_success(:get, '/api/v1/reconciliation/stripe_payments', local_stripe_payments)
        stub_backend_api_success(:get, '/api/v1/reconciliation/paypal_payments', [])
        stub_backend_api_success(:post, '/api/v1/reconciliation/report', { 'success' => true })

        stub_stripe_charges(stripe_api_payments)
      end

      it 'reconciles payments successfully' do
        result = described_class.new.execute(reconciliation_type)

        expect(result[:reconciliation_type]).to eq('daily')
        expect(result[:discrepancies]).to be_empty
        expect(result[:summary][:discrepancies_found]).to eq(0)
      end

      it 'reports reconciliation results' do
        described_class.new.execute(reconciliation_type)

        expect_api_request(:post, '/api/v1/reconciliation/report')
      end

      it 'logs completion message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(reconciliation_type)

        expect_logged(:info, /completed/)
      end
    end

    context 'with weekly reconciliation' do
      let(:reconciliation_type) { 'weekly' }

      before do
        stub_backend_api_success(:get, '/api/v1/reconciliation/stripe_payments', [])
        stub_backend_api_success(:get, '/api/v1/reconciliation/paypal_payments', [])
        stub_backend_api_success(:post, '/api/v1/reconciliation/report', { 'success' => true })

        stub_stripe_charges([])
      end

      it 'uses weekly date range' do
        result = described_class.new.execute(reconciliation_type)

        expect(result[:reconciliation_type]).to eq('weekly')
        expect(result[:date_range].begin).to be_within(1.hour).of(1.week.ago.beginning_of_week)
      end
    end

    context 'with monthly reconciliation' do
      let(:reconciliation_type) { 'monthly' }

      before do
        stub_backend_api_success(:get, '/api/v1/reconciliation/stripe_payments', [])
        stub_backend_api_success(:get, '/api/v1/reconciliation/paypal_payments', [])
        stub_backend_api_success(:post, '/api/v1/reconciliation/report', { 'success' => true })

        stub_stripe_charges([])
      end

      it 'uses monthly date range' do
        result = described_class.new.execute(reconciliation_type)

        expect(result[:reconciliation_type]).to eq('monthly')
        expect(result[:date_range].begin).to be_within(1.hour).of(1.month.ago.beginning_of_month)
      end
    end

    context 'with missing local payment discrepancy' do
      let(:stripe_api_payments_extra) do
        stripe_api_payments + [{
          id: 'ch_789',
          amount: 1999,
          currency: 'usd',
          created: 1.day.ago.to_i,
          status: 'succeeded',
          payment_intent: 'pi_789',
          customer: 'cus_789',
          description: 'Extra charge'
        }]
      end

      before do
        stub_backend_api_success(:get, '/api/v1/reconciliation/stripe_payments', local_stripe_payments)
        stub_backend_api_success(:get, '/api/v1/reconciliation/paypal_payments', [])
        stub_backend_api_success(:post, '/api/v1/reconciliation/report', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/reconciliation/corrections', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/alerts', { 'success' => true })

        stub_stripe_charges(stripe_api_payments_extra)
      end

      it 'detects missing local payment' do
        result = described_class.new.execute(reconciliation_type)

        expect(result[:discrepancies]).not_to be_empty
        missing_payment = result[:discrepancies].find { |d| d[:type] == 'missing_local_payment' }
        expect(missing_payment).to be_present
        expect(missing_payment[:provider_payment_id]).to eq('ch_789')
        expect(missing_payment[:severity]).to eq('high')
      end

      it 'creates correction action' do
        described_class.new.execute(reconciliation_type)

        expect_api_request(:post, '/api/v1/reconciliation/corrections')
      end
    end

    context 'with amount mismatch discrepancy' do
      let(:mismatched_stripe_payments) do
        [{
          id: 'ch_123',
          amount: 3999, # Different from local 2999
          currency: 'usd',
          created: 1.day.ago.to_i,
          status: 'succeeded',
          payment_intent: 'pi_123',
          customer: 'cus_123',
          description: 'Mismatched charge'
        }]
      end

      before do
        stub_backend_api_success(:get, '/api/v1/reconciliation/stripe_payments', [local_stripe_payments.first])
        stub_backend_api_success(:get, '/api/v1/reconciliation/paypal_payments', [])
        stub_backend_api_success(:post, '/api/v1/reconciliation/report', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/reconciliation/investigations', { 'success' => true })

        stub_stripe_charges(mismatched_stripe_payments)
      end

      it 'detects amount mismatch' do
        result = described_class.new.execute(reconciliation_type)

        expect(result[:discrepancies]).not_to be_empty
        mismatch = result[:discrepancies].find { |d| d[:type] == 'amount_mismatch' }
        expect(mismatch).to be_present
        expect(mismatch[:local_amount]).to eq(2999)
        expect(mismatch[:provider_amount]).to eq(3999)
        expect(mismatch[:amount_difference]).to eq(-1000)
        expect(mismatch[:severity]).to eq('medium')
      end

      it 'creates investigation' do
        described_class.new.execute(reconciliation_type)

        expect_api_request(:post, '/api/v1/reconciliation/investigations')
      end
    end

    context 'with missing provider payment discrepancy' do
      let(:local_payments_extra) do
        local_stripe_payments + [{
          'id' => SecureRandom.uuid,
          'amount_cents' => 1999,
          'metadata' => { 'stripe_charge_id' => 'ch_999' }
        }]
      end

      before do
        stub_backend_api_success(:get, '/api/v1/reconciliation/stripe_payments', local_payments_extra)
        stub_backend_api_success(:get, '/api/v1/reconciliation/paypal_payments', [])
        stub_backend_api_success(:post, '/api/v1/reconciliation/report', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/reconciliation/flags', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/alerts', { 'success' => true })

        stub_stripe_charges(stripe_api_payments)
      end

      it 'detects missing provider payment' do
        result = described_class.new.execute(reconciliation_type)

        expect(result[:discrepancies]).not_to be_empty
        missing = result[:discrepancies].find { |d| d[:type] == 'missing_provider_payment' }
        expect(missing).to be_present
        expect(missing[:external_id]).to eq('ch_999')
        expect(missing[:severity]).to eq('high')
      end

      it 'flags for manual review' do
        described_class.new.execute(reconciliation_type)

        expect_api_request(:post, '/api/v1/reconciliation/flags')
      end
    end

    context 'with significant discrepancies' do
      let(:many_stripe_charges) do
        (1..15).map do |i|
          {
            id: "ch_#{i}",
            amount: 2999,
            currency: 'usd',
            created: 1.day.ago.to_i,
            status: 'succeeded',
            payment_intent: "pi_#{i}",
            customer: "cus_#{i}",
            description: "Charge #{i}"
          }
        end
      end

      before do
        stub_backend_api_success(:get, '/api/v1/reconciliation/stripe_payments', [])
        stub_backend_api_success(:get, '/api/v1/reconciliation/paypal_payments', [])
        stub_backend_api_success(:post, '/api/v1/reconciliation/report', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/alerts', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/reconciliation/corrections', { 'success' => true })

        stub_stripe_charges(many_stripe_charges)
      end

      it 'sends reconciliation alert' do
        described_class.new.execute(reconciliation_type)

        expect_api_request(:post, '/api/v1/alerts')
      end

      it 'logs warning message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(reconciliation_type)

        expect_logged(:warn, /Sent reconciliation alert/)
      end
    end

    context 'when Stripe API fails' do
      before do
        stub_backend_api_success(:get, '/api/v1/reconciliation/stripe_payments', local_stripe_payments)
        stub_backend_api_success(:get, '/api/v1/reconciliation/paypal_payments', [])
        stub_backend_api_success(:post, '/api/v1/reconciliation/report', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/alerts', { 'success' => true })
        stub_backend_api_success(:post, '/api/v1/reconciliation/flags', { 'success' => true })

        stub_stripe_api_error(Stripe::APIConnectionError, 'Connection failed')
      end

      it 'raises GatewayError' do
        expect { described_class.new.execute(reconciliation_type) }
          .to raise_error(BillingExceptions::GatewayError, /Failed to connect to Stripe API/)
      end
    end

    context 'when backend API fails' do
      before do
        stub_backend_api_error(:get, '/api/v1/reconciliation/stripe_payments', status: 500, error_message: 'Server error')
      end

      it 'raises error' do
        expect { described_class.new.execute(reconciliation_type) }.to raise_error(StandardError)
      end
    end
  end

  describe 'PayPal reconciliation' do
    before do
      stub_backend_api_success(:get, '/api/v1/reconciliation/stripe_payments', [])
      stub_backend_api_success(:get, '/api/v1/reconciliation/paypal_payments', [])
      stub_backend_api_success(:post, '/api/v1/reconciliation/report', { 'success' => true })

      stub_stripe_charges([])
    end

    it 'reconciles PayPal payments' do
      result = described_class.new.execute(reconciliation_type)

      expect(result[:paypal_reconciliation]).to be_present
      expect(result[:paypal_reconciliation][:local_count]).to eq(0)
    end

    it 'logs PayPal reconciliation start' do
      job = described_class.new
      capture_logs_for(job)

      job.execute(reconciliation_type)

      # PayPal reconciliation is now fully implemented
      expect_logged(:info, /Reconciling PayPal payments for/)
    end
  end

  describe 'sidekiq options' do
    it 'uses billing queue' do
      expect(described_class.sidekiq_options['queue']).to eq('billing')
    end

    it 'has retry count of 2' do
      expect(described_class.sidekiq_options['retry']).to eq(2)
    end
  end
end
