# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Integrations::Executions', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['integrations.read', 'integrations.execute']) }
  let(:limited_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['integrations.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:limited_headers) { auth_headers_for(limited_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  let(:template) { create(:devops_integration_template) }
  let(:instance) { create(:devops_integration_instance, account: account, template: template) }
  let(:other_instance) { create(:devops_integration_instance, account: other_account) }

  describe 'GET /api/v1/integrations/executions' do
    let!(:execution1) { create(:devops_integration_execution, account: account, instance: instance, status: 'completed') }
    let!(:execution2) { create(:devops_integration_execution, account: account, instance: instance, status: 'failed') }
    let!(:other_execution) { create(:devops_integration_execution, account: other_account, instance: other_instance) }

    context 'with proper permissions' do
      it 'returns list of executions for current account' do
        get '/api/v1/integrations/executions', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['executions']).to be_an(Array)
        expect(data['executions'].length).to eq(2)
        expect(data['executions'].map { |e| e['id'] }).to include(execution1.id, execution2.id)
        expect(data['executions'].none? { |e| e['id'] == other_execution.id }).to be true
        expect(data['pagination']).to have_key('current_page')
      end

      it 'filters by instance_id' do
        other_instance_same_account = create(:devops_integration_instance, account: account)
        create(:devops_integration_execution, account: account, instance: other_instance_same_account)

        get '/api/v1/integrations/executions', params: { instance_id: instance.id }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['executions'].length).to eq(2)
        expect(data['executions'].all? { |e| e['id'].in?([execution1.id, execution2.id]) }).to be true
      end

      it 'filters by status' do
        get '/api/v1/integrations/executions', params: { status: 'completed' }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['executions'].length).to eq(1)
        expect(data['executions'].first['status']).to eq('completed')
      end

      it 'filters by date range' do
        get '/api/v1/integrations/executions', params: { since: 1.hour.ago.iso8601 }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['executions']).to be_an(Array)
      end

      it 'supports pagination' do
        create_list(:devops_integration_execution, 5, account: account, instance: instance)

        get '/api/v1/integrations/executions', params: { page: 1, per_page: 3 }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['executions'].length).to eq(3)
        expect(data['pagination']['per_page']).to eq(3)
      end
    end

    context 'without integrations.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/integrations/executions', headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/integrations/executions', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/integrations/executions/:id' do
    let(:execution) { create(:devops_integration_execution, :completed, account: account, instance: instance) }
    let(:other_execution) { create(:devops_integration_execution, account: other_account, instance: other_instance) }

    context 'with proper permissions' do
      it 'returns execution details' do
        get "/api/v1/integrations/executions/#{execution.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['execution']).to include(
          'id' => execution.id,
          'execution_id' => execution.execution_id,
          'status' => execution.status
        )
        expect(data['execution']).to have_key('input_data')
        expect(data['execution']).to have_key('output_data')
        expect(data['execution']).to have_key('integration_instance')
      end

      it 'returns not found for non-existent execution' do
        get "/api/v1/integrations/executions/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Execution not found', 404)
      end
    end

    context 'accessing execution from different account' do
      it 'returns not found error' do
        get "/api/v1/integrations/executions/#{other_execution.id}", headers: headers, as: :json

        expect_error_response('Execution not found', 404)
      end
    end
  end

  describe 'POST /api/v1/integrations/executions/:id/retry' do
    let(:execution) { create(:devops_integration_execution, :retriable, account: account, instance: instance) }

    context 'with proper permissions' do
      it 'retries the execution' do
        allow(Devops::ExecutionService).to receive(:retry_execution).and_return({ success: true, execution_id: 'new_exec_id' })

        post "/api/v1/integrations/executions/#{execution.id}/retry", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['result']).to have_key('success')
        expect(data['result']['success']).to be true
      end

      it 'returns error when retry fails' do
        allow(Devops::ExecutionService).to receive(:retry_execution).and_return({ success: false, error: 'Max retries reached' })

        post "/api/v1/integrations/executions/#{execution.id}/retry", headers: headers, as: :json

        expect_error_response('Max retries reached', 422)
      end
    end

    context 'without integrations.execute permission' do
      it 'returns forbidden error' do
        post "/api/v1/integrations/executions/#{execution.id}/retry", headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'POST /api/v1/integrations/executions/:id/cancel' do
    let(:execution) { create(:devops_integration_execution, :running, account: account, instance: instance) }

    context 'with proper permissions' do
      it 'cancels the execution' do
        allow(Devops::ExecutionService).to receive(:cancel_execution).and_return({ success: true })

        post "/api/v1/integrations/executions/#{execution.id}/cancel", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['result']['success']).to be true
      end

      it 'returns error when cancel fails' do
        allow(Devops::ExecutionService).to receive(:cancel_execution).and_return({ success: false, error: 'Cannot cancel completed execution' })

        post "/api/v1/integrations/executions/#{execution.id}/cancel", headers: headers, as: :json

        expect_error_response('Cannot cancel completed execution', 422)
      end
    end

    context 'without integrations.execute permission' do
      it 'returns forbidden error' do
        post "/api/v1/integrations/executions/#{execution.id}/cancel", headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'GET /api/v1/integrations/executions/stats' do
    before do
      create(:devops_integration_execution, :completed, account: account, instance: instance, created_at: 1.day.ago)
      create(:devops_integration_execution, :failed, account: account, instance: instance, created_at: 2.days.ago)
      create(:devops_integration_execution, :running, account: account, instance: instance, created_at: 3.hours.ago)
    end

    context 'with proper permissions' do
      it 'returns execution statistics' do
        get '/api/v1/integrations/executions/stats', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['stats']).to include(
          'total' => 3,
          'completed' => 1,
          'failed' => 1,
          'running' => 1
        )
        expect(data['stats']).to have_key('success_rate')
        expect(data['stats']).to have_key('by_day')
        expect(data['stats']).to have_key('by_status')
      end

      it 'filters stats by instance_id' do
        other_instance_same_account = create(:devops_integration_instance, account: account)
        create(:devops_integration_execution, account: account, instance: other_instance_same_account)

        get '/api/v1/integrations/executions/stats', params: { instance_id: instance.id }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['stats']['total']).to eq(3)
      end

      it 'supports custom period' do
        get '/api/v1/integrations/executions/stats', params: { period: 7 }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['stats']).to have_key('total')
      end
    end

    context 'without integrations.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/integrations/executions/stats', headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end
end
