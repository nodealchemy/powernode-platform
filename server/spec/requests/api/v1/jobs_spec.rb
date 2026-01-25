# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Jobs', type: :request do
  # Service token for worker authentication
  let(:worker_token) do
    ENV["WORKER_SERVICE_TOKEN"] ||
      Rails.application.credentials.dig(:worker, :service_token) ||
      "development_worker_service_token_that_persists_across_restarts"
  end

  let(:service_headers) do
    {
      'Authorization' => "Bearer #{worker_token}",
      'Content-Type' => 'application/json'
    }
  end

  describe 'POST /api/v1/jobs' do
    context 'with valid service token' do
      it 'enqueues a job successfully' do
        job_params = {
          job_class: 'TestJob',
          args: ['arg1', 'arg2'],
          options: { queue: 'default' }
        }

        # Mock Redis to avoid actual job enqueuing
        redis_mock = instance_double(Redis)
        allow(Redis).to receive(:new).and_return(redis_mock)
        allow(redis_mock).to receive(:lpush).and_return(1)

        post '/api/v1/jobs',
             params: job_params,
             headers: service_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['job_id']).to be_present
        expect(data['job_class']).to eq('TestJob')
        expect(data['status']).to eq('enqueued')
        expect(data['enqueued_at']).to be_present
      end

      it 'uses default queue when not specified' do
        job_params = {
          job_class: 'TestJob',
          args: []
        }

        redis_mock = instance_double(Redis)
        allow(Redis).to receive(:new).and_return(redis_mock)
        allow(redis_mock).to receive(:lpush).and_return(1)

        post '/api/v1/jobs',
             params: job_params,
             headers: service_headers,
             as: :json

        expect_success_response
      end

      it 'handles custom queue option' do
        job_params = {
          job_class: 'HighPriorityJob',
          args: [],
          options: { queue: 'high', retry: false }
        }

        redis_mock = instance_double(Redis)
        allow(Redis).to receive(:new).and_return(redis_mock)
        expect(redis_mock).to receive(:lpush).with(
          'queue:high',
          anything
        ).and_return(1)

        post '/api/v1/jobs',
             params: job_params,
             headers: service_headers,
             as: :json

        expect_success_response
      end

      it 'returns error when job_class is missing' do
        post '/api/v1/jobs',
             params: { args: [] },
             headers: service_headers,
             as: :json

        expect_error_response('Missing job_class parameter', 422)
      end

      it 'returns error when Redis fails' do
        job_params = {
          job_class: 'TestJob',
          args: []
        }

        allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError)

        post '/api/v1/jobs',
             params: job_params,
             headers: service_headers,
             as: :json

        expect_error_response(
          'Failed to enqueue job. Please check worker service status.',
          503
        )
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        post '/api/v1/jobs',
             params: { job_class: 'TestJob' },
             as: :json

        expect_error_response('Service authentication required', 401)
      end
    end

    context 'with invalid service token' do
      it 'returns unauthorized error' do
        invalid_headers = {
          'Authorization' => 'Bearer invalid_token',
          'Content-Type' => 'application/json'
        }

        post '/api/v1/jobs',
             params: { job_class: 'TestJob' },
             headers: invalid_headers,
             as: :json

        expect_error_response('Service authentication required', 401)
      end
    end
  end
end
