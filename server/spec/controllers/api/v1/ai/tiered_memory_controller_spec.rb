# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::TieredMemoryController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.memory.read', 'ai.memory.write']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['ai.memory.read']) }
  let(:no_perms_user) { create(:user, account: account, permissions: []) }

  let(:agent) { create(:ai_agent, account: account, creator: user) }

  before { sign_in_as_user(user) }

  # ============================================================================
  # AUTHENTICATION
  # ============================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :stats, params: { agent_id: agent.id }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ============================================================================
  # AUTHORIZATION
  # ============================================================================

  describe 'authorization' do
    context 'without permissions' do
      before { sign_in_as_user(no_perms_user) }

      it 'returns 403 for stats' do
        get :stats, params: { agent_id: agent.id }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for index' do
        get :index, params: { agent_id: agent.id }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for create' do
        post :create, params: { agent_id: agent.id, key: 'test', value: { data: 'test' } }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for destroy' do
        delete :destroy, params: { agent_id: agent.id, key: 'test_key' }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for shared_knowledge' do
        get :shared_knowledge
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for consolidate_all' do
        post :consolidate_all
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with read-only permissions' do
      before { sign_in_as_user(read_only_user) }

      it 'allows stats access' do
        router = instance_double(Ai::Memory::RouterService)
        allow(Ai::Memory::RouterService).to receive(:new).and_return(router)
        allow(router).to receive(:stats).and_return({ working: 0, short_term: 0 })

        get :stats, params: { agent_id: agent.id }
        expect(response).to have_http_status(:ok)
      end

      it 'returns 403 for create' do
        post :create, params: { agent_id: agent.id, key: 'test', value: { data: 'test' } }
        expect(response).to have_http_status(:forbidden)
      end

      it 'returns 403 for consolidate' do
        post :consolidate, params: { agent_id: agent.id, session_id: 'sess-1' }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ============================================================================
  # STATS
  # ============================================================================

  describe 'GET #stats' do
    it 'returns memory stats for agent' do
      router = instance_double(Ai::Memory::RouterService)
      allow(Ai::Memory::RouterService).to receive(:new).and_return(router)
      allow(router).to receive(:stats).and_return({ working: 0, short_term: 5, long_term: 10 })

      get :stats, params: { agent_id: agent.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'returns 404 for non-existent agent' do
      get :stats, params: { agent_id: SecureRandom.uuid }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ============================================================================
  # INDEX
  # ============================================================================

  describe 'GET #index' do
    let(:router) { instance_double(Ai::Memory::RouterService) }

    before do
      allow(Ai::Memory::RouterService).to receive(:new).and_return(router)
    end

    it 'reads by key when key param provided' do
      allow(router).to receive(:read).and_return({ key: 'test', value: 'data' })

      get :index, params: { agent_id: agent.id, key: 'test' }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'returns entries for short_term tier by default' do
      create(:ai_agent_short_term_memory, agent: agent, account: account)

      get :index, params: { agent_id: agent.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['tier']).to eq('short_term')
    end

    it 'returns entries for specified tier' do
      allow(router).to receive(:stats).and_return({ working: { count: 0 } })

      get :index, params: { agent_id: agent.id, tier: 'working' }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['tier']).to eq('working')
    end
  end

  # ============================================================================
  # CREATE
  # ============================================================================

  describe 'POST #create' do
    let(:router) { instance_double(Ai::Memory::RouterService) }

    before do
      allow(Ai::Memory::RouterService).to receive(:new).and_return(router)
    end

    it 'creates a memory entry' do
      allow(router).to receive(:write).and_return({ success: true, key: 'test_key', tier: 'short_term' })

      post :create, params: { agent_id: agent.id, key: 'test_key', value: { data: 'test' }, tier: 'short_term' }
      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
    end

    it 'returns error on write failure' do
      allow(router).to receive(:write).and_return({ success: false, error: 'Write failed' })

      post :create, params: { agent_id: agent.id, key: 'test_key', value: { data: 'test' } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ============================================================================
  # DESTROY
  # ============================================================================

  describe 'DELETE #destroy' do
    let(:router) { instance_double(Ai::Memory::RouterService) }

    before do
      allow(Ai::Memory::RouterService).to receive(:new).and_return(router)
    end

    it 'deletes a memory entry' do
      allow(router).to receive(:delete).and_return({ success: true })

      delete :destroy, params: { agent_id: agent.id, key: 'test_key' }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'returns error on delete failure' do
      allow(router).to receive(:delete).and_return({ success: false, error: 'Not found' })

      delete :destroy, params: { agent_id: agent.id, key: 'test_key' }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ============================================================================
  # CONSOLIDATE
  # ============================================================================

  describe 'POST #consolidate' do
    let(:router) { instance_double(Ai::Memory::RouterService) }

    before do
      allow(Ai::Memory::RouterService).to receive(:new).and_return(router)
    end

    it 'consolidates memory for a session' do
      allow(router).to receive(:consolidate!).and_return({ consolidated: 5 })

      post :consolidate, params: { agent_id: agent.id, session_id: 'sess-1' }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'returns bad_request without session_id' do
      post :consolidate, params: { agent_id: agent.id }
      expect(response).to have_http_status(:bad_request)
    end
  end

  # ============================================================================
  # CONSOLIDATE ALL
  # ============================================================================

  describe 'POST #consolidate_all' do
    it 'runs consolidation pipeline' do
      maintenance = instance_double(Ai::Memory::MaintenanceService)
      allow(Ai::Memory::MaintenanceService).to receive(:new).and_return(maintenance)
      allow(maintenance).to receive(:run_consolidation_pipeline).and_return({ consolidated: 10 })

      post :consolidate_all
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'returns error on pipeline failure' do
      maintenance = instance_double(Ai::Memory::MaintenanceService)
      allow(Ai::Memory::MaintenanceService).to receive(:new).and_return(maintenance)
      allow(maintenance).to receive(:run_consolidation_pipeline).and_raise(StandardError, 'Pipeline failed')

      post :consolidate_all
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ============================================================================
  # DECAY ALL
  # ============================================================================

  describe 'POST #decay_all' do
    it 'runs decay pipeline' do
      maintenance = instance_double(Ai::Memory::MaintenanceService)
      allow(Ai::Memory::MaintenanceService).to receive(:new).and_return(maintenance)
      allow(maintenance).to receive(:run_decay_pipeline).and_return({ decayed: 5 })

      post :decay_all
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # SHARED MAINTENANCE
  # ============================================================================

  describe 'POST #shared_maintenance' do
    it 'runs shared knowledge maintenance' do
      shared = instance_double(Ai::Memory::SharedKnowledgeService)
      allow(Ai::Memory::SharedKnowledgeService).to receive(:new).and_return(shared)
      allow(shared).to receive(:import_from_learnings).and_return({ imported: 3 })
      allow(shared).to receive(:recalculate_all_quality).and_return({ success: true, recalculated: 5 })
      allow(shared).to receive(:stats).and_return({ total: 10, active: 8 })

      post :shared_maintenance
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'calls import, recalculate, and stats in sequence' do
      shared = instance_double(Ai::Memory::SharedKnowledgeService)
      allow(Ai::Memory::SharedKnowledgeService).to receive(:new).and_return(shared)

      expect(shared).to receive(:import_from_learnings).ordered.and_return({ imported: 2 })
      expect(shared).to receive(:recalculate_all_quality).ordered.and_return({ success: true, recalculated: 3 })
      expect(shared).to receive(:stats).ordered.and_return({ total: 5 })

      post :shared_maintenance
    end

    it 'includes quality_recalc in response' do
      shared = instance_double(Ai::Memory::SharedKnowledgeService)
      allow(Ai::Memory::SharedKnowledgeService).to receive(:new).and_return(shared)
      allow(shared).to receive(:import_from_learnings).and_return({ imported: 1 })
      allow(shared).to receive(:recalculate_all_quality).and_return({ success: true, recalculated: 7 })
      allow(shared).to receive(:stats).and_return({ total: 10 })

      post :shared_maintenance
      expect(response).to have_http_status(:ok)

      data = json_response['data']
      expect(data).to have_key('import_result')
      expect(data).to have_key('quality_recalc')
      expect(data).to have_key('stats')
      expect(data['quality_recalc']['recalculated']).to eq(7)
    end
  end

  # ============================================================================
  # SHARED KNOWLEDGE
  # ============================================================================

  describe 'GET #shared_knowledge' do
    it 'returns shared knowledge entries' do
      create(:ai_shared_knowledge, account: account, access_level: 'account')

      get :shared_knowledge
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']).to be_an(Array)
    end
  end
end
