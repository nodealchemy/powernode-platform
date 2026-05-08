# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiProvisioningStepJob, type: :job do
  subject { described_class }

  let(:job_args) do
    {
      "mission_id" => "mission-uuid-1",
      "step_id"    => "step-uuid-1",
      "account_id" => "acc-uuid-1",
      "runner_id"  => "run-uuid-1"
    }
  end

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"

  let(:job_instance)      { described_class.new }
  let(:api_client_double) { double("BackendApiClient") }

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
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
          "data" => { "status" => "completed", "outputs" => { "ok" => true } }
        )
      end

      it "POSTs to the internal step-execute endpoint" do
        job_instance.execute(job_args)

        expect(api_client_double).to have_received(:post).with(
          "/api/v1/internal/ai/provisioning/missions/mission-uuid-1/steps/step-uuid-1/execute",
          { runner_id: "run-uuid-1" }
        )
      end

      it "passes runner_id through when provided" do
        job_instance.execute(job_args)

        expect(api_client_double).to have_received(:post) do |_path, body|
          expect(body[:runner_id]).to eq("run-uuid-1")
        end
      end

      it "omits runner_id from the body when blank" do
        job_instance.execute(job_args.except("runner_id"))

        expect(api_client_double).to have_received(:post).with(
          "/api/v1/internal/ai/provisioning/missions/mission-uuid-1/steps/step-uuid-1/execute",
          {}
        )
      end

      it "returns the controller payload" do
        result = job_instance.execute(job_args)
        expect(result["success"]).to be true
        expect(result.dig("data", "status")).to eq("completed")
      end
    end

    context "when required params are missing" do
      it "raises ArgumentError when mission_id is absent" do
        expect { job_instance.execute(job_args.except("mission_id")) }
          .to raise_error(ArgumentError, /Missing required parameters/)
      end

      it "raises ArgumentError when step_id is absent" do
        expect { job_instance.execute(job_args.except("step_id")) }
          .to raise_error(ArgumentError, /Missing required parameters/)
      end

      it "raises ArgumentError when account_id is absent" do
        expect { job_instance.execute(job_args.except("account_id")) }
          .to raise_error(ArgumentError, /Missing required parameters/)
      end
    end

    context "when the API returns success: false" do
      before do
        allow(api_client_double).to receive(:post).and_return(
          "success" => false, "error" => "skill not found"
        )
      end

      # Per worker convention (AiProvisioningExecuteJob mirrors this),
      # step-level failures don't trigger mission-level "failed" patches —
      # the runner already records per-step failure state via execute_step!,
      # and a mission-wide failure would be premature for one stuck step.
      it "returns the error payload without re-raising" do
        result = job_instance.execute(job_args)
        expect(result["success"]).to be false
        expect(result["error"]).to eq("skill not found")
      end
    end

    context "when the API raises" do
      before do
        allow(api_client_double).to receive(:post).and_raise(StandardError.new("network"))
      end

      it "re-raises so Sidekiq applies retry policy" do
        expect { job_instance.execute(job_args) }.to raise_error(StandardError, /network/)
      end
    end
  end
end
