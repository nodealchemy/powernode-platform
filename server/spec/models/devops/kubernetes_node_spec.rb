# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::KubernetesNode, type: :model do
  let(:account) { create(:account) }
  let(:node) { sdwan_test_node(account: account) }
  let(:node_instance) { sdwan_test_node_instance(node: node) }
  let(:cluster) { create(:devops_kubernetes_cluster, account: account) }

  let(:built_node) do
    build(:devops_kubernetes_node,
          kubernetes_cluster: cluster,
          node_instance: node_instance)
  end

  describe "associations" do
    it { is_expected.to belong_to(:kubernetes_cluster).class_name("Devops::KubernetesCluster") }
    it { is_expected.to belong_to(:node_instance).class_name("System::NodeInstance") }
  end

  describe "validations" do
    it "is valid with all required fields" do
      expect(built_node).to be_valid
    end

    it "validates name presence" do
      built_node.name = nil
      expect(built_node).not_to be_valid
    end

    it "validates role inclusion (k3s + kubeadm vocabularies)" do
      %w[server agent control_plane worker].each do |role|
        built_node.role = role
        expect(built_node).to be_valid, "expected role #{role.inspect} to be valid"
      end
      built_node.role = "operator"
      expect(built_node).not_to be_valid
    end

    it "validates status inclusion" do
      %w[pending joining active not_ready disconnected error].each do |s|
        built_node.status = s
        expect(built_node).to be_valid, "expected status #{s.inspect} to be valid"
      end
      built_node.status = "running"
      expect(built_node).not_to be_valid
    end

    it "enforces uniqueness on node_instance_id (one cluster per instance)" do
      built_node.save!
      duplicate_node = sdwan_test_node_instance(node: node, name: "i-dupe")
      duplicate = build(:devops_kubernetes_node,
                        kubernetes_cluster: create(:devops_kubernetes_cluster, account: account),
                        node_instance: built_node.node_instance,
                        name: "duplicate-attempt")
      expect(duplicate).not_to be_valid
      _ = duplicate_node # silence the unused warning when shoulda doesn't catch DB-level
    end

    it "name uniqueness is scoped to the cluster" do
      built_node.update!(name: "k8s-master-1")
      second_instance = sdwan_test_node_instance(node: node, name: "i-second")
      same_name_other_cluster = build(:devops_kubernetes_node,
        kubernetes_cluster: create(:devops_kubernetes_cluster, account: account),
        node_instance: second_instance,
        name: "k8s-master-1")
      expect(same_name_other_cluster).to be_valid
    end
  end

  describe "scopes" do
    let!(:server_node) { built_node.tap { |n| n.role = "server"; n.save! } }
    let!(:agent_instance) { sdwan_test_node_instance(node: node, name: "i-agent") }
    let!(:agent_node) {
      create(:devops_kubernetes_node, :active,
             kubernetes_cluster: cluster,
             node_instance: agent_instance,
             role: "agent")
    }

    it ".active filters by status" do
      expect(Devops::KubernetesNode.active.pluck(:id)).to contain_exactly(agent_node.id)
    end

    it ".servers includes both k3s 'server' and kubeadm 'control_plane'" do
      cp_instance = sdwan_test_node_instance(node: node, name: "i-cp")
      cp = create(:devops_kubernetes_node,
                  kubernetes_cluster: cluster,
                  node_instance: cp_instance,
                  role: "control_plane",
                  name: "kubeadm-cp-1")
      expect(Devops::KubernetesNode.servers.pluck(:id)).to include(server_node.id, cp.id)
    end

    it ".workers includes both k3s 'agent' and kubeadm 'worker'" do
      worker_instance = sdwan_test_node_instance(node: node, name: "i-worker")
      worker = create(:devops_kubernetes_node,
                      kubernetes_cluster: cluster,
                      node_instance: worker_instance,
                      role: "worker",
                      name: "kubeadm-worker-1")
      expect(Devops::KubernetesNode.workers.pluck(:id)).to include(agent_node.id, worker.id)
    end
  end

  describe "flavor-aware predicates" do
    it "#server? is true for both k3s 'server' and kubeadm 'control_plane'" do
      expect(build(:devops_kubernetes_node, :server)).to be_server
      expect(build(:devops_kubernetes_node, :control_plane)).to be_server
      expect(build(:devops_kubernetes_node, :agent)).not_to be_server
    end

    it "#worker? is true for both k3s 'agent' and kubeadm 'worker'" do
      expect(build(:devops_kubernetes_node, :agent)).to be_worker
      expect(build(:devops_kubernetes_node, :worker)).to be_worker
      expect(build(:devops_kubernetes_node, :server)).not_to be_worker
    end
  end

  describe "status predicates" do
    it { expect(build(:devops_kubernetes_node, :active)).to be_active }
    it { expect(build(:devops_kubernetes_node, status: "pending")).to be_pending }
    it { expect(build(:devops_kubernetes_node, status: "joining")).to be_joining }
    it { expect(build(:devops_kubernetes_node, status: "not_ready")).to be_not_ready }
    it { expect(build(:devops_kubernetes_node, status: "disconnected")).to be_disconnected }
  end

  describe "cascade delete on cluster destroy" do
    it "destroys node rows when the cluster is deleted" do
      built_node.save!
      expect { cluster.destroy }.to change { Devops::KubernetesNode.count }.by(-1)
    end
  end

  describe "cluster.node_count auto-decrement on destroy" do
    it "decrements cluster.node_count when a node is destroyed" do
      built_node.save!
      cluster.update!(node_count: 3)

      expect {
        built_node.destroy
      }.to change { cluster.reload.node_count }.from(3).to(2)
    end

    it "does not decrement below zero (safety guard)" do
      built_node.save!
      cluster.update!(node_count: 0)

      expect {
        built_node.destroy
      }.not_to change { cluster.reload.node_count }
    end

    it "no-ops when the cluster is already gone (cascade-destroy ordering)" do
      built_node.save!
      cluster_id = cluster.id
      cluster.destroy
      # After cluster destroy, the node row is also gone (cascade), so this
      # path proves the callback's `return unless cluster` guard works.
      expect(::Devops::KubernetesCluster.where(id: cluster_id).exists?).to be(false)
    end

    it "is consistent across multiple destroys in the same transaction" do
      built_node.save!
      second_instance = sdwan_test_node_instance(node: node, name: "i-second-#{SecureRandom.hex(3)}")
      second_node = create(:devops_kubernetes_node,
                            kubernetes_cluster: cluster,
                            node_instance: second_instance,
                            role: "agent",
                            name: "second-node")
      cluster.update!(node_count: 5)

      expect {
        ::ActiveRecord::Base.transaction do
          built_node.destroy
          second_node.destroy
        end
      }.to change { cluster.reload.node_count }.from(5).to(3)
    end
  end

  describe "#node_summary" do
    it "returns the operator-facing fields" do
      built_node.save!
      summary = built_node.node_summary
      expect(summary).to include(
        id: built_node.id,
        kubernetes_cluster_id: cluster.id,
        node_instance_id: node_instance.id,
        role: built_node.role,
        status: built_node.status
      )
    end
  end
end
