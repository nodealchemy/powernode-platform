# frozen_string_literal: true

require "rails_helper"

# Audit plan P0.2 — worker job spec.
RSpec.describe SystemCveResponderReconcileJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:job_args) { nil }
  let(:api_client) { instance_double(BackendApiClient) }

  before { allow(job).to receive(:api_client).and_return(api_client) }

  describe "#execute" do
    let(:endpoint) { "/api/v1/system/worker_api/cve_responder/reconcile" }

    context "happy path" do
      let(:response) do
        { "data" => { "remediated" => 2, "skipped" => 1, "errors" => 0 } }
      end

      before { allow(api_client).to receive(:post).with(endpoint, {}).and_return(response) }

      it "POSTs the reconcile endpoint and returns ok" do
        result = job.execute
        expect(result).to be_a(Hash)
        expect(result).not_to include(:error)
        expect(api_client).to have_received(:post).with(endpoint, {})
      end
    end

    context "API error" do
      before do
        allow(api_client).to receive(:post).with(endpoint, {})
          .and_raise(BackendApiClient::ApiError.new("timeout"))
      end

      it "returns ok: false (no raise)" do
        expect(job.execute).to include(ok: false)
      end
    end
  end
end
