# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Devops::Kubernetes::Nodes", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(user) }

  let(:node) { sdwan_test_node(account: account) }
  let(:cluster) { create(:devops_kubernetes_cluster, account: account) }
  let(:server_inst) { sdwan_test_node_instance(node: node, name: "i-server") }
  let(:agent_inst) { sdwan_test_node_instance(node: node, name: "i-agent") }
  let!(:server_node) {
    create(:devops_kubernetes_node, :server, :active,
           kubernetes_cluster: cluster, node_instance: server_inst, name: "k8s-server-1")
  }
  let!(:agent_node) {
    create(:devops_kubernetes_node, :agent,
           kubernetes_cluster: cluster, node_instance: agent_inst, name: "k8s-agent-1")
  }

  describe "GET /api/v1/devops/kubernetes/clusters/:cluster_id/nodes" do
    it "lists all nodes in a cluster" do
      get "/api/v1/devops/kubernetes/clusters/#{cluster.id}/nodes",
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body).dig("data")
      expect(data["cluster_id"]).to eq(cluster.id)
      expect(data["items"].size).to eq(2)
      names = data["items"].map { |n| n["name"] }
      expect(names).to contain_exactly("k8s-server-1", "k8s-agent-1")
    end

    it "filters by role" do
      get "/api/v1/devops/kubernetes/clusters/#{cluster.id}/nodes?role=server",
          headers: headers, as: :json
      items = JSON.parse(response.body).dig("data", "items")
      expect(items.map { |n| n["name"] }).to contain_exactly("k8s-server-1")
    end

    it "filters by status" do
      get "/api/v1/devops/kubernetes/clusters/#{cluster.id}/nodes?status=active",
          headers: headers, as: :json
      items = JSON.parse(response.body).dig("data", "items")
      expect(items.map { |n| n["name"] }).to contain_exactly("k8s-server-1")
    end

    it "returns 404 for foreign cluster" do
      foreign = create(:devops_kubernetes_cluster, account: create(:account))
      get "/api/v1/devops/kubernetes/clusters/#{foreign.id}/nodes",
          headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/devops/kubernetes/clusters/:cluster_id/nodes/:id" do
    it "returns the node summary" do
      get "/api/v1/devops/kubernetes/clusters/#{cluster.id}/nodes/#{server_node.id}",
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body).dig("data", "node")
      expect(body["id"]).to eq(server_node.id)
      expect(body["role"]).to eq("server")
    end

    it "returns 404 when the node belongs to a different cluster" do
      other_cluster = create(:devops_kubernetes_cluster, account: account, name: "other")
      get "/api/v1/devops/kubernetes/clusters/#{other_cluster.id}/nodes/#{server_node.id}",
          headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
