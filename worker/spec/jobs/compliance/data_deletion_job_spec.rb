# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Compliance::DataDeletionJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:deletion_request_id) { 'del-req-123' }
  let(:user_id) { 'user-456' }
  let(:account_id) { 'account-789' }
  let(:job_args) { deletion_request_id }

  let(:deletion_request_data) do
    {
      'id' => deletion_request_id,
      'user_id' => user_id,
      'account_id' => account_id,
      'status' => 'approved',
      'deletion_type' => 'full',
      'user_email' => 'user@example.com',
      'grace_period_ends_at' => 1.day.ago.iso8601,
      'data_types_to_retain' => []
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

    context 'when deletion request is approved and grace period expired' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(success: true, data: deletion_request_data)
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:delete).and_return(success: true, data: { 'deleted_count' => 5 })
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'fetches the deletion request from API' do
        expect(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")

        job.execute(deletion_request_id)
      end

      it 'updates status to processing' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(status: 'processing')
          )

        job.execute(deletion_request_id)
      end

      it 'deletes user data types' do
        expect(api_client).to receive(:delete).at_least(:once)

        job.execute(deletion_request_id)
      end

      it 'anonymizes audit logs' do
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/users/#{user_id}/anonymize_audit_logs", {})

        job.execute(deletion_request_id)
      end

      it 'marks request as completed' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/data_deletion_requests/#{deletion_request_id}",
            hash_including(status: 'completed')
          )

        job.execute(deletion_request_id)
      end

      it 'sends completion notification' do
        expect(api_client).to receive(:post)
          .with(
            '/api/v1/internal/notifications/send',
            hash_including(type: 'data_deletion_complete')
          )

        job.execute(deletion_request_id)
      end
    end

    context 'when deletion request is not approved' do
      let(:unapproved_request) { deletion_request_data.merge('status' => 'pending') }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(success: true, data: unapproved_request)
      end

      it 'skips processing' do
        expect(api_client).not_to receive(:patch)
        expect(job).to receive(:log_info).with(/not approved/)

        job.execute(deletion_request_id)
      end
    end

    context 'when still in grace period' do
      let(:in_grace_request) { deletion_request_data.merge('grace_period_ends_at' => 1.day.from_now.iso8601) }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(success: true, data: in_grace_request)
      end

      it 'skips processing' do
        expect(api_client).not_to receive(:patch)
        expect(job).to receive(:log_info).with(/grace period/)

        job.execute(deletion_request_id)
      end
    end

    context 'when API request fails' do
      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(success: false, error: 'Not found')
      end

      it 'raises an error' do
        expect { job.execute(deletion_request_id) }
          .to raise_error(/Failed to fetch deletion request/)
      end
    end

    context 'with partial deletion type' do
      let(:partial_request) do
        deletion_request_data.merge(
          'deletion_type' => 'partial',
          'data_types_to_delete' => %w[activity files]
        )
      end

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(success: true, data: partial_request)
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:delete).and_return(success: true, data: { 'deleted_count' => 3 })
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'only deletes specified data types' do
        expect(api_client).to receive(:delete)
          .with('/api/v1/internal/data_deletion/activity', anything)
        expect(api_client).to receive(:delete)
          .with('/api/v1/internal/data_deletion/files', anything)

        job.execute(deletion_request_id)
      end
    end

    context 'with anonymization type' do
      let(:anonymize_request) { deletion_request_data.merge('deletion_type' => 'anonymize') }

      before do
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/data_deletion_requests/#{deletion_request_id}")
          .and_return(success: true, data: anonymize_request)
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'anonymizes user instead of deleting' do
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/users/#{user_id}/anonymize", anything)

        job.execute(deletion_request_id)
      end
    end
  end
end
