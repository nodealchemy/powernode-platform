# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Git::Pipelines', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: [ 'git.pipelines.read' ]) }
  let(:user_with_trigger_permission) { create(:user, account: account, permissions: [ 'git.pipelines.read', 'git.pipelines.trigger' ]) }
  let(:user_with_cancel_permission) { create(:user, account: account, permissions: [ 'git.pipelines.read', 'git.pipelines.cancel' ]) }
  let(:user_with_logs_permission) { create(:user, account: account, permissions: [ 'git.pipelines.read', 'git.pipelines.logs' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  let(:provider) { create(:git_provider, :github) }
  let(:credential) { create(:git_provider_credential, account: account, provider: provider) }
  let(:repository) { create(:git_repository, account: account, provider: provider, credential: credential) }

  describe 'GET /api/v1/git/pipelines' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:git_pipeline, 3, account: account, repository: repository)
    end

    context 'with git.pipelines.read permission' do
      it 'returns list of pipelines' do
        get '/api/v1/git/pipelines', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['items']).to be_an(Array)
        expect(response_data['data']['items'].length).to eq(3)
      end

      it 'includes pipeline details' do
        get '/api/v1/git/pipelines', headers: headers, as: :json

        response_data = json_response
        first_pipeline = response_data['data']['items'].first

        expect(first_pipeline).to include('id', 'name', 'status', 'conclusion', 'ref')
      end

      it 'includes pagination' do
        get '/api/v1/git/pipelines', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['pagination']).to include('current_page', 'total_count', 'total_pages')
      end

      it 'filters by repository_id' do
        other_repo = create(:git_repository, account: account, provider: provider, credential: credential)
        create(:git_pipeline, account: account, repository: other_repo)

        get '/api/v1/git/pipelines',
            params: { repository_id: other_repo.id },
            headers: headers

        expect_success_response
        response_data = json_response

        repo_ids = response_data['data']['items'].map { |p| p['repository_id'] }
        expect(repo_ids.uniq).to eq([ other_repo.id ])
      end

      it 'filters by status' do
        create(:git_pipeline, :running, account: account, repository: repository)

        get '/api/v1/git/pipelines',
            params: { status: 'running' },
            headers: headers

        expect_success_response
        response_data = json_response

        statuses = response_data['data']['items'].map { |p| p['status'] }
        expect(statuses.uniq).to eq([ 'in_progress' ])
      end

      it 'filters by conclusion' do
        create(:git_pipeline, :failure, account: account, repository: repository)

        get '/api/v1/git/pipelines',
            params: { conclusion: 'failure' },
            headers: headers

        expect_success_response
        response_data = json_response

        conclusions = response_data['data']['items'].map { |p| p['conclusion'] }
        expect(conclusions.uniq).to eq([ 'failure' ])
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/git/pipelines', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/git/pipelines', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/git/pipelines/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:pipeline) { create(:git_pipeline, account: account, repository: repository) }

    context 'with git.pipelines.read permission' do
      it 'returns pipeline details' do
        get "/api/v1/git/pipelines/#{pipeline.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['pipeline']).to include(
          'id' => pipeline.id,
          'name' => pipeline.name,
          'status' => pipeline.status
        )
      end

      it 'includes jobs' do
        create(:git_pipeline_job, pipeline: pipeline)

        get "/api/v1/git/pipelines/#{pipeline.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['pipeline']).to have_key('jobs')
      end

      it 'includes workflow config' do
        get "/api/v1/git/pipelines/#{pipeline.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['pipeline']).to have_key('workflow_config')
      end
    end

    context 'when pipeline does not exist' do
      it 'returns not found error' do
        get '/api/v1/git/pipelines/nonexistent-id', headers: headers, as: :json

        expect_error_response('Pipeline not found', 404)
      end
    end

    context 'when accessing other account pipeline' do
      let(:other_account) { create(:account) }
      let(:other_provider) { create(:git_provider) }
      let(:other_credential) { create(:git_provider_credential, account: other_account, provider: other_provider) }
      let(:other_repo) { create(:git_repository, account: other_account, provider: other_provider, credential: other_credential) }
      let(:other_pipeline) { create(:git_pipeline, account: other_account, repository: other_repo) }

      it 'returns not found error' do
        get "/api/v1/git/pipelines/#{other_pipeline.id}", headers: headers, as: :json

        expect_error_response('Pipeline not found', 404)
      end
    end
  end

  describe 'POST /api/v1/git/pipelines/:id/cancel' do
    let(:headers) { auth_headers_for(user_with_cancel_permission) }
    let(:pipeline) { create(:git_pipeline, :running, account: account, repository: repository) }

    context 'with git.pipelines.cancel permission' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(true)
        client_double = double('api_client', cancel_workflow_run: { success: true })
        allow(Devops::Git::ApiClient).to receive(:for).and_return(client_double)
      end

      it 'cancels running pipeline' do
        post "/api/v1/git/pipelines/#{pipeline.id}/cancel", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['message']).to include('cancelled')
      end

      it 'prevents cancelling non-running pipeline' do
        completed_pipeline = create(:git_pipeline, :completed, account: account, repository: repository)

        post "/api/v1/git/pipelines/#{completed_pipeline.id}/cancel", headers: headers, as: :json

        expect_error_response('Pipeline is not running', 422)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post "/api/v1/git/pipelines/#{pipeline.id}/cancel", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/git/pipelines/:id/retry' do
    let(:headers) { auth_headers_for(user_with_trigger_permission) }
    let(:pipeline) { create(:git_pipeline, :failure, account: account, repository: repository) }

    context 'with git.pipelines.trigger permission' do
      before do
        allow_any_instance_of(Devops::GitProviderCredential).to receive(:can_be_used?).and_return(true)
        client_double = double('api_client', rerun_workflow: { success: true, pipeline_id: 'new-pipeline-123' })
        allow(Devops::Git::ApiClient).to receive(:for).and_return(client_double)
        allow_any_instance_of(WorkerApiClient).to receive(:queue_git_pipeline_sync).and_return(true)
      end

      it 'retries failed pipeline' do
        post "/api/v1/git/pipelines/#{pipeline.id}/retry", headers: headers, as: :json

        expect(response).to have_http_status(:accepted)
        response_data = json_response

        expect(response_data['data']['message']).to include('retry')
      end

      it 'prevents retrying successful pipeline' do
        successful_pipeline = create(:git_pipeline, :success, account: account, repository: repository)

        post "/api/v1/git/pipelines/#{successful_pipeline.id}/retry", headers: headers, as: :json

        expect_error_response('Cannot retry successful pipeline', 422)
      end
    end
  end

  describe 'GET /api/v1/git/pipelines/:id/jobs' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:pipeline) { create(:git_pipeline, account: account, repository: repository) }

    before do
      create_list(:git_pipeline_job, 3, pipeline: pipeline)
    end

    context 'with git.pipelines.read permission' do
      it 'returns list of jobs' do
        get "/api/v1/git/pipelines/#{pipeline.id}/jobs", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['jobs']).to be_an(Array)
        expect(response_data['data']['jobs'].length).to eq(3)
      end

      it 'includes job details' do
        get "/api/v1/git/pipelines/#{pipeline.id}/jobs", headers: headers, as: :json

        response_data = json_response
        first_job = response_data['data']['jobs'].first

        expect(first_job).to include('id', 'name', 'status', 'conclusion')
      end
    end
  end

  describe 'GET /api/v1/git/pipelines/stats' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:git_pipeline, 3, :success, account: account, repository: repository)
      create(:git_pipeline, :failure, account: account, repository: repository)
    end

    context 'with git.pipelines.read permission' do
      it 'returns pipeline statistics' do
        get '/api/v1/git/pipelines/stats', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['stats']).to include('total_runs', 'success_count', 'failed_count')
      end

      it 'includes success rate' do
        get '/api/v1/git/pipelines/stats', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['stats']).to have_key('success_rate')
      end

      it 'filters stats by repository_id' do
        get '/api/v1/git/pipelines/stats',
            params: { repository_id: repository.id },
            headers: headers

        expect_success_response
        response_data = json_response

        expect(response_data['data']['stats']['total_runs']).to eq(4)
      end
    end
  end
end
