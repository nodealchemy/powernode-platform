# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Jobs', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Worker JWT authentication via InternalBaseController
  let(:internal_worker) { create(:worker, account: account) }
  let(:service_headers) do
    token = Security::JwtService.encode({ type: "worker", sub: internal_worker.id }, 5.minutes.from_now)
    { 'Authorization' => "Bearer #{token}" }
  end

  # Helper to create background job
  let(:create_background_job) do
    ->(attrs = {}) {
      BackgroundJob.create!({
        job_id: SecureRandom.uuid,
        job_type: 'data_export',
        status: 'pending',
        arguments: { format: 'json' }
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/internal/jobs/:id' do
    let(:background_job) { create_background_job.call }

    context 'with service token authentication' do
      it 'returns job details' do
        get "/api/v1/internal/jobs/#{background_job.job_id}", headers: service_headers, as: :json

        expect_success_response
        data = json_response_data

        expect(data).to include(
          'job_id' => background_job.job_id,
          'job_type' => 'data_export',
          'status' => 'pending'
        )
      end

      it 'includes job parameters' do
        get "/api/v1/internal/jobs/#{background_job.job_id}", headers: service_headers, as: :json

        data = json_response_data
        expect(data).to have_key('parameters')
      end

      it 'includes progress information' do
        get "/api/v1/internal/jobs/#{background_job.job_id}", headers: service_headers, as: :json

        data = json_response_data
        expect(data).to have_key('progress')
      end

      it 'includes timestamps' do
        get "/api/v1/internal/jobs/#{background_job.job_id}", headers: service_headers, as: :json

        data = json_response_data
        expect(data).to have_key('created_at')
      end
    end

    context 'when job does not exist' do
      it 'returns not found error' do
        get '/api/v1/internal/jobs/nonexistent-job-id', headers: service_headers, as: :json

        expect_error_response('Job not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/internal/jobs/#{background_job.job_id}", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/internal/jobs/:id' do
    let(:background_job) { create_background_job.call(status: 'pending') }

    context 'with service token authentication' do
      it 'marks job as in_progress' do
        patch "/api/v1/internal/jobs/#{background_job.job_id}",
              params: { status: 'in_progress' },
              headers: service_headers,
              as: :json

        expect_success_response
        data = json_response_data

        expect(data['message']).to include('updated successfully')
      end

      it 'marks job as completed' do
        background_job.update!(status: 'processing', started_at: Time.current)

        patch "/api/v1/internal/jobs/#{background_job.job_id}",
              params: { status: 'completed' },
              headers: service_headers,
              as: :json

        expect_success_response
        data = json_response_data

        expect(data['status']).to eq('completed')
      end

      it 'marks job as failed with error details' do
        background_job.update!(status: 'processing', started_at: Time.current)

        patch "/api/v1/internal/jobs/#{background_job.job_id}",
              params: {
                status: 'failed',
                error: 'Processing failed due to timeout'
              },
              headers: service_headers,
              as: :json

        expect_success_response
        data = json_response_data

        expect(data['status']).to eq('failed')
      end

      it 'updates job error without status change' do
        patch "/api/v1/internal/jobs/#{background_job.job_id}",
              params: {
                error: 'Partial processing error'
              },
              headers: service_headers,
              as: :json

        expect_success_response
      end
    end

    context 'when job does not exist' do
      it 'returns not found error' do
        patch '/api/v1/internal/jobs/nonexistent-job-id',
              params: { status: 'completed' },
              headers: service_headers,
              as: :json

        expect_error_response('Job not found', 404)
      end
    end

    context 'with invalid service token' do
      it 'returns unauthorized error' do
        invalid_token = JWT.encode(
          { service: 'other', type: 'user', exp: 1.hour.from_now.to_i },
          Rails.application.config.jwt_secret_key,
          'HS256'
        )

        patch "/api/v1/internal/jobs/#{background_job.job_id}",
              params: { status: 'completed' },
              headers: { 'Authorization' => "Bearer #{invalid_token}" },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
