# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Delivery::Orchestrator, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  subject(:orchestrator) { described_class.new(account: account, user: user) }

  def target(strategy: nil, config: {})
    cfg = strategy ? config.merge("strategy" => strategy) : config
    Ai::Deploy::Target.new(kind: :project, environment: "production", config: cfg)
  end

  def deploy_run(status: "dry_run")
    Ai::DeployRun.create!(account: account, target_kind: "project", method_key: "docker", status: status, dry_run: true)
  end

  it "direct strategy delegates to Ai::Deploy and links + mirrors the deploy run" do
    deploy = deploy_run(status: "dry_run")
    expect_any_instance_of(Ai::Deploy::Orchestrator).to receive(:deploy).and_return(deploy)

    run = orchestrator.deliver(target: target, ref: "abc", dry_run: true)

    expect(run.strategy).to eq("direct")
    expect(run.deploy_run_id).to eq(deploy.id)
    expect(run.status).to eq("dry_run")
  end

  it "canary strategy records a staged rollout plan WITHOUT deploying" do
    expect_any_instance_of(Ai::Deploy::Orchestrator).not_to receive(:deploy)

    run = orchestrator.deliver(target: target(strategy: "canary"), ref: "abc", dry_run: true)

    expect(run.strategy).to eq("canary")
    expect(run.steps).to be_present
    expect(run.steps.first["phase"]).to eq("canary")
    expect(run.status).to eq("dry_run")
  end

  it "blue_green strategy records a swap plan" do
    run = orchestrator.deliver(target: target(strategy: "blue_green"), ref: "abc", dry_run: false)
    expect(run.steps.map { |s| s["phase"] }).to include("swap_traffic", "verify_active")
    expect(run.status).to eq("planned")
  end

  it "defaults to direct for an unknown strategy" do
    expect_any_instance_of(Ai::Deploy::Orchestrator).to receive(:deploy).and_return(deploy_run)
    run = orchestrator.deliver(target: target(strategy: "telepathy"), ref: "abc")
    expect(run.strategy).to eq("direct")
  end

  it "records a failed delivery (no raise) when the underlying deploy errors" do
    allow_any_instance_of(Ai::Deploy::Orchestrator).to receive(:deploy).and_raise("deploy exploded")
    run = nil
    expect { run = orchestrator.deliver(target: target, ref: "abc") }.not_to raise_error
    expect(run.status).to eq("failed")
    expect(run.error_message).to match(/deploy exploded/)
  end
end
