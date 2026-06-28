# frozen_string_literal: true

require "rails_helper"

# Idempotency regression: the deploy command ran at the irreversible boundary, then
# post-deployment validation / the final status PATCH could raise → the whole job retried
# (retry: 1) and RE-RAN the deploy command. Post-command steps are now non-raising, and a
# terminal-status precondition skips an already-completed deployment.
RSpec.describe Devops::DeploymentJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:deployment_id) { "dep-1" }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(api_client).to receive(:patch).and_return({})
    allow(job).to receive(:run_pre_deployment_review).and_return({ approved: true })
  end

  def stub_fetch(status)
    allow(job).to receive(:fetch_deployment).and_return(
      { "status" => status, "environment" => "staging", "deploy_command" => "echo deploy" }
    )
  end

  context "when post-deployment finalize fails after the command ran" do
    before do
      stub_fetch("pending")
      allow(job).to receive(:execute_deployment) # spy; do not run a real command
      allow(job).to receive(:run_post_deployment_validation).and_raise(StandardError, "validation crashed")
    end

    it "does not raise (so Sidekiq does not retry and re-run the deploy command)" do
      expect { job.execute(deployment_id) }.not_to raise_error
    end

    it "runs the deploy command exactly once" do
      job.execute(deployment_id)
      expect(job).to have_received(:execute_deployment).once
    end
  end

  context "when the deployment is already in a terminal state (a retry)" do
    before do
      stub_fetch("success")
      allow(job).to receive(:execute_deployment)
    end

    it "skips the deploy command entirely" do
      job.execute(deployment_id)
      expect(job).not_to have_received(:execute_deployment)
    end
  end

  context "when the deploy command itself fails (pre-effect)" do
    before do
      stub_fetch("pending")
      allow(job).to receive(:execute_deployment).and_raise(StandardError, "command failed")
    end

    it "re-raises so the failed command can be retried" do
      expect { job.execute(deployment_id) }.to raise_error(StandardError, /command failed/)
    end
  end
end
