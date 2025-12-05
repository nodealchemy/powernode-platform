# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::WorkflowValidations', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, :owner, account: account) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, :owner, account: other_account) }
  let(:headers) { auth_headers_for(user) }
  let(:other_headers) { auth_headers_for(other_user) }

  let(:workflow) { create(:ai_workflow, account: account, creator: user) }
  let(:other_workflow) { create(:ai_workflow, account: other_account, creator: other_user) }

  describe 'GET /api/v1/ai/workflows/:workflow_id/validations' do
    before do
      create_list(:workflow_validation, 3, :valid, workflow: workflow)
      create_list(:workflow_validation, 2, :invalid, workflow: workflow)
      create_list(:workflow_validation, 1, :with_warnings, workflow: workflow)
    end

    context 'with proper permissions' do
      it 'returns list of validations for the workflow' do
        get "/api/v1/ai/workflows/#{workflow.id}/validations", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['validations']).to be_an(Array)
        expect(data['validations'].length).to eq(6)
        expect(data['workflow']).to include('id' => workflow.id)
        expect(data['meta']).to include(
          'valid_count' => 3,
          'invalid_count' => 2,
          'warning_count' => 1
        )
      end

      it 'filters by status' do
        get "/api/v1/ai/workflows/#{workflow.id}/validations?status=valid",
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['validations'].length).to eq(3)
        expect(data['validations'].all? { |v| v['overall_status'] == 'valid' }).to be true
      end

      it 'filters by health status' do
        get "/api/v1/ai/workflows/#{workflow.id}/validations?health=healthy",
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['validations'].all? { |v| v['health_score'] >= 80 }).to be true
      end

      it 'applies time period filter' do
        # Create an old validation
        old_validation = create(:workflow_validation, :valid, workflow: workflow)
        old_validation.update_column(:created_at, 2.days.ago)

        get "/api/v1/ai/workflows/#{workflow.id}/validations?time_period=24",
            headers: headers

        expect_success_response
        data = json_response_data
        # Should not include the old validation
        expect(data['validations'].none? { |v| v['id'] == old_validation.id }).to be true
      end

      it 'supports pagination' do
        get "/api/v1/ai/workflows/#{workflow.id}/validations?page=1&per_page=2",
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['validations'].length).to eq(2)
        expect(data['pagination']).to include(
          'page' => 1,
          'per_page' => 2,
          'total' => 6,
          'pages' => 3
        )
      end
    end

    context 'with workflow from different account' do
      it 'returns not found error' do
        get "/api/v1/ai/workflows/#{other_workflow.id}/validations", headers: headers, as: :json

        expect_error_response('Workflow not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get "/api/v1/ai/workflows/#{workflow.id}/validations", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/workflows/:workflow_id/validations/:id' do
    let(:validation) { create(:workflow_validation, :with_warnings, workflow: workflow) }

    context 'with proper permissions' do
      it 'returns validation details' do
        get "/api/v1/ai/workflows/#{workflow.id}/validations/#{validation.id}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['validation']).to include(
          'id' => validation.id,
          'workflow_id' => workflow.id,
          'overall_status' => 'warning'
        )
        expect(data['validation']).to have_key('issues')
        expect(data['validation']).to have_key('summary')
        expect(data['workflow']).to include('id' => workflow.id)
      end

      it 'returns not found for non-existent validation' do
        get "/api/v1/ai/workflows/#{workflow.id}/validations/#{SecureRandom.uuid}",
            headers: headers,
            as: :json

        expect_error_response('Validation not found', 404)
      end
    end

    context 'with workflow from different account' do
      it 'returns not found error' do
        get "/api/v1/ai/workflows/#{other_workflow.id}/validations/#{validation.id}",
            headers: headers,
            as: :json

        expect_error_response('Workflow not found', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/workflows/:workflow_id/validations' do
    context 'with proper permissions' do
      context 'with valid workflow structure' do
        before do
          # Create a valid workflow structure with nodes and edges
          trigger = create(:ai_workflow_node, :trigger, ai_workflow: workflow)
          action = create(:ai_workflow_node, :action, ai_workflow: workflow)
          create(:ai_workflow_edge, ai_workflow: workflow, source_node: trigger, target_node: action)
        end

        it 'creates a new validation' do
          expect {
            post "/api/v1/ai/workflows/#{workflow.id}/validations", headers: headers, as: :json
          }.to change { workflow.workflow_validations.count }.by(1)

          expect(response).to have_http_status(:created)
          data = json_response_data
          expect(data['validation']).to include('workflow_id' => workflow.id)
          expect(data['validation']).to have_key('overall_status')
          expect(data['validation']).to have_key('health_score')
          expect(data['validation']).to have_key('issues')
          expect(data['message']).to eq('Workflow validation completed successfully')
        end

        it 'returns valid status for well-structured workflow' do
          post "/api/v1/ai/workflows/#{workflow.id}/validations", headers: headers, as: :json

          expect(response).to have_http_status(:created)
          data = json_response_data
          expect(data['validation']['overall_status']).to be_in(['valid', 'warning'])
        end
      end

      context 'with invalid workflow structure' do
        it 'returns invalid status for empty workflow' do
          post "/api/v1/ai/workflows/#{workflow.id}/validations", headers: headers, as: :json

          expect(response).to have_http_status(:created)
          data = json_response_data
          expect(data['validation']['overall_status']).to eq('invalid')
          expect(data['validation']['issues'].any? { |i| i['code'] == 'empty_workflow' }).to be true
        end

        it 'detects orphaned nodes' do
          # Create orphaned node
          create(:ai_workflow_node, :action, ai_workflow: workflow)

          post "/api/v1/ai/workflows/#{workflow.id}/validations", headers: headers, as: :json

          expect(response).to have_http_status(:created)
          data = json_response_data
          expect(data['validation']['issues'].any? { |i| i['code'] == 'orphaned_node' }).to be true
        end

        it 'detects trigger with no output' do
          # Create trigger without outgoing edges
          create(:ai_workflow_node, :trigger, ai_workflow: workflow)

          post "/api/v1/ai/workflows/#{workflow.id}/validations", headers: headers, as: :json

          expect(response).to have_http_status(:created)
          data = json_response_data
          expect(data['validation']['issues'].any? { |i| i['code'] == 'trigger_no_output' }).to be true
        end
      end
    end

    context 'with workflow from different account' do
      it 'returns not found error' do
        post "/api/v1/ai/workflows/#{other_workflow.id}/validations", headers: headers, as: :json

        expect_error_response('Workflow not found', 404)
      end
    end

    context 'without execute permission' do
      let(:limited_user) { create(:user, :member, account: account) }
      let(:limited_headers) { auth_headers_for(limited_user) }

      before do
        # Remove execute permission
        limited_user.permissions.delete('ai.workflows.execute')
        limited_user.save!
      end

      it 'returns forbidden error' do
        post "/api/v1/ai/workflows/#{workflow.id}/validations", headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions to create workflow validations', 403)
      end
    end
  end

  describe 'GET /api/v1/ai/workflows/:workflow_id/validations/latest' do
    context 'with validations present' do
      let!(:old_validation) { create(:workflow_validation, :valid, workflow: workflow, created_at: 1.hour.ago) }
      let!(:latest_validation) { create(:workflow_validation, :with_warnings, workflow: workflow) }

      it 'returns the most recent validation' do
        get "/api/v1/ai/workflows/#{workflow.id}/validations/latest", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['validation']['id']).to eq(latest_validation.id)
        expect(data['workflow']).to include('id' => workflow.id)
      end
    end

    context 'with no validations' do
      it 'returns null validation with message' do
        get "/api/v1/ai/workflows/#{workflow.id}/validations/latest", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['validation']).to be_nil
        expect(data['message']).to eq('No validations found for this workflow')
      end
    end

    context 'with workflow from different account' do
      it 'returns not found error' do
        get "/api/v1/ai/workflows/#{other_workflow.id}/validations/latest", headers: headers, as: :json

        expect_error_response('Workflow not found', 404)
      end
    end
  end
end
