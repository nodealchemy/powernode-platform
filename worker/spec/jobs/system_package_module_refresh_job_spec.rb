# frozen_string_literal: true

require "rails_helper"

# Audit plan P0.2 — worker job spec.
RSpec.describe SystemPackageModuleRefreshJob, type: :job do
  subject { described_class }

  it_behaves_like "a base job", described_class
  it_behaves_like "a job with API communication"
  it_behaves_like "a job with logging"

  let(:job) { described_class.new }
  let(:link_id) { "link-#{SecureRandom.hex(4)}" }
  let(:job_args) { [link_id, false] }
  let(:api_client) { instance_double(BackendApiClient) }

  before { allow(job).to receive(:api_client).and_return(api_client) }

  describe "#execute" do
    let(:endpoint) { "/api/v1/system/worker_api/package_modules/refresh" }

    context "successful refresh" do
      let(:response) do
        { "data" => { "success" => true, "new_version_number" => 3,
                      "new_recommends_available" => [],
                      "build_dispatches" => ["disp-1", "disp-2"] } }
      end

      before do
        allow(api_client).to receive(:post)
          .with(endpoint, hash_including(package_module_link_id: link_id, force: false))
          .and_return(response)
      end

      it "POSTs refresh endpoint with link_id + force" do
        job.execute(link_id, false)
        expect(api_client).to have_received(:post)
          .with(endpoint, hash_including(package_module_link_id: link_id, force: false))
      end

      it "returns the data hash" do
        result = job.execute(link_id, false)
        expect(result).to include("success" => true, "new_version_number" => 3)
      end
    end

    context "with force=true" do
      let(:response) { { "data" => { "success" => true } } }
      it "forwards the force flag" do
        allow(api_client).to receive(:post)
          .with(endpoint, hash_including(force: true))
          .and_return(response)
        job.execute(link_id, true)
        expect(api_client).to have_received(:post).with(endpoint, hash_including(force: true))
      end
    end

    context "API error" do
      before do
        allow(api_client).to receive(:post).with(endpoint, anything)
          .and_raise(BackendApiClient::ApiError.new("upstream timeout"))
      end

      it "re-raises so Sidekiq retries" do
        expect { job.execute(link_id, false) }.to raise_error(BackendApiClient::ApiError, /timeout/)
      end
    end
  end
end
