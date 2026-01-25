# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::IntegrationExecutions', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: ['devops.integrations.read']) }
  let(:user_with_execute_permission) { create(:user, account: account, permissions: ['devops.integrations.read', 'devops.integrations.execute']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/devops/integration_executions' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:instance) { create(:devops_integration_instance, account: account) }

    before do
      create_list(:devops_integration_execution, 3, account: account, integration_instance: instance)
    end

    context 'with devops.integrations.read permission' do
      it 'returns list of executions' do
        get '/api/v1/devops/integration_executions', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['executions']).to be_an(Array)
        expect(response_data['data']['executions'].length).to eq(3)
      end

      it 'includes pagination meta' do
        get '/api/v1/devops/integration_executions', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['pagination']).to include('current_page', 'total_pages', 'total_count')
      end

      it 'filters by instance_id' do
        other_instance = create(:devops_integration_instance, account: account)
        create(:devops_integration_execution, account: account, integration_instance: other_instance)

        get '/api/v1/devops/integration_executions',
            params: { instance_id: instance.id },
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['executions'].length).to eq(3)
      end

      it 'filters by status' do
        create(:devops_integration_execution, account: account, integration_instance: instance, status: 'failed')

        get '/api/v1/devops/integration_executions',
            params: { status: 'failed' },
            headers: headers,
            as: :json

        expect_success_response
        response_data = json_response

        statuses = response_data['data']['executions'].map { |e| e['status'] }
        expect(statuses.uniq).to eq(['failed'])
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/devops/integration_executions', headers: headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/devops/integration_executions', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/integration_executions/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:instance) { create(:devops_integration_instance, account: account) }
    let(:execution) { create(:devops_integration_execution, account: account, integration_instance: instance) }

    context 'with devops.integrations.read permission' do
      it 'returns execution details' do
        get "/api/v1/devops/integration_executions/#{execution.id}", headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['execution']).to be_present
      end
    end

    context 'when execution does not exist' do
      it 'returns not found error' do
        get '/api/v1/devops/integration_executions/nonexistent-id', headers: headers, as: :json

        expect_error_response('Execution', 404)
      end
    end

    context 'when accessing other account execution' do
      let(:other_account) { create(:account) }
      let(:other_instance) { create(:devops_integration_instance, account: other_account) }
      let(:other_execution) { create(:devops_integration_execution, account: other_account, integration_instance: other_instance) }

      it 'returns not found error' do
        get "/api/v1/devops/integration_executions/#{other_execution.id}", headers: headers, as: :json

        expect_error_response('Execution', 404)
      end
    end
  end

  describe 'POST /api/v1/devops/integration_executions/:id/retry' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:instance) { create(:devops_integration_instance, account: account) }
    let(:execution) { create(:devops_integration_execution, account: account, integration_instance: instance, status: 'failed') }

    context 'with devops.integrations.execute permission' do
      it 'retries execution successfully' do
        allow(Devops::ExecutionService).to receive(:retry_execution).and_return(
          { success: true, execution_id: 'new-execution-id' }
        )

        post "/api/v1/devops/integration_executions/#{execution.id}/retry", headers: headers, as: :json

        expect_success_response
      end

      it 'handles retry errors' do
        allow(Devops::ExecutionService).to receive(:retry_execution).and_return(
          { success: false, error: 'Cannot retry execution' }
        )

        post "/api/v1/devops/integration_executions/#{execution.id}/retry", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post "/api/v1/devops/integration_executions/#{execution.id}/retry", headers: headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'POST /api/v1/devops/integration_executions/:id/cancel' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:instance) { create(:devops_integration_instance, account: account) }
    let(:execution) { create(:devops_integration_execution, account: account, integration_instance: instance, status: 'running') }

    context 'with devops.integrations.execute permission' do
      it 'cancels execution successfully' do
        allow(Devops::ExecutionService).to receive(:cancel_execution).and_return(
          { success: true }
        )

        post "/api/v1/devops/integration_executions/#{execution.id}/cancel", headers: headers, as: :json

        expect_success_response
      end

      it 'handles cancel errors' do
        allow(Devops::ExecutionService).to receive(:cancel_execution).and_return(
          { success: false, error: 'Cannot cancel execution' }
        )

        post "/api/v1/devops/integration_executions/#{execution.id}/cancel", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /api/v1/devops/integration_executions/stats' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:instance) { create(:devops_integration_instance, account: account) }

    before do
      create_list(:devops_integration_execution, 2, account: account, integration_instance: instance, status: 'completed')
      create(:devops_integration_execution, account: account, integration_instance: instance, status: 'failed')
    end

    context 'with devops.integrations.read permission' do
      it 'returns execution statistics' do
        get '/api/v1/devops/integration_executions/stats', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['stats']).to include('total', 'completed', 'failed')
      end

      it 'includes success rate' do
        get '/api/v1/devops/integration_executions/stats', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['stats']).to have_key('success_rate')
      end

      it 'filters stats by instance_id' do
        get '/api/v1/devops/integration_executions/stats',
            params: { instance_id: instance.id },
            headers: headers,
            as: :json

        expect_success_response
      end

      it 'accepts period parameter' do
        get '/api/v1/devops/integration_executions/stats',
            params: { period: 7 },
            headers: headers,
            as: :json

        expect_success_response
      end
    end
  end
end
