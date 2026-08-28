# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::KubernetesClusterTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, agent: nil, user: user) }

  describe ".action_definitions" do
    it "exposes 3 read-only actions" do
      actions = described_class.action_definitions.keys
      expect(actions).to contain_exactly(
        "kubernetes_list_clusters",
        "kubernetes_get_cluster",
        "kubernetes_list_nodes"
      )
    end

    # IMP-48abfa2f9e74: retargeted off "kubernetes.clusters.read", which was
    # never in the permissions catalog (so it matched no role_permissions row and
    # silently degraded the whole class to super-admin-only), onto the declared
    # devops.kubernetes.* family the REST twin already uses.
    it "scopes to read-level permission" do
      expect(described_class::REQUIRED_PERMISSION).to eq("devops.kubernetes.read")
      expect(Permissions.permission_exists?(described_class::REQUIRED_PERMISSION)).to be(true)
    end
  end

  describe "kubernetes_list_clusters" do
    it "returns an empty list with count 0 when no clusters exist" do
      result = tool.send(:call, action: "kubernetes_list_clusters")
      expect(result[:success]).to be true
      expect(result[:clusters]).to eq([])
      expect(result[:count]).to eq(0)
    end

    it "returns active + pending clusters in alphabetical order" do
      create(:devops_kubernetes_cluster, account: account, name: "zeta")
      create(:devops_kubernetes_cluster, account: account, name: "alpha")

      result = tool.send(:call, action: "kubernetes_list_clusters")
      expect(result[:clusters].map { |c| c[:name] }).to eq(%w[alpha zeta])
    end

    it "scopes to the calling account only" do
      other_account = create(:account)
      create(:devops_kubernetes_cluster, account: other_account, name: "foreign")
      create(:devops_kubernetes_cluster, account: account, name: "mine")

      result = tool.send(:call, action: "kubernetes_list_clusters")
      expect(result[:clusters].map { |c| c[:name] }).to eq(%w[mine])
    end
  end

  describe "kubernetes_get_cluster" do
    let(:cluster) { create(:devops_kubernetes_cluster, :active, :with_kubeconfig, account: account) }

    it "returns full details by id" do
      result = tool.send(:call, action: "kubernetes_get_cluster", cluster_id: cluster.id)
      expect(result[:success]).to be true
      expect(result[:cluster]).to include(:id, :name, :flavor, :status, :metadata, :sync_interval_seconds)
    end

    it "returns full details by slug" do
      result = tool.send(:call, action: "kubernetes_get_cluster", cluster_id: cluster.slug)
      expect(result[:success]).to be true
      expect(result[:cluster][:id]).to eq(cluster.id)
    end

    it "returns full details by name" do
      result = tool.send(:call, action: "kubernetes_get_cluster", cluster_id: cluster.name)
      expect(result[:success]).to be true
      expect(result[:cluster][:id]).to eq(cluster.id)
    end

    it "returns error for unknown identifier" do
      result = tool.send(:call, action: "kubernetes_get_cluster", cluster_id: "no-such-cluster")
      expect(result[:success]).to be false
      expect(result[:error]).to include("not found")
    end

    it "scopes to account (foreign cluster invisible)" do
      foreign = create(:devops_kubernetes_cluster, account: create(:account))
      result = tool.send(:call, action: "kubernetes_get_cluster", cluster_id: foreign.id)
      expect(result[:success]).to be false
    end
  end

  describe "kubernetes_list_nodes" do
    let(:node) { sdwan_test_node(account: account) }
    let(:cluster) { create(:devops_kubernetes_cluster, account: account) }
    let(:server_inst) { sdwan_test_node_instance(node: node, name: "i-server") }
    let(:agent_inst) { sdwan_test_node_instance(node: node, name: "i-agent") }
    let!(:server_node) {
      create(:devops_kubernetes_node, :server, :active,
             kubernetes_cluster: cluster,
             node_instance: server_inst,
             name: "k8s-server-1")
    }
    let!(:agent_node) {
      create(:devops_kubernetes_node, :agent,
             kubernetes_cluster: cluster,
             node_instance: agent_inst,
             name: "k8s-agent-1")
    }

    it "lists all member nodes ordered by role + name" do
      result = tool.send(:call, action: "kubernetes_list_nodes", cluster_id: cluster.id)
      expect(result[:success]).to be true
      expect(result[:count]).to eq(2)
      expect(result[:nodes].map { |n| n[:name] }).to contain_exactly("k8s-server-1", "k8s-agent-1")
    end

    it "returns error for unknown cluster" do
      result = tool.send(:call, action: "kubernetes_list_nodes", cluster_id: "missing")
      expect(result[:success]).to be false
    end
  end

  describe "unknown action" do
    it "returns a structured error" do
      result = tool.send(:call, action: "kubernetes_drop_database")
      expect(result[:success]).to be false
      expect(result[:error]).to include("Unknown action")
    end
  end
end
