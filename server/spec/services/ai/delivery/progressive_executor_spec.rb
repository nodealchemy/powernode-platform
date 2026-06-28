# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Delivery::ProgressiveExecutor, type: :service do
  let(:account) { create(:account) }
  subject(:executor) { described_class.new(account: account) }

  def planned(strategy: "canary", steps: [{ "weight" => 5 }, { "weight" => 100 }])
    account.ai_delivery_runs.create!(
      target_kind: "project", strategy: strategy, status: "planned", steps: steps, ref: "abc",
      metadata: { "config" => { "health_check_url" => "http://x/up" } }
    )
  end

  def stub_canary(**ret)
    allow_any_instance_of(Devops::DeploymentStrategies::CanaryStrategy).to receive(:execute).and_return(ret)
  end

  it "records succeeded when the strategy completes" do
    stub_canary(status: :completed, results: [{ step: 0 }])
    expect(executor.execute!(planned).status).to eq("succeeded")
  end

  it "records rolled_back when the strategy auto-rolls-back" do
    stub_canary(status: :rolled_back, results: [])
    run = executor.execute!(planned)
    expect(run.status).to eq("rolled_back")
    expect(run.error_message).to match(/rolled back/)
  end

  it "records failed when the strategy reports unhealthy" do
    stub_canary(status: :unhealthy, results: [])
    expect(executor.execute!(planned).status).to eq("failed")
  end

  it "records failed on a strategy exception" do
    allow_any_instance_of(Devops::DeploymentStrategies::CanaryStrategy).to receive(:execute).and_raise("boom")
    expect(executor.execute!(planned).status).to eq("failed")
  end

  it "passes the recorded canary steps + persisted config to the strategy" do
    expect_any_instance_of(Devops::DeploymentStrategies::CanaryStrategy).to receive(:execute)
      .with(config: hash_including("steps" => [{ "weight" => 10 }], "health_check_url" => "http://x/up"), context: anything)
      .and_return(status: :completed)
    executor.execute!(planned(steps: [{ "weight" => 10 }]))
  end

  it "is a no-op for direct deliveries" do
    direct = account.ai_delivery_runs.create!(target_kind: "project", strategy: "direct", status: "dry_run")
    expect(executor.execute!(direct).status).to eq("dry_run")
  end
end
