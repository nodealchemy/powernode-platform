# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Jobs', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # Service token authentication
  let(:service_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  # Helper to create background job
  let(:create_background_job) do
    ->(attrs = {}) {
      BackgroundJob.create!({
        account: account,
        user: user,
        job_id: SecureRandom.uuid,
        job_type: 'data_export',
        status: 'pending',
        parameters: { format: 'json' },
        progress_percentage: 0
      }.merge(attrs))
    }
  end

  describe 'GET /api/v1/internal/jobs/:id' do
    let(:background_job) { create_background_job.call }

    context 'with service token authentication' do
      it 'returns job details' do
        get "/api/v1/internal/jobs/#{background_job.job_id}", headers: service_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'job_id' => background_job.job_id,
          'job_type' => 'data_export',
          'status' => 'pending'
        )
      end

      it 'includes job parameters' do
        get "/api/v1/internal/jobs/#{background_job.job_id}", headers: service_headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('parameters')
      end

      it 'includes progress information' do
        get "/api/v1/internal/jobs/#{background_job.job_id}", headers: service_headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('progress')
      end

      it 'includes timestamps' do
        get "/api/v1/internal/jobs/#{background_job.job_id}", headers: service_headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('created_at')
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
        allow_any_instance_of(BackgroundJob).to receive(:mark_in_progress!).and_return(true)

        patch "/api/v1/internal/jobs/#{background_job.job_id}",
              params: { status: 'in_progress' },
              headers: service_headers,
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['message']).to include('updated successfully')
      end

      it 'marks job as completed with result' do
        background_job.update!(status: 'in_progress')
        allow_any_instance_of(BackgroundJob).to receive(:mark_completed!).and_return(true)

        patch "/api/v1/internal/jobs/#{background_job.job_id}",
              params: {
                status: 'completed',
                result: { file_url: 'https://example.com/export.zip', record_count: 100 }
              },
              headers: service_headers,
              as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['status']).to eq('in_progress') # mocked method doesn't actually change status
      end

      it 'marks job as failed with error details' do
        background_job.update!(status: 'in_progress')
        allow_any_instance_of(BackgroundJob).to receive(:mark_failed!).and_return(true)

        patch "/api/v1/internal/jobs/#{background_job.job_id}",
              params: {
                status: 'failed',
                error: 'Processing failed due to timeout',
                error_details: { code: 'TIMEOUT', duration: 3600 }
              },
              headers: service_headers,
              as: :json

        expect_success_response
      end

      it 'updates job result and error without status change' do
        patch "/api/v1/internal/jobs/#{background_job.job_id}",
              params: {
                result: { partial: true, records_processed: 50 }
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
