# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::WorkflowGitTriggers', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.workflows.read', 'ai.workflows.create', 'ai.workflows.update', 'ai.workflows.delete']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.workflows.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }

  let(:workflow) { create(:ai_workflow, account: account) }
  let(:workflow_trigger) { create(:ai_workflow_trigger, workflow: workflow) }
  let(:repository) { create(:git_repository, account: account) }

  describe 'GET /api/v1/ai/workflow_git_triggers' do
    let!(:git_trigger) { create(:devops_git_workflow_trigger, ai_workflow_trigger: workflow_trigger, repository: repository) }

    context 'with proper permissions' do
      it 'returns list of git triggers for a workflow trigger' do
        get "/api/v1/ai/workflow_git_triggers?trigger_id=#{workflow_trigger.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['git_triggers']).to be_an(Array)
        expect(data['total']).to eq(1)
      end
    end

    context 'without trigger_id parameter' do
      it 'returns not found error' do
        get '/api/v1/ai/workflow_git_triggers', headers: headers, as: :json

        expect_error_response('Workflow trigger not found', 404)
      end
    end

    context 'without ai.workflows.read permission' do
      it 'returns forbidden error' do
        user_without_permission = create(:user, account: account, permissions: [])
        headers_without_permission = auth_headers_for(user_without_permission)

        get "/api/v1/ai/workflow_git_triggers?trigger_id=#{workflow_trigger.id}", headers: headers_without_permission, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/workflows/:workflow_id/triggers/:trigger_id/git_triggers/:id' do
    let!(:git_trigger) { create(:devops_git_workflow_trigger, ai_workflow_trigger: workflow_trigger, repository: repository) }

    context 'with proper permissions' do
      it 'returns git trigger details' do
        get "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers/#{git_trigger.id}",
            headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['git_trigger']).to include(
          'id' => git_trigger.id,
          'event_type' => git_trigger.event_type
        )
      end

      it 'includes detailed information' do
        get "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers/#{git_trigger.id}",
            headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['git_trigger']).to have_key('event_filters')
        expect(data['git_trigger']).to have_key('payload_mapping')
        expect(data['git_trigger']).to have_key('metadata')
      end
    end
  end

  describe 'POST /api/v1/ai/workflows/:workflow_id/triggers/:trigger_id/git_triggers' do
    let(:valid_params) do
      {
        git_trigger: {
          git_repository_id: repository.id,
          event_type: 'push',
          branch_pattern: 'main',
          is_active: true
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new git workflow trigger' do
        expect {
          post "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers",
               params: valid_params, headers: headers, as: :json
        }.to change { Devops::GitWorkflowTrigger.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['git_trigger']['event_type']).to eq('push')
        expect(data['git_trigger']['branch_pattern']).to eq('main')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { git_trigger: { event_type: nil } }

        post "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers",
             params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without ai.workflows.create permission' do
      it 'returns forbidden error' do
        post "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers",
             params: valid_params, headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PATCH /api/v1/ai/workflows/:workflow_id/triggers/:trigger_id/git_triggers/:id' do
    let!(:git_trigger) { create(:devops_git_workflow_trigger, ai_workflow_trigger: workflow_trigger, repository: repository) }
    let(:update_params) do
      {
        git_trigger: {
          branch_pattern: 'develop',
          is_active: false
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the git workflow trigger' do
        patch "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers/#{git_trigger.id}",
              params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['git_trigger']['branch_pattern']).to eq('develop')
        expect(data['git_trigger']['is_active']).to be false
      end
    end

    context 'without ai.workflows.update permission' do
      it 'returns forbidden error' do
        patch "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers/#{git_trigger.id}",
              params: update_params, headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'DELETE /api/v1/ai/workflows/:workflow_id/triggers/:trigger_id/git_triggers/:id' do
    let!(:git_trigger) { create(:devops_git_workflow_trigger, ai_workflow_trigger: workflow_trigger, repository: repository) }

    context 'with proper permissions' do
      it 'deletes the git workflow trigger' do
        expect {
          delete "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers/#{git_trigger.id}",
                 headers: headers, as: :json
        }.to change { Devops::GitWorkflowTrigger.count }.by(-1)

        expect_success_response
      end
    end

    context 'without ai.workflows.delete permission' do
      it 'returns forbidden error' do
        delete "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers/#{git_trigger.id}",
               headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/ai/workflows/:workflow_id/triggers/:trigger_id/git_triggers/:id/test' do
    let!(:git_trigger) { create(:devops_git_workflow_trigger, ai_workflow_trigger: workflow_trigger, repository: repository, event_type: 'push', branch_pattern: 'main') }

    context 'with proper permissions' do
      it 'tests the git trigger with sample payload' do
        post "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers/#{git_trigger.id}/test",
             headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('matched')
        expect(data).to have_key('match_details')
        expect(data).to have_key('mock_event')
      end

      it 'accepts custom sample payload' do
        custom_payload = {
          'ref' => 'refs/heads/main',
          'repository' => { 'full_name' => 'owner/repo' }
        }

        post "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers/#{git_trigger.id}/test",
             params: { sample_payload: custom_payload }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['mock_event']['payload_preview']).to include('ref' => 'refs/heads/main')
      end

      it 'extracts variables when trigger matches' do
        allow_any_instance_of(Devops::GitWorkflowTrigger).to receive(:matches_event?).and_return(true)
        allow_any_instance_of(Devops::GitWorkflowTrigger).to receive(:extract_variables).and_return({ branch: 'main' })

        post "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers/#{git_trigger.id}/test",
             headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['matched']).to be true
        expect(data['match_details']['extracted_variables']).to eq({ 'branch' => 'main' })
      end

      it 'returns empty variables when trigger does not match' do
        allow_any_instance_of(Devops::GitWorkflowTrigger).to receive(:matches_event?).and_return(false)

        post "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers/#{git_trigger.id}/test",
             headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['matched']).to be false
        expect(data['match_details']['extracted_variables']).to eq({})
      end
    end

    context 'without ai.workflows.update permission' do
      it 'returns forbidden error' do
        post "/api/v1/ai/workflows/#{workflow.id}/triggers/#{workflow_trigger.id}/git_triggers/#{git_trigger.id}/test",
             headers: read_only_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET /api/v1/ai/workflows/:workflow_id/git_triggers' do
    let!(:git_trigger1) { create(:devops_git_workflow_trigger, ai_workflow_trigger: workflow_trigger, repository: repository) }
    let!(:git_trigger2) { create(:devops_git_workflow_trigger, ai_workflow_trigger: workflow_trigger, repository: repository) }

    context 'with proper permissions' do
      it 'returns all git triggers for a workflow' do
        get "/api/v1/ai/workflows/#{workflow.id}/git_triggers", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['git_triggers']).to be_an(Array)
        expect(data['git_triggers'].length).to eq(2)
        expect(data['total']).to eq(2)
      end

      it 'includes repository and trigger information' do
        get "/api/v1/ai/workflows/#{workflow.id}/git_triggers", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        first_trigger = data['git_triggers'].first

        expect(first_trigger).to have_key('repository')
        expect(first_trigger).to have_key('workflow_trigger')
      end
    end
  end

  describe 'cross-account isolation' do
    let(:other_account) { create(:account) }
    let(:other_workflow) { create(:ai_workflow, account: other_account) }
    let(:other_trigger) { create(:ai_workflow_trigger, workflow: other_workflow) }
    let!(:other_git_trigger) { create(:devops_git_workflow_trigger, ai_workflow_trigger: other_trigger) }

    it 'does not access git triggers from other accounts' do
      get "/api/v1/ai/workflows/#{other_workflow.id}/triggers/#{other_trigger.id}/git_triggers/#{other_git_trigger.id}",
          headers: headers, as: :json

      expect_error_response('Git workflow trigger not found', 404)
    end
  end
end
