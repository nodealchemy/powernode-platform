# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::KnowledgeGraph", type: :request do
  let(:account) { create(:account) }
  # Functional (non-authorization) examples below exercise both reads and
  # writes, so the shared actor holds both knowledge-graph permissions. The
  # dedicated `authorization` describe block uses its own least-privilege
  # actors to assert the per-action gates.
  let(:user) do
    create(:user, account: account,
                  permissions: ["ai.knowledge_graph.read", "ai.knowledge_graph.manage"])
  end
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

  # Cross-tenant IDOR: extract resolves a Document by id; Document delegates its
  # account to its knowledge_base. The document must be scoped to the acting
  # account so a foreign account's document 404s (never disclose its content via
  # extracted nodes/edges).
  describe "POST /api/v1/ai/knowledge_graph/extract (IDOR)" do
    let(:extraction_result) do
      {
        stats: { nodes_created: 0, nodes_existing: 0, edges_created: 0, edges_existing: 0 },
        nodes: [],
        edges: []
      }
    end

    before do
      # Stub extraction so the IDOR is observable via status alone (no live AI):
      # under the unscoped find a foreign doc would resolve and 200; the fix 404s first.
      allow_any_instance_of(::Ai::KnowledgeGraph::ExtractionService)
        .to receive(:extract_from_document).and_return(extraction_result)
    end

    let(:own_kb) { create(:ai_knowledge_base, account: account) }
    let(:own_document) { create(:ai_document, knowledge_base: own_kb) }
    # Factory creates its own (foreign) account+knowledge_base for this document.
    let(:foreign_document) { create(:ai_document) }

    it "does not extract from a document in another account" do
      post "/api/v1/ai/knowledge_graph/extract",
           params: { document_id: foreign_document.id }.to_json, headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it "extracts from the acting account's own document" do
      post "/api/v1/ai/knowledge_graph/extract",
           params: { document_id: own_document.id }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
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

  # ==========================================================================
  # AUTHORIZATION
  #
  # Every action must be gated by a per-action permission: READ actions by
  # `ai.knowledge_graph.read` and WRITE/mutation actions by
  # `ai.knowledge_graph.manage`. Authentication alone is NOT sufficient — a
  # user holding neither permission (or only an unrelated one) must be 403
  # for both reads and writes, and the gate must run BEFORE the request body
  # is processed so a missing-param body still yields 403, never 400/200.
  # ==========================================================================
  describe "authorization" do
    # Holds an unrelated permission only — neither read nor manage.
    let(:unauthorized_user) { create(:user, account: account, permissions: ["ai.agents.read"]) }
    let(:unauthorized_headers) { auth_headers_for(unauthorized_user) }

    # Holds exactly the read permission (no manage).
    let(:read_user) { create(:user, account: account, permissions: ["ai.knowledge_graph.read"]) }
    let(:read_headers) { auth_headers_for(read_user) }

    # Holds exactly the manage permission (no read).
    let(:manage_user) { create(:user, account: account, permissions: ["ai.knowledge_graph.manage"]) }
    let(:manage_headers) { auth_headers_for(manage_user) }

    let!(:authz_node) { create(:ai_knowledge_graph_node, account: account, name: "AuthzNode") }
    let!(:authz_node2) { create(:ai_knowledge_graph_node, account: account, name: "AuthzNode2") }
    let!(:authz_edge) do
      create(:ai_knowledge_graph_edge, account: account, source_node: authz_node, target_node: authz_node2)
    end

    # READ actions → ai.knowledge_graph.read. Each entry is a callable that
    # issues the request with the given headers.
    read_requests = {
      "GET #nodes" => ->(ctx, h) { ctx.get "/api/v1/ai/knowledge_graph/nodes", headers: h },
      "GET #show_node" => ->(ctx, h) { ctx.get "/api/v1/ai/knowledge_graph/nodes/#{ctx.authz_node.id}", headers: h },
      "GET #edges" => ->(ctx, h) { ctx.get "/api/v1/ai/knowledge_graph/edges", headers: h },
      "GET #neighbors" => ->(ctx, h) { ctx.get "/api/v1/ai/knowledge_graph/nodes/#{ctx.authz_node.id}/neighbors", headers: h },
      "GET #shortest_path" => ->(ctx, h) { ctx.get "/api/v1/ai/knowledge_graph/shortest_path", params: { source_id: ctx.authz_node.id, target_id: ctx.authz_node2.id }, headers: h },
      "POST #subgraph" => ->(ctx, h) { ctx.post "/api/v1/ai/knowledge_graph/subgraph", params: { node_ids: [ctx.authz_node.id] }.to_json, headers: h },
      "GET #statistics" => ->(ctx, h) { ctx.get "/api/v1/ai/knowledge_graph/statistics", headers: h },
      "POST #multi_hop_reason" => ->(ctx, h) { ctx.post "/api/v1/ai/knowledge_graph/reason", params: { query: "q" }.to_json, headers: h },
      "POST #hybrid_search" => ->(ctx, h) { ctx.post "/api/v1/ai/knowledge_graph/search", params: { query: "q" }.to_json, headers: h }
    }

    # WRITE actions → ai.knowledge_graph.manage.
    write_requests = {
      "POST #create_node" => ->(ctx, h) { ctx.post "/api/v1/ai/knowledge_graph/nodes", params: { name: "X", node_type: "entity" }.to_json, headers: h },
      "PATCH #update_node" => ->(ctx, h) { ctx.patch "/api/v1/ai/knowledge_graph/nodes/#{ctx.authz_node.id}", params: { name: "Y" }.to_json, headers: h },
      "DELETE #destroy_node" => ->(ctx, h) { ctx.delete "/api/v1/ai/knowledge_graph/nodes/#{ctx.authz_node.id}", headers: h },
      "POST #create_edge" => ->(ctx, h) { ctx.post "/api/v1/ai/knowledge_graph/edges", params: { source_node_id: ctx.authz_node.id, target_node_id: ctx.authz_node2.id, relation_type: "related_to" }.to_json, headers: h },
      "DELETE #destroy_edge" => ->(ctx, h) { ctx.delete "/api/v1/ai/knowledge_graph/edges/#{ctx.authz_edge.id}", headers: h },
      "POST #extract" => ->(ctx, h) { ctx.post "/api/v1/ai/knowledge_graph/extract", params: { document_id: SecureRandom.uuid }.to_json, headers: h }
    }

    context "a user with no relevant permission (only an unrelated one)" do
      read_requests.each do |label, req|
        it "is forbidden from READ action #{label}" do
          req.call(self, unauthorized_headers)
          expect(response).to have_http_status(:forbidden)
        end
      end

      write_requests.each do |label, req|
        it "is forbidden from WRITE action #{label}" do
          req.call(self, unauthorized_headers)
          expect(response).to have_http_status(:forbidden)
        end
      end
    end

    context "a user holding ai.knowledge_graph.read" do
      read_requests.each do |label, req|
        it "is allowed (not forbidden) on READ action #{label}" do
          req.call(self, read_headers)
          expect(response).not_to have_http_status(:forbidden)
        end
      end

      it "is still forbidden from a WRITE action (read does not grant manage)" do
        write_requests["POST #create_node"].call(self, read_headers)
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "a user holding ai.knowledge_graph.manage" do
      write_requests.each do |label, req|
        it "is allowed (not forbidden) on WRITE action #{label}" do
          req.call(self, manage_headers)
          expect(response).not_to have_http_status(:forbidden)
        end
      end
    end
  end
end
