# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::KubernetesProvisioningTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, agent: nil, user: user) }

  describe ".action_definitions" do
    it "exposes 2 manage-level actions" do
      actions = described_class.action_definitions.keys
      expect(actions).to contain_exactly(
        "kubernetes_decommission_cluster",
        "kubernetes_get_kubeconfig"
      )
    end

    # IMP-48abfa2f9e74: retargeted off "kubernetes.clusters.manage" (absent from
    # the permissions catalog) onto devops.kubernetes.manage — the same permission
    # Api::V1::Devops::Kubernetes::ClustersController requires for destroy and
    # kubeconfig, the REST twins of these two actions.
    it "scopes to manage-level permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("devops.kubernetes.manage")
      expect(Permissions.permission_exists?(described_class::REQUIRED_PERMISSION)).to be(true)
    end
  end

  describe "kubernetes_decommission_cluster" do
    let(:node) { sdwan_test_node(account: account) }
    let(:instance) { sdwan_test_node_instance(node: node) }
    let!(:cluster) { create(:devops_kubernetes_cluster, account: account) }
    let!(:k8s_node) {
      create(:devops_kubernetes_node,
             kubernetes_cluster: cluster,
             node_instance: instance,
             name: "k8s-bootstrap")
    }

    it "destroys the cluster + cascade-deletes member nodes" do
      result = tool.send(:call, action: "kubernetes_decommission_cluster", cluster_id: cluster.id)
      expect(result[:success]).to be true
      expect(result[:freed_node_count]).to eq(1)
      expect(Devops::KubernetesCluster.where(id: cluster.id)).to be_empty
      expect(Devops::KubernetesNode.where(id: k8s_node.id)).to be_empty
    end

    it "returns error for unknown cluster" do
      result = tool.send(:call, action: "kubernetes_decommission_cluster", cluster_id: "missing")
      expect(result[:success]).to be false
      expect(result[:error]).to include("not found")
    end

    it "scopes to account (cannot decommission a foreign cluster)" do
      foreign_cluster = create(:devops_kubernetes_cluster, account: create(:account))
      result = tool.send(:call, action: "kubernetes_decommission_cluster", cluster_id: foreign_cluster.id)
      expect(result[:success]).to be false
      # Foreign cluster still exists
      expect(Devops::KubernetesCluster.where(id: foreign_cluster.id)).to exist
    end
  end

  describe "kubernetes_get_kubeconfig" do
    it "returns the kubeconfig for an active cluster" do
      cluster = create(:devops_kubernetes_cluster, :active,
                       account: account,
                       encrypted_kubeconfig: "apiVersion: v1\nkind: Config\nclusters:\n- cluster:\n    server: https://[fd00::1]:6443")
      result = tool.send(:call, action: "kubernetes_get_kubeconfig", cluster_id: cluster.id)

      expect(result[:success]).to be true
      expect(result[:kubeconfig]).to include("apiVersion: v1")
      expect(result[:api_endpoint]).to eq(cluster.api_endpoint)
      expect(result[:cluster_id]).to eq(cluster.id)
    end

    it "returns 'still bootstrapping' error when kubeconfig is empty" do
      cluster = create(:devops_kubernetes_cluster, account: account, status: "bootstrapping")
      result = tool.send(:call, action: "kubernetes_get_kubeconfig", cluster_id: cluster.id)

      expect(result[:success]).to be false
      expect(result[:error]).to include("not yet available")
      expect(result[:error]).to include("bootstrapping")
    end

    it "returns error for unknown cluster" do
      result = tool.send(:call, action: "kubernetes_get_kubeconfig", cluster_id: "missing")
      expect(result[:success]).to be false
    end
  end

  describe "unknown action" do
    it "returns a structured error" do
      result = tool.send(:call, action: "kubernetes_unknown")
      expect(result[:success]).to be false
      expect(result[:error]).to include("Unknown action")
    end
  end
end
