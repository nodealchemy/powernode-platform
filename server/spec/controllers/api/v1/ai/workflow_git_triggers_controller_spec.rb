# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::WorkflowGitTriggersController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:workflow) { create(:ai_workflow, account: account, creator: user) }
  let(:trigger) { create(:ai_workflow_trigger, workflow: workflow) }
  let(:git_trigger) { create(:git_workflow_trigger, ai_workflow_trigger: trigger) }

  before do
    sign_in_user(user)
    allow(user).to receive(:has_permission?).and_return(true)
  end

  describe 'GET #index' do
    let!(:git_triggers) { create_list(:git_workflow_trigger, 3, ai_workflow_trigger: trigger) }

    it 'returns git triggers for the workflow trigger' do
      get :index, params: { trigger_id: trigger.id }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['git_triggers'].length).to eq(3)
    end

    context 'when trigger not found' do
      it 'returns 404' do
        get :index, params: { trigger_id: 'nonexistent-id' }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET #show' do
    it 'returns the git trigger' do
      get :show, params: { trigger_id: trigger.id, id: git_trigger.id }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['git_trigger']['id']).to eq(git_trigger.id)
      expect(json['data']['git_trigger']['event_type']).to eq(git_trigger.event_type)
    end

    context 'when git trigger not found' do
      it 'returns 404' do
        get :show, params: { trigger_id: trigger.id, id: 'nonexistent-id' }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST #create' do
    let(:valid_params) do
      {
        trigger_id: trigger.id,
        git_trigger: {
          event_type: 'push',
          branch_pattern: 'main',
          is_active: true
        }
      }
    end

    it 'creates a new git workflow trigger' do
      expect {
        post :create, params: valid_params
      }.to change(Git::WorkflowTrigger, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['git_trigger']['event_type']).to eq('push')
      expect(json['data']['git_trigger']['branch_pattern']).to eq('main')
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          trigger_id: trigger.id,
          git_trigger: {
            event_type: 'invalid_type',
            branch_pattern: ''
          }
        }
      end

      it 'returns validation errors' do
        post :create, params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['success']).to be false
      end
    end

    context 'with payload mapping' do
      let(:params_with_mapping) do
        {
          trigger_id: trigger.id,
          git_trigger: {
            event_type: 'push',
            branch_pattern: '*',
            payload_mapping: {
              'commit_sha' => 'head_commit.id',
              'author' => 'head_commit.author.name'
            }
          }
        }
      end

      it 'creates trigger with payload mapping' do
        post :create, params: params_with_mapping

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json['data']['git_trigger']['payload_mapping']).to include(
          'commit_sha' => 'head_commit.id',
          'author' => 'head_commit.author.name'
        )
      end
    end
  end

  describe 'PUT #update' do
    let(:update_params) do
      {
        trigger_id: trigger.id,
        id: git_trigger.id,
        git_trigger: {
          branch_pattern: 'develop',
          event_filters: { 'action' => 'opened' }
        }
      }
    end

    it 'updates the git trigger' do
      put :update, params: update_params

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['git_trigger']['branch_pattern']).to eq('develop')

      git_trigger.reload
      expect(git_trigger.branch_pattern).to eq('develop')
    end
  end

  describe 'DELETE #destroy' do
    it 'deletes the git trigger' do
      git_trigger # ensure created

      expect {
        delete :destroy, params: { trigger_id: trigger.id, id: git_trigger.id }
      }.to change(Git::WorkflowTrigger, :count).by(-1)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
    end
  end

  describe 'POST #test' do
    let(:test_params) do
      {
        trigger_id: trigger.id,
        id: git_trigger.id,
        sample_payload: {
          ref: 'refs/heads/main',
          head_commit: { id: 'abc123', message: 'Test commit' },
          repository: { full_name: 'owner/repo' }
        }
      }
    end

    it 'tests the trigger against sample payload' do
      post :test, params: test_params

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']).to have_key('matched')
      expect(json['data']).to have_key('match_details')
    end
  end

  describe 'GET #workflow_index' do
    let!(:trigger2) { create(:ai_workflow_trigger, workflow: workflow) }
    let!(:git_trigger1) { create(:git_workflow_trigger, ai_workflow_trigger: trigger) }
    let!(:git_trigger2) { create(:git_workflow_trigger, ai_workflow_trigger: trigger2) }

    it 'returns all git triggers for the workflow' do
      get :workflow_index, params: { workflow_id: workflow.id }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['data']['git_triggers'].length).to eq(2)
    end
  end
end
