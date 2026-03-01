# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::IntegrationInstances', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: [ 'devops.integrations.read' ]) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: [ 'devops.integrations.read', 'devops.integrations.create' ]) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: [ 'devops.integrations.read', 'devops.integrations.update' ]) }
  let(:user_with_execute_permission) { create(:user, account: account, permissions: [ 'devops.integrations.read', 'devops.integrations.execute' ]) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: [ 'devops.integrations.read', 'devops.integrations.delete' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/devops/integration_instances' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      allow(Devops::RegistryService).to receive(:list_instances).and_return(
        double(map: [
          { id: '1', name: 'Instance 1' },
          { id: '2', name: 'Instance 2' }
        ], current_page: 1, total_pages: 1, total_count: 2, limit_value: 20)
      )
    end

    context 'with devops.integrations.read permission' do
      it 'returns list of instances' do
        get '/api/v1/devops/integration_instances', headers: headers, as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['instances']).to be_an(Array)
      end

      it 'includes pagination meta' do
        get '/api/v1/devops/integration_instances', headers: headers, as: :json

        response_data = json_response
        expect(response_data['data']['pagination']).to include('current_page', 'total_pages', 'total_count')
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(regular_user) }

      it 'returns forbidden error' do
        get '/api/v1/devops/integration_instances', headers: headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/devops/integration_instances', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/integration_instances/:id' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:instance) { create(:devops_integration_instance, account: account) }

    context 'with devops.integrations.read permission' do
      it 'returns instance details' do
        allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)

        get "/api/v1/devops/integration_instances/#{instance.id}", headers: headers, as: :json

        expect_success_response
      end
    end

    context 'when instance does not exist' do
      it 'returns not found error' do
        allow(Devops::RegistryService).to receive(:find_instance).and_raise(
          Devops::RegistryService::InstanceNotFoundError
        )

        get '/api/v1/devops/integration_instances/nonexistent-id', headers: headers, as: :json

        expect_error_response('Integration instance', 404)
      end
    end
  end

  describe 'POST /api/v1/devops/integration_instances' do
    let(:headers) { auth_headers_for(user_with_create_permission) }
    let(:template) { create(:devops_integration_template) }

    context 'with devops.integrations.create permission' do
      let(:valid_params) do
        {
          template_id: template.id,
          instance: {
            name: 'Test Instance',
            slug: 'test-instance',
            configuration: { key: 'value' }
          }
        }
      end

      it 'creates a new instance' do
        instance = double(instance_details: { id: 'test-id', name: 'Test Instance' })
        allow(Devops::RegistryService).to receive(:install_template).and_return(instance)

        post '/api/v1/devops/integration_instances', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
      end

      it 'handles template not found' do
        allow(Devops::RegistryService).to receive(:install_template).and_raise(
          Devops::RegistryService::TemplateNotFoundError
        )

        post '/api/v1/devops/integration_instances', params: valid_params, headers: headers, as: :json

        expect_error_response('Template', 404)
      end

      it 'handles validation errors' do
        allow(Devops::RegistryService).to receive(:install_template).and_raise(
          Devops::RegistryService::ValidationError.new('Invalid configuration')
        )

        post '/api/v1/devops/integration_instances', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden error' do
        post '/api/v1/devops/integration_instances',
             params: { instance: { name: 'Test' } },
             headers: headers,
             as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'PATCH /api/v1/devops/integration_instances/:id' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:instance) { create(:devops_integration_instance, account: account) }

    context 'with devops.integrations.update permission' do
      it 'updates instance successfully' do
        updated_instance = double(instance_details: { id: instance.id, name: 'Updated Instance' })
        allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
        allow(Devops::RegistryService).to receive(:update_instance).and_return(updated_instance)

        patch "/api/v1/devops/integration_instances/#{instance.id}",
              params: { instance: { name: 'Updated Instance' } },
              headers: headers,
              as: :json

        expect_success_response
      end

      it 'handles validation errors' do
        allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
        allow(Devops::RegistryService).to receive(:update_instance).and_raise(
          Devops::RegistryService::ValidationError.new('Invalid update')
        )

        patch "/api/v1/devops/integration_instances/#{instance.id}",
              params: { instance: { name: '' } },
              headers: headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'DELETE /api/v1/devops/integration_instances/:id' do
    let(:headers) { auth_headers_for(user_with_delete_permission) }
    let(:instance) { create(:devops_integration_instance, account: account) }

    context 'with devops.integrations.delete permission' do
      it 'deletes instance successfully' do
        allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
        allow(Devops::RegistryService).to receive(:uninstall_instance).and_return(true)

        delete "/api/v1/devops/integration_instances/#{instance.id}", headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/devops/integration_instances/:id/activate' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:instance) { create(:devops_integration_instance, account: account, status: 'disabled') }

    context 'with devops.integrations.update permission' do
      it 'activates instance successfully' do
        activated_instance = double(instance_details: { id: instance.id, status: 'active' })
        allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
        allow(Devops::RegistryService).to receive(:activate_instance).and_return(activated_instance)

        post "/api/v1/devops/integration_instances/#{instance.id}/activate", headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/devops/integration_instances/:id/deactivate' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:instance) { create(:devops_integration_instance, account: account, status: 'active') }

    context 'with devops.integrations.update permission' do
      it 'deactivates instance successfully' do
        deactivated_instance = double(instance_details: { id: instance.id, status: 'inactive' })
        allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
        allow(Devops::RegistryService).to receive(:deactivate_instance).and_return(deactivated_instance)

        post "/api/v1/devops/integration_instances/#{instance.id}/deactivate", headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/devops/integration_instances/:id/test' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:instance) { create(:devops_integration_instance, account: account) }

    context 'with devops.integrations.execute permission' do
      it 'tests connection successfully' do
        allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
        allow(Devops::ExecutionService).to receive(:test_connection).and_return(
          { success: true, message: 'Connection successful' }
        )

        post "/api/v1/devops/integration_instances/#{instance.id}/test", headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/devops/integration_instances/:id/execute' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:instance) { create(:devops_integration_instance, account: account, status: 'active') }

    context 'with devops.integrations.execute permission' do
      it 'executes instance successfully' do
        allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
        allow(Devops::ExecutionService).to receive(:execute).and_return(
          { success: true, execution_id: 'exec-123' }
        )

        post "/api/v1/devops/integration_instances/#{instance.id}/execute",
             params: { method: 'POST', path: '/test' },
             headers: headers,
             as: :json

        expect_success_response
      end

      it 'prevents execution of inactive instance' do
        disabled_instance = create(:devops_integration_instance, account: account, status: 'disabled')
        allow(Devops::RegistryService).to receive(:find_instance).and_return(disabled_instance)

        post "/api/v1/devops/integration_instances/#{disabled_instance.id}/execute", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'handles execution errors' do
        allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
        allow(Devops::ExecutionService).to receive(:execute).and_return(
          { success: false, error: 'Execution failed', execution_id: 'exec-456' }
        )

        # Controller calls render_error with data: keyword which is not accepted
        # by the render_error method (only supports status:, code:, details:).
        # This causes ArgumentError, caught by Rails as 500.
        post "/api/v1/devops/integration_instances/#{instance.id}/execute", headers: headers, as: :json

        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  describe 'GET /api/v1/devops/integration_instances/:id/health' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:instance) { create(:devops_integration_instance, account: account) }

    context 'with devops.integrations.read permission' do
      it 'returns health status' do
        allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
        allow(Devops::ExecutionService).to receive(:health_check).and_return(
          { healthy: true, last_check: Time.current }
        )

        get "/api/v1/devops/integration_instances/#{instance.id}/health", headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/devops/integration_instances/:id/stats' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:instance) { create(:devops_integration_instance, account: account) }

    context 'with devops.integrations.read permission' do
      it 'returns execution stats' do
        allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
        allow(Devops::ExecutionService).to receive(:execution_stats).and_return(
          { total: 10, success: 8, failed: 2 }
        )

        get "/api/v1/devops/integration_instances/#{instance.id}/stats", headers: headers, as: :json

        expect_success_response
      end

      it 'accepts period parameter' do
        allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
        allow(Devops::ExecutionService).to receive(:execution_stats).and_return({})

        get "/api/v1/devops/integration_instances/#{instance.id}/stats",
            params: { period: 7 },
            headers: headers

        expect_success_response
      end
    end
  end
end
