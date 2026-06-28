# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Deploy::Methods::Docker do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:method) { described_class.new(account: account, user: user) }

  let(:cluster) { instance_double(Devops::SwarmCluster, name: "swarm-1") }
  let(:service) do
    instance_double(Devops::SwarmService, service_name: "powernode-backend", image: "registry/pn:old", cluster: cluster)
  end
  let(:target) do
    Ai::Deploy::Target.new(kind: :project, config: { "swarm_service_id" => "svc-1", "image" => "registry/pn:new" })
  end

  before { allow(method).to receive(:resolve_service).and_return(service) }

  it "is available (core Devops swarm infra present)" do
    expect(described_class.available?).to be true
    expect(described_class.key).to eq(:docker)
  end

  describe "#deploy! dry-run" do
    it "describes the image rollout and enqueues nothing" do
      expect(WorkerJobService).not_to receive(:enqueue_job)
      result = method.deploy!(target: target, ref: "abc123", dry_run: true)
      expect(result).to be_dry_run
      expect(result.commands).to eq(["docker service update --image registry/pn:new powernode-backend"])
    end

    it "fails when no swarm service resolves" do
      allow(method).to receive(:resolve_service).and_return(nil)
      expect(method.deploy!(target: target, ref: "x", dry_run: true)).to be_failed
    end
  end

  describe "#deploy! real run" do
    it "creates a SwarmDeployment(update) and enqueues Swarm::ServiceUpdateJob" do
      deployment = instance_double(Devops::SwarmDeployment, id: "dep-1")
      deployments = double("swarm_deployments")
      allow(cluster).to receive(:swarm_deployments).and_return(deployments)
      expect(deployments).to receive(:create!).with(
        hash_including(service: service, deployment_type: "update", status: "pending",
                       desired_state: { "image" => "registry/pn:new" }, git_sha: "abc123")
      ).and_return(deployment)
      expect(WorkerJobService).to receive(:enqueue_job).with(
        "Swarm::ServiceUpdateJob", hash_including(args: ["dep-1"], queue: "devops_high")
      )

      result = method.deploy!(target: target, ref: "abc123", dry_run: false)
      expect(result).to be_succeeded
      expect(result.metadata[:swarm_deployment_id]).to eq("dep-1")
      expect(result.metadata[:async]).to be true
    end
  end

  describe "#verify_health (lenient for async)" do
    def run_with(meta) = instance_double(Ai::DeployRun, metadata: meta)

    it "is healthy while the swarm deployment is still converging" do
      dep = instance_double(Devops::SwarmDeployment, status: "running")
      allow(dep).to receive(:reload).and_return(dep)
      allow(Devops::SwarmDeployment).to receive(:find_by).with(id: "dep-1").and_return(dep)
      expect(method.verify_health(target: target, deploy_run: run_with("swarm_deployment_id" => "dep-1"))).to be_succeeded
    end

    it "is unhealthy only on a confirmed failed deployment" do
      dep = instance_double(Devops::SwarmDeployment, status: "failed")
      allow(dep).to receive(:reload).and_return(dep)
      allow(Devops::SwarmDeployment).to receive(:find_by).with(id: "dep-1").and_return(dep)
      expect(method.verify_health(target: target, deploy_run: run_with("swarm_deployment_id" => "dep-1"))).to be_failed
    end
  end

  describe "#rollback!" do
    it "reuses ServiceManager#rollback_service (Docker PreviousSpec)" do
      mgr = instance_double(Devops::Docker::ServiceManager, rollback_service: { success: true })
      expect(Devops::Docker::ServiceManager).to receive(:new).with(cluster: cluster, user: user).and_return(mgr)
      result = method.rollback!(target: target, deploy_run: instance_double(Ai::DeployRun))
      expect(result).to be_rolled_back
    end
  end
end
