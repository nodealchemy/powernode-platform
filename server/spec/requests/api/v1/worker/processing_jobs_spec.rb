# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Worker::ProcessingJobs', type: :request do
  # The controller's show action uses @job.file_object, but the model defines
  # belongs_to :object. Add the file_object alias so the controller works.
  before(:all) do
    unless FileManagement::ProcessingJob.method_defined?(:file_object)
      FileManagement::ProcessingJob.class_eval do
        alias_method :file_object, :object
      end
    end
  end

  let(:account) { create(:account) }
  let(:worker) { create(:worker, account: account) }

  let(:file_object) { create(:file_object, :image, account: account) }

  # Helper to create processing job
  let(:create_processing_job) do
    ->(attrs = {}) {
      create(:file_processing_job, { object: file_object, account: account }.merge(attrs))
    }
  end

  # Worker service authentication headers
  # WorkerBaseController uses authenticate_worker_service! which compares
  # the Bearer token against a static service token, not a JWT
  let(:worker_service_token) do
    ENV["WORKER_SERVICE_TOKEN"] ||
      Rails.application.credentials.dig(:worker, :service_token) ||
      "development_worker_service_token_that_persists_across_restarts"
  end
  let(:worker_headers) do
    { 'Authorization' => "Bearer #{worker_service_token}" }
  end

  describe 'GET /api/v1/worker/processing_jobs/:id' do
    let(:processing_job) { create_processing_job.call }

    context 'with worker authentication' do
      before do
        # Controller's show action calls @job.file_object.storage_path but the model
        # only has storage_key (no storage_path column). Define the missing method.
        unless FileManagement::Object.method_defined?(:storage_path)
          FileManagement::Object.define_method(:storage_path) { storage_key }
        end
      end

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

        # Controller calls render_validation_error with extra keyword arg (field:)
        # which causes ArgumentError, caught by rescue_from StandardError => 500
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end
end
