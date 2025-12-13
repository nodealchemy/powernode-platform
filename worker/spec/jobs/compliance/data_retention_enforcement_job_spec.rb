# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Compliance::DataRetentionEnforcementJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:policy_id) { 'policy-123' }
  let(:account_id) { 'account-456' }
  let(:job_args) { nil }

  let(:audit_log_policy) do
    {
      'id' => policy_id,
      'data_type' => 'audit_logs',
      'retention_days' => 365,
      'action' => 'archive',
      'account_id' => nil
    }
  end

  let(:activity_policy) do
    {
      'id' => 'policy-456',
      'data_type' => 'user_activity',
      'retention_days' => 90,
      'action' => 'delete',
      'account_id' => account_id
    }
  end

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  after do
    Sidekiq::Worker.clear_all
  end

  describe 'job configuration' do
    it 'is configured with compliance queue' do
      expect(described_class.sidekiq_options['queue']).to eq('compliance')
    end
  end

  describe '#execute' do
    let(:job) { described_class.new }
    let(:api_client) { instance_double(BackendApiClient) }

    before do
      allow(job).to receive(:api_client).and_return(api_client)
      allow(job).to receive(:log_info)
      allow(job).to receive(:log_error)
      allow(job).to receive(:log_warn)
    end

    context 'when processing retention policies' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_retention_policies', { active: true })
          .and_return(success: true, data: [audit_log_policy, activity_policy])
        allow(api_client).to receive(:post)
          .with('/api/v1/internal/retention/audit_logs/archive', anything)
          .and_return(success: true, data: { 'count' => 100 })
        allow(api_client).to receive(:delete)
          .with('/api/v1/internal/retention/activity', anything)
          .and_return(success: true, data: { 'count' => 50 })
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:post)
          .with('/api/v1/internal/audit_logs', anything)
          .and_return(success: true)
      end

      it 'fetches active retention policies' do
        expect(api_client).to receive(:get)
          .with('/api/v1/internal/data_retention_policies', { active: true })

        job.execute
      end

      it 'enforces each policy' do
        expect(api_client).to receive(:post)
          .with('/api/v1/internal/retention/audit_logs/archive', anything)
        expect(api_client).to receive(:delete)
          .with('/api/v1/internal/retention/activity', anything)

        job.execute
      end

      it 'updates policy enforcement timestamp' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_retention_policies/#{policy_id}",
            hash_including(:last_enforced_at)
          )

        job.execute
      end

      it 'logs compliance audit event' do
        expect(api_client).to receive(:post)
          .with(
            '/api/v1/internal/audit_logs',
            hash_including(action: 'compliance_check', resource_type: 'DataRetentionPolicy')
          )

        job.execute
      end

      it 'returns results summary' do
        result = job.execute

        expect(result[:policies_processed]).to eq(2)
        expect(result[:records_processed]).to eq(150)
        expect(result[:errors]).to be_empty
      end
    end

    context 'when no policies are active' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_retention_policies', { active: true })
          .and_return(success: true, data: [])
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'completes without processing' do
        result = job.execute

        expect(result[:policies_processed]).to eq(0)
        expect(result[:records_processed]).to eq(0)
      end
    end

    context 'when API request fails' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_retention_policies', { active: true })
          .and_return(success: false, error: 'Service unavailable')
      end

      it 'raises an error' do
        expect { job.execute }
          .to raise_error(/Failed to fetch retention policies/)
      end
    end

    context 'when policy enforcement fails' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_retention_policies', { active: true })
          .and_return(success: true, data: [audit_log_policy])
        allow(api_client).to receive(:post)
          .with('/api/v1/internal/retention/audit_logs/archive', anything)
          .and_raise(StandardError, 'Archive failed')
        allow(api_client).to receive(:post)
          .with('/api/v1/internal/audit_logs', anything)
          .and_return(success: true)
      end

      it 'logs error and continues' do
        expect(job).to receive(:log_error).with(/Failed to enforce policy/)

        result = job.execute

        expect(result[:errors]).not_to be_empty
        expect(result[:errors].first[:error]).to eq('Archive failed')
      end
    end

    context 'with audit log policy actions' do
      context 'when action is archive' do
        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/data_retention_policies', { active: true })
            .and_return(success: true, data: [audit_log_policy])
          allow(api_client).to receive(:post)
            .with('/api/v1/internal/retention/audit_logs/archive', anything)
            .and_return(success: true, data: { 'count' => 100 })
          allow(api_client).to receive(:patch).and_return(success: true)
          allow(api_client).to receive(:post)
            .with('/api/v1/internal/audit_logs', anything)
            .and_return(success: true)
        end

        it 'archives audit logs' do
          expect(api_client).to receive(:post)
            .with('/api/v1/internal/retention/audit_logs/archive', anything)

          job.execute
        end
      end

      context 'when action is anonymize' do
        let(:anonymize_policy) { audit_log_policy.merge('action' => 'anonymize') }

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/data_retention_policies', { active: true })
            .and_return(success: true, data: [anonymize_policy])
          allow(api_client).to receive(:patch)
            .with('/api/v1/internal/retention/audit_logs/anonymize', anything)
            .and_return(success: true, data: { 'count' => 100 })
          allow(api_client).to receive(:patch).and_return(success: true)
          allow(api_client).to receive(:post).and_return(success: true)
        end

        it 'anonymizes audit logs' do
          expect(api_client).to receive(:patch)
            .with('/api/v1/internal/retention/audit_logs/anonymize', anything)

          job.execute
        end
      end

      context 'when action is delete' do
        let(:delete_policy) { audit_log_policy.merge('action' => 'delete') }

        before do
          allow(api_client).to receive(:get)
            .with('/api/v1/internal/data_retention_policies', { active: true })
            .and_return(success: true, data: [delete_policy])
          allow(api_client).to receive(:post)
            .with('/api/v1/internal/retention/audit_logs/archive', anything)
            .and_return(success: true, data: { 'count' => 100 })
          allow(api_client).to receive(:patch).and_return(success: true)
          allow(api_client).to receive(:post)
            .with('/api/v1/internal/audit_logs', anything)
            .and_return(success: true)
        end

        it 'archives instead of deleting (audit logs should never be deleted)' do
          expect(api_client).to receive(:post)
            .with('/api/v1/internal/retention/audit_logs/archive', anything)

          job.execute
        end
      end
    end

    context 'with different data types' do
      let(:session_policy) do
        {
          'id' => 'session-policy',
          'data_type' => 'session_logs',
          'retention_days' => 30,
          'action' => 'delete',
          'account_id' => nil
        }
      end

      let(:webhook_policy) do
        {
          'id' => 'webhook-policy',
          'data_type' => 'webhook_logs',
          'retention_days' => 60,
          'action' => 'delete',
          'account_id' => account_id
        }
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_retention_policies', { active: true })
          .and_return(success: true, data: [session_policy, webhook_policy])
        allow(api_client).to receive(:delete).and_return(success: true, data: { 'count' => 25 })
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'deletes session logs' do
        expect(api_client).to receive(:delete)
          .with('/api/v1/internal/retention/sessions', anything)

        job.execute
      end

      it 'deletes webhook logs with account scope' do
        expect(api_client).to receive(:delete)
          .with('/api/v1/internal/retention/webhook_logs', hash_including(account_id: account_id))

        job.execute
      end
    end

    context 'with analytics data policy' do
      let(:analytics_policy) do
        {
          'id' => 'analytics-policy',
          'data_type' => 'analytics_data',
          'retention_days' => 180,
          'action' => 'anonymize',
          'account_id' => nil
        }
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_retention_policies', { active: true })
          .and_return(success: true, data: [analytics_policy])
        allow(api_client).to receive(:patch)
          .with('/api/v1/internal/retention/analytics/anonymize', anything)
          .and_return(success: true, data: { 'count' => 500 })
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'anonymizes analytics data' do
        expect(api_client).to receive(:patch)
          .with('/api/v1/internal/retention/analytics/anonymize', anything)

        job.execute
      end
    end

    context 'with file uploads policy' do
      let(:file_policy) do
        {
          'id' => 'file-policy',
          'data_type' => 'file_uploads',
          'retention_days' => 365,
          'action' => 'delete',
          'account_id' => account_id
        }
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_retention_policies', { active: true })
          .and_return(success: true, data: [file_policy])
        allow(api_client).to receive(:delete)
          .with('/api/v1/internal/retention/files', anything)
          .and_return(success: true, data: { 'count' => 10 })
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'deletes expired file uploads' do
        expect(api_client).to receive(:delete)
          .with('/api/v1/internal/retention/files', hash_including(account_id: account_id))

        job.execute
      end
    end

    context 'with unsupported data type' do
      let(:unsupported_policy) do
        {
          'id' => 'unsupported-policy',
          'data_type' => 'unknown_type',
          'retention_days' => 30,
          'action' => 'delete',
          'account_id' => nil
        }
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_retention_policies', { active: true })
          .and_return(success: true, data: [unsupported_policy])
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'handles gracefully with zero records' do
        result = job.execute

        expect(result[:policies_processed]).to eq(1)
        expect(result[:records_processed]).to eq(0)
      end
    end
  end
end
