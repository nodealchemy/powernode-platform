# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Workflows', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.workflows.read', 'ai.workflows.create', 'ai.workflows.update', 'ai.workflows.delete', 'ai.workflows.execute', 'ai.workflows.export']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.workflows.read']) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['ai.workflows.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  describe 'GET /api/v1/ai/workflows' do
    let!(:workflow1) { create(:ai_workflow, account: account, status: 'active') }
    let!(:workflow2) { create(:ai_workflow, account: account, status: 'draft') }
    let!(:other_workflow) { create(:ai_workflow, account: other_account) }

    context 'with proper permissions' do
      it 'returns list of workflows for current account' do
        get '/api/v1/ai/workflows', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['items']).to be_an(Array)
        expect(data['items'].length).to eq(2)
        expect(data['items'].none? { |w| w['id'] == other_workflow.id }).to be true
      end

      it 'supports pagination' do
        get "/api/v1/ai/workflows?page=1&per_page=1", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['pagination']).to include(
          'current_page' => 1,
          'per_page' => 1
        )
      end
    end

    context 'without ai.workflows.read permission' do
      it 'returns forbidden error' do
        user_without_permission = create(:user, account: account, permissions: [])
        headers_without_permission = auth_headers_for(user_without_permission)

        get '/api/v1/ai/workflows', headers: headers_without_permission, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/workflows/:id' do
    let(:workflow) { create(:ai_workflow, account: account) }

    context 'with proper permissions' do
      it 'returns workflow details' do
        get "/api/v1/ai/workflows/#{workflow.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['workflow']).to include(
          'id' => workflow.id,
          'name' => workflow.name
        )
      end

      it 'returns not found for non-existent workflow' do
        get "/api/v1/ai/workflows/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Workflow not found', 404)
      end
    end

    context 'accessing workflow from different account' do
      let(:other_workflow) { create(:ai_workflow, account: other_account) }

      it 'returns not found error' do
        get "/api/v1/ai/workflows/#{other_workflow.id}", headers: headers, as: :json

        expect_error_response('Workflow not found', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/workflows' do
    let(:valid_params) do
      {
        workflow: {
          name: 'Test Workflow',
          description: 'A test workflow',
          status: 'draft'
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new workflow' do
        expect {
          post '/api/v1/ai/workflows', params: valid_params, headers: headers, as: :json
        }.to change { account.ai_workflows.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['workflow']['name']).to eq('Test Workflow')
      end

      it 'sets creator to current user' do
        post '/api/v1/ai/workflows', params: valid_params, headers: headers, as: :json

        expect_success_response
        workflow = Ai::Workflow.last
        expect(workflow.creator_id).to eq(user.id)
      end

      it 'creates nodes if provided' do
        params_with_nodes = valid_params.deep_merge(
          workflow: {
            nodes: [
              { node_id: SecureRandom.uuid, node_type: 'start', name: 'Start', position: { x: 0, y: 0 }, is_start_node: true }
            ]
          }
        )

        post '/api/v1/ai/workflows', params: params_with_nodes, headers: headers, as: :json

        expect(response).to have_http_status(:created)
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { workflow: { name: nil } }

        post '/api/v1/ai/workflows', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without ai.workflows.create permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/workflows', params: valid_params, headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH /api/v1/ai/workflows/:id' do
    let(:workflow) { create(:ai_workflow, account: account) }
    let(:update_params) do
      {
        workflow: {
          name: 'Updated Workflow',
          description: 'Updated description'
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the workflow' do
        patch "/api/v1/ai/workflows/#{workflow.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['workflow']['name']).to eq('Updated Workflow')
        expect(data['workflow']['description']).to eq('Updated description')
      end

      it 'updates nodes if provided' do
        update_with_nodes = {
          workflow: {
            nodes: [
              { node_id: SecureRandom.uuid, node_type: 'start', name: 'Start', position: { x: 10, y: 10 }, is_start_node: true }
            ]
          }
        }

        patch "/api/v1/ai/workflows/#{workflow.id}", params: update_with_nodes, headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without ai.workflows.update permission' do
      it 'returns forbidden error' do
        patch "/api/v1/ai/workflows/#{workflow.id}", params: update_params, headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/ai/workflows/:id' do
    let(:workflow) { create(:ai_workflow, account: account) }

    context 'with proper permissions' do
      it 'deletes the workflow if allowed' do
        workflow # force creation before the expect block
        allow_any_instance_of(Ai::Workflow).to receive(:can_delete?).and_return(true)

        expect {
          delete "/api/v1/ai/workflows/#{workflow.id}", headers: headers, as: :json
        }.to change { Ai::Workflow.count }.by(-1)

        expect_success_response
      end

      it 'returns error if workflow cannot be deleted' do
        allow_any_instance_of(Ai::Workflow).to receive(:can_delete?).and_return(false)

        delete "/api/v1/ai/workflows/#{workflow.id}", headers: headers, as: :json

        expect_error_response('Cannot delete workflow with active runs', 422)
      end
    end

    context 'without ai.workflows.delete permission' do
      it 'returns forbidden error' do
        delete "/api/v1/ai/workflows/#{workflow.id}", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/workflows/:id/execute' do
    let(:workflow) { create(:ai_workflow, account: account, status: 'active') }

    context 'with proper permissions' do
      it 'executes the workflow' do
        mock_run = double(
          id: SecureRandom.uuid,
          run_id: 'run123',
          status: 'running',
          trigger_type: 'manual',
          created_at: Time.current,
          started_at: Time.current,
          completed_at: nil,
          total_nodes: 0,
          completed_nodes: 0,
          failed_nodes: 0,
          total_cost: 0.0,
          execution_time_ms: nil,
          output_variables: {},
          workflow: workflow,
          triggered_by_user: nil
        )
        service_result = double(success?: true, run: mock_run, error: nil, data: {})
        allow_any_instance_of(Ai::Workflows::ExecutionService).to receive(:execute).and_return(service_result)

        post "/api/v1/ai/workflows/#{workflow.id}/execute",
             params: { input_variables: { key: 'value' } }, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['workflow_run']).to be_present
      end

      it 'returns error on execution failure' do
        service_result = double(success?: false, error: 'Execution failed', data: { error_type: 'validation' })
        allow_any_instance_of(Ai::Workflows::ExecutionService).to receive(:execute).and_return(service_result)

        post "/api/v1/ai/workflows/#{workflow.id}/execute", headers: headers, as: :json

        expect_error_response('Execution failed', 422)
      end
    end

    context 'without ai.workflows.execute permission' do
      it 'returns forbidden error' do
        post "/api/v1/ai/workflows/#{workflow.id}/execute", headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/workflows/:id/duplicate' do
    let(:workflow) { create(:ai_workflow, account: account) }

    context 'with proper permissions' do
      it 'duplicates the workflow' do
        duplicated = create(:ai_workflow, account: account, name: "#{workflow.name} (Copy)")
        allow_any_instance_of(Ai::Workflow).to receive(:duplicate).and_return(duplicated)

        expect {
          post "/api/v1/ai/workflows/#{workflow.id}/duplicate", headers: headers, as: :json
        }.not_to change { Ai::Workflow.count }

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['workflow']).to be_present
      end
    end
  end

  describe 'GET /api/v1/ai/workflows/:id/validate' do
    let(:workflow) { create(:ai_workflow, account: account) }

    context 'with proper permissions' do
      it 'validates workflow structure' do
        allow_any_instance_of(Ai::Workflow).to receive(:validate_structure)
          .and_return({ valid: true, errors: [], warnings: [] })

        get "/api/v1/ai/workflows/#{workflow.id}/validate", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['valid']).to be true
      end

      it 'returns validation errors if invalid' do
        allow_any_instance_of(Ai::Workflow).to receive(:validate_structure)
          .and_return({ valid: false, errors: ['Missing start node'], warnings: [] })

        get "/api/v1/ai/workflows/#{workflow.id}/validate", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['valid']).to be false
        expect(data['errors']).to include('Missing start node')
      end
    end
  end

  describe 'GET /api/v1/ai/workflows/:id/export' do
    let(:workflow) { create(:ai_workflow, account: account) }

    context 'with proper permissions' do
      it 'exports workflow data' do
        get "/api/v1/ai/workflows/#{workflow.id}/export", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['export_data']).to include(
          'workflow',
          'nodes',
          'edges',
          'metadata'
        )
      end
    end

    context 'without ai.workflows.export permission' do
      it 'returns forbidden error' do
        user_without_export = create(:user, account: account, permissions: ['ai.workflows.read'])
        headers_without_export = auth_headers_for(user_without_export)

        get "/api/v1/ai/workflows/#{workflow.id}/export", headers: headers_without_export, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/workflows/import' do
    let(:import_data) do
      {
        workflow: { name: 'Imported Workflow', status: 'draft' },
        nodes: [],
        edges: []
      }
    end

    context 'with proper permissions' do
      it 'imports workflow from data' do
        imported = create(:ai_workflow, account: account, name: 'Imported Workflow')
        allow(Ai::Workflow).to receive(:import_from_data).and_return(imported)

        post '/api/v1/ai/workflows/import',
             params: { import_data: import_data }, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['workflow']).to be_present
      end

      it 'returns error if import_data is missing' do
        post '/api/v1/ai/workflows/import', headers: headers, as: :json

        expect_error_response('Import data is required', 400)
      end
    end
  end

  describe 'GET /api/v1/ai/workflows/statistics' do
    let!(:workflow1) { create(:ai_workflow, account: account, status: 'active') }
    let!(:workflow2) { create(:ai_workflow, account: account, status: 'draft') }

    context 'with proper permissions' do
      it 'returns workflow statistics' do
        get '/api/v1/ai/workflows/statistics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['statistics']).to include(
          'total_workflows',
          'active_workflows',
          'draft_workflows',
          'total_runs'
        )
      end
    end
  end

  describe 'GET /api/v1/ai/workflows/templates' do
    let!(:template) { create(:ai_workflow, account: account, is_template: true, visibility: 'public', template_category: 'automation', description: 'A public template') }

    context 'with proper permissions' do
      it 'returns available templates' do
        get '/api/v1/ai/workflows/templates', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['templates']).to be_an(Array)
      end

      it 'filters by category' do
        get '/api/v1/ai/workflows/templates?category=automation', headers: headers

        expect_success_response
      end

      it 'searches templates' do
        get '/api/v1/ai/workflows/templates?search=test', headers: headers

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/workflows/:id/convert_to_template' do
    let(:workflow) { create(:ai_workflow, account: account) }

    context 'with proper permissions' do
      it 'converts workflow to template' do
        service_result = double(success?: true, workflow: workflow)
        allow_any_instance_of(Ai::Workflows::TemplateService).to receive(:convert_to_template).and_return(service_result)

        post "/api/v1/ai/workflows/#{workflow.id}/convert_to_template",
             params: { category: 'custom' }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['template']).to be_present
      end
    end
  end

  describe 'POST /api/v1/ai/workflows/:id/create_from_template' do
    let(:template) { create(:ai_workflow, account: account, is_template: true, visibility: 'public', template_category: 'automation', description: 'A template for testing') }

    context 'with proper permissions' do
      it 'creates workflow from template' do
        new_workflow = create(:ai_workflow, account: account, name: 'New from Template')
        service_result = double(success?: true, workflow: new_workflow)
        allow_any_instance_of(Ai::Workflows::TemplateService).to receive(:create_workflow_from_source).and_return(service_result)

        post "/api/v1/ai/workflows/#{template.id}/create_from_template",
             params: { name: 'New from Template' }, headers: headers, as: :json

        expect(response).to have_http_status(:created)
      end

      it 'returns error for non-template' do
        regular_workflow = create(:ai_workflow, account: account, is_template: false)

        post "/api/v1/ai/workflows/#{regular_workflow.id}/create_from_template", headers: headers, as: :json

        expect_error_response('Template not found or not accessible', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/workflows/:id/convert_to_workflow' do
    let(:template) { create(:ai_workflow, account: account, is_template: true, template_category: 'automation', description: 'A template for conversion') }

    context 'with proper permissions' do
      it 'converts template to workflow' do
        post "/api/v1/ai/workflows/#{template.id}/convert_to_workflow", headers: headers, as: :json

        expect_success_response
        expect(template.reload.is_template).to be false
      end
    end

    context 'with non-template workflow' do
      let(:workflow) { create(:ai_workflow, account: account, is_template: false) }

      it 'returns error' do
        post "/api/v1/ai/workflows/#{workflow.id}/convert_to_workflow", headers: headers, as: :json

        expect_error_response('This workflow is not a template', 422)
      end
    end
  end
end
