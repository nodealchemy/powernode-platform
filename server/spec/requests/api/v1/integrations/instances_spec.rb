# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Integrations::Instances', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['integrations.read', 'integrations.create', 'integrations.update', 'integrations.delete', 'integrations.execute']) }
  let(:limited_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['integrations.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:limited_headers) { auth_headers_for(limited_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  let(:template) { create(:devops_integration_template) }

  describe 'GET /api/v1/integrations/instances' do
    let!(:instance1) { create(:devops_integration_instance, account: account, template: template, name: "Instance 1") }
    let!(:instance2) { create(:devops_integration_instance, :paused, account: account, template: template, name: "Instance 2") }
    let!(:other_instance) { create(:devops_integration_instance, account: other_account) }

    before do
      allow(Devops::RegistryService).to receive(:list_instances).and_return(
        double(map: [instance1.instance_summary, instance2.instance_summary],
               current_page: 1, total_pages: 1, total_count: 2, limit_value: 25)
      )
    end

    context 'with proper permissions' do
      it 'returns list of instances for current account' do
        get '/api/v1/integrations/instances', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['instances']).to be_an(Array)
        expect(data['instances'].length).to eq(2)
        expect(data['pagination']).to have_key('current_page')
      end

      it 'filters by status' do
        allow(Devops::RegistryService).to receive(:list_instances).and_return(
          double(map: [instance2.instance_summary], current_page: 1, total_pages: 1, total_count: 1, limit_value: 25)
        )

        get '/api/v1/integrations/instances', params: { status: 'paused' }, headers: headers, as: :json

        expect_success_response
      end

      it 'supports pagination' do
        get '/api/v1/integrations/instances', params: { page: 1, per_page: 10 }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['pagination']).to have_key('per_page')
      end
    end

    context 'without integrations.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/integrations/instances', headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/integrations/instances', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/integrations/instances/:id' do
    let(:instance) { create(:devops_integration_instance, account: account, template: template) }
    let(:other_instance) { create(:devops_integration_instance, account: other_account) }

    before do
      allow(Devops::RegistryService).to receive(:find_instance).with(
        account: account, instance_id: instance.id
      ).and_return(instance)
    end

    context 'with proper permissions' do
      it 'returns instance details' do
        get "/api/v1/integrations/instances/#{instance.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['instance']).to include(
          'id' => instance.id,
          'name' => instance.name,
          'slug' => instance.slug,
          'status' => instance.status
        )
        expect(data['instance']).to have_key('configuration')
        expect(data['instance']).to have_key('template')
      end

      it 'returns not found for non-existent instance' do
        allow(Devops::RegistryService).to receive(:find_instance).and_raise(Devops::RegistryService::InstanceNotFoundError)

        get "/api/v1/integrations/instances/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Integration instance not found', 404)
      end
    end

    context 'accessing instance from different account' do
      it 'returns not found error' do
        allow(Devops::RegistryService).to receive(:find_instance).with(
          account: account, instance_id: other_instance.id
        ).and_raise(Devops::RegistryService::InstanceNotFoundError)

        get "/api/v1/integrations/instances/#{other_instance.id}", headers: headers, as: :json

        expect_error_response('Integration instance not found', 404)
      end
    end
  end

  describe 'POST /api/v1/integrations/instances' do
    let(:valid_params) do
      {
        template_id: template.slug,
        instance: {
          name: 'Test Instance',
          slug: 'test-instance',
          configuration: {
            api_endpoint: 'https://api.example.com'
          }
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new instance' do
        new_instance = create(:devops_integration_instance, account: account, template: template, name: 'Test Instance')
        allow(Devops::RegistryService).to receive(:install_template).and_return(new_instance)

        post '/api/v1/integrations/instances', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['instance']).to include(
          'name' => 'Test Instance'
        )
      end

      it 'returns not found for non-existent template' do
        allow(Devops::RegistryService).to receive(:install_template).and_raise(Devops::RegistryService::TemplateNotFoundError)

        post '/api/v1/integrations/instances', params: valid_params, headers: headers, as: :json

        expect_error_response('Template not found', 404)
      end

      it 'returns validation error for invalid params' do
        allow(Devops::RegistryService).to receive(:install_template).and_raise(
          Devops::RegistryService::ValidationError.new('Name is required')
        )

        invalid_params = valid_params.deep_merge(instance: { name: nil })

        post '/api/v1/integrations/instances', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without integrations.create permission' do
      it 'returns forbidden error' do
        post '/api/v1/integrations/instances', params: valid_params, headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'PATCH /api/v1/integrations/instances/:id' do
    let(:instance) { create(:devops_integration_instance, account: account, template: template) }
    let(:update_params) do
      {
        instance: {
          name: 'Updated Instance Name',
          configuration: { timeout: 60 }
        }
      }
    end

    before do
      allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
    end

    context 'with proper permissions' do
      it 'updates the instance' do
        updated_instance = instance.dup
        updated_instance.name = 'Updated Instance Name'
        allow(Devops::RegistryService).to receive(:update_instance).and_return(updated_instance)

        patch "/api/v1/integrations/instances/#{instance.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['instance']['name']).to eq('Updated Instance Name')
      end

      it 'returns validation error for invalid update' do
        allow(Devops::RegistryService).to receive(:update_instance).and_raise(
          Devops::RegistryService::ValidationError.new('Invalid configuration')
        )

        patch "/api/v1/integrations/instances/#{instance.id}", params: update_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without integrations.update permission' do
      it 'returns forbidden error' do
        patch "/api/v1/integrations/instances/#{instance.id}", params: update_params, headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'DELETE /api/v1/integrations/instances/:id' do
    let(:instance) { create(:devops_integration_instance, account: account, template: template) }

    before do
      allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
      allow(Devops::RegistryService).to receive(:uninstall_instance).and_return(true)
    end

    context 'with proper permissions' do
      it 'deletes the instance' do
        delete "/api/v1/integrations/instances/#{instance.id}", headers: headers, as: :json

        expect_success_response
        expect(json_response_data['message']).to eq('Integration uninstalled')
      end
    end

    context 'without integrations.delete permission' do
      it 'returns forbidden error' do
        delete "/api/v1/integrations/instances/#{instance.id}", headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'POST /api/v1/integrations/instances/:id/activate' do
    let(:instance) { create(:devops_integration_instance, :paused, account: account, template: template) }

    before do
      allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
    end

    context 'with proper permissions' do
      it 'activates the instance' do
        activated_instance = instance.dup
        activated_instance.status = 'active'
        allow(Devops::RegistryService).to receive(:activate_instance).and_return(activated_instance)

        post "/api/v1/integrations/instances/#{instance.id}/activate", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['instance']['status']).to eq('active')
      end

      it 'returns error when activation fails' do
        allow(Devops::RegistryService).to receive(:activate_instance).and_raise(
          Devops::RegistryService::ValidationError.new('Cannot activate instance with missing credentials')
        )

        post "/api/v1/integrations/instances/#{instance.id}/activate", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without integrations.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/integrations/instances/#{instance.id}/activate", headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'POST /api/v1/integrations/instances/:id/deactivate' do
    let(:instance) { create(:devops_integration_instance, account: account, template: template) }

    before do
      allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
    end

    context 'with proper permissions' do
      it 'deactivates the instance' do
        deactivated_instance = instance.dup
        deactivated_instance.status = 'paused'
        allow(Devops::RegistryService).to receive(:deactivate_instance).and_return(deactivated_instance)

        post "/api/v1/integrations/instances/#{instance.id}/deactivate", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['instance']['status']).to eq('paused')
      end
    end

    context 'without integrations.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/integrations/instances/#{instance.id}/deactivate", headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'POST /api/v1/integrations/instances/:id/test' do
    let(:instance) { create(:devops_integration_instance, account: account, template: template) }

    before do
      allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
    end

    context 'with proper permissions' do
      it 'tests the connection' do
        allow(Devops::ExecutionService).to receive(:test_connection).and_return({ success: true, message: 'Connection successful' })

        post "/api/v1/integrations/instances/#{instance.id}/test", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['result']['success']).to be true
      end
    end

    context 'without integrations.execute permission' do
      it 'returns forbidden error' do
        post "/api/v1/integrations/instances/#{instance.id}/test", headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'POST /api/v1/integrations/instances/:id/execute' do
    let(:instance) { create(:devops_integration_instance, account: account, template: template) }
    let(:execute_params) do
      {
        method: 'POST',
        path: '/api/test',
        body: { key: 'value' }
      }
    end

    before do
      allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
    end

    context 'with proper permissions' do
      it 'executes the integration' do
        allow(Devops::ExecutionService).to receive(:execute).and_return({ success: true, execution_id: 'exec_123' })

        post "/api/v1/integrations/instances/#{instance.id}/execute", params: execute_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['result']['success']).to be true
      end

      it 'returns error when integration is not active' do
        inactive_instance = create(:devops_integration_instance, :paused, account: account, template: template)
        allow(Devops::RegistryService).to receive(:find_instance).and_return(inactive_instance)

        post "/api/v1/integrations/instances/#{inactive_instance.id}/execute", params: execute_params, headers: headers, as: :json

        expect_error_response('Integration is not active', 422)
      end

      it 'returns error when execution fails' do
        allow(Devops::ExecutionService).to receive(:execute).and_return({ success: false, error: 'Execution failed', execution_id: 'exec_456' })

        post "/api/v1/integrations/instances/#{instance.id}/execute", params: execute_params, headers: headers, as: :json

        expect_error_response('Execution failed', 422)
      end
    end

    context 'without integrations.execute permission' do
      it 'returns forbidden error' do
        post "/api/v1/integrations/instances/#{instance.id}/execute", params: execute_params, headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'GET /api/v1/integrations/instances/:id/health' do
    let(:instance) { create(:devops_integration_instance, account: account, template: template) }

    before do
      allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
    end

    context 'with proper permissions' do
      it 'returns health status' do
        allow(Devops::ExecutionService).to receive(:health_check).and_return({ healthy: true, status: 'healthy' })

        get "/api/v1/integrations/instances/#{instance.id}/health", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['health']).to have_key('healthy')
      end
    end

    context 'without integrations.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/integrations/instances/#{instance.id}/health", headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'GET /api/v1/integrations/instances/:id/stats' do
    let(:instance) { create(:devops_integration_instance, :with_executions, account: account, template: template) }

    before do
      allow(Devops::RegistryService).to receive(:find_instance).and_return(instance)
    end

    context 'with proper permissions' do
      it 'returns execution statistics' do
        allow(Devops::ExecutionService).to receive(:execution_stats).and_return({
          total: 10,
          success: 8,
          failed: 2,
          success_rate: 80.0
        })

        get "/api/v1/integrations/instances/#{instance.id}/stats", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['stats']).to have_key('total')
      end

      it 'supports custom period' do
        allow(Devops::ExecutionService).to receive(:execution_stats).and_return({})

        get "/api/v1/integrations/instances/#{instance.id}/stats", params: { period: 7 }, headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without integrations.read permission' do
      it 'returns forbidden error' do
        get "/api/v1/integrations/instances/#{instance.id}/stats", headers: limited_headers, as: :json

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end
end
