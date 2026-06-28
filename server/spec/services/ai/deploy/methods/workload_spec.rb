# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Deploy::Methods::Workload do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:method) { described_class.new(account: account, user: user) }
  let(:repository) { instance_double(Devops::GitRepository, full_name: "acme/widgets", id: "repo-1") }
  let(:target) do
    Ai::Deploy::Target.new(kind: :project, repository: repository, environment: "production", config: {})
  end
  let(:pipeline) { instance_double(Devops::Pipeline, name: "deploy-prod", id: "pl-1") }

  it "is available + supports projects only" do
    expect(described_class.available?).to be true
    expect(described_class.key).to eq(:workload)
    expect(described_class.supports?(target)).to be true
    expect(described_class.supports?(Ai::Deploy::Target.new(kind: :platform_self))).to be false
  end

  describe "#deploy!" do
    before { allow(method).to receive(:resolve_deploy_pipeline).and_return(pipeline) }

    it "dry-runs: describes triggering the deploy pipeline, triggers nothing" do
      expect(pipeline).not_to receive(:trigger_run!)
      result = method.deploy!(target: target, ref: "abc123", dry_run: true)
      expect(result).to be_dry_run
      expect(result.commands.first).to include("deploy-prod")
    end

    it "real run triggers the deploy pipeline and records the run" do
      run = instance_double(Devops::PipelineRun, id: "run-1", run_number: 7)
      expect(pipeline).to receive(:trigger_run!).with(
        trigger_type: "deploy",
        trigger_context: hash_including("ref" => "abc123", "environment" => "production"),
        triggered_by: user
      ).and_return(run)
      result = method.deploy!(target: target, ref: "abc123", dry_run: false)
      expect(result).to be_succeeded
      expect(result.metadata[:pipeline_run_id]).to eq("run-1")
    end

    it "fails when no deploy pipeline is configured" do
      allow(method).to receive(:resolve_deploy_pipeline).and_return(nil)
      expect(method.deploy!(target: target, ref: "x", dry_run: false)).to be_failed
    end
  end

  describe "#verify_health (guardian-driven)" do
    let(:deploy_run) { instance_double(Ai::DeployRun, metadata: { "pipeline_run_id" => "run-1" }) }
    let(:run) { instance_double(Devops::PipelineRun) }
    before { allow(Devops::PipelineRun).to receive(:find_by).with(id: "run-1").and_return(run) }

    it "is unhealthy when the guardian recommends rollback" do
      guardian = instance_double(Ai::DevopsBridge::DeploymentGuardian,
                                 recommend_action: { recommendation: "rollback", reason: "error rate 12%", confidence: 0.9 })
      allow(Ai::DevopsBridge::DeploymentGuardian).to receive(:new).with(account: account).and_return(guardian)
      expect(method.verify_health(target: target, deploy_run: deploy_run)).to be_failed
    end

    it "is healthy when the guardian recommends promote/hold" do
      guardian = instance_double(Ai::DevopsBridge::DeploymentGuardian,
                                 recommend_action: { recommendation: "promote", confidence: 0.8 })
      allow(Ai::DevopsBridge::DeploymentGuardian).to receive(:new).and_return(guardian)
      expect(method.verify_health(target: target, deploy_run: deploy_run)).to be_succeeded
    end
  end
end
