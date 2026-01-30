# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Jobs', type: :request do
  let(:account) { create(:account) }
  let(:user_with_settings_update) { create(:user, account: account, permissions: ['admin.settings.update']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/admin/jobs' do
    let(:headers) { auth_headers_for(user_with_settings_update) }

    before do
      # Create background jobs for testing
      3.times do |i|
        BackgroundJob.create!(
          job_id: SecureRandom.uuid,
          job_type: 'TestJob',
          status: 'completed',
          arguments: { test: true },
          created_at: i.hours.ago
        )
      end
    end

    context 'with admin.settings.update permission' do
      it 'returns list of jobs' do
        get '/api/v1/admin/jobs', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['jobs']).to be_an(Array)
        expect(response_data['data']['jobs'].length).to eq(3)
      end

      it 'includes job details' do
        get '/api/v1/admin/jobs', headers: headers, as: :json

        response_data = json_response
        first_job = response_data['data']['jobs'].first

        expect(first_job).to include('job_id', 'job_type', 'status', 'progress')
      end

      it 'includes pagination info' do
        get '/api/v1/admin/jobs', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('pagination')
      end

      it 'filters by status' do
        BackgroundJob.create!(
          job_id: SecureRandom.uuid,
          job_type: 'TestJob',
          status: 'pending',
          arguments: {}
        )

        get '/api/v1/admin/jobs',
            params: { status: 'pending' },
            headers: headers.merge('Accept' => 'application/json')

        expect_success_response
        response_data = json_response

        statuses = response_data['data']['jobs'].map { |j| j['status'] }
        expect(statuses.uniq).to eq(['pending'])
      end

      it 'filters by job_type' do
        BackgroundJob.create!(
          job_id: SecureRandom.uuid,
          job_type: 'SpecialJob',
          status: 'completed',
          arguments: {}
        )

        get '/api/v1/admin/jobs',
            params: { job_type: 'SpecialJob' },
            headers: headers.merge('Accept' => 'application/json')

        expect_success_response
        response_data = json_response

        job_types = response_data['data']['jobs'].map { |j| j['job_type'] }
        expect(job_types.uniq).to eq(['SpecialJob'])
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/admin/jobs', headers: headers, as: :json

        expect_error_response('Insufficient permissions to view jobs', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/admin/jobs', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/admin/jobs/:id' do
    let(:headers) { auth_headers_for(user_with_settings_update) }
    let(:background_job) do
      BackgroundJob.create!(
        job_id: SecureRandom.uuid,
        job_type: 'TestJob',
        status: 'completed',
        arguments: { input: 'test' },
        created_at: 1.hour.ago,
        started_at: 59.minutes.ago,
        finished_at: 55.minutes.ago
      )
    end

    context 'with admin.settings.update permission' do
      it 'returns job details' do
        get "/api/v1/admin/jobs/#{background_job.job_id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'job_id' => background_job.job_id,
          'job_type' => 'TestJob',
          'status' => 'completed'
        )
      end

      it 'includes progress information' do
        get "/api/v1/admin/jobs/#{background_job.job_id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('progress')
      end

      it 'includes parameters and result' do
        get "/api/v1/admin/jobs/#{background_job.job_id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to have_key('parameters')
        expect(response_data['data']).to have_key('result')
      end

      it 'includes timestamps' do
        get "/api/v1/admin/jobs/#{background_job.job_id}", headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']).to include('created_at', 'started_at', 'completed_at')
      end
    end

    context 'when job does not exist' do
      it 'returns not found error' do
        get '/api/v1/admin/jobs/nonexistent-job-id', headers: headers, as: :json

        expect_error_response('Job not found', 404)
      end
    end
  end
end
