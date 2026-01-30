# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Devops::PipelineRuns', type: :request do
  let(:account) { create(:account) }
  let(:pipeline) { create(:ci_cd_pipeline, account: account) }
  let(:pipeline_run) { create(:ci_cd_pipeline_run, pipeline: pipeline) }
  let(:pipeline_step) { create(:ci_cd_pipeline_step, pipeline: pipeline) }

  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/devops/pipeline_runs/:id' do
    context 'with valid internal authentication' do
      it 'returns the pipeline run with steps' do
        get api_v1_internal_devops_pipeline_run_path(pipeline_run), headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['pipeline_run']['id']).to eq(pipeline_run.id)
        expect(json['data']['pipeline_run']['status']).to eq(pipeline_run.status)
        expect(json['data']['pipeline_run']['pipeline_id']).to eq(pipeline.id)
        expect(json['data']['pipeline_run']['pipeline_name']).to eq(pipeline.name)
        expect(json['data']['pipeline_run']).to have_key('steps')
      end

      it 'includes active pipeline steps in order' do
        step1 = create(:ci_cd_pipeline_step, pipeline: pipeline, position: 1, is_active: true)
        step2 = create(:ci_cd_pipeline_step, pipeline: pipeline, position: 2, is_active: true)
        step3 = create(:ci_cd_pipeline_step, pipeline: pipeline, position: 3, is_active: false)

        get api_v1_internal_devops_pipeline_run_path(pipeline_run), headers: internal_headers

        json = JSON.parse(response.body)
        steps = json['data']['pipeline_run']['steps']
        expect(steps.length).to eq(2)
        expect(steps[0]['id']).to eq(step1.id)
        expect(steps[1]['id']).to eq(step2.id)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get api_v1_internal_devops_pipeline_run_path(pipeline_run)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with non-existent pipeline run' do
      it 'returns not found' do
        non_existent_id = SecureRandom.uuid

        get api_v1_internal_devops_pipeline_run_path(non_existent_id), headers: internal_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Pipeline run not found')
      end
    end
  end

  describe 'PATCH /api/v1/internal/devops/pipeline_runs/:id' do
    context 'with valid parameters' do
      let(:update_params) do
        {
          pipeline_run: {
            status: 'running',
            started_at: Time.current.iso8601,
            outputs: { result: 'success' },
            artifacts: { build: 'artifact.zip' }
          }
        }
      end

      it 'updates the pipeline run' do
        patch api_v1_internal_devops_pipeline_run_path(pipeline_run),
              params: update_params,
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['pipeline_run']['status']).to eq('running')

        pipeline_run.reload
        expect(pipeline_run.status).to eq('running')
        expect(pipeline_run.outputs['result']).to eq('success')
      end

      it 'updates completion status' do
        completed_at = Time.current
        patch api_v1_internal_devops_pipeline_run_path(pipeline_run),
              params: {
                pipeline_run: {
                  status: 'success',
                  completed_at: completed_at.iso8601
                }
              },
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        pipeline_run.reload
        expect(pipeline_run.status).to eq('success')
        expect(pipeline_run.completed_at).to be_within(1.second).of(completed_at)
      end

      it 'updates error message' do
        patch api_v1_internal_devops_pipeline_run_path(pipeline_run),
              params: {
                pipeline_run: {
                  status: 'failure',
                  error_message: 'Build failed'
                }
              },
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        pipeline_run.reload
        expect(pipeline_run.error_message).to eq('Build failed')
      end
    end

    context 'with invalid parameters' do
      it 'returns validation error' do
        patch api_v1_internal_devops_pipeline_run_path(pipeline_run),
              params: { pipeline_run: { status: 'invalid_status' } },
              headers: internal_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        patch api_v1_internal_devops_pipeline_run_path(pipeline_run),
              params: { pipeline_run: { status: 'running' } }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
