# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Repositories', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: ['devops.repositories.read']) }
  let(:user_with_write_permission) { create(:user, account: account, permissions: ['devops.repositories.read', 'devops.repositories.write']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:provider) { create(:devops_provider, account: account) }

  describe 'GET /api/v1/devops/repositories' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create_list(:devops_repository, 3, account: account, provider: provider)
    end

    context 'with devops.repositories.read permission' do
      it 'returns list of repositories' do
        get '/api/v1/devops/repositories', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['repositories']).to be_an(Array)
        expect(response_data['data']['repositories'].length).to eq(3)
      end

      it 'includes repository details' do
        get '/api/v1/devops/repositories', headers: headers, as: :json

        response_data = json_response
        first_repo = response_data['data']['repositories'].first

        expect(first_repo).to include('id', 'name', 'full_name', 'default_branch', 'is_active')
      end

      it 'includes meta information' do
        get '/api/v1/devops/repositories', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['meta']).to include('total', 'active_count')
      end

      it 'filters by provider_id' do
        other_provider = create(:devops_provider, account: account)
        create(:devops_repository, account: account, provider: other_provider)

        get '/api/v1/devops/repositories',
            params: { provider_id: other_provider.id },
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['repositories'].length).to eq(1)
      end

      it 'filters by is_active' do
        create(:devops_repository, :inactive, account: account, provider: provider)

        get '/api/v1/devops/repositories',
            params: { is_active: false },
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        active_statuses = response_data['data']['repositories'].map { |r| r['is_active'] }
        expect(active_statuses.uniq).to eq([false])
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/devops/repositories', headers: headers, as: :json

        expect_error_response('Insufficient permissions to view repositories', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/devops/repositories', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/repositories/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:repository) { create(:devops_repository, account: account, provider: provider) }

    context 'with devops.repositories.read permission' do
      it 'returns repository details' do
        get "/api/v1/devops/repositories/#{repository.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['repository']).to include(
          'id' => repository.id,
          'name' => repository.name,
          'full_name' => repository.full_name
        )
      end

      it 'includes pipelines when requested' do
        pipeline = create(:devops_pipeline, account: account)
        repository.pipeline_repositories.create!(pipeline: pipeline)

        get "/api/v1/devops/repositories/#{repository.id}",
            params: { include_pipelines: true },
            headers: headers,
            as: :json

        response_data = json_response
        expect(response_data['data']['repository']).to have_key('pipelines')
      end
    end

    context 'when repository does not exist' do
      it 'returns not found error' do
        get '/api/v1/devops/repositories/nonexistent-id', headers: headers, as: :json

        expect_error_response('Repository not found', 404)
      end
    end

    context 'when accessing other account repository' do
      let(:other_account) { create(:account) }
      let(:other_provider) { create(:devops_provider, account: other_account) }
      let(:other_repository) { create(:devops_repository, account: other_account, provider: other_provider) }

      it 'returns not found error' do
        get "/api/v1/devops/repositories/#{other_repository.id}", headers: headers, as: :json

        expect_error_response('Repository not found', 404)
      end
    end
  end

  describe 'POST /api/v1/devops/repositories' do
    let(:headers) { auth_headers_for(user_with_write_permission) }

    context 'with devops.repositories.write permission' do
      let(:valid_params) do
        {
          repository: {
            name: 'new-test-repo',
            full_name: 'testuser/new-test-repo',
            default_branch: 'main',
            provider_id: provider.id
          }
        }
      end

      it 'creates a new repository' do
        expect {
          post '/api/v1/devops/repositories', params: valid_params, headers: headers, as: :json
        }.to change(Devops::Repository, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['repository']['name']).to eq('new-test-repo')
      end
    end

    context 'with invalid provider' do
      it 'returns not found error' do
        post '/api/v1/devops/repositories',
             params: { repository: { name: 'test', provider_id: 'invalid' } },
             headers: headers,
             as: :json

        expect_error_response('Provider not found', 404)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/devops/repositories',
             params: { repository: { name: 'test', provider_id: provider.id } },
             headers: headers,
             as: :json

        expect_error_response('Insufficient permissions to manage repositories', 403)
      end
    end
  end

  describe 'PUT /api/v1/devops/repositories/:id' do
    let(:headers) { auth_headers_for(user_with_write_permission) }
    let(:repository) { create(:devops_repository, account: account, provider: provider) }

    context 'with devops.repositories.write permission' do
      it 'updates repository successfully' do
        put "/api/v1/devops/repositories/#{repository.id}",
            params: { repository: { default_branch: 'develop' } },
            headers: headers,
            as: :json

        expect_success_response

        repository.reload
        expect(repository.default_branch).to eq('develop')
      end
    end
  end

  describe 'DELETE /api/v1/devops/repositories/:id' do
    let(:headers) { auth_headers_for(user_with_write_permission) }
    let(:repository) { create(:devops_repository, account: account, provider: provider) }

    context 'with devops.repositories.write permission' do
      it 'deletes repository successfully' do
        repository_id = repository.id

        delete "/api/v1/devops/repositories/#{repository_id}", headers: headers, as: :json

        expect_success_response
        expect(Devops::Repository.find_by(id: repository_id)).to be_nil
      end
    end
  end

  describe 'POST /api/v1/devops/repositories/:id/sync' do
    let(:headers) { auth_headers_for(user_with_write_permission) }
    let(:repository) { create(:devops_repository, account: account, provider: provider) }

    context 'with devops.repositories.write permission' do
      it 'initiates repository sync' do
        post "/api/v1/devops/repositories/#{repository.id}/sync", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['repository_id']).to eq(repository.id)
        expect(response_data['data']).to have_key('sync_started_at')
      end
    end
  end

  describe 'POST /api/v1/devops/repositories/:id/attach_pipeline' do
    let(:headers) { auth_headers_for(user_with_write_permission) }
    let(:repository) { create(:devops_repository, account: account, provider: provider) }
    let(:pipeline) { create(:devops_pipeline, account: account) }

    context 'with devops.repositories.write permission' do
      it 'attaches pipeline to repository' do
        post "/api/v1/devops/repositories/#{repository.id}/attach_pipeline",
             params: { pipeline_id: pipeline.id },
             headers: headers,
             as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['attached_pipeline']['id']).to eq(pipeline.id)
      end

      it 'prevents duplicate attachment' do
        repository.pipeline_repositories.create!(pipeline: pipeline)

        post "/api/v1/devops/repositories/#{repository.id}/attach_pipeline",
             params: { pipeline_id: pipeline.id },
             headers: headers,
             as: :json

        expect_error_response('Pipeline already attached to this repository', 422)
      end
    end
  end

  describe 'DELETE /api/v1/devops/repositories/:id/detach_pipeline' do
    let(:headers) { auth_headers_for(user_with_write_permission) }
    let(:repository) { create(:devops_repository, account: account, provider: provider) }
    let(:pipeline) { create(:devops_pipeline, account: account) }

    context 'with devops.repositories.write permission' do
      it 'detaches pipeline from repository' do
        repository.pipeline_repositories.create!(pipeline: pipeline)

        delete "/api/v1/devops/repositories/#{repository.id}/detach_pipeline",
               params: { pipeline_id: pipeline.id },
               headers: headers,
               as: :json

        expect_success_response
      end

      it 'returns error if pipeline not attached' do
        delete "/api/v1/devops/repositories/#{repository.id}/detach_pipeline",
               params: { pipeline_id: pipeline.id },
               headers: headers,
               as: :json

        expect_error_response('Pipeline not attached to this repository', 404)
      end
    end
  end
end
