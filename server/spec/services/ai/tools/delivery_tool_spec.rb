# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Tools::DeliveryTool do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:tool) { described_class.new(account: account, user: user) }

  def exec(params)
    tool.execute(params: params.with_indifferent_access)
  end

  it "declares its actions + a deploy-management permission" do
    expect(described_class::REQUIRED_PERMISSION).to eq("git.pipelines.manage")
    expect(described_class.action_definitions.keys).to contain_exactly("deliver", "delivery_status", "delivery_list")
  end

  it "deliver with canary records a staged plan without deploying" do
    expect_any_instance_of(Ai::Deploy::Orchestrator).not_to receive(:deploy)
    res = exec(action: "deliver", target_kind: "project", strategy: "canary", ref: "abc", dry_run: true)
    expect(res[:success]).to be true
    expect(res[:data][:delivery][:strategy]).to eq("canary")
    expect(res[:data][:delivery][:steps]).to be_present
  end

  it "deliver direct delegates to Ai::Deploy and links the deploy run" do
    deploy = Ai::DeployRun.create!(account: account, target_kind: "project", method_key: "docker", status: "dry_run", dry_run: true)
    expect_any_instance_of(Ai::Deploy::Orchestrator).to receive(:deploy).and_return(deploy)
    res = exec(action: "deliver", target_kind: "project", strategy: "direct", ref: "abc")
    expect(res[:success]).to be true
    expect(res[:data][:delivery][:deploy_run_id]).to eq(deploy.id)
  end

  it "delivery_status + delivery_list return the account's runs" do
    run = account.ai_delivery_runs.create!(target_kind: "project", strategy: "canary", status: "planned")
    expect(exec(action: "delivery_status", delivery_id: run.id)[:data][:delivery][:id]).to eq(run.id)
    expect(exec(action: "delivery_list")[:data][:deliveries].map { |d| d[:id] }).to include(run.id)
  end

  it "errors on an unknown delivery + a foreign/missing repository" do
    expect(exec(action: "delivery_status", delivery_id: SecureRandom.uuid)[:success]).to be false
    expect(exec(action: "deliver", target_kind: "project", repository_id: SecureRandom.uuid, ref: "x")[:success]).to be false
  end

  it "is halted when the account AI is suspended (kill-switch)" do
    account.update!(ai_suspended: true)
    expect(exec(action: "deliver", strategy: "canary", ref: "x")[:data][:halted]).to be true
  end
end
