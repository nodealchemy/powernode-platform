# frozen_string_literal: true

require "rails_helper"

RSpec.describe Devops::KubernetesCluster, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:kubernetes_nodes).dependent(:destroy) }
    it { is_expected.to have_many(:node_instances).through(:kubernetes_nodes) }
  end

  describe "validations" do
    subject(:cluster) { build(:devops_kubernetes_cluster) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:api_endpoint) }
    it { is_expected.to validate_presence_of(:flavor) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:flavor).in_array(%w[k3s kubeadm]) }
    it {
      is_expected.to validate_inclusion_of(:status).in_array(
        %w[pending bootstrapping active degraded disconnected error]
      )
    }

    it "rejects api_endpoint without https://" do
      cluster.api_endpoint = "k8s.example.com:6443"
      expect(cluster).not_to be_valid
    end

    it "accepts http:// and https:// endpoints" do
      cluster.api_endpoint = "http://internal:6443"
      expect(cluster).to be_valid
      cluster.api_endpoint = "https://k8s.example.com:6443"
      expect(cluster).to be_valid
    end

    it "rejects sync_interval_seconds < 30 or > 3600" do
      cluster.sync_interval_seconds = 10
      expect(cluster).not_to be_valid
      cluster.sync_interval_seconds = 7200
      expect(cluster).not_to be_valid
    end

    context "name uniqueness scoped to account" do
      let(:account) { create(:account) }
      before { create(:devops_kubernetes_cluster, name: "prod", account: account) }

      it "rejects duplicate names within the same account" do
        duplicate = build(:devops_kubernetes_cluster, name: "prod", account: account)
        expect(duplicate).not_to be_valid
      end

      it "allows the same name in a different account" do
        other = create(:account)
        cluster = build(:devops_kubernetes_cluster, name: "prod", account: other)
        expect(cluster).to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:active) { create(:devops_kubernetes_cluster, :active) }
    let!(:pending) { create(:devops_kubernetes_cluster) } # default :pending
    let!(:k3s) { create(:devops_kubernetes_cluster) }
    let!(:kubeadm_cluster) { create(:devops_kubernetes_cluster, :kubeadm) }

    it ".active partitions by status" do
      expect(Devops::KubernetesCluster.active.pluck(:id)).to contain_exactly(active.id)
    end

    it ".k3s vs .kubeadm partitions by flavor" do
      expect(Devops::KubernetesCluster.k3s.pluck(:id)).to include(active.id, pending.id, k3s.id)
      expect(Devops::KubernetesCluster.kubeadm.pluck(:id)).to contain_exactly(kubeadm_cluster.id)
    end

    it ".auto_syncable returns active + auto_sync only" do
      manual = create(:devops_kubernetes_cluster, :active, auto_sync: false)
      expect(Devops::KubernetesCluster.auto_syncable.pluck(:id)).to include(active.id)
      expect(Devops::KubernetesCluster.auto_syncable.pluck(:id)).not_to include(manual.id, pending.id)
    end
  end

  describe "predicates" do
    it { expect(build(:devops_kubernetes_cluster, :active)).to be_active }
    it { expect(build(:devops_kubernetes_cluster, status: "pending")).to be_pending }
    it { expect(build(:devops_kubernetes_cluster, status: "bootstrapping")).to be_bootstrapping }
    it { expect(build(:devops_kubernetes_cluster, status: "degraded")).to be_degraded }
    it { expect(build(:devops_kubernetes_cluster, status: "disconnected")).to be_disconnected }
  end

  describe "callbacks" do
    it "auto-generates a slug from the name on create" do
      cluster = build(:devops_kubernetes_cluster, slug: nil, name: "Production Cluster")
      cluster.valid?
      expect(cluster.slug).to eq("production-cluster")
    end

    it "appends -N to disambiguate when the base slug is taken" do
      create(:devops_kubernetes_cluster, slug: "stage-cluster", name: "Stage Cluster")
      cluster = build(:devops_kubernetes_cluster,
                      slug: nil,
                      name: "Stage Cluster",
                      account: create(:account))
      cluster.valid?
      expect(cluster.slug).to eq("stage-cluster-1")
    end
  end

  describe "sync helpers" do
    let(:cluster) { create(:devops_kubernetes_cluster, :active, consecutive_failures: 3) }

    describe "#record_success!" do
      it "resets failures + stamps last_synced_at" do
        cluster.record_success!
        expect(cluster.reload.consecutive_failures).to eq(0)
        expect(cluster.last_synced_at).to be_within(2.seconds).of(Time.current)
        expect(cluster.status).to eq("active")
      end
    end

    describe "#record_failure!" do
      it "increments failures" do
        cluster.record_failure!
        expect(cluster.reload.consecutive_failures).to eq(4)
      end

      it "promotes status to 'degraded' at MAX_CONSECUTIVE_FAILURES" do
        cluster.update!(consecutive_failures: 4)
        cluster.record_failure!
        expect(cluster.reload.status).to eq("degraded")
      end
    end
  end

  describe "serialization" do
    let(:cluster) { create(:devops_kubernetes_cluster, :active, :with_kubeconfig) }

    it "#cluster_summary returns the operator-facing fields" do
      summary = cluster.cluster_summary
      expect(summary).to include(
        id: cluster.id,
        name: cluster.name,
        flavor: "k3s",
        status: "active",
        has_kubeconfig: true
      )
    end

    it "#cluster_details extends summary with internal fields" do
      details = cluster.cluster_details
      expect(details).to include(:description, :sync_interval_seconds, :metadata, :created_at)
    end
  end

  describe "VIP cleanup on destroy (slice 3)" do
    let(:account) { create(:account) }

    it "destroys the api VIP referenced in metadata.api_vip_id" do
      # We can't easily seed a real Sdwan::VirtualIp here without
      # the system extension factories; verify the callback is wired
      # by stubbing the lookup.
      cluster = create(:devops_kubernetes_cluster, account: account)
      cluster.update!(metadata: { "api_vip_id" => "fake-vip-id" })

      expect(::Sdwan::VirtualIp).to receive(:where).with(id: "fake-vip-id").and_return(
        double(destroy_all: true)
      )
      cluster.destroy!
    end

    it "is no-op when metadata.api_vip_id is absent" do
      cluster = create(:devops_kubernetes_cluster, account: account)
      expect(::Sdwan::VirtualIp).not_to receive(:where)
      expect { cluster.destroy! }.not_to raise_error
    end

    it "rescues VIP cleanup failures (cluster destroy still succeeds)" do
      cluster = create(:devops_kubernetes_cluster, account: account)
      cluster.update!(metadata: { "api_vip_id" => "any-id" })

      allow(::Sdwan::VirtualIp).to receive(:where).and_raise(StandardError, "vault unreachable")
      expect(Rails.logger).to receive(:warn).with(/VIP cleanup failed/)

      expect { cluster.destroy! }.not_to raise_error
      expect(Devops::KubernetesCluster.where(id: cluster.id)).to be_empty
    end
  end

  describe "DB-level constraints" do
    it "rejects an invalid flavor at the DB layer" do
      cluster = build(:devops_kubernetes_cluster)
      cluster.save!(validate: false)
      expect {
        cluster.update_column(:flavor, "openshift")
      }.to raise_error(ActiveRecord::StatementInvalid, /chk_kubernetes_clusters_flavor/)
    end
  end
end
