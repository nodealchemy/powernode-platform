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
      'account_id' => account_id
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
      expect(described_class.sidekiq_options['queue'].to_s).to eq('compliance')
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
          .and_return('success' => true, 'data' => [audit_log_policy, activity_policy])
        allow(api_client).to receive(:post)
          .with('/api/v1/internal/retention/audit_logs/archive', anything)
          .and_return('success' => true, 'data' => { 'count' => 100 })
        allow(api_client).to receive(:delete)
          .with('/api/v1/internal/retention/activity', anything)
          .and_return('success' => true, 'data' => { 'count' => 50 })
        allow(api_client).to receive(:patch).and_return('success' => true)
        allow(api_client).to receive(:post)
          .with('/api/v1/internal/audit_logs', anything)
          .and_return('success' => true)
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
          .and_return('success' => true, 'data' => [])
        allow(api_client).to receive(:post).and_return('success' => true)
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
          .and_return('success' => false, 'error' => 'Service unavailable')
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
          .and_return('success' => true, 'data' => [audit_log_policy])
        allow(api_client).to receive(:post)
          .with('/api/v1/internal/retention/audit_logs/archive', anything)
          .and_raise(StandardError, 'Archive failed')
        allow(api_client).to receive(:post)
          .with('/api/v1/internal/audit_logs', anything)
          .and_return('success' => true)
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
            .and_return('success' => true, 'data' => [audit_log_policy])
          allow(api_client).to receive(:post)
            .with('/api/v1/internal/retention/audit_logs/archive', anything)
            .and_return('success' => true, 'data' => { 'count' => 100 })
          allow(api_client).to receive(:patch).and_return('success' => true)
          allow(api_client).to receive(:post)
            .with('/api/v1/internal/audit_logs', anything)
            .and_return('success' => true)
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
            .and_return('success' => true, 'data' => [anonymize_policy])
          allow(api_client).to receive(:patch)
            .with('/api/v1/internal/retention/audit_logs/anonymize', anything)
            .and_return('success' => true, 'data' => { 'count' => 100 })
          allow(api_client).to receive(:patch).and_return('success' => true)
          allow(api_client).to receive(:post).and_return('success' => true)
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
            .and_return('success' => true, 'data' => [delete_policy])
          allow(api_client).to receive(:post)
            .with('/api/v1/internal/retention/audit_logs/archive', anything)
            .and_return('success' => true, 'data' => { 'count' => 100 })
          allow(api_client).to receive(:patch).and_return('success' => true)
          allow(api_client).to receive(:post)
            .with('/api/v1/internal/audit_logs', anything)
            .and_return('success' => true)
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
          'account_id' => account_id
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
          .and_return('success' => true, 'data' => [session_policy, webhook_policy])
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 25 })
        allow(api_client).to receive(:patch).and_return('success' => true)
        allow(api_client).to receive(:post).and_return('success' => true)
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
          'account_id' => account_id
        }
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_retention_policies', { active: true })
          .and_return('success' => true, 'data' => [analytics_policy])
        allow(api_client).to receive(:patch)
          .with('/api/v1/internal/retention/analytics/anonymize', anything)
          .and_return('success' => true, 'data' => { 'count' => 500 })
        allow(api_client).to receive(:patch).and_return('success' => true)
        allow(api_client).to receive(:post).and_return('success' => true)
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
          .and_return('success' => true, 'data' => [file_policy])
        allow(api_client).to receive(:delete)
          .with('/api/v1/internal/retention/files', anything)
          .and_return('success' => true, 'data' => { 'count' => 10 })
        allow(api_client).to receive(:patch).and_return('success' => true)
        allow(api_client).to receive(:post).and_return('success' => true)
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
          'account_id' => account_id
        }
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/data_retention_policies', { active: true })
          .and_return('success' => true, 'data' => [unsupported_policy])
        allow(api_client).to receive(:patch).and_return('success' => true)
        allow(api_client).to receive(:post).and_return('success' => true)
      end

      it 'handles gracefully with zero records and reports it as unsupported, not enforced' do
        result = job.execute

        expect(result[:policies_processed]).to eq(0)
        expect(result[:records_processed]).to eq(0)
        expect(result[:policy_results].first[:status]).to eq('unsupported')
      end
    end
  end

  # IMP-01a163fa: the index omitted account_id, and a nil account_id was read
  # as "system-wide". These pin that a policy only ever purges its own tenant.
  describe 'tenant scope' do
    let(:job) { described_class.new }
    let(:api_client) { instance_double(BackendApiClient) }
    let(:account_a) { 'account-a' }
    let(:account_b) { 'account-b' }
    let(:retention_calls) { [] }

    def a_policy(data_type, action, overrides = {})
      {
        'id' => "policy-#{data_type}",
        'data_type' => data_type,
        'retention_days' => 30,
        'action' => action,
        'account_id' => account_a
      }.merge(overrides)
    end

    before do
      allow(job).to receive(:api_client).and_return(api_client)
      allow(job).to receive(:log_info)
      allow(job).to receive(:log_error)
      allow(job).to receive(:log_warn)

      %i[post patch delete].each do |verb|
        allow(api_client).to receive(verb) do |path, params|
          retention_calls << { verb: verb, path: path, params: params } if path.start_with?('/api/v1/internal/retention/')
          { 'success' => true, 'data' => { 'count' => 1 } }
        end
      end
    end

    def serve(policies)
      allow(api_client).to receive(:get)
        .with('/api/v1/internal/data_retention_policies', { active: true })
        .and_return('success' => true, 'data' => policies)
    end

    context 'with account-A policies covering every purge path' do
      before do
        serve([
          a_policy('audit_logs', 'archive'),
          a_policy('user_activity', 'anonymize'),
          a_policy('session_logs', 'delete'),
          a_policy('email_logs', 'delete'),
          a_policy('webhook_logs', 'delete'),
          a_policy('api_request_logs', 'delete'),
          a_policy('analytics_data', 'delete'),
          a_policy('file_uploads', 'delete')
        ])
      end

      it 'scopes every purge request to account A and never to account B or all tenants' do
        job.execute

        expect(retention_calls.size).to eq(8)
        retention_calls.each do |call|
          expect(call[:params]).to include(account_id: account_a, scope: 'account'),
                                   "#{call[:verb]} #{call[:path]} sent #{call[:params].inspect}"
          expect(call[:params][:account_id]).not_to eq(account_b)
        end
      end
    end

    context 'with a policy that has no explicit scope (nil account_id)' do
      before { serve([a_policy('session_logs', 'delete', 'account_id' => nil)]) }

      it 'refuses it: no purge request and no enforcement bookkeeping' do
        job.execute

        expect(retention_calls).to be_empty
        expect(api_client).not_to have_received(:patch)
          .with(%r{\A/api/v1/internal/data_retention_policies/}, anything)
      end

      it 'logs the refusal and records it in the per-type results' do
        result = job.execute

        expect(job).to have_received(:log_warn).with(/no explicit scope/)
        expect(result[:policies_processed]).to eq(0)
        expect(result[:policy_results]).to contain_exactly(
          hash_including(policy_id: 'policy-session_logs', data_type: 'session_logs', status: 'skipped_unscoped')
        )
      end
    end

    context 'with a blank-string account_id' do
      before { serve([a_policy('session_logs', 'delete', 'account_id' => '')]) }

      it 'refuses it' do
        job.execute

        expect(retention_calls).to be_empty
      end
    end

    context 'with an account policy that also claims scope "system"' do
      before { serve([a_policy('session_logs', 'delete', 'scope' => 'system')]) }

      it 'refuses the contradictory scope' do
        result = job.execute

        expect(retention_calls).to be_empty
        expect(result[:policy_results].first[:status]).to eq('skipped_unscoped')
      end
    end

    context 'with an explicitly system-wide policy' do
      before { serve([a_policy('session_logs', 'delete', 'account_id' => nil, 'scope' => 'system')]) }

      it 'sends an explicit system scope and no account_id' do
        job.execute

        expect(retention_calls.size).to eq(1)
        expect(retention_calls.first[:params]).to include(scope: 'system')
        expect(retention_calls.first[:params]).not_to have_key(:account_id)
      end
    end
  end

  # IMP-01a163fa: the nightly compliance_check said nothing about whether any
  # purge actually ran, so a job whose every call 404'd looked like success.
  describe 'truthful audit' do
    let(:job) { described_class.new }
    let(:api_client) { instance_double(BackendApiClient) }
    let(:audits) { [] }
    let(:not_found) { BackendApiClient::ApiError.new('Resource not found', 404) }

    let(:policies) do
      [
        { 'id' => 'p1', 'data_type' => 'session_logs', 'retention_days' => 30,
          'action' => 'delete', 'account_id' => 'account-a' },
        { 'id' => 'p2', 'data_type' => 'audit_logs', 'retention_days' => 365,
          'action' => 'archive', 'account_id' => 'account-a' }
      ]
    end

    before do
      allow(job).to receive(:api_client).and_return(api_client)
      allow(job).to receive(:log_info)
      allow(job).to receive(:log_error)
      allow(job).to receive(:log_warn)
      allow(api_client).to receive(:post).with('/api/v1/internal/audit_logs', anything) do |_path, body|
        audits << body
        { 'success' => true }
      end
    end

    def serve(list)
      allow(api_client).to receive(:get)
        .with('/api/v1/internal/data_retention_policies', { active: true })
        .and_return('success' => true, 'data' => list)
    end

    context 'when no policies are configured' do
      before { serve([]) }

      it 'says retention is not configured' do
        job.execute

        expect(audits.size).to eq(1)
        expect(audits.first[:metadata]).to include(outcome: 'not_configured', summary: 'retention not configured')
      end
    end

    context 'when every purge call 404s' do
      before do
        serve(policies)
        allow(api_client).to receive(:delete).and_raise(not_found)
        allow(api_client).to receive(:post).with('/api/v1/internal/retention/audit_logs/archive', anything)
                                           .and_raise(not_found)
        allow(api_client).to receive(:patch).and_return('success' => true)
      end

      it 'reports enforcement failed with the unrouted call count' do
        job.execute

        meta = audits.first[:metadata]
        expect(meta).to include(outcome: 'failed', summary: 'retention enforcement failed: 2 calls unrouted')
        expect(meta[:policies_processed]).to eq(0)
      end

      it 'records a per-type unrouted result and skips the enforcement bookkeeping' do
        job.execute

        expect(audits.first[:metadata][:policy_results]).to contain_exactly(
          hash_including(data_type: 'session_logs', status: 'unrouted', records_processed: 0),
          hash_including(data_type: 'audit_logs', status: 'unrouted', records_processed: 0)
        )
        expect(api_client).not_to have_received(:patch)
      end
    end

    context 'when every purge call fails' do
      before do
        serve(policies)
        allow(api_client).to receive(:delete).and_raise(BackendApiClient::ApiError.new('Backend server error', 500))
        allow(api_client).to receive(:post).with('/api/v1/internal/retention/audit_logs/archive', anything)
                                           .and_raise(BackendApiClient::ApiError.new('Backend server error', 500))
      end

      it 'reports enforcement failed, not a completed check' do
        job.execute

        meta = audits.first[:metadata]
        expect(meta[:outcome]).to eq('failed')
        expect(meta[:summary]).to start_with('retention enforcement failed')
        expect(meta[:policy_results].map { |r| r[:status] }).to all(eq('failed'))
      end
    end

    context 'when every purge call succeeds' do
      before do
        serve(policies)
        allow(api_client).to receive(:delete).and_return('success' => true, 'data' => { 'count' => 4 })
        allow(api_client).to receive(:post).with('/api/v1/internal/retention/audit_logs/archive', anything)
                                           .and_return('success' => true, 'data' => { 'count' => 6 })
        allow(api_client).to receive(:patch).and_return('success' => true)
      end

      it 'reports enforced with per-type record counts' do
        job.execute

        meta = audits.first[:metadata]
        expect(meta[:outcome]).to eq('enforced')
        expect(meta[:policy_results]).to contain_exactly(
          hash_including(data_type: 'session_logs', status: 'enforced', records_processed: 4),
          hash_including(data_type: 'audit_logs', status: 'enforced', records_processed: 6)
        )
      end
    end
  end
end
