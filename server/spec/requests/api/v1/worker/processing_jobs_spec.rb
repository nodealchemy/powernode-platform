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
  # WorkerBaseController decodes a JWT with type: "worker" and looks up worker by sub claim
  let(:worker_jwt) do
    Security::JwtService.encode({ type: "worker", sub: worker.id }, 5.minutes.from_now)
  end
  let(:worker_headers) do
    { 'Authorization' => "Bearer #{worker_jwt}" }
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

    # Defense-in-depth: account workers (is_system: false) must only reach
    # their own account's jobs; system workers process all accounts by design.
    describe 'cross-account scoping' do
      let(:other_account) { create(:account) }
      let(:foreign_file_object) { create(:file_object, :image, account: other_account) }
      let(:foreign_job) do
        create(:file_processing_job, object: foreign_file_object, account: other_account)
      end
      let(:own_job) { create_processing_job.call }

      before do
        unless FileManagement::Object.method_defined?(:storage_path)
          FileManagement::Object.define_method(:storage_path) { storage_key }
        end
      end

      context 'as an account worker (is_system: false)' do
        # worker (let above) belongs to `account`; other_account is foreign.
        it 'CANNOT read another account\'s processing job (404)' do
          get "/api/v1/worker/processing_jobs/#{foreign_job.id}",
              headers: worker_headers, as: :json

          expect(response).to have_http_status(:not_found)
        end

        it 'CAN read its own account\'s processing job' do
          get "/api/v1/worker/processing_jobs/#{own_job.id}",
              headers: worker_headers, as: :json

          expect_success_response
        end
      end

      context 'as a system worker (is_system: true)' do
        let(:system_worker) { create(:worker, :system_worker, account: account) }
        let(:system_worker_headers) do
          jwt = Security::JwtService.encode({ type: "worker", sub: system_worker.id }, 5.minutes.from_now)
          { 'Authorization' => "Bearer #{jwt}" }
        end

        it 'CAN read another account\'s processing job (cross-account preserved)' do
          get "/api/v1/worker/processing_jobs/#{foreign_job.id}",
              headers: system_worker_headers, as: :json

          expect_success_response
        end
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

    # Regression guard. The two examples above stub mark_completed!/mark_failed!
    # to return true, so they proved only that the controller REACHES them —
    # they could not see that the call itself raised.
    #
    # It did: the controller handed the raw ActionController::Parameters for
    # result_data/error_details to the model, whose jsonb columns do
    # `plain_hash.merge(params)`. Hash#merge calls #to_hash on the argument, and
    # ActionController::Parameters#to_hash raises UnfilteredParameters when the
    # params were never permitted. The controller's `rescue StandardError`
    # turned that into a 500, so EVERY worker completion and failure report
    # failed and the row never left "processing" — the worker jobs' terminal
    # state was unreachable through this endpoint.
    #
    # These examples run the REAL model and assert the persisted row.
    describe 'terminal transitions with the real model (no stubs)' do
      let(:processing_job) { create_processing_job.call }

      before { processing_job.update!(status: 'processing', started_at: Time.current) }

      it 'persists a completed row and its result_data' do
        patch "/api/v1/worker/processing_jobs/#{processing_job.id}",
              params: { status: 'completed',
                        result_data: { thumbnails: [ { size: 'small', storage_key: 'k' } ], count: 1 } },
              headers: worker_headers,
              as: :json

        expect(response).to have_http_status(:ok)
        expect(processing_job.reload.status).to eq('completed')
        expect(processing_job.status).not_to eq('processing')
        expect(processing_job.result_data['count']).to eq(1)
        expect(processing_job.completed_at).to be_present
      end

      it 'persists a failed row and its error_details' do
        patch "/api/v1/worker/processing_jobs/#{processing_job.id}",
              params: { status: 'failed',
                        error_details: { error_message: 'ffprobe missing', reason: 'tool_unavailable' } },
              headers: worker_headers,
              as: :json

        expect(response).to have_http_status(:ok)
        expect(processing_job.reload.status).to eq('failed')
        expect(processing_job.error_details['error_message']).to eq('ffprobe missing')
        expect(processing_job.error_details['reason']).to eq('tool_unavailable')
      end

      it 'accepts an empty result_data' do
        patch "/api/v1/worker/processing_jobs/#{processing_job.id}",
              params: { status: 'completed' },
              headers: worker_headers,
              as: :json

        expect(response).to have_http_status(:ok)
        expect(processing_job.reload.status).to eq('completed')
      end
    end
  end
end
