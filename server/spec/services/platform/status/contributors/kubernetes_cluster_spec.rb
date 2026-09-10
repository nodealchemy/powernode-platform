# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A3 — the `kubernetes_cluster` core
# contributor.
RSpec.describe Platform::Status::Contributors::KubernetesCluster do
  subject(:contributor) { described_class.new }

  let(:account) { create(:account) }
  let(:unknown_reason) { Platform::Status::Contributors::EnumConditions::UNKNOWN_REASON }

  def only_condition(cluster) = contributor.conditions_for(cluster).first

  def enumerate(for_account)
    [].tap { |acc| contributor.each_component(for_account) { |record| acc << record } }
  end

  describe "the contract" do
    it "answers the registry key and is account scoped" do
      expect(described_class::KIND).to eq("kubernetes_cluster")
      expect(contributor.kind).to eq("kubernetes_cluster")
      expect(contributor.account_scoped?).to be(true)
    end

    it "presents a string icon name, a label and a group order" do
      expect(contributor.presentation).to eq(
        "icon" => "Boxes", "label" => "Kubernetes Cluster", "group_order" => 31
      )
    end

    it "links to the cluster page and declares no A3 actions" do
      cluster = create(:devops_kubernetes_cluster, account: account)

      expect(contributor.links_for(cluster))
        .to eq([ { "label" => "Cluster", "path" => "/app/devops/kubernetes/#{cluster.id}" } ])
      expect(contributor.actions_for(cluster)).to eq([])
    end

    it "reports the kubernetes version as the observed generation" do
      cluster = build(:devops_kubernetes_cluster, k8s_version: "v1.30.4+k3s1")

      expect(contributor.observed_generation_for(cluster)).to eq("v1.30.4+k3s1")
    end
  end

  describe "status coverage" do
    it "maps every value of Devops::KubernetesCluster::STATUSES" do
      expect(contributor.mapped_values(described_class::STATUS_CONDITIONS))
        .to eq(::Devops::KubernetesCluster::STATUSES.sort)
    end

    it "gives every status a reason that is not UnknownStatus" do
      cluster = build(:devops_kubernetes_cluster, account: account)

      ::Devops::KubernetesCluster::STATUSES.each do |status|
        cluster.status = status
        condition = only_condition(cluster)

        expect(condition).not_to be_nil, "no condition for #{status}"
        expect(condition["reason"]).not_to eq(unknown_reason), "#{status} fell through to UnknownStatus"
      end
    end

    it "reports an out-of-band status as unknown/UnknownStatus, never ok" do
      cluster = build(:devops_kubernetes_cluster, account: account)
      cluster.status = "draining"

      condition = only_condition(cluster)

      expect(condition["type"]).to eq("Available")
      expect(condition["status"]).to eq(Platform::Status::Condition::UNKNOWN)
      expect(condition["reason"]).to eq(unknown_reason)
      expect(condition["evidence"]["unmapped_value"]).to eq("draining")
    end

    it "derives the ladder from the status column" do
      cluster = build(:devops_kubernetes_cluster, account: account)

      {
        "active" => Platform::ComponentStatus::OK,
        "pending" => Platform::ComponentStatus::PROGRESSING,
        "bootstrapping" => Platform::ComponentStatus::PROGRESSING,
        "degraded" => Platform::ComponentStatus::DEGRADED,
        "disconnected" => Platform::ComponentStatus::DEGRADED,
        "error" => Platform::ComponentStatus::DOWN
      }.each do |status, verdict|
        cluster.status = status

        expect(Platform::Status::Condition.verdict_for_set(contributor.conditions_for(cluster)))
          .to eq(verdict), "status=#{status}"
      end
    end

    it "carries the raw fields the reason came from as evidence" do
      cluster = build(:devops_kubernetes_cluster, account: account, status: "degraded",
                                                  consecutive_failures: 5, node_count: 3, pod_count: 17)

      expect(only_condition(cluster)["evidence"]).to include(
        "status" => "degraded",
        "consecutive_failures" => 5,
        "node_count" => 3,
        "pod_count" => 17,
        "flavor" => "k3s"
      )
    end
  end

  describe "#dependencies_for" do
    # Built in memory: a persisted membership row needs a System::NodeInstance,
    # which does not exist in core mode, and `dependencies_for` reads only the
    # FK column off the preloaded association.
    it "declares one edge per member node instance" do
      cluster = build(:devops_kubernetes_cluster, account: account)
      first = SecureRandom.uuid
      second = SecureRandom.uuid
      cluster.kubernetes_nodes.build(name: "n1", role: "server", node_instance_id: first)
      cluster.kubernetes_nodes.build(name: "n2", role: "agent", node_instance_id: second)

      expect(contributor.dependencies_for(cluster)).to eq([
        { "kind" => "node_instance", "ref" => first, "relation" => "hosts" },
        { "kind" => "node_instance", "ref" => second, "relation" => "hosts" }
      ])
    end

    it "declares nothing for a cluster with no members yet" do
      cluster = build(:devops_kubernetes_cluster, account: account)

      expect(contributor.dependencies_for(cluster)).to eq([])
    end
  end

  describe "#each_component" do
    it "yields only this account's clusters" do
      mine = create(:devops_kubernetes_cluster, account: account)
      theirs = create(:devops_kubernetes_cluster, account: create(:account))

      ids = enumerate(account).map(&:id)

      expect(ids).to eq([ mine.id ])
      expect(ids).not_to include(theirs.id)
    end

    it "yields nothing without an account" do
      create(:devops_kubernetes_cluster, account: account)

      expect(enumerate(nil)).to eq([])
    end
  end
end
