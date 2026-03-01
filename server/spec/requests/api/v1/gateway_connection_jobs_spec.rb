# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::GatewayConnectionJobs', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:headers) { auth_headers_for(user) }
  let(:admin_headers) { auth_headers_for(admin_user) }

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:service_headers) do
    token = Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 5.minutes.from_now)
    {
      'Authorization' => "Bearer #{token}",
      'Content-Type' => 'application/json'
    }
  end

  describe 'GET /api/v1/gateway_connection_jobs/:id' do
    let!(:job) { GatewayConnectionJob.create!(gateway: 'stripe', status: 'pending', operation: 'test_connection') }

    context 'with admin permission' do
      before do
        admin_user.grant_permission('admin.settings.payment')
      end

      it 'returns job details' do
        get "/api/v1/gateway_connection_jobs/#{job.id}", headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq(job.id)
        expect(data['gateway']).to eq('stripe')
        expect(data['status']).to eq('pending')
        expect(data).to have_key('created_at')
        expect(data).to have_key('updated_at')
      end

      it 'returns error for non-existent job' do
        get "/api/v1/gateway_connection_jobs/#{SecureRandom.uuid}", headers: admin_headers, as: :json

        expect_error_response('Gateway connection job not found', 404)
      end
    end

    context 'without admin.settings.payment permission' do
      it 'returns forbidden error' do
        get "/api/v1/gateway_connection_jobs/#{job.id}", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/gateway_connection_jobs/#{job.id}", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/gateway_connection_jobs/:id' do
    let!(:job) { GatewayConnectionJob.create!(gateway: 'stripe', status: 'pending', operation: 'test_connection') }

    context 'with service token' do
      it 'updates job status to completed' do
        update_params = {
          status: 'completed',
          result: { success: true, message: 'Connection successful' }
        }

        patch "/api/v1/gateway_connection_jobs/#{job.id}",
              params: update_params,
              headers: service_headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data['status']).to eq('completed')
        expect(data['result']).to include('success' => true)
        expect(data['completed_at']).not_to be_nil
      end

      it 'updates job status to failed' do
        update_params = {
          status: 'failed',
          result: { success: false, error: 'Invalid credentials' }
        }

        patch "/api/v1/gateway_connection_jobs/#{job.id}",
              params: update_params,
              headers: service_headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data['status']).to eq('failed')
        expect(data['result']).to include('success' => false)
        expect(data['completed_at']).not_to be_nil
      end

      it 'sets completed_at timestamp when status changes to completed' do
        freeze_time = Time.current
        travel_to(freeze_time) do
          patch "/api/v1/gateway_connection_jobs/#{job.id}",
                params: { status: 'completed' },
                headers: service_headers,
                as: :json

          expect_success_response
          data = json_response_data
          expect(Time.parse(data['completed_at'])).to be_within(1.second).of(freeze_time)
        end
      end

      it 'returns error for non-existent job' do
        patch "/api/v1/gateway_connection_jobs/#{SecureRandom.uuid}",
              params: { status: 'completed' },
              headers: service_headers,
              as: :json

        expect_error_response('Gateway connection job not found', 404)
      end
    end

    context 'with admin user permission' do
      before do
        admin_user.grant_permission('admin.settings.payment')
      end

      it 'allows admin user to update job' do
        patch "/api/v1/gateway_connection_jobs/#{job.id}",
              params: { status: 'completed' },
              headers: admin_headers,
              as: :json

        expect_success_response
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        patch "/api/v1/gateway_connection_jobs/#{job.id}",
              params: { status: 'completed' },
              as: :json

        expect_error_response('Access token required', 401)
      end
    end

    context 'without proper permissions' do
      it 'returns forbidden error' do
        patch "/api/v1/gateway_connection_jobs/#{job.id}",
              params: { status: 'completed' },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
