# frozen_string_literal: true

require "rails_helper"

# IMP-b24afe85a309 — worker job spec for the IPFIX flow-samples retention
# sweep. Mirrors SystemFleetEventRetentionJob's spec; runs on the maintenance
# queue, not system.
RSpec.describe SdwanFlowSampleRetentionJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:job_args) { nil }
  let(:api_client) { instance_double(BackendApiClient) }

  before { allow(job).to receive(:api_client).and_return(api_client) }

  describe "sidekiq_options" do
    it "uses the maintenance queue (not system)" do
      expect(described_class.get_sidekiq_options["queue"]).to eq("maintenance")
    end
  end

  describe "#execute" do
    let(:endpoint) { "/api/v1/system/worker_api/sdwan/flow_sample_retention_sweep" }

    context "happy path" do
      let(:response) do
        { "data" => { "accounts" => 2, "deleted_total" => 4_200, "batches" => 3,
                      "capped" => false, "floored" => false } }
      end

      before { allow(api_client).to receive(:post).with(endpoint, {}).and_return(response) }

      it "POSTs the retention sweep endpoint" do
        result = job.execute

        expect(result).to be_a(Hash)
        expect(result).not_to include(:error)
        expect(api_client).to have_received(:post).with(endpoint, {})
      end

      # The window itself is DB-driven and resolved server-side; the job must
      # not carry a retention value of its own. A body that is anything but {}
      # would mean the schedule had started configuring policy.
      it "sends no retention parameters of its own" do
        job.execute

        expect(api_client).to have_received(:post).with(endpoint, {})
      end

      it "surfaces the capped flag so a draining backlog is visible" do
        allow(api_client).to receive(:post).with(endpoint, {}).and_return(
          { "data" => { "accounts" => 1, "deleted_total" => 500_000, "batches" => 100,
                        "capped" => true, "floored" => false } }
        )

        expect(job.execute).to include(capped: true)
      end
    end

    context "API error" do
      before do
        allow(api_client).to receive(:post).with(endpoint, {})
          .and_raise(BackendApiClient::ApiError.new("boom"))
      end

      it "returns ok: false" do
        expect(job.execute).to include(ok: false)
      end
    end
  end
end
