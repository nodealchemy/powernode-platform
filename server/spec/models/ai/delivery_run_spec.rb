# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::DeliveryRun, type: :model do
  let(:account) { create(:account) }
  let(:run) { account.ai_delivery_runs.create!(target_kind: "project", strategy: "direct", status: "pending") }

  def deploy_run(status:)
    Ai::DeployRun.create!(account: account, target_kind: "project", method_key: "docker", status: status, detail: "d")
  end

  it "validates strategy + status inclusion" do
    expect(account.ai_delivery_runs.build(target_kind: "project", strategy: "bogus", status: "pending")).not_to be_valid
    expect(account.ai_delivery_runs.build(target_kind: "project", strategy: "direct", status: "nope")).not_to be_valid
  end

  it "start! moves to running" do
    run.start!
    expect(run.status).to eq("running")
    expect(run.started_at).to be_present
  end

  it "attach_deploy_run! links the deploy run and mirrors its status" do
    deploy = deploy_run(status: "succeeded")
    run.attach_deploy_run!(deploy)
    expect(run.deploy_run).to eq(deploy)
    expect(run.status).to eq("succeeded")
    expect(run.metadata["method_key"]).to eq("docker")
    expect(run.completed_at).to be_present
  end

  it "maps a blocked/skipped deploy onto delivery failed" do
    run.attach_deploy_run!(deploy_run(status: "blocked"))
    expect(run.status).to eq("failed")
  end

  it "plan! records the rollout steps (planned for real, dry_run for dry)" do
    run.update!(strategy: "canary")
    run.plan!([{ "weight" => 5 }, { "weight" => 100 }], dry: false)
    expect(run.status).to eq("planned")
    expect(run.steps.size).to eq(2)

    run.plan!([{ "weight" => 5 }], dry: true)
    expect(run.status).to eq("dry_run")
  end
end
