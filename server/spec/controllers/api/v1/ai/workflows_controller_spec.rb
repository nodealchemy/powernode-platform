# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::WorkflowsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.workflows.read', 'ai.workflows.create', 'ai.workflows.update', 'ai.workflows.delete', 'ai.workflows.execute', 'ai.workflows.export' ]) }
  let(:admin_user) { create(:user, :system_admin, account: account) }
  let(:read_only_user) { create(:user, account: account, permissions: [ 'ai.workflows.read' ]) }
  let(:user_without_permissions) { create(:user, account: account, permissions: []) }
  let(:other_account_user) { create(:user) }

  let!(:workflow) do
    create(:ai_workflow, :with_simple_chain,
           account: account,
           creator: user,
           name: 'Test Workflow',
           status: 'active')
  end

  let!(:other_account_workflow) do
    create(:ai_workflow,
           account: other_account_user.account,
           creator: other_account_user)
  end

  before do
    sign_in user
  end

  describe 'GET #index' do
    let!(:workflow2) { create(:ai_workflow, account: account, creator: user, name: 'Workflow 2') }
    let!(:draft_workflow) { create(:ai_workflow, account: account, creator: user, status: 'draft') }

    context 'with valid permissions' do
      it 'returns all workflows for current account' do
        get :index

        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true

        workflow_ids = json_response['data']['items'].map { |w| w['id'] }
        expect(workflow_ids).to include(workflow.id, workflow2.id, draft_workflow.id)
        expect(workflow_ids).not_to include(other_account_workflow.id)
      end

      it 'includes pagination metadata' do
        create_list(:ai_workflow, 15, account: account, creator: user)

        get :index, params: { per_page: 10, page: 2 }

        expect(response).to have_http_status(:ok)
        pagination = json_response['data']['pagination']
        expect(pagination['current_page']).to eq(2)
        expect(pagination['total_pages']).to be >= 2
      end

      it 'filters by status' do
        get :index, params: { status: 'active' }

        statuses = json_response['data']['items'].map { |w| w['status'] }
        expect(statuses).to all(eq('active'))
      end

      it 'supports search functionality' do
        searchable_workflow = create(:ai_workflow, account: account, creator: user, name: 'Searchable Content Workflow')

        get :index, params: { search: 'Content' }

        workflow_names = json_response['data']['items'].map { |w| w['name'] }
        expect(workflow_names).to include('Searchable Content Workflow')
      end
    end

    context 'without proper permissions' do
      before { sign_in user_without_permissions }

      it 'denies access without read permissions' do
        get :index

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #show' do
    context 'with valid workflow' do
      it 'returns detailed workflow information' do
        get :show, params: { id: workflow.id }

        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true

        workflow_data = json_response['data']['workflow']
        expect(workflow_data['id']).to eq(workflow.id)
        expect(workflow_data).to include(
          'name',
          'description',
          'status',
          'created_at',
          'updated_at',
          'created_by',
          'nodes',
          'edges',
          'stats'
        )
      end
    end

    context 'with invalid workflow' do
      it 'returns 404 for non-existent workflow' do
        get :show, params: { id: 'non-existent-id' }

        expect(response).to have_http_status(:not_found)
        expect(json_response['error']).to eq('Workflow not found')
      end

      it 'returns 404 for other account workflow' do
        get :show, params: { id: other_account_workflow.id }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST #create' do
    let(:valid_workflow_params) do
      {
        workflow: {
          name: 'New Test Workflow',
          description: 'A workflow for testing',
          status: 'draft',
          visibility: 'private',
          configuration: {
            execution_mode: 'sequential',
            timeout_seconds: 3600
          }
        }
      }
    end

    context 'with valid parameters' do
      it 'creates new workflow' do
        expect {
          post :create, params: valid_workflow_params
        }.to change { AiWorkflow.count }.by(1)

        expect(response).to have_http_status(:created)
        expect(json_response['success']).to be true

        created_workflow = AiWorkflow.last
        expect(created_workflow.name).to eq('New Test Workflow')
        expect(created_workflow.account).to eq(account)
        expect(created_workflow.creator).to eq(user)
      end

      it 'creates audit log entry' do
        expect {
          post :create, params: valid_workflow_params
        }.to change { AuditLog.where(resource_type: 'AiWorkflow').count }.by(1)

        audit_log = AuditLog.where(resource_type: 'AiWorkflow').last
        expect(audit_log.action).to eq('ai.workflows.create')
      end
    end

    context 'with invalid parameters' do
      it 'returns validation errors for missing name' do
        invalid_params = valid_workflow_params.deep_dup
        invalid_params[:workflow][:name] = ''

        post :create, params: invalid_params

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
        expect(json_response['details']['errors']).to be_an(Array)
        expect(json_response['details']['errors'].any? { |e| e.include?('Name') }).to be true
      end
    end

    context 'without create permissions' do
      before { sign_in read_only_user }

      it 'denies access without create permissions' do
        post :create, params: valid_workflow_params

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH #update' do
    let(:update_params) do
      {
        id: workflow.id,
        workflow: {
          name: 'Updated Workflow Name',
          description: 'Updated description'
        }
      }
    end

    context 'with valid parameters' do
      it 'updates workflow' do
        patch :update, params: update_params

        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true

        workflow.reload
        expect(workflow.name).to eq('Updated Workflow Name')
        expect(workflow.description).to eq('Updated description')
      end

      it 'creates audit log entry' do
        expect {
          patch :update, params: update_params
        }.to change { AuditLog.where(resource_type: 'AiWorkflow').count }.by(1)

        audit_log = AuditLog.where(resource_type: 'AiWorkflow').last
        expect(audit_log.action).to eq('ai.workflows.update')
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'with valid workflow' do
      it 'deletes workflow when it can be deleted' do
        allow_any_instance_of(AiWorkflow).to receive(:can_delete?).and_return(true)

        workflow_id = workflow.id

        delete :destroy, params: { id: workflow_id }

        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
        expect(AiWorkflow.exists?(workflow_id)).to be false
      end

      it 'prevents deletion when workflow has active runs' do
        allow_any_instance_of(AiWorkflow).to receive(:can_delete?).and_return(false)

        delete :destroy, params: { id: workflow.id }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to include('Cannot delete')
      end
    end
  end

  describe 'POST #execute' do
    before do
      # Mock WorkerJobService
      allow(WorkerJobService).to receive(:enqueue_ai_workflow_execution).and_return(true)
      # Mock ProviderAvailabilityService to allow execution
      allow(ProviderAvailabilityService).to receive(:validate_workflow_providers!).and_return(true)
    end

    context 'with valid workflow' do
      it 'creates workflow run and queues execution' do
        expect {
          post :execute, params: {
            id: workflow.id,
            input_variables: { key: 'value' },
            trigger_type: 'manual'
          }
        }.to change { AiWorkflowRun.count }.by(1)

        expect(response).to have_http_status(:created)
        expect(json_response['success']).to be true
        expect(json_response['data']).to include('workflow_run', 'execution_url')

        run = AiWorkflowRun.last
        expect(run.status).to eq('initializing')
        expect(run.input_variables).to eq({ 'key' => 'value' })
        expect(run.trigger_type).to eq('manual')
      end

      it 'creates audit log entry' do
        expect {
          post :execute, params: { id: workflow.id }
        }.to change { AuditLog.count }.by_at_least(1)

        # Note: AiWorkflowRun doesn't include Auditable concern, so audit log is created manually
        # The manual log_audit_event call happens after render, so we just verify logs were created
      end
    end

    context 'when worker service fails' do
      before do
        allow(WorkerJobService).to receive(:enqueue_ai_workflow_execution)
          .and_raise(WorkerJobService::WorkerServiceError.new('Worker unavailable'))
      end

      it 'returns service unavailable error' do
        post :execute, params: { id: workflow.id }

        expect(response).to have_http_status(:service_unavailable)
        expect(json_response['error']).to include('Worker unavailable')
      end
    end
  end

  describe 'POST #duplicate' do
    it 'duplicates workflow' do
      expect {
        post :duplicate, params: { id: workflow.id }
      }.to change { AiWorkflow.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true

      duplicated = AiWorkflow.last
      expect(duplicated.name).to eq('Test Workflow (Copy)')
      expect(duplicated.account).to eq(account)
      expect(duplicated.creator).to eq(user)
    end
  end

  describe 'GET #validate' do
    it 'validates workflow structure' do
      allow_any_instance_of(AiWorkflow).to receive(:validate_structure)
        .and_return({ valid: true })

      get :validate, params: { id: workflow.id }

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['valid']).to be true
    end

    it 'returns validation errors' do
      allow_any_instance_of(AiWorkflow).to receive(:validate_structure)
        .and_return({
          valid: false,
          errors: [ 'Missing start node' ],
          warnings: [ 'No end node defined' ]
        })

      get :validate, params: { id: workflow.id }

      expect(response).to have_http_status(:ok)
      expect(json_response['data']['valid']).to be false
      expect(json_response['data']['errors']).to include('Missing start node')
    end
  end

  describe 'GET #export' do
    it 'exports workflow data' do
      get :export, params: { id: workflow.id }

      expect(response).to have_http_status(:ok)
      expect(json_response['data']).to include('export_data', 'filename')

      export_data = json_response['data']['export_data']
      expect(export_data).to include('workflow', 'nodes', 'edges', 'metadata')
    end
  end

  describe 'POST #import' do
    let(:import_data) do
      {
        workflow: {
          name: 'Imported Workflow',
          description: 'Test import',
          status: 'draft'
        },
        nodes: [],
        edges: []
      }
    end

    it 'imports workflow from data' do
      allow(AiWorkflow).to receive(:import_from_data).and_return(
        create(:ai_workflow, account: account, creator: user)
      )

      post :import, params: { import_data: import_data }

      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
    end

    it 'returns error for missing import data' do
      post :import

      expect(response).to have_http_status(:bad_request)
      expect(json_response['error']).to include('Import data is required')
    end
  end

  describe 'GET #statistics' do
    before do
      create_list(:ai_workflow, 5, account: account, creator: user, status: 'active')
      create(:ai_workflow, account: account, creator: user, status: 'draft')
    end

    it 'returns account-wide workflow statistics' do
      get :statistics

      expect(response).to have_http_status(:ok)
      stats = json_response['data']['statistics']
      expect(stats).to include(
        'total_workflows',
        'active_workflows',
        'draft_workflows',
        'total_runs',
        'successful_runs'
      )
    end
  end

  describe 'GET #templates' do
    it 'returns workflow templates' do
      get :templates

      expect(response).to have_http_status(:ok)
      templates = json_response['data']['templates']
      expect(templates).to be_an(Array)
      expect(templates.first).to include('id', 'name', 'description', 'category')
    end
  end

  describe 'nested workflow runs' do
    let!(:workflow_run) { create(:ai_workflow_run, ai_workflow: workflow, account: account, triggered_by_user: user) }

    describe 'GET #runs_index' do
      it 'returns runs for specific workflow' do
        get :runs_index, params: { workflow_id: workflow.id }

        expect(response).to have_http_status(:ok)
        run_ids = json_response['data']['items'].map { |r| r['run_id'] }
        expect(run_ids).to include(workflow_run.run_id)
      end
    end

    describe 'GET #run_show' do
      it 'returns detailed run information' do
        get :run_show, params: { workflow_id: workflow.id, run_id: workflow_run.run_id }

        expect(response).to have_http_status(:ok)
        run_data = json_response['data']['workflow_run']
        expect(run_data['run_id']).to eq(workflow_run.run_id)
        expect(run_data).to include(
          'status',
          'trigger_type',
          'input_variables',
          'output_variables',
          'workflow',
          'node_executions'
        )
      end
    end

    describe 'PATCH #run_update' do
      it 'updates workflow run' do
        patch :run_update, params: {
          workflow_id: workflow.id,
          run_id: workflow_run.run_id,
          workflow_run: {
            status: 'completed',
            completed_at: Time.current,
            total_cost: 0.05
          }
        }

        expect(response).to have_http_status(:ok)
        workflow_run.reload
        expect(workflow_run.status).to eq('completed')
        expect(workflow_run.total_cost).to eq(BigDecimal('0.05'))
      end
    end

    describe 'DELETE #run_destroy' do
      it 'deletes workflow run when not running' do
        workflow_run.update!(status: 'completed', completed_at: Time.current)

        run_id = workflow_run.run_id

        delete :run_destroy, params: { workflow_id: workflow.id, run_id: run_id }

        expect(response).to have_http_status(:ok)
        expect(AiWorkflowRun.exists?(id: workflow_run.id)).to be false
      end

      it 'prevents deletion of running workflow' do
        workflow_run.update!(status: 'running')

        delete :run_destroy, params: { workflow_id: workflow.id, run_id: workflow_run.run_id }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to include('Cannot delete')
      end
    end

    describe 'POST #run_cancel' do
      before do
        workflow_run.update!(status: 'running')
        allow_any_instance_of(AiWorkflowRun).to receive(:can_cancel?).and_return(true)
        allow_any_instance_of(AiWorkflowRun).to receive(:cancel!).and_return(true)
      end

      it 'cancels running workflow run' do
        post :run_cancel, params: {
          workflow_id: workflow.id,
          run_id: workflow_run.run_id,
          reason: 'Test cancellation'
        }

        expect(response).to have_http_status(:ok)
        expect(json_response['success']).to be true
      end
    end

    describe 'POST #run_retry' do
      before do
        workflow_run.update!(
          status: 'failed',
          completed_at: Time.current,
          error_details: { message: 'Test error' }
        )
        allow_any_instance_of(AiWorkflowRun).to receive(:can_retry?).and_return(true)
        allow_any_instance_of(AiWorkflowRun).to receive(:retry!).and_return(
          create(:ai_workflow_run, ai_workflow: workflow, account: account, triggered_by_user: user)
        )
      end

      it 'retries failed workflow run' do
        post :run_retry, params: { workflow_id: workflow.id, run_id: workflow_run.run_id }

        expect(response).to have_http_status(:created)
        expect(json_response['data']).to include('original_run', 'new_run')
      end
    end

    describe 'GET #run_logs' do
      let!(:log) { create(:ai_workflow_run_log, ai_workflow_run: workflow_run) }

      it 'returns workflow run logs' do
        get :run_logs, params: { workflow_id: workflow.id, run_id: workflow_run.run_id }

        expect(response).to have_http_status(:ok)
        logs = json_response['data']['logs']
        expect(logs).to be_an(Array)
        expect(logs.first).to include('level', 'message', 'created_at')
      end
    end

    describe 'GET #run_node_executions' do
      let!(:node_execution) { create(:ai_workflow_node_execution, ai_workflow_run: workflow_run) }

      it 'returns node executions for workflow run' do
        get :run_node_executions, params: { workflow_id: workflow.id, run_id: workflow_run.run_id }

        expect(response).to have_http_status(:ok)
        executions = json_response['data']['node_executions']
        expect(executions).to be_an(Array)
        expect(executions.first).to include('execution_id', 'status', 'node')
      end
    end

    describe 'GET #run_metrics' do
      it 'returns workflow run metrics' do
        allow_any_instance_of(AiWorkflowRun).to receive(:calculate_execution_metrics)
          .and_return({
            total_nodes: 5,
            completed_nodes: 3,
            duration_ms: 5000
          })

        get :run_metrics, params: { workflow_id: workflow.id, run_id: workflow_run.run_id }

        expect(response).to have_http_status(:ok)
        metrics = json_response['data']['metrics']
        expect(metrics).to include('total_nodes', 'completed_nodes', 'duration_ms')
      end
    end

    describe 'GET #run_download' do
      it 'downloads workflow run data as JSON' do
        get :run_download, params: { workflow_id: workflow.id, run_id: workflow_run.run_id, format: 'json' }

        expect(response).to have_http_status(:ok)
        expect(json_response['data']).to include('export_data', 'filename')
      end
    end

    describe 'POST #run_process' do
      it 'processes workflow run via orchestrator' do
        allow_any_instance_of(Mcp::AiWorkflowOrchestrator).to receive(:execute).and_return(workflow_run)
        workflow_run.update!(status: 'completed', completed_at: Time.current)

        post :run_process, params: { workflow_id: workflow.id, run_id: workflow_run.run_id }

        expect(response).to have_http_status(:ok)
        expect(json_response['data']['success']).to be true
      end
    end

    describe 'GET #runs_lookup' do
      it 'looks up workflow run by run_id' do
        get :runs_lookup, params: { run_id: workflow_run.run_id }

        expect(response).to have_http_status(:ok)
        run_data = json_response['data']['workflow_run']
        expect(run_data['run_id']).to eq(workflow_run.run_id)
        expect(run_data['workflow_id']).to eq(workflow.id)
      end

      it 'returns 404 for non-existent run' do
        get :runs_lookup, params: { run_id: 'non-existent' }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
