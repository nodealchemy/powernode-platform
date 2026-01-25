# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Git::JobLogs', type: :request do
  let(:account) { create(:account) }
  let(:git_provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, account: account, git_provider: git_provider) }
  let(:repository) { create(:git_repository, credential: credential, account: account) }
  let(:pipeline) { create(:git_pipeline, repository: repository, account: account) }
  let(:job) { create(:git_pipeline_job, pipeline: pipeline, account: account) }

  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'POST /api/v1/internal/git/job_logs/:id/broadcast' do
    context 'with valid parameters' do
      let(:broadcast_params) do
        {
          content: 'Build step completed',
          offset: 0,
          is_complete: false
        }
      end

      it 'broadcasts log chunk successfully' do
        allow(GitJobLogsChannel).to receive(:broadcast_log_chunk)

        post broadcast_api_v1_internal_git_job_log_path(job.id),
             params: broadcast_params,
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['message']).to eq('Log chunk broadcast successfully')
        expect(json['data']['job_id']).to eq(job.id)
        expect(json['data']['offset']).to eq(0)
        expect(json['data']['is_complete']).to be false

        expect(GitJobLogsChannel).to have_received(:broadcast_log_chunk).with(
          job.id,
          content: 'Build step completed',
          offset: 0,
          is_complete: false
        )
      end

      it 'caches logs in database when content is present' do
        allow(GitJobLogsChannel).to receive(:broadcast_log_chunk)

        post broadcast_api_v1_internal_git_job_log_path(job.id),
             params: { content: 'Initial logs', offset: 0 },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        job.reload
        expect(job.cached_logs).to eq('Initial logs')
      end

      it 'appends logs when offset is greater than zero' do
        job.update!(cached_logs: 'Initial logs')
        allow(GitJobLogsChannel).to receive(:broadcast_log_chunk)

        post broadcast_api_v1_internal_git_job_log_path(job.id),
             params: { content: ' Additional logs', offset: 'Initial logs'.bytesize },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        job.reload
        expect(job.cached_logs).to eq('Initial logs Additional logs')
      end

      it 'marks logs as complete when is_complete is true' do
        allow(GitJobLogsChannel).to receive(:broadcast_log_chunk)

        post broadcast_api_v1_internal_git_job_log_path(job.id),
             params: { content: 'Final logs', offset: 0, is_complete: true },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        job.reload
        expect(job.logs_complete).to be true
      end

      it 'handles empty content gracefully' do
        allow(GitJobLogsChannel).to receive(:broadcast_log_chunk)

        post broadcast_api_v1_internal_git_job_log_path(job.id),
             params: { offset: 0 },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        expect(GitJobLogsChannel).to have_received(:broadcast_log_chunk).with(
          job.id,
          content: '',
          offset: 0,
          is_complete: false
        )
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        post broadcast_api_v1_internal_git_job_log_path(job.id),
             params: { content: 'Test logs' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/git/job_logs/:id/error' do
    context 'with valid parameters' do
      it 'broadcasts error message successfully' do
        allow(GitJobLogsChannel).to receive(:broadcast_log_error)

        post error_api_v1_internal_git_job_log_path(job.id),
             params: { error: 'Build failed with exit code 1' },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['message']).to eq('Error broadcast successfully')
        expect(json['data']['job_id']).to eq(job.id)

        expect(GitJobLogsChannel).to have_received(:broadcast_log_error).with(
          job.id,
          error: 'Build failed with exit code 1'
        )
      end

      it 'uses default error message when not provided' do
        allow(GitJobLogsChannel).to receive(:broadcast_log_error)

        post error_api_v1_internal_git_job_log_path(job.id),
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        expect(GitJobLogsChannel).to have_received(:broadcast_log_error).with(
          job.id,
          error: 'Unknown error'
        )
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        post error_api_v1_internal_git_job_log_path(job.id),
             params: { error: 'Build failed' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/internal/git/job_logs/:id/status' do
    context 'with valid parameters' do
      it 'broadcasts job status successfully' do
        allow(GitJobLogsChannel).to receive(:broadcast_job_status)

        post status_api_v1_internal_git_job_log_path(job.id),
             params: { status: 'completed', conclusion: 'success' },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['message']).to eq('Status broadcast successfully')
        expect(json['data']['job_id']).to eq(job.id)

        expect(GitJobLogsChannel).to have_received(:broadcast_job_status).with(
          job.id,
          status: 'completed',
          conclusion: 'success'
        )
      end

      it 'handles status without conclusion' do
        allow(GitJobLogsChannel).to receive(:broadcast_job_status)

        post status_api_v1_internal_git_job_log_path(job.id),
             params: { status: 'in_progress' },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        expect(GitJobLogsChannel).to have_received(:broadcast_job_status).with(
          job.id,
          status: 'in_progress',
          conclusion: nil
        )
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        post status_api_v1_internal_git_job_log_path(job.id),
             params: { status: 'completed' }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
