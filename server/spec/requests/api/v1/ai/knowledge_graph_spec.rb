# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::KnowledgeGraph", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/ai/knowledge_graph/nodes" do
    let!(:node1) { create(:ai_knowledge_graph_node, account: account, name: "Ruby") }
    let!(:node2) { create(:ai_knowledge_graph_node, :concept, account: account, name: "OOP") }

    it "returns list of active nodes" do
      get "/api/v1/ai/knowledge_graph/nodes", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"]["nodes"].size).to eq(2)
    end

    it "filters by node_type" do
      get "/api/v1/ai/knowledge_graph/nodes", params: { node_type: "entity" }, headers: headers

      body = JSON.parse(response.body)
      expect(body["data"]["nodes"].size).to eq(1)
      expect(body["data"]["nodes"].first["name"]).to eq("Ruby")
    end

    it "searches by query" do
      get "/api/v1/ai/knowledge_graph/nodes", params: { query: "Ruby" }, headers: headers

      body = JSON.parse(response.body)
      expect(body["data"]["nodes"].size).to eq(1)
    end
  end

  describe "GET /api/v1/ai/knowledge_graph/nodes/:id" do
    let!(:node) { create(:ai_knowledge_graph_node, account: account) }

    it "returns node details" do
      get "/api/v1/ai/knowledge_graph/nodes/#{node.id}", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"]["node"]["id"]).to eq(node.id)
    end

    it "returns 404 for non-existent node" do
      get "/api/v1/ai/knowledge_graph/nodes/#{SecureRandom.uuid}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/ai/knowledge_graph/nodes" do
    let(:node_params) do
      { name: "Python", node_type: "entity", entity_type: "technology", description: "A programming language" }
    end

    it "creates a new node" do
      expect {
        post "/api/v1/ai/knowledge_graph/nodes", params: node_params.to_json, headers: headers
      }.to change(Ai::KnowledgeGraphNode, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["data"]["node"]["name"]).to eq("Python")
    end

    it "returns error for invalid params" do
      post "/api/v1/ai/knowledge_graph/nodes",
           params: { name: "Test", node_type: "invalid" }.to_json,
           headers: headers

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/ai/knowledge_graph/nodes/:id" do
    let!(:node) { create(:ai_knowledge_graph_node, account: account, name: "Old Name") }

    it "updates node" do
      patch "/api/v1/ai/knowledge_graph/nodes/#{node.id}",
            params: { name: "New Name" }.to_json,
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(node.reload.name).to eq("New Name")
    end
  end

  describe "DELETE /api/v1/ai/knowledge_graph/nodes/:id" do
    let!(:node) { create(:ai_knowledge_graph_node, account: account) }

    it "deletes node" do
      expect {
        delete "/api/v1/ai/knowledge_graph/nodes/#{node.id}", headers: headers
      }.to change(Ai::KnowledgeGraphNode, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /api/v1/ai/knowledge_graph/edges" do
    let(:node_a) { create(:ai_knowledge_graph_node, account: account) }
    let(:node_b) { create(:ai_knowledge_graph_node, account: account) }
    let!(:edge) { create(:ai_knowledge_graph_edge, account: account, source_node: node_a, target_node: node_b) }

    it "returns list of edges" do
      get "/api/v1/ai/knowledge_graph/edges", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"]["edges"].size).to eq(1)
    end
  end

  describe "POST /api/v1/ai/knowledge_graph/edges" do
    let(:node_a) { create(:ai_knowledge_graph_node, account: account) }
    let(:node_b) { create(:ai_knowledge_graph_node, account: account) }

    it "creates an edge" do
      post "/api/v1/ai/knowledge_graph/edges",
           params: {
             source_node_id: node_a.id,
             target_node_id: node_b.id,
             relation_type: "depends_on"
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["data"]["edge"]["relation_type"]).to eq("depends_on")
    end
  end

  describe "DELETE /api/v1/ai/knowledge_graph/edges/:id" do
    let(:node_a) { create(:ai_knowledge_graph_node, account: account) }
    let(:node_b) { create(:ai_knowledge_graph_node, account: account) }
    let!(:edge) { create(:ai_knowledge_graph_edge, account: account, source_node: node_a, target_node: node_b) }

    it "deletes edge" do
      expect {
        delete "/api/v1/ai/knowledge_graph/edges/#{edge.id}", headers: headers
      }.to change(Ai::KnowledgeGraphEdge, :count).by(-1)
    end
  end

  describe "GET /api/v1/ai/knowledge_graph/nodes/:id/neighbors" do
    let(:center) { create(:ai_knowledge_graph_node, account: account, name: "Center") }
    let(:neighbor) { create(:ai_knowledge_graph_node, account: account, name: "Neighbor") }

    before do
      create(:ai_knowledge_graph_edge, account: account, source_node: center, target_node: neighbor)
    end

    it "returns neighbors" do
      get "/api/v1/ai/knowledge_graph/nodes/#{center.id}/neighbors", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"]["neighbors"]).to be_an(Array)
    end
  end

  describe "GET /api/v1/ai/knowledge_graph/shortest_path" do
    let(:node_a) { create(:ai_knowledge_graph_node, account: account) }
    let(:node_b) { create(:ai_knowledge_graph_node, account: account) }

    before do
      create(:ai_knowledge_graph_edge, account: account, source_node: node_a, target_node: node_b)
    end

    it "finds shortest path" do
      get "/api/v1/ai/knowledge_graph/shortest_path",
          params: { source_id: node_a.id, target_id: node_b.id },
          headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"]["path"]).to be_an(Array)
    end
  end

  describe "POST /api/v1/ai/knowledge_graph/subgraph" do
    let(:node_a) { create(:ai_knowledge_graph_node, account: account) }
    let(:node_b) { create(:ai_knowledge_graph_node, account: account) }

    it "returns subgraph" do
      post "/api/v1/ai/knowledge_graph/subgraph",
           params: { node_ids: [node_a.id, node_b.id] }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"]["nodes"]).to be_an(Array)
    end
  end

  describe "GET /api/v1/ai/knowledge_graph/statistics" do
    before do
      create(:ai_knowledge_graph_node, account: account)
    end

    it "returns graph statistics" do
      get "/api/v1/ai/knowledge_graph/statistics", headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"]["node_count"]).to eq(1)
    end
  end

  describe "POST /api/v1/ai/knowledge_graph/reason" do
    it "performs multi-hop reasoning" do
      post "/api/v1/ai/knowledge_graph/reason",
           params: { query: "What technologies are related?" }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"]).to have_key("answer_nodes")
    end

    it "requires query parameter" do
      post "/api/v1/ai/knowledge_graph/reason",
           params: {}.to_json,
           headers: headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "POST /api/v1/ai/knowledge_graph/search" do
    it "performs hybrid search" do
      post "/api/v1/ai/knowledge_graph/search",
           params: { query: "Ruby programming", mode: "hybrid" }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"]).to have_key("results")
    end

    it "requires query parameter" do
      post "/api/v1/ai/knowledge_graph/search",
           params: {}.to_json,
           headers: headers

      expect(response).to have_http_status(:bad_request)
    end
  end
end
