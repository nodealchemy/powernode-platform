# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Git::PipelineApprovalExpiryJob, type: :job do
  subject { described_class }

  let(:job_instance) { described_class.new }
  let(:api_client_double) { instance_double(BackendApiClient) }
  let(:account_id) { 'account-123-uuid' }

  let(:expired_approval) do
    {
      'id' => 'approval-456',
      'status' => 'expired',
      'gate_name' => 'production-deploy',
      'environment' => 'production',
      'pipeline' => { 'name' => 'Build Pipeline' },
      'repository' => { 'full_name' => 'owner/repo' },
      'requested_by' => { 'id' => 'user-123' },
      'required_approvers' => ['user-456', 'user-789']
    }
  end

  let(:expiry_response) do
    {
      'expired_count' => 2,
      'expired_ids' => ['approval-456', 'approval-789']
    }
  end

  before do
    mock_powernode_worker_config
    allow(BackendApiClient).to receive(:new).and_return(api_client_double)
    allow(api_client_double).to receive(:get).and_return({ 'data' => {} })
    allow(api_client_double).to receive(:post).and_return({ 'success' => true, 'data' => expiry_response })
    # Mock idempotency methods
    allow(job_instance).to receive(:already_processed?).and_return(false)
    allow(job_instance).to receive(:mark_processed)
  end

  describe 'class configuration' do
    it_behaves_like 'a base job', described_class

    it 'uses maintenance queue' do
      expect(described_class.sidekiq_options['queue']).to eq('maintenance')
    end

    it 'has 3 retries configured' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  describe '#execute' do
    context 'with no parameters (all accounts)' do
      before do
        allow(api_client_double).to receive(:post)
          .with('/api/v1/internal/git/approvals/expire_stale')
          .and_return({ 'success' => true, 'data' => expiry_response })

        allow(api_client_double).to receive(:get)
          .with('/api/v1/internal/git/approvals/approval-456')
          .and_return({ 'data' => expired_approval })

        allow(api_client_double).to receive(:get)
          .with('/api/v1/internal/git/approvals/approval-789')
          .and_return({ 'data' => expired_approval })
      end

      it 'calls expire_stale endpoint' do
        job_instance.execute({})

        expect(api_client_double).to have_received(:post)
          .with('/api/v1/internal/git/approvals/expire_stale')
      end

      it 'returns expiry results' do
        result = job_instance.execute({})

        expect(result).to include(
          success: true,
          expired_count: 2,
          expired_ids: ['approval-456', 'approval-789']
        )
      end

      it 'marks as processed for idempotency' do
        job_instance.execute({})

        expect(job_instance).to have_received(:mark_processed)
      end
    end

    context 'with account_id' do
      before do
        allow(api_client_double).to receive(:post)
          .with('/api/v1/internal/git/approvals/expire_stale', { account_id: account_id })
          .and_return({ 'success' => true, 'data' => expiry_response })

        allow(api_client_double).to receive(:get)
          .with('/api/v1/internal/git/approvals/approval-456')
          .and_return({ 'data' => expired_approval })

        allow(api_client_double).to receive(:get)
          .with('/api/v1/internal/git/approvals/approval-789')
          .and_return({ 'data' => expired_approval })
      end

      it 'calls expire_stale with account filter' do
        job_instance.execute(account_id: account_id)

        expect(api_client_double).to have_received(:post)
          .with('/api/v1/internal/git/approvals/expire_stale', { account_id: account_id })
      end

      it 'returns results with account_id' do
        result = job_instance.execute(account_id: account_id)

        expect(result).to include(
          success: true,
          account_id: account_id,
          expired_count: 2
        )
      end
    end

    context 'when already processed (idempotency)' do
      before do
        allow(job_instance).to receive(:already_processed?).and_return(true)
      end

      it 'skips processing' do
        result = job_instance.execute({})

        expect(result).to eq({ skipped: true, reason: 'already_processed' })
      end

      it 'does not call expire endpoint' do
        job_instance.execute({})

        expect(api_client_double).not_to have_received(:post)
      end
    end

    context 'when no approvals expired' do
      before do
        allow(api_client_double).to receive(:post)
          .with('/api/v1/internal/git/approvals/expire_stale')
          .and_return({ 'success' => true, 'data' => { 'expired_count' => 0, 'expired_ids' => [] } })
      end

      it 'returns zero count' do
        result = job_instance.execute({})

        expect(result[:expired_count]).to eq(0)
      end

      it 'does not send notifications' do
        job_instance.execute({})

        expect(api_client_double).not_to have_received(:post)
          .with('/api/v1/internal/notifications', anything)
      end
    end

    context 'notification sending' do
      before do
        allow(api_client_double).to receive(:post)
          .with('/api/v1/internal/git/approvals/expire_stale')
          .and_return({ 'success' => true, 'data' => { 'expired_count' => 1, 'expired_ids' => ['approval-456'] } })

        allow(api_client_double).to receive(:get)
          .with('/api/v1/internal/git/approvals/approval-456')
          .and_return({ 'data' => expired_approval })

        allow(api_client_double).to receive(:post)
          .with('/api/v1/internal/notifications', anything)
          .and_return({ 'success' => true })
      end

      it 'sends notification to requester' do
        job_instance.execute({})

        expect(api_client_double).to have_received(:post)
          .with('/api/v1/internal/notifications', hash_including(
            user_id: 'user-123',
            notification_type: 'approval_expired'
          ))
      end

      it 'sends notification to required approvers' do
        job_instance.execute({})

        expect(api_client_double).to have_received(:post)
          .with('/api/v1/internal/notifications', hash_including(
            user_id: 'user-456'
          ))

        expect(api_client_double).to have_received(:post)
          .with('/api/v1/internal/notifications', hash_including(
            user_id: 'user-789'
          ))
      end

      it 'includes approval details in notification' do
        job_instance.execute({})

        expect(api_client_double).to have_received(:post)
          .with('/api/v1/internal/notifications', hash_including(
            title: 'Pipeline Approval Expired',
            metadata: hash_including(
              gate_name: 'production-deploy',
              environment: 'production'
            )
          )).at_least(:once)
      end
    end

    context 'when notification sending fails' do
      before do
        allow(api_client_double).to receive(:post)
          .with('/api/v1/internal/git/approvals/expire_stale')
          .and_return({ 'success' => true, 'data' => { 'expired_count' => 1, 'expired_ids' => ['approval-456'] } })

        allow(api_client_double).to receive(:get)
          .with('/api/v1/internal/git/approvals/approval-456')
          .and_return({ 'data' => expired_approval })

        allow(api_client_double).to receive(:post)
          .with('/api/v1/internal/notifications', anything)
          .and_raise(StandardError.new('Notification failed'))
      end

      it 'continues without raising error' do
        expect { job_instance.execute({}) }.not_to raise_error
      end

      it 'still returns success' do
        result = job_instance.execute({})

        expect(result).to include(success: true, expired_count: 1)
      end
    end

    context 'when approval fetch fails' do
      before do
        allow(api_client_double).to receive(:post)
          .with('/api/v1/internal/git/approvals/expire_stale')
          .and_return({ 'success' => true, 'data' => { 'expired_count' => 1, 'expired_ids' => ['approval-456'] } })

        allow(api_client_double).to receive(:get)
          .with('/api/v1/internal/git/approvals/approval-456')
          .and_return({ 'data' => nil })
      end

      it 'skips notification for unfetchable approvals' do
        job_instance.execute({})

        expect(api_client_double).not_to have_received(:post)
          .with('/api/v1/internal/notifications', anything)
      end
    end
  end

  describe 'API error handling' do
    before do
      allow(api_client_double).to receive(:post)
        .and_raise(BackendApiClient::ApiError.new('API Error', 500))
    end

    it 'raises the error for retry' do
      expect { job_instance.execute({}) }
        .to raise_error(BackendApiClient::ApiError)
    end
  end

  describe 'logging' do
    let(:job_args) { {} }

    before do
      allow(api_client_double).to receive(:post)
        .with('/api/v1/internal/git/approvals/expire_stale')
        .and_return({ 'success' => true, 'data' => { 'expired_count' => 0, 'expired_ids' => [] } })
    end

    it_behaves_like 'a job with logging'
  end
end
