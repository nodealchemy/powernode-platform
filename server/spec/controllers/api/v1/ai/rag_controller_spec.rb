# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::RagController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.create', 'ai.agents.update', 'ai.agents.delete']) }
  let(:no_perms_user) { create(:user, account: account, permissions: []) }

  let!(:knowledge_base) { create(:ai_knowledge_base, account: account) }
  let(:rag_service) { instance_double(Ai::RagService) }

  before do
    sign_in_as_user(user)
    allow(Ai::RagService).to receive(:new).and_return(rag_service)
    allow(rag_service).to receive(:get_knowledge_base).and_return(knowledge_base)
  end

  # ============================================================================
  # AUTHENTICATION
  # ============================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      get :index
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ============================================================================
  # KNOWLEDGE BASES - INDEX
  # ============================================================================

  describe 'GET #index' do
    it 'returns knowledge bases' do
      allow(rag_service).to receive(:list_knowledge_bases).and_return([knowledge_base])

      get :index
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['knowledge_bases']).to be_an(Array)
      expect(json_response['data']['knowledge_bases'].first['name']).to eq(knowledge_base.name)
    end
  end

  # ============================================================================
  # KNOWLEDGE BASES - SHOW
  # ============================================================================

  describe 'GET #show_knowledge_base' do
    it 'returns knowledge base details' do
      get :show_knowledge_base, params: { id: knowledge_base.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['name']).to eq(knowledge_base.name)
    end
  end

  # ============================================================================
  # KNOWLEDGE BASES - CREATE
  # ============================================================================

  describe 'POST #create_knowledge_base' do
    let(:new_kb) { create(:ai_knowledge_base, account: account, name: 'New KB') }

    it 'creates a new knowledge base' do
      allow(rag_service).to receive(:create_knowledge_base).and_return(new_kb)

      post :create_knowledge_base, params: {
        name: 'New KB',
        description: 'A new knowledge base',
        embedding_model: 'text-embedding-3-small'
      }
      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
      expect(json_response['data']['name']).to eq('New KB')
    end
  end

  # ============================================================================
  # KNOWLEDGE BASES - UPDATE
  # ============================================================================

  describe 'PATCH #update_knowledge_base' do
    it 'updates a knowledge base' do
      updated_kb = knowledge_base
      updated_kb.name = 'Updated Name'
      allow(rag_service).to receive(:update_knowledge_base).and_return(updated_kb)

      patch :update_knowledge_base, params: { id: knowledge_base.id, name: 'Updated Name' }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # KNOWLEDGE BASES - DELETE
  # ============================================================================

  describe 'DELETE #delete_knowledge_base' do
    it 'deletes a knowledge base' do
      allow(rag_service).to receive(:delete_knowledge_base).and_return(true)

      delete :delete_knowledge_base, params: { id: knowledge_base.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # DOCUMENTS
  # ============================================================================

  describe 'GET #list_documents' do
    let(:document) { create(:ai_document, knowledge_base: knowledge_base) }

    it 'returns documents for a knowledge base' do
      allow(rag_service).to receive(:list_documents).and_return([document])

      get :list_documents, params: { knowledge_base_id: knowledge_base.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['documents']).to be_an(Array)
    end
  end

  describe 'POST #create_document' do
    let(:new_doc) { create(:ai_document, knowledge_base: knowledge_base) }

    it 'creates a document' do
      allow(rag_service).to receive(:create_document).and_return(new_doc)

      post :create_document, params: {
        knowledge_base_id: knowledge_base.id,
        name: 'test.txt',
        source_type: 'text',
        content: 'Some test content'
      }
      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
    end
  end

  # ============================================================================
  # QUERIES
  # ============================================================================

  describe 'POST #query' do
    it 'queries a knowledge base' do
      allow(rag_service).to receive(:query).and_return({
        results: [{ content: 'relevant text', score: 0.95 }],
        query_id: 'q-123'
      })

      post :query, params: {
        knowledge_base_id: knowledge_base.id,
        query: 'What is Ruby?',
        top_k: 5
      }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end

  describe 'GET #query_history' do
    it 'returns query history' do
      allow(rag_service).to receive(:get_query_history).and_return([])

      get :query_history, params: { knowledge_base_id: knowledge_base.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['queries']).to be_an(Array)
    end
  end

  # ============================================================================
  # CONNECTORS
  # ============================================================================

  describe 'GET #list_connectors' do
    it 'returns connectors for a knowledge base' do
      allow(rag_service).to receive(:list_connectors).and_return([])

      get :list_connectors, params: { knowledge_base_id: knowledge_base.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['connectors']).to be_an(Array)
    end
  end

  # ============================================================================
  # ANALYTICS
  # ============================================================================

  describe 'GET #analytics' do
    it 'returns analytics for a knowledge base' do
      allow(rag_service).to receive(:get_analytics).and_return({
        query_count: 100, avg_latency_ms: 150
      })

      get :analytics, params: { knowledge_base_id: knowledge_base.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end
  end
end
