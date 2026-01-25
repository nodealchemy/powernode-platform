# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::Devops::StepExecutions', type: :request do
  let(:account) { create(:account) }
  let(:pipeline) { create(:ci_cd_pipeline, account: account) }
  let(:pipeline_run) { create(:ci_cd_pipeline_run, pipeline: pipeline, account: account) }
  let(:pipeline_step) { create(:ci_cd_pipeline_step, pipeline: pipeline) }
  let(:step_execution) do
    create(:ci_cd_step_execution,
           pipeline_run: pipeline_run,
           pipeline_step: pipeline_step,
           account: account)
  end

  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'POST /api/v1/internal/devops/step_executions' do
    context 'with valid parameters' do
      let(:create_params) do
        {
          step_execution: {
            pipeline_run_id: pipeline_run.id,
            pipeline_step_id: pipeline_step.id,
            status: 'pending'
          }
        }
      end

      it 'creates a new step execution' do
        expect {
          post api_v1_internal_devops_step_executions_path,
               params: create_params,
               headers: internal_headers
        }.to change(Devops::StepExecution, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['step_execution']['status']).to eq('pending')
        expect(json['data']['step_execution']['pipeline_run_id']).to eq(pipeline_run.id)
        expect(json['data']['step_execution']['pipeline_step_id']).to eq(pipeline_step.id)
      end

      it 'defaults status to pending if not provided' do
        params = {
          step_execution: {
            pipeline_run_id: pipeline_run.id,
            pipeline_step_id: pipeline_step.id
          }
        }

        post api_v1_internal_devops_step_executions_path,
             params: params,
             headers: internal_headers

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['data']['step_execution']['status']).to eq('pending')
      end
    end

    context 'with non-existent pipeline run' do
      it 'returns not found error' do
        params = {
          step_execution: {
            pipeline_run_id: SecureRandom.uuid,
            pipeline_step_id: pipeline_step.id
          }
        }

        post api_v1_internal_devops_step_executions_path,
             params: params,
             headers: internal_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to include('Record not found')
      end
    end

    context 'with non-existent pipeline step' do
      it 'returns not found error' do
        params = {
          step_execution: {
            pipeline_run_id: pipeline_run.id,
            pipeline_step_id: SecureRandom.uuid
          }
        }

        post api_v1_internal_devops_step_executions_path,
             params: params,
             headers: internal_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        post api_v1_internal_devops_step_executions_path,
             params: { step_execution: { pipeline_run_id: pipeline_run.id } }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/internal/devops/step_executions/:id' do
    context 'with valid internal authentication' do
      it 'returns the step execution' do
        get api_v1_internal_devops_step_execution_path(step_execution),
            headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['step_execution']['id']).to eq(step_execution.id)
        expect(json['data']['step_execution']['status']).to eq(step_execution.status)
        expect(json['data']['step_execution']['pipeline_run_id']).to eq(pipeline_run.id)
        expect(json['data']['step_execution']['pipeline_step_id']).to eq(pipeline_step.id)
      end

      it 'includes outputs and logs' do
        step_execution.update!(
          outputs: { result: 'success', data: 'output' },
          logs: 'Step completed successfully'
        )

        get api_v1_internal_devops_step_execution_path(step_execution),
            headers: internal_headers

        json = JSON.parse(response.body)
        expect(json['data']['step_execution']['outputs']['result']).to eq('success')
        expect(json['data']['step_execution']['logs']).to eq('Step completed successfully')
      end
    end

    context 'with non-existent step execution' do
      it 'returns not found' do
        get api_v1_internal_devops_step_execution_path(SecureRandom.uuid),
            headers: internal_headers

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['error']).to eq('Step execution not found')
      end
    end
  end

  describe 'PATCH /api/v1/internal/devops/step_executions/:id' do
    context 'with valid parameters' do
      let(:update_params) do
        {
          step_execution: {
            status: 'running',
            started_at: Time.current.iso8601,
            logs: 'Execution started',
            outputs: { progress: 50 }
          }
        }
      end

      it 'updates the step execution' do
        patch api_v1_internal_devops_step_execution_path(step_execution),
              params: update_params,
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['step_execution']['status']).to eq('running')
        expect(json['data']['step_execution']['logs']).to eq('Execution started')

        step_execution.reload
        expect(step_execution.status).to eq('running')
        expect(step_execution.outputs['progress']).to eq(50)
      end

      it 'updates completion status' do
        completed_at = Time.current
        patch api_v1_internal_devops_step_execution_path(step_execution),
              params: {
                step_execution: {
                  status: 'success',
                  completed_at: completed_at.iso8601
                }
              },
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        step_execution.reload
        expect(step_execution.status).to eq('success')
        expect(step_execution.completed_at).to be_within(1.second).of(completed_at)
      end

      it 'updates error message on failure' do
        patch api_v1_internal_devops_step_execution_path(step_execution),
              params: {
                step_execution: {
                  status: 'failed',
                  error_message: 'Step execution failed'
                }
              },
              headers: internal_headers

        expect(response).to have_http_status(:ok)
        step_execution.reload
        expect(step_execution.error_message).to eq('Step execution failed')
      end
    end

    context 'with invalid parameters' do
      it 'returns validation error' do
        patch api_v1_internal_devops_step_execution_path(step_execution),
              params: { step_execution: { status: 'invalid_status' } },
              headers: internal_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        patch api_v1_internal_devops_step_execution_path(step_execution),
              params: { step_execution: { status: 'running' } }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
