# frozen_string_literal: true

require "rails_helper"

# Campaign 019f5885 inc3 — every-60s CI runner lease reconcile tick. Thin
# HTTP shim (mirrors System::InstancePoolReplenisherJob's spec pattern):
# POSTs the worker_api advance endpoint, which runs
# System::CiRunnerLeaseSweepService server-side (server has no Sidekiq).
RSpec.describe System::CiRunnerLeaseReconcileJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class

  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:endpoint) { "/api/v1/system/worker_api/ci_runner_leases/advance" }

  before { allow(job).to receive(:api_client).and_return(api_client) }

  describe "#execute" do
    context "happy path with no args" do
      let(:response) do
        {
          "success" => true,
          "data" => { "accounts_swept" => 2, "advanced" => 1, "released" => 3,
                      "flagged" => 0, "errored" => 0, "orphans_reaped" => 1 }
        }
      end

      before { allow(api_client).to receive(:post).with(endpoint, {}).and_return(response) }

      it "POSTs the advance endpoint with an empty body and returns the data hash" do
        result = job.execute

        expect(result).to eq(response["data"])
        expect(api_client).to have_received(:post).with(endpoint, {})
      end
    end

    context "with an account_id arg" do
      let(:response) { { "success" => true, "data" => { "accounts_swept" => 1 } } }

      before do
        allow(api_client).to receive(:post)
          .with(endpoint, { account_id: "acct-123" })
          .and_return(response)
      end

      it "passes account_id through in the POST body" do
        job.execute("account_id" => "acct-123")

        expect(api_client).to have_received(:post).with(endpoint, { account_id: "acct-123" })
      end
    end

    context "when the server reports failure" do
      before do
        allow(api_client).to receive(:post).with(endpoint, {})
          .and_return("success" => false, "error" => "sweep exploded")
      end

      it "raises with the server's error message" do
        expect { job.execute }.to raise_error("sweep exploded")
      end
    end

    context "when the server reports failure with no error message" do
      before do
        allow(api_client).to receive(:post).with(endpoint, {}).and_return("success" => false)
      end

      it "raises the default fallback message" do
        expect { job.execute }.to raise_error("ci_runner_lease_advance_failed")
      end
    end
  end
end
