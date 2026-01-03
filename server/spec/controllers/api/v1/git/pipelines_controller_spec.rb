# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Git::PipelinesController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Permission users
  let(:pipeline_read_user) { create(:user, account: account, permissions: ['git.pipelines.read']) }
  let(:pipeline_manage_user) do
    create(:user, account: account, permissions: %w[
      git.pipelines.read git.pipelines.trigger git.pipelines.cancel git.pipelines.logs
    ])
  end
  let(:user_without_permissions) { create(:user, account: account, permissions: []) }

  let(:provider) { create(:git_provider, :github, supports_ci_cd: true) }
  let(:credential) { create(:git_provider_credential, git_provider: provider, account: account) }
  let(:repository) { create(:git_repository, git_provider_credential: credential, account: account) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
  end

  # =============================================================================
  # PIPELINE LISTING
  # =============================================================================

  describe 'GET #index' do
    let!(:pipeline1) { create(:git_pipeline, git_repository: repository, account: account) }
    let!(:pipeline2) { create(:git_pipeline, git_repository: repository, account: account) }
    let!(:other_pipeline) { create(:git_pipeline) }

    context 'with valid permissions' do
      before { sign_in pipeline_read_user }

      it 'returns pipelines for the account' do
        get :index

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['items'].length).to eq(2)
      end

      it 'filters by repository_id' do
        other_repo = create(:git_repository, git_provider_credential: credential, account: account)
        other_repo_pipeline = create(:git_pipeline, git_repository: other_repo, account: account)

        get :index, params: { repository_id: repository.id }

        json = JSON.parse(response.body)
        pipeline_ids = json['data']['items'].map { |p| p['id'] }
        expect(pipeline_ids).to include(pipeline1.id, pipeline2.id)
        expect(pipeline_ids).not_to include(other_repo_pipeline.id)
      end

      it 'filters by status' do
        running_pipeline = create(:git_pipeline, :running, git_repository: repository, account: account)

        get :index, params: { status: 'running' }

        json = JSON.parse(response.body)
        pipeline_ids = json['data']['items'].map { |p| p['id'] }
        expect(pipeline_ids).to include(running_pipeline.id)
      end

      it 'filters by conclusion' do
        success_pipeline = create(:git_pipeline, :success, git_repository: repository, account: account)
        failure_pipeline = create(:git_pipeline, :failure, git_repository: repository, account: account)

        get :index, params: { conclusion: 'success' }

        json = JSON.parse(response.body)
        pipeline_ids = json['data']['items'].map { |p| p['id'] }
        expect(pipeline_ids).to include(success_pipeline.id)
        expect(pipeline_ids).not_to include(failure_pipeline.id)
      end

      it 'includes pagination metadata' do
        get :index

        json = JSON.parse(response.body)
        expect(json['data']['pagination']).to be_present
      end
    end

    context 'without permissions' do
      before { sign_in user_without_permissions }

      it 'returns forbidden error' do
        get :index

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #show' do
    let(:pipeline) { create(:git_pipeline, git_repository: repository, account: account) }
    let!(:job1) { create(:git_pipeline_job, git_pipeline: pipeline, account: account) }
    let!(:job2) { create(:git_pipeline_job, git_pipeline: pipeline, account: account) }

    context 'with valid permissions' do
      before { sign_in pipeline_read_user }

      it 'returns pipeline details' do
        get :show, params: { id: pipeline.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['pipeline']['id']).to eq(pipeline.id)
      end

      it 'includes pipeline jobs' do
        get :show, params: { id: pipeline.id }

        json = JSON.parse(response.body)
        expect(json['data']['pipeline']['jobs'].length).to eq(2)
      end
    end

    context 'when pipeline belongs to another account' do
      let(:other_pipeline) { create(:git_pipeline) }
      before { sign_in pipeline_read_user }

      it 'returns not found error' do
        get :show, params: { id: other_pipeline.id }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # =============================================================================
  # PIPELINE ACTIONS
  # =============================================================================

  describe 'POST #trigger' do
    let(:mock_client) { double('GitApiClient') }

    before do
      allow(::Git::ApiClient).to receive(:for).and_return(mock_client)
      allow(mock_client).to receive(:trigger_workflow).and_return({
        success: true,
        pipeline_id: 'new_pipeline_123'
      })
    end

    context 'with valid permissions' do
      before { sign_in pipeline_manage_user }

      it 'triggers a new pipeline' do
        post :trigger, params: {
          repository_id: repository.id,
          workflow: 'ci.yml',
          ref: 'main'
        }

        expect(response).to have_http_status(:accepted)
        json = JSON.parse(response.body)
        expect(json['data']['message']).to include('triggered')
      end
    end

    context 'without permissions' do
      before { sign_in pipeline_read_user }

      it 'returns forbidden error' do
        post :trigger, params: {
          repository_id: repository.id,
          workflow: 'ci.yml',
          ref: 'main'
        }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #cancel' do
    let(:pipeline) { create(:git_pipeline, :running, git_repository: repository, account: account) }
    let(:mock_client) { double('GitApiClient') }

    before do
      allow(::Git::ApiClient).to receive(:for).and_return(mock_client)
      allow(mock_client).to receive(:cancel_workflow_run).and_return({ success: true })
    end

    context 'with valid permissions' do
      before { sign_in pipeline_manage_user }

      it 'cancels the pipeline' do
        post :cancel, params: { id: pipeline.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['message']).to include('cancelled')
      end
    end

    context 'when pipeline is not running' do
      let(:completed_pipeline) { create(:git_pipeline, :completed, git_repository: repository, account: account) }
      before { sign_in pipeline_manage_user }

      it 'returns error' do
        post :cancel, params: { id: completed_pipeline.id }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'POST #retry' do
    let(:pipeline) { create(:git_pipeline, :failure, git_repository: repository, account: account) }
    let(:mock_client) { double('GitApiClient') }
    let(:job_class) { Class.new { def self.perform_async(*args); end } }

    before do
      stub_const('Git::PipelineSyncJob', job_class)
      allow(::Git::ApiClient).to receive(:for).and_return(mock_client)
      allow(mock_client).to receive(:rerun_workflow).and_return({
        success: true,
        pipeline_id: 'rerun_123'
      })
    end

    context 'with valid permissions' do
      before { sign_in pipeline_manage_user }

      it 'retries the pipeline' do
        post :retry, params: { id: pipeline.id }

        expect(response).to have_http_status(:accepted)
        json = JSON.parse(response.body)
        expect(json['data']['message']).to include('retr')
      end
    end

    context 'when pipeline was successful' do
      let(:success_pipeline) { create(:git_pipeline, :success, git_repository: repository, account: account) }
      before { sign_in pipeline_manage_user }

      it 'returns error' do
        post :retry, params: { id: success_pipeline.id }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  # =============================================================================
  # PIPELINE JOBS
  # =============================================================================

  describe 'GET #jobs' do
    let(:pipeline) { create(:git_pipeline, git_repository: repository, account: account) }
    let!(:job1) { create(:git_pipeline_job, :running, git_pipeline: pipeline, account: account) }
    let!(:job2) { create(:git_pipeline_job, :success, git_pipeline: pipeline, account: account) }

    context 'with valid permissions' do
      before { sign_in pipeline_read_user }

      it 'returns pipeline jobs' do
        get :jobs, params: { id: pipeline.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['jobs'].length).to eq(2)
      end
    end
  end

  describe 'GET #job_logs' do
    let(:pipeline) { create(:git_pipeline, git_repository: repository, account: account) }
    let(:job) { create(:git_pipeline_job, :with_logs, git_pipeline: pipeline, account: account) }

    context 'with valid permissions' do
      before { sign_in pipeline_manage_user }

      it 'returns job logs' do
        get :job_logs, params: { pipeline_id: pipeline.id, id: job.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['logs']).to be_present
      end
    end

    context 'without logs permission' do
      before { sign_in pipeline_read_user }

      it 'returns forbidden error' do
        get :job_logs, params: { pipeline_id: pipeline.id, id: job.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # =============================================================================
  # PIPELINE STATISTICS
  # =============================================================================

  describe 'GET #stats' do
    before do
      create_list(:git_pipeline, 5, :success, git_repository: repository, account: account)
      create_list(:git_pipeline, 2, :failure, git_repository: repository, account: account)
      create(:git_pipeline, :running, git_repository: repository, account: account)
    end

    context 'with valid permissions' do
      before { sign_in pipeline_read_user }

      it 'returns pipeline statistics' do
        get :stats

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['stats']).to include(
          'total_runs',
          'success_rate',
          'active_runs'
        )
      end

      it 'filters stats by repository' do
        get :stats, params: { repository_id: repository.id }

        expect(response).to have_http_status(:success)
      end
    end
  end
end
