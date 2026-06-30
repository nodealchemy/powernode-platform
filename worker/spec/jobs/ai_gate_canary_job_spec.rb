# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGateCanaryJob, type: :job do
  it_behaves_like "a base job", described_class

  let(:job) { described_class.new }
  let(:api_client_double) { double("BackendApiClient") }

  let(:canary_path) { "/api/v1/internal/ai/ralph_loops/gate_canary" }
  let(:broadcast_path) { "/api/v1/ai/autonomy/broadcast" }

  let(:healthy_response) do
    { "success" => true, "data" => { "healthy" => true,
                                     "checks" => [{ "name" => "rspec_clean_pass", "ok" => true }] } }
  end

  let(:unhealthy_response) do
    {
      "success" => true,
      "data" => {
        "healthy" => false,
        "checks" => [
          { "name" => "rspec_clean_pass", "expected" => true, "actual" => true, "ok" => true },
          { "name" => "blank_framework_fail_closed", "expected" => false, "actual" => true, "ok" => false }
        ]
      }
    }
  end

  before do
    allow(job).to receive(:api_client).and_return(api_client_double)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow(api_client_double).to receive(:post).and_return("success" => true)
  end

  it "runs on the ai_orchestration queue" do
    expect(described_class.get_sidekiq_options["queue"]).to eq("ai_orchestration")
  end

  describe "#execute" do
    it "runs the canary via the internal endpoint and does NOT alert when healthy" do
      allow(api_client_double).to receive(:post).with(canary_path).and_return(healthy_response)

      expect(job).not_to receive(:log_error)
      job.execute

      expect(api_client_double).not_to have_received(:post).with(broadcast_path, anything)
    end

    it "alerts (log_error + broadcast) when the gate is broken (unhealthy)" do
      allow(api_client_double).to receive(:post).with(canary_path).and_return(unhealthy_response)

      expect(job).to receive(:log_error).with(/verification gate is broken/i, failing_checks: anything)
      job.execute

      expect(api_client_double).to have_received(:post).with(
        broadcast_path,
        hash_including(broadcast_type: "health_status",
                       data: hash_including(source: "gate_canary", status: "critical", healthy: false))
      )
    end

    it "includes the offending check names in the broadcast payload" do
      allow(api_client_double).to receive(:post).with(canary_path).and_return(unhealthy_response)
      allow(job).to receive(:log_error)

      job.execute

      expect(api_client_double).to have_received(:post).with(
        broadcast_path,
        hash_including(data: hash_including(
          failing_checks: array_including(hash_including("name" => "blank_framework_fail_closed"))
        ))
      )
    end

    it "does not let a broadcast failure mask the log alert" do
      allow(api_client_double).to receive(:post).with(canary_path).and_return(unhealthy_response)
      allow(api_client_double).to receive(:post).with(broadcast_path, anything).and_raise(StandardError.new("down"))

      expect(job).to receive(:log_error).with(/verification gate is broken/i, failing_checks: anything)
      expect { job.execute }.not_to raise_error
    end

    it "logs and does not alert when the canary run itself fails" do
      allow(api_client_double).to receive(:post).with(canary_path)
        .and_return("success" => false, "error" => "boom")

      job.execute

      expect(api_client_double).not_to have_received(:post).with(broadcast_path, anything)
    end

    it "skips quietly when the backend is unavailable" do
      allow(api_client_double).to receive(:post).with(canary_path).and_raise(Errno::ECONNREFUSED)

      expect { job.execute }.not_to raise_error
      expect(api_client_double).not_to have_received(:post).with(broadcast_path, anything)
    end
  end
end
