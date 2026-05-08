# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiProvisioningVerifyJob, type: :job do
  subject { described_class }

  let(:job_args) { { "mission_id" => "mission-uuid-1", "account_id" => "acc-uuid-1" } }

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
          "data" => { "healthy" => true, "checked_at" => Time.now.iso8601 }
        )
      end

      it "POSTs to the internal verify endpoint" do
        job_instance.execute(job_args)

        expect(api_client_double).to have_received(:post).with(
          "/api/v1/internal/ai/provisioning/missions/mission-uuid-1/verify",
          {}
        )
      end

      it "returns the verify payload" do
        result = job_instance.execute(job_args)
        expect(result.dig("data", "healthy")).to be true
      end
    end

    context "when required params are missing" do
      it "raises ArgumentError on empty params" do
        # mission_id absent → report_failure short-circuits (no patch call),
        # so the bare ArgumentError propagates cleanly.
        expect { job_instance.execute({}) }
          .to raise_error(ArgumentError, /Missing required parameters/)
      end

      it "raises ArgumentError when mission_id is absent" do
        expect { job_instance.execute(job_args.except("mission_id")) }
          .to raise_error(ArgumentError, /Missing required parameters/)
      end

      it "reports failure and re-raises when only account_id is absent" do
        # mission_id is present, so the rescue path patches the mission
        # before re-raising. Stub patch so the double doesn't error on the
        # unexpected message.
        allow(api_client_double).to receive(:patch).and_return("success" => true)
        expect { job_instance.execute(job_args.except("account_id")) }
          .to raise_error(ArgumentError, /Missing required parameters/)
        expect(api_client_double).to have_received(:patch).with(
          "/api/v1/ai/missions/mission-uuid-1",
          hash_including(mission: hash_including(status: "failed"))
        )
      end
    end

    context "when the API returns success: false" do
      before do
        allow(api_client_double).to receive(:post).and_return(
          "success" => false, "error" => "slo not met"
        )
        allow(api_client_double).to receive(:patch).and_return("success" => true)
      end

      it "reports mission failure" do
        job_instance.execute(job_args)
        expect(api_client_double).to have_received(:patch).with(
          "/api/v1/ai/missions/mission-uuid-1",
          hash_including(mission: hash_including(status: "failed"))
        )
      end

      it "returns the error payload without re-raising" do
        result = job_instance.execute(job_args)
        expect(result["success"]).to be false
        expect(result["error"]).to eq("slo not met")
      end
    end

    context "when the API raises" do
      before do
        allow(api_client_double).to receive(:post).and_raise(StandardError.new("network"))
        allow(api_client_double).to receive(:patch).and_return("success" => true)
      end

      it "reports failure and re-raises so Sidekiq retries" do
        expect { job_instance.execute(job_args) }.to raise_error(StandardError, /network/)
        expect(api_client_double).to have_received(:patch)
      end
    end
  end
end
