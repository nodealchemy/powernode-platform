# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Ai::KnowledgeGraphController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.agents.read', 'ai.agents.create', 'ai.agents.update', 'ai.agents.delete']) }
  let(:user_no_perms) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }

  let!(:node) { create(:ai_knowledge_graph_node, account: account, name: 'Ruby') }
  let!(:node2) { create(:ai_knowledge_graph_node, account: account, name: 'Rails') }
  let!(:edge) { create(:ai_knowledge_graph_edge, account: account, source_node: node, target_node: node2) }

  let(:graph_service) { instance_double(Ai::KnowledgeGraph::GraphService) }

  before do
    sign_in_as_user(user)
    allow(Ai::KnowledgeGraph::GraphService).to receive(:new).and_return(graph_service)
  end

  # ============================================================================
  # AUTHENTICATION
  # ============================================================================

  describe 'authentication' do
    it 'returns 401 without token' do
      @request.env.delete('HTTP_AUTHORIZATION')
      allow(graph_service).to receive(:list_nodes).and_return([])
      get :nodes
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ============================================================================
  # NODES
  # ============================================================================

  describe 'GET #nodes' do
    before do
      allow(graph_service).to receive(:list_nodes).and_return([node, node2])
    end

    it 'returns nodes list' do
      get :nodes
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
      expect(json_response['data']['nodes']).to be_an(Array)
      expect(json_response['data']['nodes'].size).to eq(2)
    end

    it 'passes filter params to service' do
      expect(graph_service).to receive(:list_nodes).with(
        ActionController::Parameters.new('node_type' => 'entity').permit(:node_type, :entity_type, :query, :knowledge_base_id, :page, :per_page)
      ).and_return([node])

      get :nodes, params: { node_type: 'entity' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET #show_node' do
    it 'returns a single node' do
      allow(graph_service).to receive(:find_node!).with(node.id).and_return(node)

      get :show_node, params: { id: node.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['node']['id']).to eq(node.id)
      expect(json_response['data']['node']['name']).to eq('Ruby')
    end

    it 'returns 404 for non-existent node' do
      allow(graph_service).to receive(:find_node!).and_raise(
        Ai::KnowledgeGraph::GraphServiceError.new('Node not found')
      )

      get :show_node, params: { id: 'nonexistent' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST #create_node' do
    let(:new_node) { build(:ai_knowledge_graph_node, account: account, name: 'Python') }

    it 'creates a new node' do
      allow(graph_service).to receive(:create_node).and_return(new_node)

      post :create_node, params: { name: 'Python', node_type: 'entity', entity_type: 'technology' }
      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
    end

    it 'returns error on creation failure' do
      allow(graph_service).to receive(:create_node).and_raise(
        Ai::KnowledgeGraph::GraphServiceError.new('Validation failed')
      )

      post :create_node, params: { name: '', node_type: 'entity' }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'PATCH #update_node' do
    it 'updates a node' do
      allow(graph_service).to receive(:update_node).and_return(node)

      patch :update_node, params: { id: node.id, name: 'Updated Ruby' }
      expect(response).to have_http_status(:ok)
      expect(json_response['success']).to be true
    end

    it 'returns error on update failure' do
      allow(graph_service).to receive(:update_node).and_raise(
        Ai::KnowledgeGraph::GraphServiceError.new('Update failed')
      )

      patch :update_node, params: { id: node.id, name: '' }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'DELETE #destroy_node' do
    it 'deletes a node' do
      allow(graph_service).to receive(:delete_node).with(node.id).and_return(true)

      delete :destroy_node, params: { id: node.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['deleted']).to be true
    end

    it 'returns 404 for non-existent node' do
      allow(graph_service).to receive(:delete_node).and_raise(
        Ai::KnowledgeGraph::GraphServiceError.new('Node not found')
      )

      delete :destroy_node, params: { id: 'nonexistent' }
      expect(response).to have_http_status(:not_found)
    end
  end

  # ============================================================================
  # EDGES
  # ============================================================================

  describe 'GET #edges' do
    it 'returns edges list' do
      allow(graph_service).to receive(:list_edges).and_return([edge])

      get :edges
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['edges']).to be_an(Array)
    end
  end

  describe 'POST #create_edge' do
    it 'creates a new edge' do
      allow(graph_service).to receive(:create_edge).and_return(edge)

      post :create_edge, params: {
        source_node_id: node.id,
        target_node_id: node2.id,
        relation_type: 'related_to'
      }
      expect(response).to have_http_status(:created)
      expect(json_response['success']).to be true
    end
  end

  describe 'DELETE #destroy_edge' do
    it 'deletes an edge' do
      allow(graph_service).to receive(:delete_edge).with(edge.id).and_return(true)

      delete :destroy_edge, params: { id: edge.id }
      expect(response).to have_http_status(:ok)
    end
  end

  # ============================================================================
  # GRAPH TRAVERSAL
  # ============================================================================

  describe 'GET #neighbors' do
    it 'returns neighbors for a node' do
      allow(graph_service).to receive(:find_neighbors).and_return([{ id: node2.id, name: 'Rails' }])

      get :neighbors, params: { id: node.id, depth: 1 }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['neighbors']).to be_an(Array)
    end
  end

  describe 'GET #shortest_path' do
    it 'returns a path between two nodes' do
      allow(graph_service).to receive(:shortest_path).and_return([edge])

      get :shortest_path, params: { source_id: node.id, target_id: node2.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['path']).to be_an(Array)
      expect(json_response['data']['length']).to eq(1)
    end

    it 'returns empty path when no path found' do
      allow(graph_service).to receive(:shortest_path).and_return(nil)

      get :shortest_path, params: { source_id: node.id, target_id: node2.id }
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['path']).to eq([])
      expect(json_response['data']['length']).to eq(0)
    end
  end

  describe 'POST #subgraph' do
    it 'returns subgraph data' do
      allow(graph_service).to receive(:subgraph).and_return({ nodes: [node], edges: [edge] })

      post :subgraph, params: { node_ids: [node.id, node2.id] }
      expect(response).to have_http_status(:ok)
    end

    it 'returns error when node_ids missing' do
      post :subgraph, params: {}
      expect(response).to have_http_status(:bad_request)
    end
  end

  # ============================================================================
  # EXTRACTION & REASONING
  # ============================================================================

  describe 'GET #statistics' do
    it 'returns graph statistics' do
      allow(graph_service).to receive(:statistics).and_return({
        total_nodes: 2, total_edges: 1, node_types: { entity: 2 }
      })

      get :statistics
      expect(response).to have_http_status(:ok)
      expect(json_response['data']['total_nodes']).to eq(2)
    end
  end

  describe 'POST #extract' do
    it 'returns error when document_id missing' do
      post :extract, params: {}
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'POST #multi_hop_reason' do
    it 'returns error when query missing' do
      post :multi_hop_reason, params: {}
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'POST #hybrid_search' do
    it 'returns error when query missing' do
      post :hybrid_search, params: {}
      expect(response).to have_http_status(:bad_request)
    end
  end
end
