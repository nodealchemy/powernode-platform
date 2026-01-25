# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Workers', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  before do
    # Grant required permissions
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
  end

  describe 'GET /api/v1/workers/stats' do
    context 'with proper permissions' do
      it 'returns worker statistics' do
        allow_any_instance_of(Api::V1::WorkersController).to receive(:fetch_worker_stats).and_return({
          total_jobs: 100,
          completed_jobs: 90,
          failed_jobs: 10,
          success_rate: 90.0,
          avg_processing_time: 1.5,
          queue_depth: 5,
          queues: {},
          workers_active: 3
        })

        get '/api/v1/workers/stats', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['total_jobs']).to eq(100)
        expect(data['completed_jobs']).to eq(90)
        expect(data['failed_jobs']).to eq(10)
        expect(data['workers_active']).to eq(3)
      end

      it 'returns fallback stats on error' do
        allow_any_instance_of(Api::V1::WorkersController).to receive(:fetch_worker_stats).and_raise(StandardError)

        get '/api/v1/workers/stats', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['total_jobs']).to eq(0)
        expect(data).to have_key('error')
      end
    end
  end

  describe 'GET /api/v1/workers' do
    let!(:worker1) { create(:worker, account: account, name: 'Worker 1') }
    let!(:worker2) { create(:worker, account: account, name: 'Worker 2') }

    context 'with proper permissions' do
      it 'returns list of workers' do
        get '/api/v1/workers', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['workers']).to be_an(Array)
        expect(data['total']).to eq(2)
        expect(data['account_workers']).to eq(2)
      end
    end

    context 'without permissions' do
      before do
        allow_any_instance_of(User).to receive(:has_permission?).and_return(false)
      end

      it 'returns forbidden error' do
        get '/api/v1/workers', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/workers/:id' do
    let(:worker) { create(:worker, account: account) }

    context 'with proper permissions' do
      it 'returns worker details' do
        allow(WorkerActivity).to receive(:activity_summary).and_return({
          total_requests: 10,
          successful_requests: 8
        })

        get "/api/v1/workers/#{worker.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['worker']).to be_present
        expect(data['worker']['id']).to eq(worker.id)
        expect(data).to have_key('activity_summary')
        expect(data).to have_key('recent_activities')
      end
    end

    context 'when worker not found' do
      it 'returns not found error' do
        get "/api/v1/workers/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Worker not found', 404)
      end
    end
  end

  describe 'POST /api/v1/workers' do
    let(:valid_params) do
      {
        worker: {
          name: 'Test Worker',
          description: 'A test worker',
          roles: ['api_worker']
        }
      }
    end

    context 'with valid params' do
      it 'creates a new worker' do
        allow(Billing::UsageLimitService).to receive(:can_create_worker?).and_return(true)

        expect {
          post '/api/v1/workers', params: valid_params, headers: headers, as: :json
        }.to change { account.workers.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['worker']['name']).to eq('Test Worker')
        expect(data['message']).to match(/created successfully/)
      end
    end

    context 'when worker limit reached' do
      it 'returns error' do
        allow(Billing::UsageLimitService).to receive(:can_create_worker?).and_return(false)

        post '/api/v1/workers', params: valid_params, headers: headers, as: :json

        expect_error_response('Worker limit reached for your current plan', 200)
      end
    end

    context 'with invalid params' do
      it 'returns validation error' do
        invalid_params = { worker: { name: nil } }

        post '/api/v1/workers', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'PATCH /api/v1/workers/:id' do
    let(:worker) { create(:worker, account: account) }
    let(:update_params) do
      {
        worker: {
          name: 'Updated Worker',
          description: 'Updated description'
        }
      }
    end

    context 'with valid params' do
      it 'updates the worker' do
        patch "/api/v1/workers/#{worker.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['worker']['name']).to eq('Updated Worker')
        expect(data['message']).to match(/updated successfully/)
      end
    end
  end

  describe 'DELETE /api/v1/workers/:id' do
    let!(:worker) { create(:worker, account: account) }

    context 'with proper permissions' do
      it 'deletes the worker' do
        expect {
          delete "/api/v1/workers/#{worker.id}", headers: headers, as: :json
        }.to change { account.workers.count }.by(-1)

        expect_success_response
        data = json_response_data
        expect(data['message']).to match(/deleted successfully/)
      end
    end
  end

  describe 'POST /api/v1/workers/:id/regenerate_token' do
    let(:worker) { create(:worker, account: account) }

    it 'regenerates worker token' do
      post "/api/v1/workers/#{worker.id}/regenerate_token", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['new_token']).to be_present
      expect(data['message']).to match(/Token regenerated/)
    end
  end

  describe 'POST /api/v1/workers/:id/suspend' do
    let(:worker) { create(:worker, account: account, status: 'active') }

    it 'suspends the worker' do
      post "/api/v1/workers/#{worker.id}/suspend", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['message']).to match(/suspended/)
      expect(worker.reload.status).to eq('suspended')
    end
  end

  describe 'POST /api/v1/workers/:id/activate' do
    let(:worker) { create(:worker, account: account, status: 'suspended') }

    it 'activates the worker' do
      post "/api/v1/workers/#{worker.id}/activate", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['message']).to match(/activated/)
      expect(worker.reload.status).to eq('active')
    end
  end

  describe 'POST /api/v1/workers/:id/revoke' do
    let(:worker) { create(:worker, account: account, status: 'active') }

    it 'revokes the worker' do
      post "/api/v1/workers/#{worker.id}/revoke", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['message']).to match(/revoked/)
      expect(worker.reload.status).to eq('revoked')
    end
  end

  describe 'POST /api/v1/workers/:id/test' do
    let(:worker) { create(:worker, account: account) }

    context 'when test job is enqueued successfully' do
      it 'returns success' do
        allow(WorkerJobService).to receive(:enqueue_test_worker_job).and_return(true)

        post "/api/v1/workers/#{worker.id}/test", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to match(/Test job enqueued/)
        expect(data['job_status']).to eq('enqueued')
      end
    end

    context 'when test job fails' do
      it 'returns error' do
        allow(WorkerJobService).to receive(:enqueue_test_worker_job).and_raise(
          WorkerJobService::WorkerServiceError, 'Service unavailable'
        )

        post "/api/v1/workers/#{worker.id}/test", headers: headers, as: :json

        expect_error_response('Failed to enqueue test job: Service unavailable', 503)
      end
    end
  end

  describe 'POST /api/v1/workers/:id/health_check' do
    let(:worker) { create(:worker, account: account, last_seen_at: 5.minutes.ago) }

    it 'performs health check' do
      post "/api/v1/workers/#{worker.id}/health_check", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['status']).to be_in(['healthy', 'warning', 'error'])
      expect(data['checks']).to be_a(Hash)
      expect(data['checks']).to have_key('connectivity')
      expect(data['checks']).to have_key('authentication')
    end
  end

  describe 'GET /api/v1/workers/:id/config' do
    let(:worker) { create(:worker, account: account) }

    it 'returns worker configuration' do
      allow(worker).to receive(:effective_config).and_return({
        security: { token_rotation_enabled: true }
      })

      get "/api/v1/workers/#{worker.id}/config", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'PUT /api/v1/workers/:id/config' do
    let(:worker) { create(:worker, account: account) }
    let(:config_params) do
      {
        worker_config: {
          security: {
            token_rotation_enabled: true,
            token_expiry_days: 90
          }
        }
      }
    end

    it 'updates worker configuration' do
      put "/api/v1/workers/#{worker.id}/config", params: config_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['message']).to eq('Worker configuration updated successfully')
    end
  end

  describe 'POST /api/v1/workers/:id/config/reset' do
    let(:worker) { create(:worker, account: account) }

    it 'resets worker configuration to defaults' do
      post "/api/v1/workers/#{worker.id}/config/reset", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['message']).to eq('Worker configuration reset to defaults')
    end
  end
end
