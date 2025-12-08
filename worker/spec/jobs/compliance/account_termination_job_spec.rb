# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Compliance::AccountTerminationJob, type: :job do
  subject { described_class }

  it_behaves_like 'a base job', described_class
  it_behaves_like 'a job with API communication'
  it_behaves_like 'a job with retry logic'
  it_behaves_like 'a job with logging'

  let(:termination_id) { 'term-123' }
  let(:account_id) { 'account-456' }
  let(:user_id) { 'user-789' }
  let(:job_args) { nil }

  let(:termination_data) do
    {
      'id' => termination_id,
      'account_id' => account_id,
      'status' => 'grace_period',
      'owner_email' => 'owner@example.com',
      'grace_period_ends_at' => 1.day.ago.iso8601,
      'termination_log' => []
    }
  end

  let(:users_data) do
    [{ 'id' => user_id, 'email' => 'user@example.com' }]
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

    context 'when processing ready terminations' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return(success: true, data: [termination_data])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return(success: true, data: [])
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/users")
          .and_return(success: true, data: users_data)
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:delete).and_return(success: true, data: { 'count' => 5 })
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'fetches ready terminations from API' do
        expect(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })

        job.execute
      end

      it 'processes each ready termination' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/account_terminations/#{termination_id}",
            hash_including(status: 'processing')
          )

        job.execute
      end

      it 'deletes user data' do
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/users/#{user_id}/consents")

        job.execute
      end

      it 'anonymizes audit logs' do
        expect(api_client).to receive(:patch)
          .with("/api/v1/internal/users/#{user_id}/anonymize_audit_logs", {})

        job.execute
      end

      it 'deletes account files' do
        expect(api_client).to receive(:delete)
          .with("/api/v1/internal/accounts/#{account_id}/files")

        job.execute
      end

      it 'marks account as terminated' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/accounts/#{account_id}",
            hash_including(status: 'terminated')
          )

        job.execute
      end

      it 'sends completion notification' do
        expect(api_client).to receive(:post)
          .with(
            '/api/v1/internal/notifications/send',
            hash_including(type: 'account_termination_complete')
          )

        job.execute
      end

      it 'returns results summary' do
        result = job.execute

        expect(result[:processed]).to eq(1)
        expect(result[:errors]).to be_empty
      end
    end

    context 'when no terminations are ready' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return(success: true, data: [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return(success: true, data: [])
      end

      it 'completes without processing' do
        result = job.execute

        expect(result[:processed]).to eq(0)
      end
    end

    context 'when sending termination reminders' do
      let(:reminder_termination) do
        termination_data.merge('grace_period_ends_at' => 7.days.from_now.iso8601)
      end

      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return(success: true, data: [])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return(success: true, data: [reminder_termination])
        allow(api_client).to receive(:patch).and_return(success: true)
        allow(api_client).to receive(:post).and_return(success: true)
      end

      it 'sends 7-day reminder notification' do
        expect(api_client).to receive(:post)
          .with(
            '/api/v1/internal/notifications/send',
            hash_including(type: 'account_termination_reminder')
          )

        job.execute
      end

      it 'updates termination log with reminder sent' do
        expect(api_client).to receive(:patch)
          .with(
            "/api/v1/internal/account_terminations/#{termination_id}",
            hash_including(:termination_log)
          )

        job.execute
      end

      it 'returns reminders sent count' do
        result = job.execute

        expect(result[:reminders_sent]).to eq(1)
      end
    end

    context 'when termination processing fails' do
      before do
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period', grace_period_expired: true })
          .and_return(success: true, data: [termination_data])
        allow(api_client).to receive(:get)
          .with('/api/v1/internal/account_terminations', { status: 'grace_period' })
          .and_return(success: true, data: [])
        allow(api_client).to receive(:get)
          .with("/api/v1/internal/accounts/#{account_id}/users")
          .and_return(success: true, data: users_data)
        allow(api_client).to receive(:patch)
          .and_raise(StandardError, 'API error')
      end

      it 'logs error and continues' do
        expect(job).to receive(:log_error).with(/Failed to process termination/)

        result = job.execute

        expect(result[:errors]).not_to be_empty
      end
    end
  end
end
