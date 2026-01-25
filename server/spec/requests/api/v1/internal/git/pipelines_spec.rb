# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Git::Pipelines', type: :request do
  let(:account) { create(:account) }
  let(:git_provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, account: account, git_provider: git_provider) }
  let(:repository) { create(:git_repository, credential: credential, account: account) }
  let(:pipeline) { create(:git_pipeline, repository: repository, account: account) }

  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/git/pipelines/:id' do
    context 'with valid internal authentication' do
      it 'returns the pipeline' do
        get api_v1_internal_git_pipeline_path(pipeline), headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['id']).to eq(pipeline.id)
        expect(json['data']['name']).to eq(pipeline.name)
        expect(json['data']['status']).to eq(pipeline.status)
      end

      it 'includes repository information' do
        get api_v1_internal_git_pipeline_path(pipeline), headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data']['repository']).to be_present
        expect(json['data']['repository']['id']).to eq(repository.id)
        expect(json['data']['repository']['name']).to eq(repository.name)
        expect(json['data']['repository']['full_name']).to eq(repository.full_name)
      end

      it 'includes associated jobs' do
        job1 = create(:git_pipeline_job, pipeline: pipeline, account: account)
        job2 = create(:git_pipeline_job, pipeline: pipeline, account: account)

        get api_v1_internal_git_pipeline_path(pipeline), headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data']['jobs'].length).to eq(2)
        expect(json['data']['jobs'].map { |j| j['id'] }).to contain_exactly(job1.id, job2.id)
      end

      it 'includes workflow configuration and metadata' do
        pipeline.update!(
          workflow_config: { steps: ['build', 'test'] },
          metadata: { branch: 'main' }
        )

        get api_v1_internal_git_pipeline_path(pipeline), headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data']['workflow_config']).to eq({ 'steps' => ['build', 'test'] })
        expect(json['data']['metadata']).to eq({ 'branch' => 'main' })
      end
    end

    context 'with non-existent pipeline' do
      it 'returns not found' do
        get api_v1_internal_git_pipeline_path(SecureRandom.uuid), headers: internal_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Pipeline not found')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get api_v1_internal_git_pipeline_path(pipeline)

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/internal/git/pipelines/:id' do
    context 'with valid parameters' do
      let(:update_params) do
        {
          status: 'completed',
          conclusion: 'success',
          total_jobs: 5,
          completed_jobs: 5,
          failed_jobs: 0,
          duration_seconds: 120,
          completed_at: Time.current.iso8601
        }
      end

      it 'updates the pipeline' do
        patch api_v1_internal_git_pipeline_path(pipeline),
              params: update_params,
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['status']).to eq('completed')
        expect(json['data']['conclusion']).to eq('success')
        expect(json['data']['total_jobs']).to eq(5)

        pipeline.reload
        expect(pipeline.status).to eq('completed')
        expect(pipeline.conclusion).to eq('success')
      end

      it 'updates workflow configuration' do
        patch api_v1_internal_git_pipeline_path(pipeline),
              params: { workflow_config: { steps: ['deploy'] } },
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        pipeline.reload
        expect(pipeline.workflow_config['steps']).to eq(['deploy'])
      end

      it 'updates metadata' do
        patch api_v1_internal_git_pipeline_path(pipeline),
              params: { metadata: { environment: 'production' } },
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        pipeline.reload
        expect(pipeline.metadata['environment']).to eq('production')
      end
    end

    context 'with invalid parameters' do
      it 'returns unprocessable entity' do
        allow_any_instance_of(Devops::GitPipeline).to receive(:update).and_return(false)
        allow_any_instance_of(Devops::GitPipeline).to receive_message_chain(:errors, :full_messages).and_return(['Invalid status'])

        patch api_v1_internal_git_pipeline_path(pipeline),
              params: { status: 'invalid' },
              headers: internal_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end
  end

  describe 'POST /api/v1/internal/git/pipelines/:id/sync_jobs' do
    context 'with valid job data' do
      let(:jobs_data) do
        [
          {
            external_id: 'job-1',
            name: 'Build',
            status: 'completed',
            conclusion: 'success',
            step_number: 1,
            runner_name: 'ubuntu-latest',
            runner_id: 'runner-1',
            runner_os: 'Linux',
            logs_url: 'https://example.com/logs/1',
            duration_seconds: 60,
            started_at: 1.hour.ago.iso8601,
            completed_at: 30.minutes.ago.iso8601
          },
          {
            external_id: 'job-2',
            name: 'Test',
            status: 'completed',
            conclusion: 'success',
            step_number: 2
          }
        ]
      end

      it 'syncs jobs successfully' do
        post sync_jobs_api_v1_internal_git_pipeline_path(pipeline),
             params: { jobs: jobs_data },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['pipeline_id']).to eq(pipeline.id)
        expect(json['data']['synced_count']).to eq(2)
        expect(json['data']['job_ids'].length).to eq(2)
      end

      it 'creates new jobs' do
        expect {
          post sync_jobs_api_v1_internal_git_pipeline_path(pipeline),
               params: { jobs: jobs_data },
               headers: internal_headers
        }.to change(Devops::GitPipelineJob, :count).by(2)
      end

      it 'updates existing jobs' do
        existing_job = create(:git_pipeline_job,
                              pipeline: pipeline,
                              account: account,
                              external_id: 'job-1',
                              status: 'in_progress')

        post sync_jobs_api_v1_internal_git_pipeline_path(pipeline),
             params: { jobs: jobs_data },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        existing_job.reload
        expect(existing_job.status).to eq('completed')
        expect(existing_job.conclusion).to eq('success')
      end

      it 'updates pipeline job counts' do
        expect_any_instance_of(Devops::GitPipeline).to receive(:update_job_counts!)

        post sync_jobs_api_v1_internal_git_pipeline_path(pipeline),
             params: { jobs: jobs_data },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
      end

      it 'handles empty jobs array' do
        post sync_jobs_api_v1_internal_git_pipeline_path(pipeline),
             params: { jobs: [] },
             headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['data']['synced_count']).to eq(0)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        post sync_jobs_api_v1_internal_git_pipeline_path(pipeline),
             params: { jobs: [] }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
