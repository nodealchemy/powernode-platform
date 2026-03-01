# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::AutonomyController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:agents_read_user) { create(:user, account: account, permissions: ['ai.agents.read']) }
  let(:manage_user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.autonomy.manage']) }
  let(:agent) { create(:ai_agent, account: account) }
  let!(:trust_score) { create(:ai_agent_trust_score, account: account, agent: agent) }

  before do
    @request.headers['Content-Type'] = 'application/json'
    @request.headers['Accept'] = 'application/json'
  end

  describe 'GET #trust_scores' do
    context 'with valid permissions' do
      before { sign_in agents_read_user }

      it 'returns trust scores list' do
        get :trust_scores

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to be_an(Array)
        expect(json['data'].first).to include('agent_id', 'tier', 'overall_score')
      end

      it 'filters by tier' do
        get :trust_scores, params: { tier: 'supervised' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        json['data'].each do |score|
          expect(score['tier']).to eq('supervised')
        end
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :trust_scores

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #show_trust_score' do
    context 'with valid permissions' do
      before { sign_in agents_read_user }

      it 'returns trust score for agent' do
        get :show_trust_score, params: { agent_id: agent.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']['agent_id']).to eq(agent.id)
      end

      it 'returns not found for missing trust score' do
        other_agent = create(:ai_agent, account: account)
        get :show_trust_score, params: { agent_id: other_agent.id }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :show_trust_score, params: { agent_id: agent.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #lineage' do
    let(:child_agent) { create(:ai_agent, account: account) }
    let!(:lineage) { create(:ai_agent_lineage, account: account, parent_agent: agent, child_agent: child_agent) }

    context 'with valid permissions' do
      before { sign_in agents_read_user }

      it 'returns lineage data for agent' do
        get :lineage, params: { agent_id: agent.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('agent_id', 'children', 'parents', 'total_children', 'total_parents')
        expect(json['data']['total_children']).to eq(1)
      end

      it 'returns not found for non-existent agent' do
        get :lineage, params: { agent_id: SecureRandom.uuid }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :lineage, params: { agent_id: agent.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #budgets' do
    let!(:budget) { create(:ai_agent_budget, account: account, agent: agent) }

    context 'with valid permissions' do
      before { sign_in agents_read_user }

      it 'returns budgets list' do
        get :budgets

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to be_an(Array)
        expect(json['data'].first).to include('agent_id', 'total_budget_cents', 'spent_cents')
      end

      it 'filters by active' do
        get :budgets, params: { active: 'true' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end

      it 'filters by period' do
        get :budgets, params: { period: 'monthly' }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :budgets

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'GET #stats' do
    let!(:budget) { create(:ai_agent_budget, account: account, agent: agent) }

    context 'with valid permissions' do
      before { sign_in agents_read_user }

      it 'returns flat autonomy stats matching frontend type' do
        get :stats

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include(
          'total_agents', 'supervised', 'monitored', 'trusted', 'autonomous',
          'pending_promotions', 'pending_demotions'
        )
        expect(json['data']['budgets']).to include('total', 'active')
      end

      it 'counts agents by tier correctly' do
        get :stats

        json = JSON.parse(response.body)
        expect(json['data']['total_agents']).to eq(1)
        expect(json['data']['supervised']).to eq(1)
        expect(json['data']['monitored']).to eq(0)
      end
    end

    context 'without permissions' do
      before { sign_in user }

      it 'returns forbidden' do
        get :stats

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST #evaluate' do
    context 'with manage permissions' do
      before { sign_in manage_user }

      it 'evaluates trust score for agent' do
        post :evaluate, params: { agent_id: agent.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('agent_id', 'overall_score', 'tier')
      end

      it 'returns not found for missing agent' do
        post :evaluate, params: { agent_id: SecureRandom.uuid }

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'without manage permissions' do
      before { sign_in agents_read_user }

      it 'returns forbidden' do
        post :evaluate, params: { agent_id: agent.id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'PUT #override_trust_score' do
    context 'with manage permissions' do
      before { sign_in manage_user }

      it 'overrides trust tier' do
        put :override_trust_score, params: {
          agent_id: agent.id,
          tier: 'monitored',
          reason: 'Manual promotion after review'
        }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['tier']).to eq('monitored')
      end

      it 'rejects invalid tier' do
        put :override_trust_score, params: {
          agent_id: agent.id,
          tier: 'invalid_tier',
          reason: 'test'
        }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'POST #emergency_demote' do
    let!(:trusted_score) { create(:ai_agent_trust_score, :trusted, account: account, agent: create(:ai_agent, account: account)) }

    context 'with manage permissions' do
      before { sign_in manage_user }

      it 'demotes agent to supervised' do
        post :emergency_demote, params: {
          agent_id: trusted_score.agent_id,
          reason: 'Security violation detected'
        }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['new_tier']).to eq('supervised')
      end
    end
  end

  describe 'POST #create_budget' do
    context 'with manage permissions' do
      before { sign_in manage_user }

      it 'creates a budget for agent' do
        post :create_budget, params: {
          agent_id: agent.id,
          total_budget_cents: 10000,
          currency: 'USD',
          period_type: 'monthly'
        }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['total_budget_cents']).to eq(10000)
        expect(json['data']['agent_id']).to eq(agent.id)
      end
    end
  end

  describe 'PUT #update_budget' do
    let!(:budget) { create(:ai_agent_budget, account: account, agent: agent) }

    context 'with manage permissions' do
      before { sign_in manage_user }

      it 'updates budget' do
        put :update_budget, params: { id: budget.id, total_budget_cents: 20000 }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['total_budget_cents']).to eq(20000)
      end
    end
  end

  describe 'DELETE #destroy_budget' do
    let!(:budget) { create(:ai_agent_budget, account: account, agent: agent) }

    context 'with manage permissions' do
      before { sign_in manage_user }

      it 'deletes budget' do
        delete :destroy_budget, params: { id: budget.id }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['data']['deleted']).to be true
      end
    end
  end
end
