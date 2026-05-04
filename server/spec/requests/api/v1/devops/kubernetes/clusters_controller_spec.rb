# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Devops::Kubernetes::Clusters", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/devops/kubernetes/clusters" do
    let!(:active_cluster) { create(:devops_kubernetes_cluster, :active, account: account, name: "prod") }
    let!(:pending_cluster) { create(:devops_kubernetes_cluster, account: account, name: "stage") }
    let!(:foreign_cluster) { create(:devops_kubernetes_cluster, account: create(:account), name: "alien") }

    it "lists clusters in the calling account" do
      get "/api/v1/devops/kubernetes/clusters", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body).dig("data")
      expect(data["items"].size).to eq(2)
      names = data["items"].map { |c| c["name"] }
      expect(names).to contain_exactly("prod", "stage")
      expect(names).not_to include("alien")
    end

    it "filters by status" do
      get "/api/v1/devops/kubernetes/clusters?status=active", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      items = JSON.parse(response.body).dig("data", "items")
      expect(items.map { |c| c["name"] }).to contain_exactly("prod")
    end

    it "filters by flavor" do
      create(:devops_kubernetes_cluster, :kubeadm, account: account, name: "kubeadm-cluster")
      get "/api/v1/devops/kubernetes/clusters?flavor=kubeadm", headers: headers, as: :json
      items = JSON.parse(response.body).dig("data", "items")
      expect(items.map { |c| c["name"] }).to contain_exactly("kubeadm-cluster")
    end

    it "rejects unauthenticated requests" do
      get "/api/v1/devops/kubernetes/clusters", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/devops/kubernetes/clusters/:id" do
    let!(:cluster) { create(:devops_kubernetes_cluster, :active, account: account) }

    it "returns full cluster details by id" do
      get "/api/v1/devops/kubernetes/clusters/#{cluster.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body).dig("data", "cluster")
      expect(body).to include("id" => cluster.id, "flavor" => "k3s", "status" => "active")
      expect(body).to include("description", "sync_interval_seconds", "metadata", "created_at")
    end

    it "resolves by slug" do
      get "/api/v1/devops/kubernetes/clusters/#{cluster.slug}", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "cluster", "id")).to eq(cluster.id)
    end

    it "returns 404 for unknown id" do
      get "/api/v1/devops/kubernetes/clusters/no-such-cluster", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for foreign account cluster (account-scoped)" do
      foreign = create(:devops_kubernetes_cluster, account: create(:account))
      get "/api/v1/devops/kubernetes/clusters/#{foreign.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/devops/kubernetes/clusters/:id" do
    let!(:cluster) { create(:devops_kubernetes_cluster, account: account) }
    let(:node) { sdwan_test_node(account: account) }
    let(:instance) { sdwan_test_node_instance(node: node) }
    let!(:k8s_node) {
      create(:devops_kubernetes_node, kubernetes_cluster: cluster, node_instance: instance,
             name: "k8s-bootstrap")
    }

    it "destroys the cluster + cascades to member nodes" do
      delete "/api/v1/devops/kubernetes/clusters/#{cluster.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body).dig("data")
      expect(body["freed_node_count"]).to eq(1)
      expect(Devops::KubernetesCluster.where(id: cluster.id)).to be_empty
      expect(Devops::KubernetesNode.where(id: k8s_node.id)).to be_empty
    end

    it "returns 404 when destroying a foreign cluster" do
      foreign = create(:devops_kubernetes_cluster, account: create(:account))
      delete "/api/v1/devops/kubernetes/clusters/#{foreign.id}", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      # Foreign cluster preserved
      expect(Devops::KubernetesCluster.where(id: foreign.id)).to exist
    end
  end

  describe "GET /api/v1/devops/kubernetes/clusters/:id/kubeconfig" do
    it "returns kubeconfig YAML for an active cluster" do
      # Don't use the :with_kubeconfig trait — its randomized hex would
      # apply AFTER our explicit kwarg in some FactoryBot versions,
      # leaving us with random bytes instead of actual YAML.
      cluster = create(:devops_kubernetes_cluster, :active,
                       account: account,
                       encrypted_kubeconfig: "apiVersion: v1\nkind: Config")

      get "/api/v1/devops/kubernetes/clusters/#{cluster.id}/kubeconfig",
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body).dig("data")
      expect(data["kubeconfig"]).to include("apiVersion: v1")
      expect(data["api_endpoint"]).to eq(cluster.api_endpoint)
    end

    it "returns 422 when cluster is still bootstrapping (no kubeconfig yet)" do
      cluster = create(:devops_kubernetes_cluster, account: account, status: "bootstrapping")
      get "/api/v1/devops/kubernetes/clusters/#{cluster.id}/kubeconfig",
          headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to include("not yet available")
    end
  end
end
