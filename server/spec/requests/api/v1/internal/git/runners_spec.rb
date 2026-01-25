# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Git::Runners', type: :request do
  let(:account) { create(:account) }
  let(:git_provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, account: account, git_provider: git_provider) }
  let(:repository) { create(:git_repository, credential: credential, account: account) }
  let(:runner) { create(:git_runner, credential: credential, account: account) }

  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'POST /api/v1/internal/git/runners/sync' do
    context 'with valid parameters' do
      let(:runners_data) do
        [
          {
            external_id: 'runner-1',
            name: 'Ubuntu Runner',
            status: 'online',
            busy: false,
            runner_scope: 'repository',
            labels: ['ubuntu', 'self-hosted'],
            os: 'Linux',
            architecture: 'x64',
            version: '2.300.0'
          },
          {
            external_id: 'runner-2',
            name: 'macOS Runner',
            status: 'online',
            busy: true,
            runner_scope: 'organization',
            labels: ['macos'],
            os: 'macOS',
            architecture: 'arm64'
          }
        ]
      end

      it 'syncs runners successfully' do
        allow(Devops::GitRunner).to receive(:sync_from_provider).and_return(runner)

        post sync_api_v1_internal_git_runners_path,
             params: {
               credential_id: credential.id,
               repository_id: repository.id,
               runners: runners_data
             },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['synced_count']).to eq(2)
        expect(json['data']['runners'].length).to eq(2)

        expect(Devops::GitRunner).to have_received(:sync_from_provider).twice
      end

      it 'syncs without repository_id for organization runners' do
        allow(Devops::GitRunner).to receive(:sync_from_provider).and_return(runner)

        post sync_api_v1_internal_git_runners_path,
             params: {
               credential_id: credential.id,
               runners: runners_data
             },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['synced_count']).to eq(2)
      end

      it 'includes runner details in response' do
        allow(Devops::GitRunner).to receive(:sync_from_provider).and_return(runner)

        post sync_api_v1_internal_git_runners_path,
             params: {
               credential_id: credential.id,
               runners: [runners_data.first]
             },
             headers: internal_headers

        json = JSON.parse(response.body)
        runner_data = json['data']['runners'].first
        expect(runner_data).to have_key('id')
        expect(runner_data).to have_key('external_id')
        expect(runner_data).to have_key('name')
        expect(runner_data).to have_key('status')
        expect(runner_data).to have_key('success_rate')
      end
    end

    context 'with non-existent credential' do
      it 'returns not found' do
        post sync_api_v1_internal_git_runners_path,
             params: {
               credential_id: SecureRandom.uuid,
               runners: []
             },
             headers: internal_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end

    context 'with sync errors' do
      it 'handles errors gracefully' do
        allow(Devops::GitRunner).to receive(:sync_from_provider).and_raise(StandardError.new('Sync failed'))

        post sync_api_v1_internal_git_runners_path,
             params: {
               credential_id: credential.id,
               runners: [{ external_id: 'runner-1' }]
             },
             headers: internal_headers

        expect(response).to have_http_status(:internal_server_error)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        post sync_api_v1_internal_git_runners_path,
             params: { credential_id: credential.id, runners: [] }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PUT /api/v1/internal/git/runners/:id/status' do
    context 'with valid parameters' do
      it 'updates runner status successfully' do
        last_seen = Time.current

        put update_status_api_v1_internal_git_runner_path(runner),
            params: {
              status: 'offline',
              busy: false,
              last_seen_at: last_seen.iso8601
            },
            headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['runner']['status']).to eq('offline')
        expect(json['data']['runner']['busy']).to be false

        runner.reload
        expect(runner.status).to eq('offline')
        expect(runner.busy).to be false
        expect(runner.last_seen_at).to be_within(1.second).of(last_seen)
      end

      it 'defaults last_seen_at to current time if not provided' do
        freeze_time do
          put update_status_api_v1_internal_git_runner_path(runner),
              params: { status: 'online', busy: true },
              headers: internal_headers

          expect(response).to have_http_status(:ok)
          runner.reload
          expect(runner.last_seen_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'updates busy status independently' do
        put update_status_api_v1_internal_git_runner_path(runner),
            params: { busy: true },
            headers: internal_headers

        expect(response).to have_http_status(:ok)
        runner.reload
        expect(runner.busy).to be true
      end
    end

    context 'with non-existent runner' do
      it 'returns not found' do
        put update_status_api_v1_internal_git_runner_path(SecureRandom.uuid),
            params: { status: 'online' },
            headers: internal_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        put update_status_api_v1_internal_git_runner_path(runner),
            params: { status: 'online' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/git/runners/:id/job_completed' do
    context 'with successful job' do
      it 'records success' do
        expect_any_instance_of(Devops::GitRunner).to receive(:record_success!)

        post job_completed_api_v1_internal_git_runner_path(runner),
             params: { success: true },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['runner']['id']).to eq(runner.id)
      end

      it 'updates runner metrics' do
        initial_count = runner.total_jobs_run || 0

        post job_completed_api_v1_internal_git_runner_path(runner),
             params: { success: true },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        runner.reload
        expect(runner.total_jobs_run).to eq(initial_count + 1)
      end
    end

    context 'with failed job' do
      it 'records failure' do
        expect_any_instance_of(Devops::GitRunner).to receive(:record_failure!)

        post job_completed_api_v1_internal_git_runner_path(runner),
             params: { success: false },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end

      it 'updates failure metrics' do
        post job_completed_api_v1_internal_git_runner_path(runner),
             params: { success: false },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        runner.reload
        expect(runner.total_jobs_run).to be >= 1
      end
    end

    context 'with non-existent runner' do
      it 'returns not found' do
        post job_completed_api_v1_internal_git_runner_path(SecureRandom.uuid),
             params: { success: true },
             headers: internal_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        post job_completed_api_v1_internal_git_runner_path(runner),
             params: { success: true }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
