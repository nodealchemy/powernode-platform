# frozen_string_literal: true

require "rails_helper"

# AI/MCP workload substrate L3 — the fleet phase jobs must honor the kill
# switch (AiSuspensionCheckConcern) like every other AI execution job:
# emergency_halt has to stop fleet provisioning mid-chain.
RSpec.describe "AiAgentFleet phase jobs" do
  let(:job_args) { { "mission_id" => "mission-uuid-1", "account_id" => "acc-uuid-1" } }
  let(:api_client_double) { double("BackendApiClient") }

  before do
    mock_powernode_worker_config
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  [
    AiAgentFleetPlanJob,
    AiAgentFleetProvisionJob,
    AiAgentFleetDelegateJob,
    AiAgentFleetAggregateJob,
    AiAgentFleetReapJob
  ].each do |job_class|
    describe job_class do
      it "includes AiSuspensionCheckConcern" do
        expect(job_class.include?(AiSuspensionCheckConcern)).to be true
      end

      it "bails before POSTing its phase when AI is suspended for the account" do
        job = job_class.new
        allow(job).to receive(:api_client).and_return(api_client_double)
        allow(job).to receive(:ai_suspended?).with("acc-uuid-1").and_return(true)
        expect(api_client_double).not_to receive(:post)

        job.execute(job_args)
      end
    end
  end
end
