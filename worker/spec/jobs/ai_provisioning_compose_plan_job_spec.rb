# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiProvisioningComposePlanJob, type: :job do
  subject { described_class }

  let(:job_args) { { "mission_id" => "mission-uuid-1", "account_id" => "acc-uuid-1" } }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"

  let(:job_instance)     { described_class.new }
  let(:api_client_double) { double("BackendApiClient") }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    # Kill-switch suspension check runs first in #execute (AiSuspensionCheckConcern):
    # stub it to report "not suspended" so the job proceeds.
    allow(api_client_double).to receive(:get).with(
      "/api/v1/internal/ai/kill_switch/check",
      { account_id: "acc-uuid-1" }
    ).and_return("data" => { "suspended" => false })
  end

  after { Sidekiq::Worker.clear_all }

  describe "job configuration" do
    it "uses the ai_execution queue" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("ai_execution")
    end
  end

  describe "#execute" do
    context "with valid params" do
      before do
        allow(api_client_double).to receive(:post).and_return(
          "success" => true,
          "data" => { "plan_id" => "plan-1", "mission_id" => "mission-uuid-1" }
        )
      end

      it "POSTs to the internal compose_plan endpoint" do
        job_instance.execute(job_args)

        expect(api_client_double).to have_received(:post).with(
          "/api/v1/internal/ai/provisioning/missions/mission-uuid-1/compose_plan",
          {}
        )
      end

      it "returns the API response" do
        result = job_instance.execute(job_args)
        expect(result.dig("data", "plan_id")).to eq("plan-1")
      end
    end

    context "when required params are missing" do
      it "raises ArgumentError" do
        expect { job_instance.execute({}) }.to raise_error(ArgumentError, /Missing required parameters/)
      end
    end

    context "when the API returns success: false" do
      before do
        allow(api_client_double).to receive(:post).and_return("success" => false, "error" => "no brief")
        allow(api_client_double).to receive(:patch).and_return("success" => true)
      end

      it "reports mission failure" do
        job_instance.execute(job_args)
        expect(api_client_double).to have_received(:patch).with(
          "/api/v1/ai/missions/mission-uuid-1",
          hash_including(mission: hash_including(status: "failed"))
        )
      end
    end

    context "when the API raises" do
      before do
        allow(api_client_double).to receive(:post).and_raise(StandardError.new("boom"))
        allow(api_client_double).to receive(:patch).and_return("success" => true)
      end

      it "reports failure and re-raises" do
        expect { job_instance.execute(job_args) }.to raise_error(StandardError, /boom/)
        expect(api_client_double).to have_received(:patch)
      end
    end
  end
end
