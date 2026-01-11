# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Internal::Git::PipelinesController, type: :controller do
  let(:account) { create(:account) }
  let(:provider) { create(:git_provider, :github, supports_ci_cd: true) }
  let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
  let(:repository) { create(:git_repository, credential: credential, account: account) }
  let(:pipeline) do
    create(:git_pipeline,
           repository: repository,
           account: account,
           name: 'CI Build',
           status: 'in_progress')
  end

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
    set_service_auth_headers
  end

  # =============================================================================
  # SHOW
  # =============================================================================

  describe 'GET #show' do
    it 'returns pipeline details' do
      get :show, params: { id: pipeline.id }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['id']).to eq(pipeline.id)
      expect(json['data']['name']).to eq('CI Build')
      expect(json['data']['status']).to eq('in_progress')
    end

    it 'includes repository information' do
      get :show, params: { id: pipeline.id }

      json = JSON.parse(response.body)
      expect(json['data']['repository']['id']).to eq(repository.id)
      expect(json['data']['repository']['full_name']).to eq(repository.full_name)
      expect(json['data']['repository']['credential_id']).to eq(credential.id)
    end

    it 'includes pipeline jobs' do
      job1 = create(:git_pipeline_job, pipeline: pipeline, account: account, name: 'build')
      job2 = create(:git_pipeline_job, pipeline: pipeline, account: account, name: 'test')

      get :show, params: { id: pipeline.id }

      json = JSON.parse(response.body)
      expect(json['data']['jobs'].length).to eq(2)
      expect(json['data']['jobs'].map { |j| j['name'] }).to include('build', 'test')
    end

    it 'returns not found for non-existent pipeline' do
      get :show, params: { id: SecureRandom.uuid }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['success']).to be false
    end
  end

  # =============================================================================
  # UPDATE
  # =============================================================================

  describe 'PATCH #update' do
    it 'updates pipeline status' do
      patch :update, params: {
        id: pipeline.id,
        status: 'completed',
        conclusion: 'success'
      }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true

      pipeline.reload
      expect(pipeline.status).to eq('completed')
      expect(pipeline.conclusion).to eq('success')
    end

    it 'recalculates job counts from actual jobs on save' do
      # Create some jobs for the pipeline
      create(:git_pipeline_job, pipeline: pipeline, account: account, status: 'completed', conclusion: 'success')
      create(:git_pipeline_job, pipeline: pipeline, account: account, status: 'completed', conclusion: 'success')
      create(:git_pipeline_job, pipeline: pipeline, account: account, status: 'completed', conclusion: 'failure')

      # Trigger an update to recalculate counts
      patch :update, params: {
        id: pipeline.id,
        status: 'completed'
      }

      expect(response).to have_http_status(:success)
      pipeline.reload
      expect(pipeline.total_jobs).to eq(3)
      expect(pipeline.completed_jobs).to eq(3)  # All have status 'completed'
      expect(pipeline.failed_jobs).to eq(1)     # One has conclusion 'failure'
    end

    it 'updates timestamps' do
      start_time = 1.hour.ago
      end_time = Time.current

      patch :update, params: {
        id: pipeline.id,
        started_at: start_time.iso8601,
        completed_at: end_time.iso8601,
        duration_seconds: 3600
      }

      expect(response).to have_http_status(:success)
      pipeline.reload
      expect(pipeline.started_at).to be_within(1.second).of(start_time)
      expect(pipeline.completed_at).to be_within(1.second).of(end_time)
      expect(pipeline.duration_seconds).to eq(3600)
    end

    it 'can update workflow config' do
      patch :update, params: {
        id: pipeline.id,
        workflow_config: { name: 'ci.yml', path: '.github/workflows/ci.yml' }
      }

      expect(response).to have_http_status(:success)
      pipeline.reload
      expect(pipeline.workflow_config['name']).to eq('ci.yml')
    end
  end

  # =============================================================================
  # SYNC JOBS
  # =============================================================================

  describe 'POST #sync_jobs' do
    let(:jobs_data) do
      [
        {
          external_id: 'job_1',
          name: 'build',
          status: 'completed',
          conclusion: 'success',
          step_number: 1,
          runner_name: 'ubuntu-latest',
          runner_os: 'Linux',
          duration_seconds: 120,
          started_at: 1.hour.ago.iso8601,
          completed_at: 58.minutes.ago.iso8601,
          steps: [
            { name: 'Checkout', status: 'completed', conclusion: 'success' },
            { name: 'Build', status: 'completed', conclusion: 'success' }
          ]
        },
        {
          external_id: 'job_2',
          name: 'test',
          status: 'in_progress',
          step_number: 2,
          runner_name: 'ubuntu-latest',
          runner_os: 'Linux',
          started_at: 55.minutes.ago.iso8601
        },
        {
          external_id: 'job_3',
          name: 'deploy',
          status: 'queued',
          step_number: 3
        }
      ]
    end

    it 'creates job records' do
      expect {
        post :sync_jobs, params: { id: pipeline.id, jobs: jobs_data }
      }.to change(Devops::GitPipelineJob, :count).by(3)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['synced_count']).to eq(3)
    end

    it 'updates existing jobs' do
      existing_job = create(:git_pipeline_job,
                            pipeline: pipeline,
                            account: account,
                            external_id: 'job_1',
                            status: 'in_progress')

      expect {
        post :sync_jobs, params: { id: pipeline.id, jobs: jobs_data }
      }.to change(Devops::GitPipelineJob, :count).by(2) # Only 2 new

      existing_job.reload
      expect(existing_job.status).to eq('completed')
      expect(existing_job.conclusion).to eq('success')
    end

    it 'includes job steps' do
      post :sync_jobs, params: { id: pipeline.id, jobs: jobs_data }

      job = Devops::GitPipelineJob.find_by(external_id: 'job_1')
      expect(job.steps).to be_present
      expect(job.steps.first['name']).to eq('Checkout')
    end

    it 'updates pipeline job counts' do
      post :sync_jobs, params: { id: pipeline.id, jobs: jobs_data }

      pipeline.reload
      expect(pipeline.total_jobs).to be_present
    end

    it 'associates jobs with account' do
      post :sync_jobs, params: { id: pipeline.id, jobs: jobs_data }

      json = JSON.parse(response.body)
      job_id = json['data']['job_ids'].first
      job = Devops::GitPipelineJob.find(job_id)
      expect(job.account_id).to eq(account.id)
    end

    it 'handles empty jobs list' do
      post :sync_jobs, params: { id: pipeline.id, jobs: [] }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['data']['synced_count']).to eq(0)
    end
  end

  # =============================================================================
  # AUTHENTICATION
  # =============================================================================

  describe 'authentication' do
    it 'requires service token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :show, params: { id: pipeline.id }

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
