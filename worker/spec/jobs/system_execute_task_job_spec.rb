# frozen_string_literal: true

require "rails_helper"

# Audit plan P0.2 — worker job spec. SystemExecuteTaskJob runs with retry: 0,
# returns gracefully on 409 Conflict (already claimed), and RE-RAISES on other
# API errors (Sidekiq's no-retry policy means the reaper picks up failures).
RSpec.describe SystemExecuteTaskJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:operation_id) { "op-#{SecureRandom.hex(4)}" }
  let(:job_args) { operation_id }
  let(:api_client) { instance_double(BackendApiClient) }

  before { allow(job).to receive(:api_client).and_return(api_client) }

  describe "#execute" do
    let(:endpoint) { "/api/v1/system/worker_api/operations/#{operation_id}/execute" }

    context "happy path (server returns 200)" do
      let(:response) do
        { "data" => { "task" => { "id" => operation_id, "status" => "complete" },
                      "runtime_result" => { "success" => true } } }
      end

      before { allow(api_client).to receive(:post).with(endpoint).and_return(response) }

      it "returns the full response payload" do
        expect(job.execute(operation_id)).to eq(response)
      end

      it "POSTs the per-operation execute endpoint" do
        job.execute(operation_id)
        expect(api_client).to have_received(:post).with(endpoint)
      end
    end

    context "when the server returns 409 Conflict (already claimed)" do
      let(:err) do
        e = BackendApiClient::ApiError.new("Conflict")
        e.define_singleton_method(:status) { 409 }
        e
      end

      before { allow(api_client).to receive(:post).with(endpoint).and_raise(err) }

      it "returns {skipped: true, reason: 'already_claimed'} (no raise)" do
        result = job.execute(operation_id)
        expect(result).to include(skipped: true, reason: "already_claimed")
      end
    end

    context "when the server returns a non-409 API error" do
      let(:err) do
        e = BackendApiClient::ApiError.new("502 Bad Gateway")
        e.define_singleton_method(:status) { 502 }
        e
      end

      before { allow(api_client).to receive(:post).with(endpoint).and_raise(err) }

      it "re-raises so Sidekiq's retry policy (retry: 0 → DLQ) takes over" do
        expect { job.execute(operation_id) }.to raise_error(BackendApiClient::ApiError, /502/)
      end
    end
  end

  describe "sidekiq_options" do
    it "uses retry: 0 (reaper recovers, not Sidekiq)" do
      expect(described_class.get_sidekiq_options["retry"]).to eq(0)
    end
  end
end
