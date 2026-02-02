# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Rag', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  let(:rag_service) { instance_double(Ai::RagService) }

  # Knowledge base mock with all required attributes
  let(:knowledge_base_attrs) do
    {
      id: 'kb123',
      name: 'Test KB',
      description: 'A test knowledge base',
      status: 'active',
      embedding_model: 'text-embedding-ada-002',
      embedding_provider: 'openai',
      embedding_dimensions: 1536,
      chunking_strategy: 'recursive',
      chunk_size: 1000,
      chunk_overlap: 200,
      is_public: false,
      document_count: 5,
      chunk_count: 50,
      total_tokens: 10000,
      storage_bytes: 50000,
      last_indexed_at: Time.current,
      last_queried_at: Time.current,
      created_at: Time.current,
      metadata_schema: {},
      settings: {}
    }
  end

  let(:knowledge_base) do
    double('KnowledgeBase', knowledge_base_attrs)
  end

  # Document mock with all required attributes
  let(:document_attrs) do
    {
      id: 'doc123',
      name: 'Test Doc',
      source_type: 'upload',
      source_url: nil,
      content_type: 'text/plain',
      status: 'processed',
      chunk_count: 10,
      token_count: 500,
      content_size_bytes: 2000,
      processed_at: Time.current,
      created_at: Time.current,
      metadata: {},
      processing_errors: nil,
      checksum: 'abc123'
    }
  end

  let(:document) do
    double('Document', document_attrs)
  end

  # Query mock
  let(:query_attrs) do
    {
      id: 'query123',
      query_text: 'test query',
      retrieval_strategy: 'semantic',
      status: 'completed',
      chunks_retrieved: 5,
      avg_similarity_score: 0.85,
      query_latency_ms: 150,
      created_at: Time.current
    }
  end

  # Connector mock
  let(:connector_attrs) do
    {
      id: 'conn123',
      name: 'GitHub Connector',
      connector_type: 'github',
      status: 'active',
      sync_frequency: 'daily',
      documents_synced: 10,
      sync_errors: nil,
      last_sync_at: Time.current,
      next_sync_at: 1.day.from_now,
      created_at: Time.current
    }
  end

  let(:connector) do
    double('Connector', connector_attrs)
  end

  before do
    allow(Ai::RagService).to receive(:new).with(account).and_return(rag_service)
  end

  describe 'GET /api/v1/ai/rag/knowledge_bases' do
    context 'with authentication' do
      it 'returns list of knowledge bases' do
        knowledge_bases = [ knowledge_base ]
        knowledge_bases.define_singleton_method(:total_count) { 1 }
        allow(rag_service).to receive(:list_knowledge_bases).and_return(knowledge_bases)

        get '/api/v1/ai/rag/knowledge_bases', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['knowledge_bases']).to be_an(Array)
        expect(data['knowledge_bases'].length).to eq(1)
        expect(data['knowledge_bases'].first['id']).to eq('kb123')
        expect(data['total_count']).to eq(1)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/rag/knowledge_bases', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/rag/knowledge_bases/:id' do
    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
    end

    context 'with authentication' do
      it 'returns knowledge base details' do
        get '/api/v1/ai/rag/knowledge_bases/kb123', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq('kb123')
        expect(data['name']).to eq('Test KB')
        expect(data['status']).to eq('active')
        # Detailed fields are included in show response
        expect(data['metadata_schema']).to be_a(Hash)
        expect(data['settings']).to be_a(Hash)
      end
    end
  end

  describe 'POST /api/v1/ai/rag/knowledge_bases' do
    let(:valid_params) do
      {
        name: 'Test Knowledge Base',
        description: 'A test KB',
        embedding_model: 'text-embedding-ada-002',
        embedding_provider: 'openai'
      }
    end

    context 'with authentication' do
      it 'creates a new knowledge base' do
        allow(rag_service).to receive(:create_knowledge_base).and_return(knowledge_base)

        post '/api/v1/ai/rag/knowledge_bases', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(rag_service).to have_received(:create_knowledge_base)
          .with(hash_including(name: 'Test Knowledge Base'), user: user)
      end

      it 'returns the created knowledge base' do
        allow(rag_service).to receive(:create_knowledge_base).and_return(knowledge_base)

        post '/api/v1/ai/rag/knowledge_bases', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['id']).to eq('kb123')
      end
    end
  end

  describe 'PATCH /api/v1/ai/rag/knowledge_bases/:id' do
    let(:update_params) { { name: 'Updated KB' } }

    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
      allow(rag_service).to receive(:update_knowledge_base).and_return(knowledge_base)
    end

    context 'with authentication' do
      it 'updates the knowledge base' do
        patch '/api/v1/ai/rag/knowledge_bases/kb123', params: update_params, headers: headers, as: :json

        expect_success_response
        expect(rag_service).to have_received(:update_knowledge_base).with('kb123', hash_including(name: 'Updated KB'))
      end
    end
  end

  describe 'DELETE /api/v1/ai/rag/knowledge_bases/:id' do
    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
      allow(rag_service).to receive(:delete_knowledge_base).and_return(true)
    end

    context 'with authentication' do
      it 'deletes the knowledge base' do
        delete '/api/v1/ai/rag/knowledge_bases/kb123', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['success']).to be true
        expect(rag_service).to have_received(:delete_knowledge_base).with('kb123')
      end
    end
  end

  describe 'GET /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/documents' do
    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
    end

    context 'with authentication' do
      it 'returns list of documents' do
        documents = [ document ]
        documents.define_singleton_method(:total_count) { 1 }
        allow(rag_service).to receive(:list_documents).and_return(documents)

        get '/api/v1/ai/rag/knowledge_bases/kb123/documents', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['documents']).to be_an(Array)
        expect(data['documents'].length).to eq(1)
        expect(data['documents'].first['id']).to eq('doc123')
        expect(data['total_count']).to eq(1)
      end
    end
  end

  describe 'POST /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/documents' do
    let(:valid_params) do
      {
        name: 'Test Document',
        source_type: 'upload',
        content_type: 'text/plain',
        content: 'Test content'
      }
    end

    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
    end

    context 'with authentication' do
      it 'creates a new document' do
        allow(rag_service).to receive(:create_document).and_return(document)

        post '/api/v1/ai/rag/knowledge_bases/kb123/documents', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(rag_service).to have_received(:create_document).with('kb123', hash_including(name: 'Test Document'), user: user)
      end
    end
  end

  describe 'GET /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/documents/:id' do
    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
      allow(rag_service).to receive(:get_document).with('kb123', 'doc123').and_return(document)
    end

    context 'with authentication' do
      it 'returns document details' do
        get '/api/v1/ai/rag/knowledge_bases/kb123/documents/doc123', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq('doc123')
        expect(data['name']).to eq('Test Doc')
        # Detailed fields are included
        expect(data).to have_key('metadata')
      end
    end
  end

  describe 'DELETE /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/documents/:id' do
    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
      allow(rag_service).to receive(:delete_document).and_return(true)
    end

    context 'with authentication' do
      it 'deletes the document' do
        delete '/api/v1/ai/rag/knowledge_bases/kb123/documents/doc123', headers: headers, as: :json

        expect_success_response
        expect(rag_service).to have_received(:delete_document).with('kb123', 'doc123')
      end
    end
  end

  describe 'POST /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/documents/:id/process' do
    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
      allow(rag_service).to receive(:process_document).with('kb123', 'doc123').and_return(document)
    end

    context 'with authentication' do
      it 'processes the document' do
        post '/api/v1/ai/rag/knowledge_bases/kb123/documents/doc123/process', headers: headers, as: :json

        expect_success_response
        expect(rag_service).to have_received(:process_document).with('kb123', 'doc123')
      end
    end
  end

  describe 'POST /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/embed' do
    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
    end

    context 'with authentication' do
      it 'embeds chunks' do
        result = { success: true, chunks_embedded: 10 }
        allow(rag_service).to receive(:embed_chunks).and_return(result)

        post '/api/v1/ai/rag/knowledge_bases/kb123/embed', headers: headers, as: :json

        expect_success_response
        expect(rag_service).to have_received(:embed_chunks).with('kb123', document_id: nil)
      end

      it 'accepts document_id parameter' do
        result = { success: true, chunks_embedded: 5 }
        allow(rag_service).to receive(:embed_chunks).and_return(result)

        post '/api/v1/ai/rag/knowledge_bases/kb123/embed', params: { document_id: 'doc123' }, headers: headers, as: :json

        expect_success_response
        expect(rag_service).to have_received(:embed_chunks).with('kb123', document_id: 'doc123')
      end
    end
  end

  describe 'POST /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/query' do
    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
    end

    context 'with authentication' do
      it 'performs a query' do
        result = { results: [], chunks: [] }
        allow(rag_service).to receive(:query).and_return(result)

        post '/api/v1/ai/rag/knowledge_bases/kb123/query',
             params: { query: 'test query' }, headers: headers, as: :json

        expect_success_response
        expect(rag_service).to have_received(:query).with('kb123', hash_including(query: 'test query'), user: user)
      end
    end
  end

  describe 'GET /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/query_history' do
    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
    end

    context 'with authentication' do
      it 'returns query history' do
        query = double('Query', query_attrs)
        queries = [ query ]
        queries.define_singleton_method(:total_count) { 1 }
        allow(rag_service).to receive(:get_query_history).and_return(queries)

        get '/api/v1/ai/rag/knowledge_bases/kb123/query_history', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['queries']).to be_an(Array)
        expect(data['queries'].length).to eq(1)
        expect(data['total_count']).to eq(1)
      end
    end
  end

  describe 'GET /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/connectors' do
    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
    end

    context 'with authentication' do
      it 'returns list of connectors' do
        connectors = [ connector ]
        allow(rag_service).to receive(:list_connectors).and_return(connectors)

        get '/api/v1/ai/rag/knowledge_bases/kb123/connectors', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['connectors']).to be_an(Array)
        expect(data['connectors'].length).to eq(1)
        expect(data['connectors'].first['id']).to eq('conn123')
      end
    end
  end

  describe 'POST /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/connectors' do
    let(:valid_params) do
      {
        name: 'GitHub Connector',
        connector_type: 'github',
        sync_frequency: 'daily'
      }
    end

    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
    end

    context 'with authentication' do
      it 'creates a new connector' do
        allow(rag_service).to receive(:create_connector).and_return(connector)

        post '/api/v1/ai/rag/knowledge_bases/kb123/connectors', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect(rag_service).to have_received(:create_connector)
      end
    end
  end

  describe 'POST /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/connectors/:id/sync' do
    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
    end

    context 'with authentication' do
      it 'syncs the connector' do
        result = { success: true, documents_synced: 5 }
        allow(rag_service).to receive(:sync_connector).and_return(result)

        post '/api/v1/ai/rag/knowledge_bases/kb123/connectors/conn123/sync', headers: headers, as: :json

        expect_success_response
        expect(rag_service).to have_received(:sync_connector).with('kb123', 'conn123')
      end
    end
  end

  describe 'GET /api/v1/ai/rag/knowledge_bases/:knowledge_base_id/analytics' do
    before do
      allow(rag_service).to receive(:get_knowledge_base).with('kb123').and_return(knowledge_base)
    end

    context 'with authentication' do
      it 'returns analytics data' do
        analytics = { total_queries: 100, avg_latency: 50 }
        allow(rag_service).to receive(:get_analytics).and_return(analytics)

        get '/api/v1/ai/rag/knowledge_bases/kb123/analytics', headers: headers, as: :json

        expect_success_response
        expect(rag_service).to have_received(:get_analytics).with('kb123', period_days: 30)
      end

      it 'accepts custom period_days' do
        analytics = { total_queries: 50, avg_latency: 45 }
        allow(rag_service).to receive(:get_analytics).and_return(analytics)

        get '/api/v1/ai/rag/knowledge_bases/kb123/analytics?period_days=7', headers: headers, as: :json

        expect_success_response
        expect(rag_service).to have_received(:get_analytics).with('kb123', period_days: 7)
      end
    end
  end
end
