# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Git::JobLogs', type: :request do
  let(:account) { create(:account) }
  let(:git_provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, account: account, provider: git_provider) }
  let(:repository) { create(:git_repository, credential: credential, account: account) }
  let(:pipeline) { create(:git_pipeline, repository: repository, account: account) }
  let(:job) { create(:git_pipeline_job, pipeline: pipeline, account: account) }

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    token = Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 5.minutes.from_now)
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
        expect(json['message'] || json.dig('data', 'message')).to eq('Log chunk broadcast successfully')
        expect(json['data']['job_id']).to eq(job.id).or eq(job.id.to_s)
        expect(json['data']['offset']).to eq(0)
        expect(json['data']['is_complete']).to be false

        expect(GitJobLogsChannel).to have_received(:broadcast_log_chunk).with(
          job.id,
          content: 'Build step completed',
          offset: 0,
          is_complete: false
        )
      end

      it 'processes log content when present' do
        allow(GitJobLogsChannel).to receive(:broadcast_log_chunk)

        post broadcast_api_v1_internal_git_job_log_path(job.id),
             params: { content: 'Initial logs', offset: 0 },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        expect(GitJobLogsChannel).to have_received(:broadcast_log_chunk)
      end

      it 'handles offset for appended logs' do
        allow(GitJobLogsChannel).to receive(:broadcast_log_chunk)

        post broadcast_api_v1_internal_git_job_log_path(job.id),
             params: { content: ' Additional logs', offset: 100 },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        expect(GitJobLogsChannel).to have_received(:broadcast_log_chunk)
      end

      it 'handles is_complete flag' do
        allow(GitJobLogsChannel).to receive(:broadcast_log_chunk)

        post broadcast_api_v1_internal_git_job_log_path(job.id),
             params: { content: 'Final logs', offset: 0, is_complete: true },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        expect(GitJobLogsChannel).to have_received(:broadcast_log_chunk)
      end

      it 'handles empty content gracefully' do
        allow(GitJobLogsChannel).to receive(:broadcast_log_chunk)

        post broadcast_api_v1_internal_git_job_log_path(job.id),
             params: { offset: 0 },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        expect(GitJobLogsChannel).to have_received(:broadcast_log_chunk).with(
          job.id.to_s,
          content: '',
          offset: 0,
          is_complete: anything
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
        expect(json['message'] || json.dig('data', 'message')).to eq('Error broadcast successfully')
        expect(json['data']['job_id']).to eq(job.id).or eq(job.id.to_s)

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
        expect(json['message'] || json.dig('data', 'message')).to eq('Status broadcast successfully')
        expect(json['data']['job_id']).to eq(job.id).or eq(job.id.to_s)

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
