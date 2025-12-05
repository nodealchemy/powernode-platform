# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Billing::DunningProcessJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class

  before { mock_powernode_worker_config }

  let(:subscription_id) { SecureRandom.uuid }
  let(:account_id) { SecureRandom.uuid }
  let(:reason) { 'payment_failure' }
  let(:dunning_stage) { 1 }

  let(:subscription_data) do
    {
      'id' => subscription_id,
      'account_id' => account_id,
      'status' => 'past_due'
    }
  end

  describe '#execute' do
    context 'with stage 1 (first reminder)' do
      before do
        stub_backend_api_success(:get, "/api/v1/internal/subscriptions/#{subscription_id}", {
          'success' => true,
          'data' => subscription_data
        })
        stub_backend_api_success(:post, "/api/v1/internal/subscriptions/#{subscription_id}/dunning", {
          'success' => true,
          'data' => {}
        })
      end

      it 'executes first reminder action' do
        result = described_class.new.execute(subscription_id, reason, dunning_stage)

        expect(result[:success]).to be true
        expect(result[:action]).to eq('first_reminder')
        expect_api_request(:post, "/api/v1/internal/subscriptions/#{subscription_id}/dunning")
      end

      it 'schedules next dunning stage' do
        expect(Billing::DunningProcessJob).to receive(:perform_in).with(
          3.days,
          subscription_id,
          reason,
          2
        )

        described_class.new.execute(subscription_id, reason, dunning_stage)
      end

      it 'logs success message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(subscription_id, reason, dunning_stage)

        expect_logged(:info, /completed successfully/)
      end
    end

    context 'with stage 2 (second reminder)' do
      let(:dunning_stage) { 2 }

      before do
        stub_backend_api_success(:get, "/api/v1/internal/subscriptions/#{subscription_id}", {
          'success' => true,
          'data' => subscription_data
        })
        stub_backend_api_success(:post, "/api/v1/internal/subscriptions/#{subscription_id}/dunning", {
          'success' => true,
          'data' => {}
        })
      end

      it 'executes second reminder action' do
        result = described_class.new.execute(subscription_id, reason, dunning_stage)

        expect(result[:action]).to eq('second_reminder')
      end

      it 'schedules next stage in 7 days' do
        expect(Billing::DunningProcessJob).to receive(:perform_in).with(
          7.days,
          subscription_id,
          reason,
          3
        )

        described_class.new.execute(subscription_id, reason, dunning_stage)
      end
    end

    context 'with stage 3 (final notice)' do
      let(:dunning_stage) { 3 }

      before do
        stub_backend_api_success(:get, "/api/v1/internal/subscriptions/#{subscription_id}", {
          'success' => true,
          'data' => subscription_data
        })
        stub_backend_api_success(:post, "/api/v1/internal/subscriptions/#{subscription_id}/dunning", {
          'success' => true,
          'data' => {}
        })
      end

      it 'executes final notice action' do
        result = described_class.new.execute(subscription_id, reason, dunning_stage)

        expect(result[:action]).to eq('final_notice')
      end

      it 'schedules account suspension' do
        expect(Billing::DunningProcessJob).to receive(:perform_in).with(
          14.days,
          subscription_id,
          reason,
          4
        )

        described_class.new.execute(subscription_id, reason, dunning_stage)
      end
    end

    context 'with stage 4 (suspend account)' do
      let(:dunning_stage) { 4 }

      before do
        stub_backend_api_success(:get, "/api/v1/internal/subscriptions/#{subscription_id}", {
          'success' => true,
          'data' => subscription_data
        })
        stub_backend_api_success(:post, "/api/v1/internal/subscriptions/#{subscription_id}/dunning", {
          'success' => true,
          'data' => {}
        })
      end

      it 'executes suspend account action' do
        result = described_class.new.execute(subscription_id, reason, dunning_stage)

        expect(result[:action]).to eq('suspend_account')
      end

      it 'does not schedule next stage' do
        expect(Billing::DunningProcessJob).not_to receive(:perform_in)

        described_class.new.execute(subscription_id, reason, dunning_stage)
      end
    end

    context 'when subscription not found' do
      before do
        stub_backend_api_success(:get, "/api/v1/internal/subscriptions/#{subscription_id}", {
          'success' => false,
          'error' => 'Not found'
        })
      end

      it 'returns failure result' do
        result = described_class.new.execute(subscription_id, reason, dunning_stage)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Not found')
      end

      it 'logs error message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(subscription_id, reason, dunning_stage)

        expect_logged(:error, /Failed to fetch/)
      end
    end

    context 'with invalid dunning stage' do
      let(:dunning_stage) { 5 }

      before do
        stub_backend_api_success(:get, "/api/v1/internal/subscriptions/#{subscription_id}", {
          'success' => true,
          'data' => subscription_data
        })
      end

      it 'returns error' do
        result = described_class.new.execute(subscription_id, reason, dunning_stage)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid dunning stage')
      end
    end

    context 'when dunning action fails' do
      before do
        stub_backend_api_success(:get, "/api/v1/internal/subscriptions/#{subscription_id}", {
          'success' => true,
          'data' => subscription_data
        })
        stub_backend_api_success(:post, "/api/v1/internal/subscriptions/#{subscription_id}/dunning", {
          'success' => false,
          'error' => 'Action failed'
        })
      end

      it 'returns failure result' do
        result = described_class.new.execute(subscription_id, reason, dunning_stage)

        expect(result[:success]).to be false
      end

      it 'logs error message' do
        job = described_class.new
        capture_logs_for(job)

        job.execute(subscription_id, reason, dunning_stage)

        expect_logged(:error, /action failed/)
      end
    end

    context 'when API call fails' do
      before do
        stub_backend_api_connection_failure(:get, "/api/v1/internal/subscriptions/#{subscription_id}")
      end

      it 'returns failure result' do
        result = described_class.new.execute(subscription_id, reason, dunning_stage)

        expect(result[:success]).to be false
      end
    end
  end

  describe 'dunning stages' do
    it 'has 4 stages defined' do
      expect(Billing::DunningProcessJob::DUNNING_STAGES.keys).to eq([1, 2, 3, 4])
    end

    it 'has correct delays' do
      expect(Billing::DunningProcessJob::DUNNING_STAGES[1][:delay]).to eq(3.days)
      expect(Billing::DunningProcessJob::DUNNING_STAGES[2][:delay]).to eq(7.days)
      expect(Billing::DunningProcessJob::DUNNING_STAGES[3][:delay]).to eq(14.days)
      expect(Billing::DunningProcessJob::DUNNING_STAGES[4][:delay]).to eq(21.days)
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
