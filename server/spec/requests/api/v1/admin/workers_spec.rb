# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Workers', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:user_with_view_permission) { create(:user, account: account, permissions: ['system.workers.view']) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: ['system.workers.view', 'system.workers.create']) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: ['system.workers.view', 'system.workers.update']) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: ['system.workers.view', 'system.workers.delete']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/admin/workers' do
    let(:headers) { auth_headers_for(user_with_view_permission) }

    before do
      create_list(:worker, 3, account: account)
    end

    context 'with system.workers.view permission' do
      it 'returns list of workers' do
        get '/api/v1/admin/workers', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['workers']).to be_an(Array)
        expect(response_data['data']['workers'].length).to eq(3)
      end

      it 'includes worker summary data' do
        get '/api/v1/admin/workers', headers: headers, as: :json

        response_data = json_response
        first_worker = response_data['data']['workers'].first

        expect(first_worker).to include('id', 'name', 'status', 'masked_token')
      end

      it 'includes total count' do
        get '/api/v1/admin/workers', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('total')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/admin/workers', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/admin/workers', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/admin/workers/:id' do
    let(:headers) { auth_headers_for(user_with_view_permission) }
    let(:worker) { create(:worker, account: account) }

    context 'with system.workers.view permission' do
      it 'returns worker details' do
        get "/api/v1/admin/workers/#{worker.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['worker']).to include(
          'id' => worker.id,
          'name' => worker.name
        )
      end

      it 'includes activity summary' do
        get "/api/v1/admin/workers/#{worker.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('activity_summary')
      end

      it 'includes recent activities' do
        get "/api/v1/admin/workers/#{worker.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('recent_activities')
      end

      it 'includes full token in details view' do
        get "/api/v1/admin/workers/#{worker.id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['worker']).to have_key('token')
      end
    end

    context 'when worker does not exist' do
      it 'returns not found error' do
        get '/api/v1/admin/workers/nonexistent-id', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when accessing other account worker' do
      let(:other_account) { create(:account) }
      let(:other_worker) { create(:worker, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/admin/workers/#{other_worker.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/admin/workers' do
    let(:headers) { auth_headers_for(user_with_create_permission) }

    context 'with system.workers.create permission' do
      let(:valid_params) do
        {
          worker: {
            name: 'Test Worker',
            description: 'A test worker for processing jobs'
          }
        }
      end

      it 'creates a new worker' do
        expect {
          post '/api/v1/admin/workers', params: valid_params, headers: headers, as: :json
        }.to change(Worker, :count).by(1)

        expect(response).to have_http_status(:created)
        response_data = json_response

        expect(response_data['data']['worker']['name']).to eq('Test Worker')
      end

      it 'returns worker with token' do
        post '/api/v1/admin/workers', params: valid_params, headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['worker']).to have_key('token')
        expect(response_data['data']['worker']['token']).to be_present
      end

      it 'records creation activity' do
        expect {
          post '/api/v1/admin/workers', params: valid_params, headers: headers, as: :json
        }.to change(WorkerActivity, :count).by_at_least(1)
      end
    end

    context 'with invalid data' do
      it 'returns validation error for blank name' do
        post '/api/v1/admin/workers',
             params: { worker: { name: '' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_view_permission) }

      it 'returns forbidden error' do
        post '/api/v1/admin/workers',
             params: { worker: { name: 'Test' } },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PUT /api/v1/admin/workers/:id' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:worker) { create(:worker, account: account) }

    context 'with system.workers.update permission' do
      it 'updates worker successfully' do
        put "/api/v1/admin/workers/#{worker.id}",
            params: { worker: { description: 'Updated description' } },
            headers: headers,
            as: :json

        expect_success_response

        worker.reload
        expect(worker.description).to eq('Updated description')
      end

      it 'records update activity' do
        expect {
          put "/api/v1/admin/workers/#{worker.id}",
              params: { worker: { description: 'Updated' } },
              headers: headers,
              as: :json
        }.to change(WorkerActivity, :count).by_at_least(1)
      end
    end
  end

  describe 'DELETE /api/v1/admin/workers/:id' do
    let(:headers) { auth_headers_for(user_with_delete_permission) }
    let(:worker) { create(:worker, account: account) }

    context 'with system.workers.delete permission' do
      it 'deletes worker successfully' do
        worker_id = worker.id

        delete "/api/v1/admin/workers/#{worker_id}", headers: headers, as: :json

        expect_success_response
        expect(Worker.find_by(id: worker_id)).to be_nil
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_view_permission) }

      it 'returns forbidden error' do
        delete "/api/v1/admin/workers/#{worker.id}", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/admin/workers/:id/regenerate_token' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:worker) { create(:worker, account: account) }

    context 'with system.workers.update permission' do
      it 'regenerates worker token' do
        old_token = worker.token

        post "/api/v1/admin/workers/#{worker.id}/regenerate_token", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to have_key('new_token')
        expect(response_data['data']['new_token']).not_to eq(old_token)
      end

      it 'records regeneration activity' do
        expect {
          post "/api/v1/admin/workers/#{worker.id}/regenerate_token", headers: headers, as: :json
        }.to change(WorkerActivity, :count).by_at_least(1)
      end
    end
  end

  describe 'POST /api/v1/admin/workers/:id/suspend' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:worker) { create(:worker, :active, account: account) }

    context 'with system.workers.update permission' do
      it 'suspends the worker' do
        post "/api/v1/admin/workers/#{worker.id}/suspend", headers: headers, as: :json

        expect_success_response

        worker.reload
        expect(worker.status).to eq('suspended')
      end

      it 'records suspension activity' do
        expect {
          post "/api/v1/admin/workers/#{worker.id}/suspend", headers: headers, as: :json
        }.to change(WorkerActivity, :count).by_at_least(1)
      end
    end
  end

  describe 'POST /api/v1/admin/workers/:id/activate' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:worker) { create(:worker, :suspended, account: account) }

    context 'with system.workers.update permission' do
      it 'activates the worker' do
        post "/api/v1/admin/workers/#{worker.id}/activate", headers: headers, as: :json

        expect_success_response

        worker.reload
        expect(worker.status).to eq('active')
      end
    end
  end

  describe 'POST /api/v1/admin/workers/:id/revoke' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:worker) { create(:worker, :active, account: account) }

    context 'with system.workers.update permission' do
      it 'revokes the worker' do
        post "/api/v1/admin/workers/#{worker.id}/revoke", headers: headers, as: :json

        expect_success_response

        worker.reload
        expect(worker.status).to eq('revoked')
      end
    end
  end
end
