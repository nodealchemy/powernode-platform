# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Worker::ProcessingJobs', type: :request do
  let(:account) { create(:account) }
  let(:worker) { create(:worker, account: account) }

  # Helper to create processing job
  let(:create_processing_job) do
    ->(attrs = {}) {
      FileManagement::ProcessingJob.create!({
        file_object: create_file_object.call,
        job_type: 'thumbnail_generation',
        status: 'pending',
        priority: 0,
        job_parameters: {},
        retry_count: 0,
        max_retries: 3
      }.merge(attrs))
    }
  end

  # Helper to create file object
  let(:create_file_object) do
    ->(attrs = {}) {
      FileManagement::Object.create!({
        account: account,
        user: create(:user, account: account),
        filename: "test-file-#{SecureRandom.hex(4)}.jpg",
        content_type: 'image/jpeg',
        file_size: 1024,
        storage_key: "files/#{SecureRandom.uuid}",
        file_type: 'image',
        processing_status: 'pending'
      }.merge(attrs))
    }
  end

  # Worker authentication headers
  let(:worker_headers) do
    token = JWT.encode(
      { worker_id: worker.id, type: 'worker', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/worker/processing_jobs/:id' do
    let(:processing_job) { create_processing_job.call }

    context 'with worker authentication' do
      it 'returns processing job details' do
        get "/api/v1/worker/processing_jobs/#{processing_job.id}", headers: worker_headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => processing_job.id,
          'job_type' => processing_job.job_type,
          'status' => processing_job.status
        )
      end

      it 'includes file object information' do
        get "/api/v1/worker/processing_jobs/#{processing_job.id}", headers: worker_headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('file_object')
      end

      it 'includes job parameters' do
        get "/api/v1/worker/processing_jobs/#{processing_job.id}", headers: worker_headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('job_parameters')
      end
    end

    context 'when job does not exist' do
      it 'returns not found error' do
        get '/api/v1/worker/processing_jobs/nonexistent-id', headers: worker_headers, as: :json

        expect_error_response('Processing job not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/worker/processing_jobs/#{processing_job.id}", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/worker/processing_jobs/:id' do
    let(:processing_job) { create_processing_job.call(status: 'pending') }

    context 'with worker authentication' do
      it 'starts processing job' do
        allow_any_instance_of(FileManagement::ProcessingJob).to receive(:start_processing!).and_return(true)

        patch "/api/v1/worker/processing_jobs/#{processing_job.id}",
              params: { status: 'processing' },
              headers: worker_headers,
              as: :json

        expect_success_response
      end

      it 'marks job as completed' do
        processing_job.update!(status: 'processing')
        allow_any_instance_of(FileManagement::ProcessingJob).to receive(:mark_completed!).and_return(true)

        patch "/api/v1/worker/processing_jobs/#{processing_job.id}",
              params: { status: 'completed', result_data: { thumbnail_url: 'http://example.com/thumb.jpg' } },
              headers: worker_headers,
              as: :json

        expect_success_response
      end

      it 'marks job as failed' do
        processing_job.update!(status: 'processing')
        allow_any_instance_of(FileManagement::ProcessingJob).to receive(:mark_failed!).and_return(true)

        patch "/api/v1/worker/processing_jobs/#{processing_job.id}",
              params: { status: 'failed', error_details: { error_message: 'Processing failed' } },
              headers: worker_headers,
              as: :json

        expect_success_response
      end

      it 'rejects invalid status' do
        patch "/api/v1/worker/processing_jobs/#{processing_job.id}",
              params: { status: 'invalid_status' },
              headers: worker_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
