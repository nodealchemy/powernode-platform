# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::ModelRouterController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.routing.read', 'ai.routing.manage']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.routing.read']) }
  let(:no_perms_user) { create(:user, account: account, permissions: []) }

  let!(:routing_rule) { create(:ai_model_routing_rule, account: account) }

  before do
    sign_in_as_user(user)
    allow(Audit::LoggingService.instance).to receive(:log).and_return(true)
  end

  # ============================================================================
  # AUTHENTICATION
  # ============================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :rules_index
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ============================================================================
  # AUTHORIZATION
  # ============================================================================

  describe 'authorization' do
    context 'without permissions' do
      before { sign_in_as_user(no_perms_user) }

      it 'returns 403 for rules_index' do
        get :rules_index
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for show_rule' do
        get :show_rule, params: { id: routing_rule.id }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for create_rule' do
        post :create_rule, params: { rule: { name: 'Test', rule_type: 'cost_based' } }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for update_rule' do
        patch :update_rule, params: { id: routing_rule.id, rule: { name: 'Updated' } }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for destroy_rule' do
        delete :destroy_rule, params: { id: routing_rule.id }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for toggle_rule' do
        post :toggle_rule, params: { id: routing_rule.id }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for decisions' do
        get :decisions
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read-only permissions' do
      before { sign_in_as_user(read_only_user) }

      it 'allows rules_index' do
        get :rules_index
        expect(response).to have_http_status(:ok)
      end

      it 'allows show_rule' do
        get :show_rule, params: { id: routing_rule.id }
        expect(response).to have_http_status(:ok)
      end

      it 'returns 403 for create_rule' do
        post :create_rule, params: { rule: { name: 'Test', rule_type: 'cost_based' } }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for toggle_rule' do
        post :toggle_rule, params: { id: routing_rule.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ============================================================================
  # RULES INDEX
  # ============================================================================

  describe 'GET #rules_index' do
    it 'returns routing rules' do
      get :rules_index
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['rules']).to be_an(Array)
      expect(json_response['data']['pagination']).to be_present
    end

    it 'filters by active status' do
      create(:ai_model_routing_rule, :inactive, account: account)

      get :rules_index, params: { active: 'true' }
      expect(response).to have_http_status(:ok)
      rules = json_response['data']['rules']
      expect(rules).to all(include('is_active' => true))
    end

    it 'filters by rule_type' do
      get :rules_index, params: { rule_type: 'cost_based' }
      expect(response).to have_http_status(:ok)
    end

    it 'paginates results' do
      get :rules_index, params: { page: 1, per_page: 5 }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['pagination']['per_page']).to eq(5)
    end
  end

  # ============================================================================
  # SHOW RULE
  # ============================================================================

  describe 'GET #show_rule' do
    it 'returns rule details' do
      get :show_rule, params: { id: routing_rule.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['rule']['id']).to eq(routing_rule.id)
    end

    it 'returns 404 for non-existent rule' do
      get :show_rule, params: { id: SecureRandom.uuid }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ============================================================================
  # CREATE RULE
  # ============================================================================

  describe 'POST #create_rule' do
    let(:valid_params) do
      {
        rule: {
          name: 'New Cost Rule',
          description: 'Optimize for cost',
          rule_type: 'cost_based',
          priority: 50,
          is_active: true,
          conditions: { max_cost_per_token: 0.01 },
          target: { strategy: 'cost_optimized' }
        }
      }
    end

    it 'creates a new routing rule' do
      expect {
        post :create_rule, params: valid_params
      }.to change { Ai::ModelRoutingRule.count }.by(1)

      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
    end

    it 'returns error for invalid params' do
      post :create_rule, params: { rule: { name: '' } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ============================================================================
  # UPDATE RULE
  # ============================================================================

  describe 'PATCH #update_rule' do
    it 'updates a routing rule' do
      patch :update_rule, params: { id: routing_rule.id, rule: { name: 'Updated Rule' } }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(routing_rule.reload.name).to eq('Updated Rule')
    end

    it 'returns 404 for non-existent rule' do
      patch :update_rule, params: { id: SecureRandom.uuid, rule: { name: 'Nope' } }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ============================================================================
  # DESTROY RULE
  # ============================================================================

  describe 'DELETE #destroy_rule' do
    it 'deletes a routing rule' do
      expect {
        delete :destroy_rule, params: { id: routing_rule.id }
      }.to change { Ai::ModelRoutingRule.count }.by(-1)

      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # TOGGLE RULE
  # ============================================================================

  describe 'POST #toggle_rule' do
    it 'toggles rule active status' do
      expect(routing_rule.is_active).to be true

      post :toggle_rule, params: { id: routing_rule.id }
      expect(response).to have_http_status(:ok)
      expect(routing_rule.reload.is_active).to be false
    end
  end

  # ============================================================================
  # DECISIONS
  # ============================================================================

  describe 'GET #decisions' do
    let!(:decision) { create(:ai_routing_decision, :successful, account: account) }

    it 'returns routing decisions' do
      get :decisions
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['decisions']).to be_an(Array)
      expect(json_response['data']['time_range']).to be_present
    end

    it 'accepts time_range parameter' do
      get :decisions, params: { time_range: '7d' }
      expect(response).to have_http_status(:ok)
    end

    it 'filters by strategy' do
      get :decisions, params: { strategy: 'cost_optimized' }
      expect(response).to have_http_status(:ok)
    end
  end

  # ============================================================================
  # SHOW DECISION
  # ============================================================================

  describe 'GET #show_decision' do
    let!(:decision) { create(:ai_routing_decision, :successful, account: account) }

    it 'returns decision details' do
      get :show_decision, params: { id: decision.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['decision']['id']).to eq(decision.id)
    end

    it 'returns 404 for non-existent decision' do
      get :show_decision, params: { id: SecureRandom.uuid }
      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for decision from another account' do
      other_account = create(:account)
      other_decision = create(:ai_routing_decision, account: other_account)

      get :show_decision, params: { id: other_decision.id }
      expect(response).to have_http_status(:not_found)
    end
  end
end
