# frozen_string_literal: true

require 'rails_helper'

# IMP-01a04d08-9288. These examples used to stub Devops::RegistryService — the
# actuator behind every endpoint here — wholesale, returning doubles, so each
# write path asserted only on the status the controller renders around a stub.
# Proven by execution: with every save/update/destroy in RegistryService
# disabled, the file stayed 100% green.
#
# They now drive the REAL service and assert the ROW: what was created, changed
# or removed, and what was left alone. Stubs remain only at genuine external
# boundaries — Devops::ExecutionService (it calls the integration's remote
# API) and the executor's test_connection on activate.
RSpec.describe 'Api::V1::Devops::IntegrationInstances', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:template) { create(:devops_integration_template, usage_count: 0) }
  let(:user_with_read_permission) { create(:user, account: account, permissions: [ 'devops.integrations.read' ]) }
  let(:user_with_create_permission) { create(:user, account: account, permissions: [ 'devops.integrations.read', 'devops.integrations.create' ]) }
  let(:user_with_update_permission) { create(:user, account: account, permissions: [ 'devops.integrations.read', 'devops.integrations.update' ]) }
  let(:user_with_execute_permission) { create(:user, account: account, permissions: [ 'devops.integrations.read', 'devops.integrations.execute' ]) }
  let(:user_with_delete_permission) { create(:user, account: account, permissions: [ 'devops.integrations.read', 'devops.integrations.delete' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  def account_instances = Devops::IntegrationInstance.where(account: account)

  describe 'GET /api/v1/devops/integration_instances' do
    let(:headers) { auth_headers_for(user_with_read_permission) }

    before do
      create(:devops_integration_instance, account: account, template: template, name: 'Instance 1', slug: 'instance-1')
      create(:devops_integration_instance, account: account, template: template, name: 'Instance 2', slug: 'instance-2')
      create(:devops_integration_instance, account: other_account, template: template, name: 'Foreign', slug: 'foreign')
    end

    context 'with devops.integrations.read permission' do
      it "lists this account's instances and nobody else's" do
        get '/api/v1/devops/integration_instances', headers: headers, as: :json

        expect_success_response
        names = json_response['data']['instances'].map { |i| i['name'] }
        expect(names).to contain_exactly('Instance 1', 'Instance 2')
      end

      it 'includes pagination meta' do
        get '/api/v1/devops/integration_instances', headers: headers, as: :json

        expect(json_response['data']['pagination']).to include('current_page', 'total_pages', 'total_count')
        expect(json_response['data']['pagination']['total_count']).to eq(2)
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
    let(:instance) { create(:devops_integration_instance, account: account, template: template) }

    it 'returns the instance' do
      get "/api/v1/devops/integration_instances/#{instance.id}", headers: headers, as: :json

      expect_success_response
      expect(json_response['data']['instance']['id']).to eq(instance.id)
    end

    it 'returns not found for an unknown id' do
      get "/api/v1/devops/integration_instances/#{SecureRandom.uuid}", headers: headers, as: :json

      expect_error_response('Integration instance', 404)
    end

    it "returns not found for another account's instance" do
      foreign = create(:devops_integration_instance, account: other_account, template: template)

      get "/api/v1/devops/integration_instances/#{foreign.id}", headers: headers, as: :json

      expect_error_response('Integration instance', 404)
    end
  end

  describe 'POST /api/v1/devops/integration_instances' do
    let(:headers) { auth_headers_for(user_with_create_permission) }
    let(:valid_params) do
      {
        template_id: template.id,
        instance: { name: 'Test Instance', slug: 'test-instance', configuration: { key: 'value' } }
      }
    end

    context 'with devops.integrations.create permission' do
      it 'installs the template as a pending instance in this account and counts the install' do
        expect {
          post '/api/v1/devops/integration_instances', params: valid_params, headers: headers, as: :json
        }.to change { account_instances.count }.by(1)

        expect(response).to have_http_status(:created)
        row = account_instances.find_by!(slug: 'test-instance')
        expect(row).to have_attributes(name: 'Test Instance', status: 'pending', integration_template_id: template.id)
        # The caller's configuration is merged over the template default.
        expect(row.configuration).to include('timeout' => 30, 'key' => 'value')
        expect(template.reload.usage_count).to eq(1)
        expect(json_response['data']['instance']['id']).to eq(row.id)
      end

      it 'answers 404 and creates nothing for an unknown template' do
        expect {
          post '/api/v1/devops/integration_instances',
               params: valid_params.merge(template_id: SecureRandom.uuid), headers: headers, as: :json
        }.not_to change(Devops::IntegrationInstance, :count)

        expect_error_response('Template', 404)
      end

      it 'answers 422 and creates nothing when the slug is already taken in this account' do
        create(:devops_integration_instance, account: account, template: template, slug: 'test-instance')

        expect {
          post '/api/v1/devops/integration_instances', params: valid_params, headers: headers, as: :json
        }.not_to change(Devops::IntegrationInstance, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(template.reload.usage_count).to eq(0)
      end
    end

    context 'without permission' do
      let(:headers) { auth_headers_for(user_with_read_permission) }

      it 'returns forbidden and creates nothing' do
        expect {
          post '/api/v1/devops/integration_instances', params: valid_params, headers: headers, as: :json
        }.not_to change(Devops::IntegrationInstance, :count)

        expect_error_response("You don't have permission to perform this action", 403)
      end
    end
  end

  describe 'PATCH /api/v1/devops/integration_instances/:id' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:instance) { create(:devops_integration_instance, account: account, template: template, name: 'Before') }

    it 'persists the new name' do
      patch "/api/v1/devops/integration_instances/#{instance.id}",
            params: { instance: { name: 'Updated Instance' } }, headers: headers, as: :json

      expect_success_response
      expect(instance.reload.name).to eq('Updated Instance')
    end

    it 'answers 422 and leaves the row alone when the update is invalid' do
      patch "/api/v1/devops/integration_instances/#{instance.id}",
            params: { instance: { name: '' } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(instance.reload.name).to eq('Before')
    end

    it "cannot reach another account's instance" do
      foreign = create(:devops_integration_instance, account: other_account, template: template, name: 'Theirs')

      patch "/api/v1/devops/integration_instances/#{foreign.id}",
            params: { instance: { name: 'Hijacked' } }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.name).to eq('Theirs')
    end
  end

  describe 'DELETE /api/v1/devops/integration_instances/:id' do
    let(:headers) { auth_headers_for(user_with_delete_permission) }
    let(:counted_template) { create(:devops_integration_template, usage_count: 1) }
    let!(:instance) { create(:devops_integration_instance, account: account, template: counted_template) }

    it 'removes the row and gives the install back to the template' do
      expect {
        delete "/api/v1/devops/integration_instances/#{instance.id}", headers: headers, as: :json
      }.to change { account_instances.count }.by(-1)

      expect_success_response
      expect(Devops::IntegrationInstance.exists?(instance.id)).to be(false)
      expect(counted_template.reload.usage_count).to eq(0)
    end

    it "cannot delete another account's instance" do
      foreign = create(:devops_integration_instance, account: other_account, template: counted_template)

      delete "/api/v1/devops/integration_instances/#{foreign.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Devops::IntegrationInstance.exists?(foreign.id)).to be(true)
    end
  end

  describe 'POST /api/v1/devops/integration_instances/:id/activate' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:instance) { create(:devops_integration_instance, account: account, template: template, status: 'disabled') }

    # The connection test reaches the integration's remote API — the one
    # external boundary on this path, and the only thing stubbed here.
    def connection_test_returns(result)
      allow(Devops::ExecutionService).to receive(:build_executor).and_return(double(test_connection: result))
    end

    it 'activates the row when the connection test passes' do
      connection_test_returns({ success: true })

      post "/api/v1/devops/integration_instances/#{instance.id}/activate", headers: headers, as: :json

      expect_success_response
      expect(instance.reload.status).to eq('active')
    end

    it 'answers 422 and leaves the row inactive when the connection test fails' do
      connection_test_returns({ success: false, error: 'unreachable' })

      post "/api/v1/devops/integration_instances/#{instance.id}/activate", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(instance.reload.status).to eq('disabled')
    end
  end

  describe 'POST /api/v1/devops/integration_instances/:id/deactivate' do
    let(:headers) { auth_headers_for(user_with_update_permission) }
    let(:instance) { create(:devops_integration_instance, account: account, template: template, status: 'active') }

    it 'pauses the row' do
      post "/api/v1/devops/integration_instances/#{instance.id}/deactivate", headers: headers, as: :json

      expect_success_response
      expect(instance.reload.status).to eq('paused')
    end
  end

  describe 'POST /api/v1/devops/integration_instances/:id/test' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:instance) { create(:devops_integration_instance, account: account, template: template) }

    it 'tests the connection of the resolved instance' do
      allow(Devops::ExecutionService).to receive(:test_connection).and_return({ success: true, message: 'Connection successful' })

      post "/api/v1/devops/integration_instances/#{instance.id}/test", headers: headers, as: :json

      expect_success_response
      expect(Devops::ExecutionService).to have_received(:test_connection).with(instance: instance)
    end
  end

  describe 'POST /api/v1/devops/integration_instances/:id/execute' do
    let(:headers) { auth_headers_for(user_with_execute_permission) }
    let(:instance) { create(:devops_integration_instance, account: account, template: template, status: 'active') }

    it 'executes the resolved instance' do
      allow(Devops::ExecutionService).to receive(:execute).and_return({ success: true, execution_id: 'exec-123' })

      post "/api/v1/devops/integration_instances/#{instance.id}/execute",
           params: { method: 'POST', path: '/test' }, headers: headers, as: :json

      expect_success_response
      expect(Devops::ExecutionService).to have_received(:execute).with(hash_including(instance: instance))
    end

    it 'refuses to execute an inactive instance without calling out' do
      disabled_instance = create(:devops_integration_instance, account: account, template: template, status: 'disabled')
      allow(Devops::ExecutionService).to receive(:execute)

      post "/api/v1/devops/integration_instances/#{disabled_instance.id}/execute", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Devops::ExecutionService).not_to have_received(:execute)
    end

    it 'handles execution errors' do
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

  describe 'GET /api/v1/devops/integration_instances/:id/health' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:instance) { create(:devops_integration_instance, account: account, template: template) }

    it 'returns health status' do
      allow(Devops::ExecutionService).to receive(:health_check).and_return({ healthy: true, last_check: Time.current })

      get "/api/v1/devops/integration_instances/#{instance.id}/health", headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/devops/integration_instances/:id/stats' do
    let(:headers) { auth_headers_for(user_with_read_permission) }
    let(:instance) { create(:devops_integration_instance, account: account, template: template) }

    it 'returns execution stats' do
      allow(Devops::ExecutionService).to receive(:execution_stats).and_return({ total: 10, success: 8, failed: 2 })

      get "/api/v1/devops/integration_instances/#{instance.id}/stats", headers: headers, as: :json

      expect_success_response
    end

    it 'accepts period parameter' do
      allow(Devops::ExecutionService).to receive(:execution_stats).and_return({})

      get "/api/v1/devops/integration_instances/#{instance.id}/stats", params: { period: 7 }, headers: headers

      expect_success_response
    end
  end
end
