# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::AutonomyController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:agents_read_user) { create(:user, account: account, permissions: ['ai.agents.read']) }
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

      it 'returns autonomy stats' do
        get :stats

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to include('trust_scores', 'budgets', 'lineages')
        expect(json['data']['trust_scores']).to include('total', 'by_tier', 'average_score')
        expect(json['data']['budgets']).to include('total', 'active')
        expect(json['data']['lineages']).to include('total', 'active', 'terminated')
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
end
